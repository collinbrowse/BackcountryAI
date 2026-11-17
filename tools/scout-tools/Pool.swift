// scout-tools pool: for each test question, everything the app's searches match before its rules for choosing among
// them (one passage per article, six per search, ten candidates), with whole passages. Other rules can then be
// tried offline against the same hits and judged once (tools/grade-answers/pool_eval.py, docs/answer-quality.md).
//   scout-tools pool <library-folder> <questions.tsv> --json FILE [--conversations FILE] [--depth 40]
//                    [--plans POOL.json] [--wide 12,16,20]
// The planner (Apple's model) runs once per question and its searches are saved, so every rule is compared on the
// same plan. Follow-ups are searched with what came before them, as in the app; nothing is answered.
//
// FILE: {"records": [{area, question, conversation, history, kind, searches, context,
//                     lists: [{name, query, hits: [[passage id, score, coverage]]}], dense: [[passage id, score]],
//                     app: [{id, text, signals}], signal_names}],
//        "passages": {id: {doc, key, source, title, text, first}}}
// `app` is what the app's own rule made of the same plan (Retrieval.signalled: rank-fusion order, before the
// ranker), with the excerpts as it cuts them and each one's signals: the baseline every other rule is compared
// with, and what tools/grade-answers/fit_ranker.py fits the ranker's weights to.
// `first` marks an article's first passage. For forum threads every passage of the thread is included, so "the
// accepted answer instead of the question" can be tried.
import Foundation
import FoundationModels

@MainActor
enum Pool {
    static func run(_ args: [String]) async throws {
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count && !args[$0 + 1].hasPrefix("--") ? args[$0 + 1] : nil }
        }
        guard args.count >= 2, let out = value("--json") else {
            throw ToolError.usage("pool <library-folder> <questions.tsv> --json FILE [--conversations FILE] [--depth 40] "
                                  + "[--plans POOL.json] [--wide 12,16,20]")
        }
        let library = try Library(folder: URL(fileURLWithPath: args[0]))
        let depth = value("--depth").flatMap(Int.init) ?? 40
        // --wide A,B,C: the app's candidates with A passages a keyword search, B from meaning and C in all, to
        // try wider nets than Retrieval's own (6, 8, 10).
        let wide = (value("--wide") ?? "").split(separator: ",").compactMap { Int($0) }
        let perSearch = wide.count == 3 ? wide[0] : Retrieval.perKeywordSearch
        let perMeaning = wide.count == 3 ? wide[1] : Retrieval.perMeaningSearch
        let limit = wide.count == 3 ? wide[2] : 10
        // --plans POOL.json: the planner's searches from an earlier pool, so a rebuilt pool compares like with
        // like (and needs no model).
        var plans: [String: (kind: Retrieval.Kind, searches: [String])] = [:]
        if let file = value("--plans"),
           let old = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: file))) as? [String: Any] {
            for r in old["records"] as? [[String: Any]] ?? [] {
                guard let q = r["question"] as? String, let searches = r["searches"] as? [String],
                      let kind = (r["kind"] as? String).flatMap(Retrieval.Kind.init(rawValue:)) else { continue }
                plans[((r["history"] as? [String]) ?? []).joined(separator: "\n") + "\n" + q] = (kind, searches)
            }
        }
        var questions = try Check.readTSV(args[1]).map { (conversation: String?.none, area: $0[0], text: $0[1]) }
        if let file = value("--conversations") {
            questions += try Check.readTSV(file).map { (conversation: Optional($0[0]), area: $0[1], text: $0[2]) }
        }
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { print("Apple's model unavailable: \(model.availability)"); exit(1) }
        await SearchModels.shared.load(for: library)

        var records: [[String: Any]] = []
        var ids = Set<Int64>()
        var history: [Retrieval.Turn] = [], lastConversation: String?
        for q in questions {
            if q.conversation != lastConversation || q.conversation == nil { history = [] }
            lastConversation = q.conversation
            defer { history.append(Retrieval.Turn(question: q.text, answer: "")) }
            var record: [String: Any] = ["area": q.area, "question": q.text, "conversation": q.conversation ?? "",
                                         "history": history.map(\.question)]
            // "Explain step 1 more" is answered from the last answer's excerpts, and small talk from nothing.
            if !history.isEmpty, Retrieval.asksAboutLastAnswer(q.text) {
                record["skipped"] = "about the last answer"
                records.append(record)
                continue
            }
            let planned: Retrieval.Plan?
            if let saved = plans[history.map(\.question).joined(separator: "\n") + "\n" + q.text] {
                planned = Retrieval.Plan(kind: saved.kind, searches: saved.searches)
            } else {
                planned = await Retrieval.plan(for: q.text, history: history, model: model)
            }
            guard let plan = planned else {
                record["skipped"] = "small talk"
                records.append(record)
                continue
            }
            let context = Retrieval.situation(q.text, history: history)
            let queries = [("question", q.text)] + plan.searches.map { ("search", $0) }
                + (context.map { [("context", $0)] } ?? [])
            var lists: [[String: Any]] = []
            for (name, query) in queries {
                let hits = library.keywordHits(query, limit: depth)
                ids.formUnion(hits.map(\.passageID))
                lists.append(["name": name, "query": query,
                              "hits": hits.map { [$0.passageID, $0.score, $0.coverage] as [Any] }])
            }
            let dense = await SearchModels.shared.denseHits(context ?? q.text, library: library, limit: depth)
            ids.formUnion(dense.map(\.id))
            // The app's own candidates from this plan, for checking a port of its rule.
            let denseApp = await SearchModels.shared.denseSearch(
                context ?? q.text, library: library, limit: perMeaning, perArticle: Retrieval.passagesPerArticle,
                whole: true, maxChars: Retrieval.excerptCharacters)
            let app = Retrieval.signalled(question: q.text, searches: plan.searches, dense: denseApp,
                                          context: context, library: library, perSearch: perSearch, limit: limit)
            ids.formUnion(app.map(\.passage.id))
            record["kind"] = plan.kind.rawValue
            record["searches"] = plan.searches
            record["context"] = context ?? ""
            record["lists"] = lists
            record["dense"] = dense.map { [$0.id, Double($0.score)] as [Any] }
            record["app"] = app.map {
                ["id": $0.passage.id, "text": $0.passage.text, "signals": $0.signals.values] as [String: Any]
            }
            record["signal_names"] = Retrieval.Signals.names
            records.append(record)
            print("\(q.area)\t\(q.text.prefix(70))\t\(plan.searches.joined(separator: " | "))")
        }

        // Whole passages, and for forum threads the rest of the thread.
        var passages: [String: Any] = [:]
        var pending = Array(ids), seen = ids
        while !pending.isEmpty {
            let batch = library.wholePassages(ids: pending)
            pending = []
            for p in batch {
                let siblings = library.passageIDs(inArticleOf: p.id)
                passages[String(p.id)] = ["doc": p.docID, "key": p.sourceKey, "source": p.source, "title": p.title,
                                          "text": p.text, "first": siblings.first == p.id] as [String: Any]
                if p.sourceKey.hasPrefix("se-") {
                    for s in siblings where !seen.contains(s) {
                        seen.insert(s)
                        pending.append(s)
                    }
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["records": records, "passages": passages])
        try data.write(to: URL(fileURLWithPath: out))
        print("\(records.count) questions, \(passages.count) passages -> \(out)")
    }
}
