import Foundation
import FoundationModels
import os

let log = Logger(subsystem: "com.collinbrowse.backcountryai", category: "assistant")

/// Finds the library passages that actually answer a question. Keyword search alone matches words, not meaning
/// ("a power line is down in my yard" finds football articles), so the on-device model helps twice:
/// 1. it rewrites the question into searches phrased the way a manual or Q&A site would be, and
/// 2. it reads the best candidates and keeps only the ones that help answer this question.
enum Retrieval {
    // Both steps ask for plain text: Apple's guardrails reject guided generation (@Generable) for many medical
    // questions ("May contain sensitive content") but allow plain answers with permissive transformations.

    static let planInstructions = """
    First line: the kind of question, one word. FIX when something isn't working and they need to find out why \
    (an engine won't start, a stove won't light, a filter is slow, a radio has no signal). HOWTO when they want to \
    know what to do or how to do something. FACT when they want a fact or an explanation.
    Then you write keyword searches for an offline library of first-aid and survival manuals, government safety guides, \
    repair and outdoors Q&A, Wikipedia, and the person's own gear manuals. After the first line, write 2 or 3 searches, one per \
    line, 2 to 5 words each, and nothing else. Each search names the main subject of the question (the injury, machine, animal, weather or \
    task) plus words an article about it would use: the medical or technical name, or a common synonym. \
    Questions are often dictated, so a word that makes no sense may be a misheard brand: search for the kind of \
    product instead (a water filter, a stove).
    If the message asks for no information or help at all (a greeting, thanks, a reaction like "ok", a question \
    about you or how to use this app, or a request that has nothing to do with the outdoors, safety, gear or \
    vehicles), reply with only: CHAT
    Search for what the newest question asks. Earlier questions in the conversation only fill in what it leaves \
    out (the situation, the place, the gear); never search for an earlier topic again unless the newest question \
    asks about it. If they say they don't have something (a map, a compass, a signal, a first-aid kit), search for \
    ways to manage without it, not for the thing itself.
    """

    static let pickInstructions = """
    You check library excerpts for a field guide. For each excerpt write one line: its number, a few words on what \
    it is about, then YES if it helps with the task or question the person asked, or NO if it doesn't. Sharing a \
    word is not enough: an excerpt about 3D-printing a snowmobile part doesn't help someone add oil to a \
    snowmobile, and a football "line" doesn't help with a downed power line. An excerpt that answers part of the \
    question does help.
    """

    /// What a question needs: troubleshooting gets a different answer shape (checks in order, then one question).
    enum Kind: String, Codable, Sendable {
        case howTo = "HOWTO", troubleshoot = "FIX", fact = "FACT"

        /// A guess from the words alone, for when the model can't say.
        static func guess(_ question: String) -> Kind {
            let q = question.lowercased()
            let broken = /\b(won'?t|wont|isn'?t|is not|doesn'?t|does not|not|no longer|stopped|keeps|can'?t get)\b.{0,30}\b(start|starting|work|working|light|lighting|run|running|turn over|turning over|crank|cranking|charge|charging|fire|firing|flow|pump|pumping|connect|heat|heating|idle)/
            let symptom = /\b(dead|broken|leaking|sputters?|sputtering|stalls?|stalling|overheats?|overheating|clogged|flooded|no power|no spark|smoking|squeals?|grinding)\b/
            if q.contains(broken) || q.contains(symptom) { return .troubleshoot }
            if q.hasPrefix("what is") || q.hasPrefix("what's") || q.hasPrefix("why ") { return .fact }
            return .howTo
        }
    }

    struct Plan: Sendable {
        var kind: Kind
        var searches: [String]
    }

