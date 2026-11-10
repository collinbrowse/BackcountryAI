import Foundation
import FoundationModels

/// Finds the library passages that actually answer a question. Keyword search alone matches words, not meaning
/// ("a power line is down in my yard" finds football articles), so the on-device model helps twice:
/// 1. it rewrites the question into searches phrased the way a manual or Q&A site would be, and
/// 2. it reads the best candidates and keeps only the ones that help answer this question.
enum Retrieval {
    @Generable
    struct SearchPlan {
        @Guide(description: "Two or three short keyword searches, 2 to 6 words each, in the words a first-aid "
            + "manual, repair guide, Q&A site or encyclopedia would use. Keep the specific thing named (snowmobile, "
            + "chainsaw, insulin) and add the technical term or synonym (bleeding: hemorrhage, tourniquet).",
            .count(2...3))
        var searches: [String]
    }

    @Generable
    struct Picks {
        @Guide(description: "The numbers of the excerpts that contain information that helps answer the question, "
            + "most useful first. Empty if none do.")
        var useful: [Int]
    }

    static let planInstructions = """
    You turn a person's question into keyword searches for an offline library of first-aid and survival manuals, \
    government safety guides, repair and outdoors Q&A, and Wikipedia.
    """

    static let pickInstructions = """
    You choose which library excerpts help answer a question. Pick an excerpt only if it contains information that \
    helps answer this exact question. An excerpt that shares a word but is about a different machine, place, \
    activity or topic does not help. It's fine to pick none.
    """

    /// The model's searches for a question. Empty if the model fails, so search falls back to the question alone.
    static func searches(for question: String, previous: String?, model: SystemLanguageModel) async -> [String] {
        var prompt = ""
        if let previous { prompt += "Their previous question, for context: \(previous)\n" }
        prompt += "Question: \(question)"
        let session = LanguageModelSession(model: model, instructions: planInstructions)
        let plan = try? await session.respond(to: prompt, generating: SearchPlan.self,
                                              options: GenerationOptions(temperature: 0))
        return plan?.content.searches.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
    }

    /// Up to `limit` passages from the question and the model's searches, merged by reciprocal rank fusion:
    /// a passage near the top of several searches beats one that tops a single search.
    static func candidates(question: String, searches: [String], library: Library, limit: Int = 8) -> [Passage] {
        var score: [Int64: Double] = [:]
        var byDoc: [Int64: Passage] = [:]
        for q in [question] + searches {
            for (i, p) in library.search(q, limit: 6, maxChars: 700).enumerated() {
                score[p.docID, default: 0] += 1 / Double(8 + i)
                if (byDoc[p.docID]?.coverage ?? -1) < p.coverage { byDoc[p.docID] = p }
            }
        }
        return byDoc.values.sorted { score[$0.docID]! > score[$1.docID]! }.prefix(limit).map { $0 }
    }

    /// The candidates the model judges useful, best first. If the model fails, the top candidates unfiltered.
    static func pick(question: String, from candidates: [Passage], model: SystemLanguageModel,
                     limit: Int = 4) async -> [Passage] {
        guard !candidates.isEmpty else { return [] }
        var prompt = "Question: \(question)\n\nExcerpts:\n"
        for (i, p) in candidates.enumerated() {
            prompt += "[\(i + 1)] \(p.title) (\(p.source)): \(p.text.prefix(320))\n\n"
        }
        prompt += "Which excerpts help answer the question?"
        let session = LanguageModelSession(model: model, instructions: pickInstructions)
        guard let picks = try? await session.respond(to: prompt, generating: Picks.self,
                                                     options: GenerationOptions(temperature: 0))
        else { return Array(candidates.prefix(limit)) }
        var out: [Passage] = []
        for n in picks.content.useful where (1...candidates.count).contains(n) {
            let p = candidates[n - 1]
            if !out.contains(where: { $0.docID == p.docID }) { out.append(p) }
        }
        return Array(out.prefix(limit))
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
