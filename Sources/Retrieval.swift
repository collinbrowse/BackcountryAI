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
    task) plus words an article about it would use: the medical or technical name, or a common synonym. \
    Questions are often dictated, so a word that makes no sense may be a misheard brand: search for the kind of \
    product instead (a water filter, a stove).
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
    emergencies. Answer the exact question the person asked, using every detail they gave: the gear they have, what \
    they already tried, where they are. Questions are often dictated, so a word that makes no sense may be a \
    misheard product or place name; work out what they meant.
    Answer like an expert guide, from what you know plus the library excerpts. The excerpts are search results: \
    some are about a different situation, vehicle or product than the person's. Use only the facts that fit their \
    situation and cite them inline like [1]. Never describe or answer an excerpt's situation instead of theirs.
    Open with one sentence that answers the question. Then, if there is something to do, give only the numbered \
    steps this situation needs, one sentence each, with no sub-points. Two to four steps is typical; never add a \
    step just to have more, and never more than five. Be concrete (amounts, times, sizes, what to look for). \
    Stop after the last step: no closing note, summary or disclaimer.
    If you don't know a specific fact (a model's oil type, a dose, whether a plant is edible), say so in one \
    sentence instead of making it up. Don't list things you don't know about their situation.
    If none of the excerpts helped, start the answer with "Not from the library:". Never end with that phrase.
    Only when the question describes someone hurt, sick or in danger right now: make the urgent first action and \
    calling or texting 911 or using an SOS/satellite messenger the first sentence and step. Otherwise never mention \
    911, SOS or emergency help.
    """

    static func prompt(question: String, sources: [Passage], previous: String?, previousAnswer: String?) -> String {
        // The question comes first and last: a small model otherwise drifts to whatever the excerpts are about.
        var p = ""
        if let previous, let previousAnswer, !previousAnswer.isEmpty {
            p += "Earlier in this conversation they asked: \(previous)\n"
            p += "You answered (shortened): \(previousAnswer.prefix(500))\n\n"
        }
        p += "Their question: \(question)\n\n"
        if sources.isEmpty {
            p += "No library excerpts matched this question.\n\n"
        } else {
            p += "Library search results (some may not fit their situation):\n"
            for (i, s) in sources.enumerated() {
                p += "[\(i + 1)] \(s.title) (\(s.source))\n\(s.text)\n\n"
            }
        }
        p += "Now answer their question: \(question)"
        return p
    }
}
