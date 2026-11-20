// scout-tools check: runs questions through the app's own retrieval (Retrieval.find: plan, keyword + meaning search, pick) with
// Apple's on-device model on this Mac, and reports for each question whether a relevant article made it to the
// answer model, plus what was searched, scored and kept. Run with scripts/check-answers.sh.
//
// --answers writes answers too (Apple's model, or --qwen for the better-answers model). --json FILE saves one record
// per question for scripts/grade-answers.sh and the training pipeline (docs/answer-quality.md):
//   {area, question, kind, history: [{question, answer}], instructions, prompt, sources: [{title, source, text}],
//    candidates: [{title, source, text}], searches, answer, engine, seconds}
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
                                  + "[--json FILE] [--conversations FILE] [--qwen [DIR]] [--no-rerank] [--no-dense] "
                                  + "[--no-decline]")
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
        var keywordPass = 0, pass = 0, total = 0, unplanned = 0
        var history: [Retrieval.Turn] = [], lastConversation: String?
        for q in questions {
            if let only, !q.text.lowercased().contains(only) { continue }
            if q.conversation != lastConversation || q.conversation == nil { history = [] }
            lastConversation = q.conversation
            total += 1
            let plain = library.search(q.text, limit: 5)
            // The app's own retrieval (Retrieval.find): plan, search, pick, and the follow-up handling.
            let found = await Retrieval.find(question: q.text, history: history, library: library, model: model,
                                             dense: dense, rerank: rerank)
            let picked = found.sources, candidates = found.candidates
            let plan = Retrieval.Plan(kind: found.kind, searches: found.searches)
            if !found.isChat, !found.reusedLastSources, found.searches.isEmpty { unplanned += 1 }
            let kOK = plain.contains { $0.title.contains(q.about) }
            let ok = picked.contains { $0.title.contains(q.about) }
            keywordPass += kOK ? 1 : 0
            pass += ok ? 1 : 0
            let turn = q.conversation.map { "[\($0) turn \(history.count + 1)] " } ?? ""
            print("\(ok ? "PASS" : (picked.isEmpty ? "NONE" : "MISS"))\t\(q.area)\t\(turn)\(q.text)")
            if found.isChat {
                print("    CHAT: the app would reply to this as small talk, with no search")
            } else if found.reusedLastSources {
                print("    about the last answer: answered from its excerpts, no new search")
            } else {
                print(String(format: "    %@ · searches (%.1fs): %@", plan.kind.rawValue, found.planSeconds,
                             plan.searches.joined(separator: " | ")))
                if !found.dense.isEmpty { print("    meaning search: " + found.dense.prefix(5).map(\.title).joined(separator: " · ")) }
                print(String(format: "    search %.1fs; picked (%.1fs):", found.searchSeconds, found.pickSeconds))
                if !found.cards.isEmpty {
                    print(String(format: "    field card (%.1fs): %@", found.cardSeconds, found.cards.joined(separator: ", ")))
                }
            }
            for p in picked { print("      [\(p.sourceKey)] \(p.title)") }
            // Every candidate's score (the ranker's, or a reranker model's), so the cutoff can be checked by eye.
            let scored = found.scores.map { Array(zip(candidates.map(\.title), $0)) } ?? []
            let cutoff = found.reranked ? Retrieval.minimumRelevance : Retrieval.Ranker.minimum
            for (title, s) in scored.sorted(by: { $0.1 > $1.1 }) {
                print(String(format: "      %.2f %@%@", s, s >= cutoff ? "" : "(dropped) ", title))
            }
            if scored.isEmpty {
                let dropped = candidates.filter { c in !picked.contains { $0.docID == c.docID } }
                if !dropped.isEmpty { print("    dropped: " + dropped.map(\.title).joined(separator: " · ")) }
            }

            // What the app does with a dose, an identification or a medical question the library doesn't cover:
            // fixed words, no model (Stakes). --no-decline answers anyway, to see what the model would have said.
            let stakes = Stakes.of(q.text, earlier: Retrieval.earlier(in: history))
            let wouldDecline = noLibrary ? nil : Retrieval.declines(question: q.text, history: history, sources: picked,
                                                                    keepsWarnings: engine.keepsWarnings)
            let declined = args.contains("--no-decline") ? nil : wouldDecline
            if stakes != .ordinary { print("    stakes: \(stakes.rawValue)\(wouldDecline == nil ? "" : ", declined") ") }
            // Fitted to the answering model's context with its own tokenizer, as in the app.
            let kind = plan.kind, text = q.text, turns = history
            let fitted = await PromptFit.fit(noLibrary ? [] : picked, engine: engine, config: .answers) { kept in
                [.system(Retrieval.instructions(for: engine.stepHabit, emergency: Urgency.needsHelpNow(text),
                                                followUp: Retrieval.carriesOn(text, history: turns), stakes: stakes)),
                 .user(Retrieval.prompt(question: text, sources: kept, history: turns, kind: kind))]
            }
            let sources = fitted.sources
            let prompt = fitted.messages.last?.content ?? ""
            var answer = ""
            let began = Date()
            // Conversations always answer, so the next turn has its history, as in the app.
            if let declined {
                answer = declined
                print("    declined:\n" + declined.split(separator: "\n").map { "      " + $0 }.joined(separator: "\n"))
            } else if answers || q.conversation != nil {
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
                "instructions": fitted.messages.first?.content ?? "", "prompt": prompt,
                "emergency": Urgency.needsHelpNow(q.text),
                "sources": sources.map { ["title": $0.title, "source": $0.source, "text": $0.text] },
                // Everything search found before the picker chose, for tools/grade-answers/judge_passages.py.
                "candidates": candidates.map { ["title": $0.title, "source": $0.source, "text": $0.text] },
                "answer": answer, "engine": useQwen ? "qwen" : "apple",
                "small_talk": found.isChat, "about_last_answer": found.reusedLastSources,
                "stakes": stakes.rawValue, "declined": declined != nil, "would_decline": wouldDecline != nil,
                "searches": found.searches, "cards": found.cards, "card_seconds": found.cardSeconds,
                "plan_seconds": found.planSeconds, "search_seconds": found.searchSeconds, "pick_seconds": found.pickSeconds,
                "seconds": Date().timeIntervalSince(began), "found_relevant": ok,
            ])
            if q.conversation != nil {
                history.append(Retrieval.Turn(question: q.text, answer: Clarify.split(answer).text, sources: sources,
                                              kind: plan.kind))
            }
            fflush(stdout)
        }
        if let jsonOut {
            let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: jsonOut))
            print("wrote \(records.count) records to \(jsonOut)")
        }
        if unplanned > total / 10 {
            // Apple's model fails silently under memory pressure, and the app carries on with the question alone.
            // A run like that measures something else.
            print("\nWARNING: the planner gave no searches for \(unplanned) of \(total) questions. Apple's model may "
                  + "be failing (it does when memory is short): don't compare this run with others.")
        }
        print("\nkeyword search alone: \(keywordPass)/\(total); with the full pipeline: \(pass)/\(total)")
    }

    /// scout-tools instructions <records.json> --json FILE [--apple]
    /// Rewrites each record's instructions as the better-answers model gets them (`StepHabit.runsLong`), or as
    /// Apple's model does with --apple. `check` without --qwen writes Apple's, which ask for the steps another
    /// way; the training pipeline needs Qwen's without an hour of Qwen answering every question
    /// (scripts/train-answers.sh prompts). The prompt is the same for both models.
    static func instructions(_ args: [String]) throws {
        guard let input = args.first, !input.hasPrefix("--"),
              let out = args.firstIndex(of: "--json").flatMap({ $0 + 1 < args.count ? args[$0 + 1] : nil }) else {
            throw ToolError.usage("instructions <records.json> --json FILE [--apple]")
        }
        let habit: StepHabit = args.contains("--apple") ? .stopsEarly : .runsLong
        guard var records = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: input)))
                as? [[String: Any]] else { throw ToolError.usage("\(input) isn't a list of check records") }
        var changed = 0
        for i in records.indices {
            guard let question = records[i]["question"] as? String else { continue }
            let history = (records[i]["history"] as? [[String: String]] ?? []).map {
                Retrieval.Turn(question: $0["question"] ?? "", answer: $0["answer"] ?? "")
            }
            let text = Retrieval.instructions(
                for: habit, emergency: Urgency.needsHelpNow(question),
                followUp: Retrieval.carriesOn(question, history: history),
                stakes: Stakes.of(question, earlier: Retrieval.earlier(in: history)))
            if records[i]["instructions"] as? String != text { changed += 1 }
            records[i]["instructions"] = text
            records[i]["instructions_for"] = habit == .runsLong ? "qwen" : "apple"
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: out))
        print("\(records.count) records, \(changed) with new instructions -> \(out)")
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
