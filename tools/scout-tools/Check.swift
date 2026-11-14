// scout-tools check: runs questions through the app's own retrieval (plan, keyword + meaning search, reranker) with
// Apple's on-device model on this Mac, and reports for each question whether a relevant article made it to the
// answer model, plus what was searched, scored and kept. Run with scripts/check-answers.sh.
//
// --answers writes answers too (Apple's model, or --qwen for the better-answers model). --json FILE saves one record
// per question for scripts/grade-answers.sh and the training pipeline (docs/answer-quality.md):
//   {area, question, kind, history: [{question, answer}], instructions, prompt, sources: [{title, source, text}],
//    answer, engine, seconds}
// --conversations FILE runs multi-turn chats (TSV: id, area, question, about-regex; rows sharing an id are turns),
// answering each turn so the next one has its history, as in the app.
import Foundation
import FoundationModels

@MainActor
enum Check {
    struct Question {
        let conversation: String?
        let area, text: String
        let about: Regex<AnyRegexOutput>
    }

    static func run(_ args: [String]) async throws {
        guard args.count >= 2 else {
            throw ToolError.usage("check <library-folder> <questions.tsv> [--answers] [--no-library] [--only TEXT] "
                                  + "[--json FILE] [--conversations FILE] [--qwen [DIR]] [--no-rerank] [--no-dense]")
        }
        let library = try Library(folder: URL(fileURLWithPath: args[0]))
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count && !args[$0 + 1].hasPrefix("--") ? args[$0 + 1] : nil }
        }
        let noLibrary = args.contains("--no-library")  // answer from the model alone, to see what it knows
        let useQwen = args.contains("--qwen")
        let answers = args.contains("--answers") || noLibrary || useQwen
        let only = value("--only")?.lowercased()
        let jsonOut = value("--json")
        let rerank = !args.contains("--no-rerank")
        let dense = !args.contains("--no-dense")

        var questions = try readTSV(args[1]).map {
            Question(conversation: nil, area: $0[0], text: $0[1], about: try Regex($0[2]).ignoresCase())
        }
        if let file = value("--conversations") {
            questions += try readTSV(file).map {
                Question(conversation: $0[0], area: $0[1], text: $0[2], about: try Regex($0[3]).ignoresCase())
            }
        }
        if args[1] == "-" { questions.removeAll { $0.conversation == nil } }

        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { print("Apple's model unavailable: \(model.availability)"); exit(1) }
        // The app's own engines (LLMEngine): Apple's model, or the better-answers model from the catalog. --qwen DIR
        // runs a local copy instead (a fine-tuned one from scripts/train-answers.sh).
        let spec = ModelCatalog.qwen35_4B
        let qwenDir = value("--qwen").map { URL(fileURLWithPath: $0) }
        let engine: any LLMEngine = useQwen
            ? MLXEngine(name: spec.displayName, weightsBytes: spec.weightsBytes, extraEOSTokens: spec.extraEOSTokens,
                        templateContext: spec.templateContext,
                        source: { qwenDir.map { .folder($0) } ?? .hub(spec.hubID, revision: spec.revision) })
            : FoundationEngine(model: model)
        if answers || args.contains("--conversations") { try await engine.load() }
        if dense || rerank { await SearchModels.shared.load(for: library) }

        var records: [[String: Any]] = []
        var keywordPass = 0, pass = 0, total = 0
        var history: [Retrieval.Turn] = [], lastConversation: String?
        for q in questions {
            if let only, !q.text.lowercased().contains(only) { continue }
            if q.conversation != lastConversation || q.conversation == nil { history = [] }
            lastConversation = q.conversation
            total += 1
            let start = Date()
            let plain = library.search(q.text, limit: 5)
            let plan = await Retrieval.plan(for: q.text, history: history, model: model)
                ?? Retrieval.Plan(kind: .howTo, searches: [])
            let planned = Date()
            let context = ([history.last?.question].compactMap { $0 } + [q.text]).joined(separator: " ")
            let denseHits = dense ? await SearchModels.shared.denseSearch(context, library: library) : []
            let candidates = Retrieval.candidates(question: q.text, searches: plan.searches, dense: denseHits,
                                                  library: library)
            let searched = Date()
            // Print every score, so Retrieval.minimumRelevance can be checked by eye.
            let recorder = ScoreRecorder()
            let scorer = rerank ? recorder.wrap(SearchModels.shared.scorer) : nil
            let picked = await Retrieval.pick(question: q.text, history: history, from: candidates, model: model,
                                              scorer: scorer)
            let done = Date()
            let kOK = plain.contains { $0.title.contains(q.about) }
            let ok = picked.contains { $0.title.contains(q.about) }
            keywordPass += kOK ? 1 : 0
            pass += ok ? 1 : 0
            let turn = q.conversation.map { "[\($0) turn \(history.count + 1)] " } ?? ""
            print("\(ok ? "PASS" : (picked.isEmpty ? "NONE" : "MISS"))\t\(q.area)\t\(turn)\(q.text)")
            print(String(format: "    %@ · searches (%.1fs): %@", plan.kind.rawValue, planned.timeIntervalSince(start),
                         plan.searches.joined(separator: " | ")))
            if !denseHits.isEmpty { print("    meaning search: " + denseHits.prefix(5).map(\.title).joined(separator: " · ")) }
            print(String(format: "    search %.1fs; picked (%.1fs):", searched.timeIntervalSince(planned),
                         done.timeIntervalSince(searched)))
            for p in picked { print("      [\(p.sourceKey)] \(p.title)") }
            let scored = recorder.scores.map { Array(zip(candidates.map(\.title), $0)) } ?? []
            for (title, s) in scored.sorted(by: { $0.1 > $1.1 }) {
                print(String(format: "      %.2f %@%@", s, s >= Retrieval.minimumRelevance ? "" : "(dropped) ", title))
            }
            if scored.isEmpty {
                let dropped = candidates.filter { c in !picked.contains { $0.docID == c.docID } }
                if !dropped.isEmpty { print("    dropped: " + dropped.map(\.title).joined(separator: " · ")) }
            }

            // Fitted to the answering model's context with its own tokenizer, as in the app.
            let kind = plan.kind, text = q.text, turns = history
            let fitted = await PromptFit.fit(noLibrary ? [] : picked, engine: engine, config: .answers) { kept in
                [.system(Retrieval.instructions),
                 .user(Retrieval.prompt(question: text, sources: kept, history: turns, kind: kind))]
            }
            let sources = fitted.sources
            let prompt = fitted.messages.last?.content ?? ""
            var answer = ""
            let began = Date()
            // Conversations always answer, so the next turn has its history, as in the app.
            if answers || q.conversation != nil {
                let box = TextBox()
                _ = try? await engine.answer(fitted.messages, config: .answers) { box.text = $0 }
                answer = box.text
                let split = Clarify.split(answer)
                print("    answer:\n" + (answer.isEmpty ? "(failed)" : split.text).split(separator: "\n")
                    .map { "      " + $0 }.joined(separator: "\n"))
                if !split.choices.isEmpty { print("      choices: " + split.choices.joined(separator: " | ")) }
            }
            records.append([
                "area": q.area, "question": q.text, "kind": plan.kind.rawValue.lowercased() == "fix" ? "troubleshoot"
                    : plan.kind == .howTo ? "howto" : "fact",
                "conversation": q.conversation ?? "",
                "history": history.map { ["question": $0.question, "answer": $0.answer] },
                "instructions": Retrieval.instructions, "prompt": prompt,
                "sources": sources.map { ["title": $0.title, "source": $0.source, "text": $0.text] },
                "answer": answer, "engine": useQwen ? "qwen" : "apple",
                "seconds": Date().timeIntervalSince(began), "found_relevant": ok,
            ])
            if q.conversation != nil { history.append(Retrieval.Turn(question: q.text, answer: Clarify.split(answer).text)) }
            fflush(stdout)
        }
        if let jsonOut {
            let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: jsonOut))
            print("wrote \(records.count) records to \(jsonOut)")
        }
        print("\nkeyword search alone: \(keywordPass)/\(total); with the full pipeline: \(pass)/\(total)")
    }

    static func readTSV(_ path: String) throws -> [[String]] {
        guard path != "-" else { return [] }
        return try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").dropFirst()
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.count >= 3 && !$0[0].hasPrefix("#") }
    }

}

/// The answer so far, from the engine's main-actor callback.
@MainActor final class TextBox { var text = "" }

/// Keeps the reranker's scores so they can be printed after Retrieval.pick has used them.
final class ScoreRecorder: @unchecked Sendable {
    var scores: [Double]?

    func wrap(_ inner: Retrieval.Scorer?) -> Retrieval.Scorer? {
        guard let inner else { return nil }
        return { [self] query, excerpts in
            let s = await inner(query, excerpts)
            scores = s
            return s
        }
    }
}
