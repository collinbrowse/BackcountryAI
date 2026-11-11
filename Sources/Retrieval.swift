import Foundation
import FoundationModels

/// Finds the library passages that actually answer a question. Keyword search alone matches words, not meaning
/// ("a power line is down in my yard" finds football articles), so the on-device model helps twice:
/// 1. it rewrites the question into searches phrased the way a manual or Q&A site would be, and
/// 2. it reads the best candidates and keeps only the ones that help answer this question.
enum Retrieval {
    // Both steps ask for plain text: Apple's guardrails reject guided generation (@Generable) for many medical
    // questions ("May contain sensitive content") but allow plain answers with permissive transformations.

    static let planInstructions = """
    You write keyword searches for an offline library of first-aid and survival manuals, government safety guides, \
    repair and outdoors Q&A, and Wikipedia. Reply with 2 or 3 searches, one per line, 2 to 5 words each, and \
    nothing else. Each search names the main subject of the question (the injury, machine, animal, weather or \
    task) plus words an article about it would use: the medical or technical name, or a common synonym.
    """

    static let pickInstructions = """
    You check library excerpts for a field guide. For each excerpt write one line: its number, a few words on what \
    it is about, then YES if it helps with the task or question the person asked, or NO if it doesn't. Sharing a \
    word is not enough: an excerpt about 3D-printing a snowmobile part doesn't help someone add oil to a \
    snowmobile, and a football "line" doesn't help with a downed power line. An excerpt that answers part of the \
    question does help.
    """

    /// The model's searches for a question. Empty if the model fails, so search falls back to the question alone.
    static func searches(for question: String, previous: String?, model: SystemLanguageModel) async -> [String] {
        var prompt = ""
        if let previous { prompt += "Their previous question, for context: \(previous)\n" }
        prompt += "Question: \(question)"
        let session = LanguageModelSession(model: model, instructions: planInstructions)
        guard let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                            maximumResponseTokens: 80))
        else { return [] }
        return reply.content.split(whereSeparator: \.isNewline).compactMap { line in
            // Tolerate "1. ", "- ", quotes and trailing periods.
            let s = line.replacing(/^\s*(\d+[.)]|[-*•])\s*/, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”. ").union(.whitespaces))
            return s.isEmpty || s.count > 60 ? nil : s
        }.prefix(3).map { $0 }
    }

    /// Up to `limit` passages from the question and the model's searches, merged by reciprocal rank fusion:
    /// a passage near the top of several searches beats one that tops a single search.
    static func candidates(question: String, searches: [String], library: Library, limit: Int = 8) -> [Passage] {
        var score: [Int64: Double] = [:]
        var byDoc: [Int64: Passage] = [:]
        for q in [question] + searches {
            for (i, p) in library.search(q, limit: 6, maxChars: 700).enumerated() {
                score[p.docID, default: 0] += 1 / Double(8 + i)
                if (byDoc[p.docID]?.coverage ?? -1) < (p.coverage ?? 0) { byDoc[p.docID] = p }
            }
        }
        return byDoc.values.sorted { score[$0.docID]! > score[$1.docID]! }.prefix(limit).map { $0 }
    }

    /// The candidates the model says help, in search order. If the model fails, only candidates that matched
    /// every word of a search, since an unchecked partial match is how off-topic articles got through.
    static func pick(question: String, from candidates: [Passage], model: SystemLanguageModel,
                     limit: Int = 4) async -> [Passage] {
        guard !candidates.isEmpty else { return [] }
        var prompt = "Question: \(question)\n\nExcerpts:\n"
        for (i, p) in candidates.enumerated() {
            prompt += "[\(i + 1)] \(p.title) (\(p.source)): \(p.text.prefix(320))\n\n"
        }
        prompt += "One line per excerpt: number, what it's about, YES or NO."
        let session = LanguageModelSession(model: model, instructions: pickInstructions)
        guard let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                            maximumResponseTokens: 300))
        else { return Array(candidates.filter { ($0.coverage ?? 0) >= 0.99 }.prefix(3)) }
        var helps = Set<Int>()
        for line in reply.content.split(whereSeparator: \.isNewline) {
            guard let m = line.firstMatch(of: /^\W*(\d+)/), let n = Int(m.1), (1...candidates.count).contains(n)
            else { continue }
            let words = line.uppercased().split(whereSeparator: { !$0.isLetter })
            if words.last(where: { $0 == "YES" || $0 == "NO" }) == "YES" { helps.insert(n) }
        }
        return Array(candidates.enumerated().filter { helps.contains($0.offset + 1) }.map(\.element).prefix(limit))
    }

    // MARK: - Answer

    static let instructions = """
    You are Scout, an offline field guide on a phone for backcountry trips, outdoor work, vehicles, gear and \
    emergencies. Answer the person's actual question.
    Use the numbered library excerpts when they help and cite them inline like [1] or [2]. Ignore any excerpt about \
    something else: don't cite it or bring up its topic.
    Start with the answer: for a task, short numbered steps; for a question, a direct answer. Be concrete and brief.
    If the excerpts don't cover the question, say the library doesn't cover it, then give careful general guidance \
    under the heading "Not from the library:". Never end with that heading alone.
    Treat it as an emergency only when the question describes one (an injury, illness or danger). Then start with \
    the most urgent actions and say to call or text 911 or use an SOS/satellite messenger if there is any way to.
    """

    static func prompt(question: String, sources: [Passage], previous: String?, previousAnswer: String?) -> String {
        var p = ""
        if let previous, let previousAnswer, !previousAnswer.isEmpty {
            p += "Earlier in this conversation they asked: \(previous)\n"
            p += "You answered (shortened): \(previousAnswer.prefix(500))\n\n"
        }
        if sources.isEmpty {
            p += "No library excerpts matched this question.\n\n"
        } else {
            p += "Library excerpts:\n"
            for (i, s) in sources.enumerated() {
                p += "[\(i + 1)] \(s.title) (\(s.source))\n\(s.text)\n\n"
            }
        }
        p += "Question: \(question)"
        return p
    }
}
