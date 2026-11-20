// scout-tools cards: scores test messages against the field cards with the app's own matcher (CardMatcher), to set
// its thresholds and to see what it would attach to a question.
//   scout-tools cards <library-folder> <messages.tsv> [--json FILE] [--words] [--no-confirm] [--close-ask]
// messages.tsv: expected card id (or "none") <tab> kind <tab> message. A follow-up is written "earlier || new": the
// new part is the message and both together are its situation, as in the app. --words matches by shared words
// only, as the app does without the library's embedder. --no-confirm skips asking Apple's model whether the nearest
// card fits, as when the model won't say. --close-ask asks the model about both cards when two are too close to
// call (CardMatcher.WhenClose.askBoth) instead of attaching none.
import Foundation
import FoundationModels

@MainActor
enum Cards {
    static func run(_ args: [String]) async throws {
        guard args.count >= 2 else { throw ToolError.usage("cards <library-folder> <messages.tsv> [--json FILE] [--words] [--no-confirm] [--close-ask]") }
        let library = try Library(folder: URL(fileURLWithPath: args[0]))
        if !args.contains("--words") { await SearchModels.shared.load(for: library) }
        let jsonOut = args.firstIndex(of: "--json").map { args[$0 + 1] }
        let rows = try String(contentsOfFile: args[1], encoding: .utf8).split(separator: "\n").dropFirst()
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }.filter { $0.count >= 3 }
        // --vectors FILE: every phrase and message as its vector, to try other ways of scoring offline.
        if let i = args.firstIndex(of: "--vectors") {
            func embed(_ texts: [String]) async -> [[Float]] {
                var out: [[Float]] = []
                for start in stride(from: 0, to: texts.count, by: 64) {
                    out += await SearchModels.shared.embedPlain(Array(texts[start..<min(start + 64, texts.count)])) ?? []
                }
                return out
            }
            var cards: [[String: Any]] = []
            for card in FieldCard.all {
                let words = "\(card.title). " + (card.recognize + card.treat).joined(separator: " ")
                cards.append(["id": card.id, "asks": await embed(card.asks), "nots": await embed(card.notAsks),
                              "title": await embed([card.title]), "text": await embed([words])])
            }
            var messages: [[String: Any]] = []
            for row in rows {
                let parts = row[2].components(separatedBy: " || ")
                let question = parts.last ?? row[2], situation = parts.joined(separator: " ")
                let v = await embed([question, situation, SearchModels.queryPrefix + question, SearchModels.queryPrefix + situation])
                messages.append(["expected": row[0], "kind": row[1], "message": row[2], "q": v[0], "s": v[1], "qp": v[2], "sp": v[3]])
            }
            try JSONSerialization.data(withJSONObject: ["cards": cards, "messages": messages])
                .write(to: URL(fileURLWithPath: args[i + 1]))
            print("wrote vectors to \(args[i + 1])")
            return
        }
        let model: SystemLanguageModel? = args.contains("--no-confirm") ? nil
            : SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        // --confirm N: another wording of the question put to the model, to try before changing CardMatcher's.
        let variant = args.firstIndex(of: "--confirm").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
        var records: [[String: Any]] = []
        var right = 0, wrong = 0, missed = 0, falseAlarm = 0, quiet = 0, two = 0, byMeaning = false
        if args.contains("--close-ask") { CardMatcher.whenClose = .askBoth }
        let started = Date()
        for row in rows {
            let parts = row[2].components(separatedBy: " || ")
            let question = parts.last ?? row[2]
            let earlier = parts.count > 1 ? parts.dropLast().joined(separator: " ") : nil
            let ranked = await CardMatcher.ranked(question, earlier: earlier)
            byMeaning = ranked.byMeaning
            let matches = await CardMatcher.match(question, earlier: earlier) { card, q, e in
                guard let model else { return nil }
                if let variant { return await Self.confirm(variant, card, question: q, earlier: e, model: model) }
                return await Retrieval.confirmCard(card, question: q, earlier: e, model: model)
            }
            let ids = matches.map(\.card.id)
            let got = ids.isEmpty ? "none" : ids.joined(separator: "+")
            if ids.count == 2 { two += 1 }
            if row[0] == "none" { ids.isEmpty ? (quiet += 1) : (falseAlarm += 1) }
            else if ids.contains(row[0]) { right += 1 } else if ids.isEmpty { missed += 1 } else { wrong += 1 }
            if got != row[0] {
                let top = ranked.matches.prefix(2).map { String(format: "%@ %.2f (ask %.2f, not %.2f)", $0.card.id, $0.score, $0.nearest, $0.rival) }
                print("\(row[0]) -> \(got)\t[\(row[1])] \(row[2].prefix(90))\t\(top.joined(separator: ", "))")
            }
            records.append(["expected": row[0], "kind": row[1], "message": row[2], "got": got,
                            "top": ranked.matches.prefix(5).map { ["id": $0.card.id, "score": $0.score, "nearest": $0.nearest, "rival": $0.rival] }])
        }
        let cards = right + wrong + missed, none = quiet + falseAlarm
        print(String(format: "\nmatched by %@ in %.1f s (first call embeds the cards' phrases)", byMeaning ? "meaning" : "words",
                     Date().timeIntervalSince(started)))
        print("messages about a card: \(cards): right card \(right), wrong card \(wrong), no card \(missed)")
        print("two cards attached: \(two)")
        print("messages about none:   \(none): no card \(quiet), a card attached \(falseAlarm)")
        if let jsonOut {
            try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: jsonOut))
        }
    }

    /// Other wordings of CardMatcher's yes-or-no question (--confirm N).
    static func confirm(_ variant: Int, _ card: FieldCard, question: String, earlier: String?,
                        model: SystemLanguageModel) async -> Bool? {
        let strict = """
        You check whether a quick-reference card answers what a person wrote to a field guide app. Answer YES only \
        if the card's steps are what this person needs for the situation or question in their message. Answer NO if \
        the card is about a neighbouring subject, or if they ask something the card's steps don't cover, even when \
        the message shares words with the card. Reply with one word: YES or NO.
        """
        let steps = card.treat.prefix(3).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
        let said = (earlier.map { "Earlier they said: \($0)\n" } ?? "") + "Their message: \(question)\n\n"
        let (instructions, prompt): (String, String) = switch variant {
        case 2: (strict, said + "Card: \(card.title). \(card.recognize.joined(separator: " "))\nIts steps: \(steps)\n\n"
                 + "Would this card's steps answer their message? YES or NO.")
        case 3: (strict, said + "Card: \(card.title). \(card.recognize.joined(separator: " "))\n\n"
                 + "Would this card answer their message? YES or NO.")
        default: (CardMatcher.confirmInstructions, CardMatcher.confirmPrompt(card, question: question, earlier: earlier))
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
        guard let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                         maximumResponseTokens: 5))
        else { return nil }
        return CardMatcher.readConfirmation(reply.content)
    }
}