    /// The model's plan for a question: what kind it is and what to search for. Searches are empty if the model
    /// fails, so search falls back to the question alone. Nil when the message is small talk, with nothing to look up.
    static func plan(for question: String, history: [Turn], model: SystemLanguageModel) async -> Plan? {
        var prompt = ""
        if !history.isEmpty {
            prompt += "Earlier in the conversation, for context only:\n"
            prompt += history.map { "- \($0.question)" }.joined(separator: "\n") + "\n\n"
        }
        prompt += "Newest question (search for this): \(question)"
        let session = LanguageModelSession(model: model, instructions: planInstructions)
        guard let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                            maximumResponseTokens: 90))
        else { return Plan(kind: Kind.guess(question), searches: []) }
        if reply.content.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .uppercased() == "CHAT" { return nil }
        var kind: Kind?
        var searches: [String] = []
        for line in reply.content.split(whereSeparator: \.isNewline) {
            let bare = line.uppercased().replacing(/[^A-Z]/, with: "")
            if kind == nil, searches.isEmpty, let k = Kind(rawValue: bare.replacing(/^(TYPE|KIND)/, with: "")) {
                kind = k
                continue
            }
            if ["CHAT", "FIX", "FIXED", "HOWTO", "FACT"].contains(bare) { continue }  // a repeated label isn't a search
            // Tolerate "1. ", "- ", quotes and trailing periods.
            let s = line.replacing(/^\s*(\d+[.)]|[-*•])\s*/, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”. ").union(.whitespaces))
            if !s.isEmpty && s.count <= 60 { searches.append(s) }
        }
        // The words win when they clearly describe something broken: the model often calls those HOWTO.
        let guessed = Kind.guess(question)
        return Plan(kind: guessed == .troubleshoot ? .troubleshoot : (kind ?? guessed),
                    searches: Array(searches.prefix(3)))
    }

    /// Up to `limit` passages from the question and the model's searches, merged by reciprocal rank fusion:
    /// a passage near the top of several searches beats one that tops a single search.
    /// `dense` is the meaning-based search's list (SearchModels), fused as one more ranked list: it finds articles
    /// that answer the question in other words ("engine won't fire" for "snowmobile isn't starting").
    static func candidates(question: String, searches: [String], dense: [Passage] = [], library: Library,
                           limit: Int = 10) -> [Passage] {
        var score: [Int64: Double] = [:]
        var byDoc: [Int64: Passage] = [:]
        let lists = ([question] + searches).map { library.search($0, limit: 6, maxChars: 700) } + [dense]
        for list in lists {
            for (i, p) in list.enumerated() {
                score[p.docID, default: 0] += 1 / Double(8 + i)
                if (byDoc[p.docID]?.coverage ?? -1) < (p.coverage ?? 0) { byDoc[p.docID] = p }
            }
        }
        return byDoc.values.sorted { score[$0.docID]! > score[$1.docID]! }.prefix(limit).map { $0 }
    }

    /// Scores question–excerpt pairs from 0 (no help) to 1, in the excerpts' order; nil when it can't run.
    typealias Scorer = @Sendable (_ query: String, _ excerpts: [String]) async -> [Double]?

    /// The lowest reranker score that counts as helping. Set from a handful of questions with Qwen3-Reranker-0.6B,
    /// where on-topic articles scored 0.6 to 0.9 and off-topic ones under 0.1; scripts/check-answers.sh prints
    /// every score, so check it against library/questions.tsv on the full library, and again if the reranker changes.
    static let minimumRelevance = 0.3

    /// The excerpts worth giving the answer model, best first. With a reranker (a model trained only to judge
    /// whether a passage answers a question) every candidate gets a score and only those above the cutoff are kept;
    /// that replaces asking Apple's model YES or NO, which let topic-adjacent forum threads through.
    static func pick(question: String, history: [Turn] = [], from candidates: [Passage], model: SystemLanguageModel,
                     scorer: Scorer? = nil, limit: Int = 4) async -> [Passage] {
        guard !candidates.isEmpty else { return [] }
        let context = history.last.map { "\($0.question) " } ?? ""
        if let scorer, let scores = await scorer(context + question,
                                                 candidates.map { "\($0.title) (\($0.source))\n\($0.text.prefix(600))" }),
           scores.count == candidates.count {
            for (p, s) in zip(candidates, scores) { log.notice("rerank \(String(format: "%.2f", s)) \(p.title)") }
            return zip(candidates, scores).filter { $0.1 >= minimumRelevance }.sorted { $0.1 > $1.1 }
                .prefix(limit).map(\.0)
        }
        return await modelPick(question: question, history: history, from: candidates, model: model, limit: limit)
    }

    /// Without a reranker (the simulator, or before its download): Apple's model says YES or NO to each candidate.
    private static func modelPick(question: String, history: [Turn], from candidates: [Passage],
                                  model: SystemLanguageModel, limit: Int) async -> [Passage] {
        // Kept in search order. If the model fails, only candidates that matched every word of a search, since an
        // unchecked partial match is how off-topic articles got through.
        // A follow-up ("should I go uphill?") only makes sense with the situation it follows.
        var prompt = history.last.map { "Their situation (from an earlier question): \($0.question)\n" } ?? ""
        prompt += "Question: \(question)\n\nExcerpts:\n"
        for (i, p) in candidates.enumerated() {
            prompt += "[\(i + 1)] \(p.title) (\(p.source)): \(p.text.prefix(320))\n\n"
        }
        prompt += "One line per excerpt: number, what it's about, YES or NO."
        let session = LanguageModelSession(model: model, instructions: pickInstructions)
        guard let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                            maximumResponseTokens: 300))
        else {
            // The model couldn't check them (its guardrails refuse some medical prompts). Keep the candidates that
            // matched every word, or else the person's own documents that matched most of them: their manual is
            // why they added it, and dropping it leaves an emergency answer with no source at all.
            let exact = candidates.filter { ($0.coverage ?? 0) >= 0.99 }
            if !exact.isEmpty { return Array(exact.prefix(3)) }
            return Array(candidates.filter { $0.isMine && ($0.coverage ?? 0) >= 0.6 }.prefix(2))
        }
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
    emergencies. Answer the exact question the person asked. Only their own words describe their situation: what \
    they have, what they tried, where they are. Questions are often dictated, so a word that makes no sense may be \
    a misheard product or place name; work out what they meant.
    Answer like an expert guide, from what you know plus the library articles. The articles are search results \
    written by other people about other situations, vehicles and products. They never tell you what this person \
    has, where they are or what happened: never say "you have" anything that only appears in an article. Use only \
    the facts that fit their situation and cite them inline like [1]. When no article fits, answer from what you \
    know.
    Open with one sentence that answers the question. Then, if there is something to do, give only the numbered \
    steps this situation needs, one sentence each, with no sub-points. Two to four steps is typical; never add a \
    step just to have more, and never more than five. Be concrete (amounts, times, sizes, what to look for). \
    Stop after the last step: no closing note, summary or disclaimer.
    If you don't know a specific fact (a model's oil type, a dose, whether a plant is edible), say so in one \
    sentence instead of making it up. Don't list things you don't know about their situation.
    If none of the excerpts helped, start the answer with "Not from the library:". Never end with that phrase.
    You have no internet: no live weather, forecasts, news, maps or locations. If they ask for those, say so in one \
    sentence, give what general guidance fits, and suggest saving a forecast or map (a screenshot or PDF) to Your \
    documents in the Offline library before they lose signal, so you can read it later.
    Only when the question describes someone hurt, sick or in danger right now: make the urgent first action and \
    calling or texting 911 or using an SOS/satellite messenger the first sentence and step. Otherwise never mention \
    911, SOS or emergency help.
    In a follow-up, answer only the new question. Don't repeat or reword what you already told them. If they say \
    they don't have something or a step didn't work, never suggest it again: work with what they have.
    """

    /// One earlier question and Scout's answer, for follow-ups.
    struct Turn: Sendable {
        let question: String
        let answer: String
    }

    /// The extra shape for troubleshooting answers: what to check, in order, then one question that narrows it down.
    static let troubleshootShape = """
    This is troubleshooting: something isn't working and they need to find out why. Open with one sentence naming \
    the most likely causes for exactly their situation. Then numbered checks, the quickest and most likely first: \
    each one says what to check and what to do about it. Skip anything they've already ruled out. End with a line \
    that starts "Ask:", one short question whose answer would narrow it down most, then 2 or 3 short possible \
    answers in square brackets separated by "|". Example: Ask: Does the engine turn over? [Yes, it cranks | No, \
    nothing happens | It just clicks]
    """

    static func prompt(question: String, sources: [Passage], history: [Turn], kind: Kind = .howTo) -> String {
        // Their words and the library's are kept apart and labelled, so a small model doesn't mistake an article's
        // subject (a "choke lever" in a title) for something they have. The question comes first and last: a small
        // model otherwise drifts to whatever the articles are about.
        var p = "WHAT THEY TOLD YOU (only this describes their situation):\n"
        if !history.isEmpty {
            for (i, t) in history.enumerated() {
                let room = i == history.count - 1 ? 500 : 240  // the latest answer matters most
                p += "Earlier they asked: \(t.question)\nYou answered (shortened): \(t.answer.prefix(room))\n"
            }
            p += "This is a follow-up. Answer the new question; don't repeat what you already said.\n"
        }
        p += "Their question: \(question)\n\n"
        if sources.isEmpty {
            p += "LIBRARY ARTICLES: none matched this question.\n\n"
        } else {
            p += "LIBRARY ARTICLES (about other people's situations; use only what fits theirs):\n"
            for (i, s) in sources.enumerated() {
                p += "[\(i + 1)] \(s.title) (\(s.source))\n\(s.text)\n\n"
            }
        }
        if kind == .troubleshoot { p += troubleshootShape + "\n\n" }
        p += "Now answer their question: \(question)"
        return p
    }
}

/// The question a troubleshooting answer ends with ("Ask: Does it crank? [Yes | No]"): the options become tap-to-answer
/// chips and come out of the text. Works on a partial answer too, so the brackets never flash while it streams.
enum Clarify {
    static func split(_ text: String) -> (text: String, choices: [String]) {
        var lines = text.components(separatedBy: "\n")
        guard let i = lines.lastIndex(where: isAsk) else { return (text, []) }
        var line = lines[i].replacing(/^\s*[*_]*\s*[Aa][Ss][Kk]\s*:\s*[*_]*\s*/, with: "")
        var choices: [String] = []
        var closed = false
        // The options are the last bracket that isn't a citation like [1] or [2, 3].
        if let open = line.lastIndex(of: "["),
           line[open...].wholeMatch(of: /\[\s*\d{1,2}(\s*,\s*\d{1,2})*\s*\][.?!\s]*/) == nil {
            let inside = line[line.index(after: open)...]
            closed = inside.contains("]")
            choices = inside.replacing("]", with: "").split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "*_."))) }
                .filter { !$0.isEmpty && $0.count <= 40 }
            line = String(line[..<open]).trimmingCharacters(in: .whitespaces)
        }
        lines[i] = line
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Options only count once the answer has finished writing them.
        return (body, closed && choices.count >= 2 ? Array(choices.prefix(3)) : [])
    }

    private static func isAsk(_ line: String) -> Bool {
        line.contains(/^\s*[*_]*\s*[Aa][Ss][Kk]\s*:/)
    }
}
