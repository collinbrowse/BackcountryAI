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

    /// The planner's reply is read by `parsePlan`. Labelled lines and two worked examples: asked in a paragraph
    /// for "the kind on the first line, then searches", Apple's model gave a usable reply for 50 of 130 test
    /// messages (the label ran into the first search, or it wrote "Search for:" lines); with this, for 126.
    /// A longer version with a third example and finer rules did worse: it called a bleeding arm FIX.
    static let planInstructions = """
    You plan searches of an offline library for a field guide app. The library holds first-aid and survival \
    manuals, government safety guides, repair and outdoors Q&A, Wikipedia's medical articles, and the person's own \
    gear manuals.
    Reply with these lines and nothing else:
    KIND: FIX, HOWTO or FACT
    SEARCH: 2 to 5 lowercase keywords
    SEARCH: 2 to 5 lowercase keywords
    SEARCH: 2 to 5 lowercase keywords
    KIND is FIX when a machine or piece of gear isn't working and they need to find out why (an engine won't \
    start, a stove won't light, a filter is slow, a radio has no signal). It is HOWTO when they want to know what \
    to do or how to do something, including any injury, illness or danger. It is FACT when they want a fact or an \
    explanation.
    Each SEARCH names the main subject of the question (the injury, machine, animal, weather or task) plus words an \
    article about it would use: the medical or technical name, or a common synonym. Questions are often dictated, \
    so a word that makes no sense may be a misheard brand: search for the kind of product instead (a water \
    filter, a stove).
    If the message asks for no information or help at all (a greeting, thanks, a reaction like "ok", a question \
    about you or how to use this app, or a request that has nothing to do with the outdoors, safety, gear or \
    vehicles), reply with only: CHAT
    Search for what the newest question asks. Earlier questions in the conversation only fill in what it leaves \
    out (the situation, the place, the gear); never search for an earlier topic again unless the newest question \
    asks about it. If they say they don't have something (a map, a compass, a signal, a first-aid kit), search for \
    ways to manage without it, not for the thing itself.
    Two examples.
    Newest question (search for this): my buddy got stung and his lips are swelling up
    KIND: HOWTO
    SEARCH: anaphylaxis first aid
    SEARCH: allergic reaction insect sting
    SEARCH: epinephrine swelling breathing
    Newest question (search for this): the chainsaw bogs down when I give it gas
    KIND: FIX
    SEARCH: chainsaw bogs under throttle
    SEARCH: two-stroke carburetor adjustment
    SEARCH: clogged fuel filter small engine
    """

    /// What a question needs: troubleshooting gets a different answer shape (checks in order, then one question).
    enum Kind: String, Codable, Sendable {
        case howTo = "HOWTO", troubleshoot = "FIX", fact = "FACT"

        /// The planner's label, in the spellings it uses.
        init?(label: String) {
            switch label.uppercased().replacing(/[^A-Z]/, with: "") {
            case "FIX", "FIXED": self = .troubleshoot
            case "HOWTO": self = .howTo
            case "FACT": self = .fact
            default: return nil
            }
        }

        /// Something that worked has stopped: "won't start", "isn't charging", "keeps stalling".
        private static var stoppedWorking: some RegexComponent {
            /\b(won't|wont|isn't|is not|doesn't|does not|not|no longer|stopped|keeps|can't get)\b.{0,30}\b(start|starting|work|working|light|lighting|run|running|turn over|turning over|crank|cranking|charge|charging|fire|firing|flow|pump|pumping|connect|heat|heating|idle)/
        }
        /// A fault named by how it looks or sounds.
        private static var symptom: some RegexComponent {
            /\b(dead|broken|leaking|sputters?|sputtering|stalls?|stalling|overheats?|overheating|clogged|flooded|no power|no spark|smoking|squeals?|grinding)\b/
        }
        /// An injury: a broken leg is not a broken stove.
        private static var injury: some RegexComponent {
            /\b(sprain\w*|splint\w*|fractur\w*|dislocat\w*|injur\w*|wound\w*|bone)\b|\bbroken\s+(\w+\s+){0,2}(leg|arm|ankle|wrist|rib|nose|finger|toe|hip|collarbone|tooth|foot|hand|jaw|knee|shoulder|elbow|neck|back)\b|\b(leg|arm|ankle|wrist|rib|nose|finger|toe|hip|collarbone|tooth|foot|hand|jaw|knee|shoulder|elbow|neck|back)\b.{0,20}\bbroken\b/
        }
        /// Someone, or an animal, is the subject.
        private static var person: some RegexComponent {
            /\b(he|she|him|her|his|someone|somebody|anyone|friend|buddy|partner|kid|child|baby|son|daughter|wife|husband|mom|dad|dog|puppy|horse|patient|hiker|climber|skier|person)\b/
        }
        /// A machine or a piece of gear is named.
        private static var gear: some RegexComponent {
            /\b(engine|motor|truck|car|jeep|suv|van|vehicle|rv|camper|trailer|snowmobile|sled|atv|utv|quad|dirt ?bike|motorcycle|bike|e-?bike|boat|outboard|generator|chainsaw|saw|mower|stove|burner|jet ?boil|whisperlite|pocket ?rocket|lantern|heater|furnace|pump|filter|purifier|steripen|radio|baofeng|walkie|gps|garmin|inreach|beacon|transceiver|plb|phone|battery|charger|power ?bank|solar panel|headlamp|flashlight|zipper|winch|starter|alternator|carburetor|carb|spark plug|ignition|compass|inverter|fridge|cooler)s?\b/
        }
        /// They know what's wrong and ask for the repair: "how do I patch a flat tire", "how to replace a spark plug".
        private static var askedHow: some RegexComponent {
            /\bhow (do|can|should|would) (i|we|you)\b|\bhow to\b|\bbest way to\b/
        }

        private static func normal(_ question: String) -> String {
            question.lowercased().replacing(/[’‘]/, with: "'")
        }

        /// Whether the message asks how to do something ("how do I…", "best way to…").
        static func asksHow(_ question: String) -> Bool { normal(question).contains(askedHow) }

        /// Whether the words are about a body, not a machine: an injury, or someone named with no gear in sight
        /// ("he isn't breathing right after the heat" has "isn't" and "heat", and is not a broken heater).
        private static func aboutABody(_ q: String) -> Bool {
            q.contains(injury) || (q.contains(person) && !q.contains(gear))
        }

        /// The same, for `Urgency`: "broken", "dying" and "severe" mean an emergency only when said of someone.
        static func isAboutABody(_ question: String) -> Bool { aboutABody(normal(question)) }

        /// A guess from the words alone, for when the model can't say.
        static func guess(_ question: String) -> Kind {
            let q = normal(question)
            if !aboutABody(q) {
                if q.contains(stoppedWorking) { return .troubleshoot }
                // "Broken" or "leaking" names a fault, but "how do I repair a broken tent pole" already knows
                // what is wrong: it wants the repair, not a list of causes.
                if q.contains(symptom) && !q.contains(askedHow) { return .troubleshoot }
            }
            if q.hasPrefix("what is") || q.hasPrefix("what's") || q.hasPrefix("why ") { return .fact }
            return .howTo
        }

        /// The kind to answer with: the words, then the planner's label, then the conversation.
        /// - Parameters:
        ///   - model: the planner's label, if it gave one.
        ///   - previous: the kind of the turn before, in a follow-up.
        static func decide(question: String, model: Kind?, previous: Kind? = nil, isFollowUp: Bool = false) -> Kind {
            // The words win when they clearly describe something that stopped working: the model often calls
            // those HOWTO.
            let guessed = guess(question)
            if guessed == .troubleshoot { return .troubleshoot }
            guard model == .troubleshoot else { return model ?? guessed }
            // The model also says FIX for repairs they asked how to do, for injuries, and for follow-ups of every
            // sort ("I've got a lighter but no fire starters"). Believe it when the message names a machine or
            // gear, or follows up inside a troubleshooting conversation.
            let q = normal(question)
            let believable = !q.contains(askedHow) && !aboutABody(q)
                && (isFollowUp ? previous == .troubleshoot : q.contains(gear))
            return believable ? .troubleshoot : .howTo
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
        let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                      maximumResponseTokens: 90))
        func kind(_ label: Kind?) -> Kind {
            Kind.decide(question: question, model: label, previous: history.last?.kind, isFollowUp: !history.isEmpty)
        }
        guard let reply else { return Plan(kind: kind(nil), searches: []) }
        guard let parsed = parsePlan(reply.content) else { return nil }
        return Plan(kind: kind(parsed.kind), searches: parsed.searches)
    }

    /// Reads the planner's reply: its label and up to three searches. Nil when the reply is CHAT (small talk).
    /// It is written for the labelled lines the instructions ask for ("KIND: FIX", "SEARCH: …") and for what
    /// Apple's model writes when it doesn't follow them: the label run into a search ("FACT freezer temperature"),
    /// an invented label on its own line ("FIXTURE"), "Search for:" lines, numbered lists, three searches on one
    /// line with commas. Left in, each of those was searched for: "FIXTURE" found shower fixtures.
    static func parsePlan(_ reply: String) -> (kind: Kind?, searches: [String])? {
        let lines = reply.split(whereSeparator: \.isNewline)
            .map { $0.replacing(/[*_`#]+/, with: "").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).uppercased() == "CHAT" {
            return nil
        }
        var kind: Kind?
        var searches: [String] = []
        for (i, raw) in lines.enumerated() {
            var line = raw.replacing(/^\s*(\d+[.)]|[-•])\s*/, with: "")
            if let m = line.firstMatch(of: /^(?i:kind|type)\s*[:=]\s*([A-Za-z-]+)/) {
                kind = kind ?? Kind(label: String(m.1))
                continue
            }
            var labelled = false
            if let m = line.firstMatch(of: /^(?i:search|query|keywords?)\s*\d*\s*[:=]\s*(.*)$/) {
                line = String(m.1)
                labelled = true
            }
            // A label alone on a line, or stuck to the front of a search: "FIX. Battery connection".
            if let m = line.firstMatch(of: /^(FIX(?:ED)?|HOW-?TO|FACT|CHAT)\b[\s.:-]*(.*)$/) {
                kind = kind ?? Kind(label: String(m.1))
                line = String(m.2)
            }
            // Words about searching, not searches: "Search for:", "Keyword searches:", "medical name:".
            line = line.replacing(/(?i)\b(keyword )?search(es|s)?( for)?\s*:|\b(medical|technical|common) (name|term)\s*:/, with: " ")
            // An invented one-word label on the first line: "FIXTURE", "TOOL", "PROBLEM".
            if !labelled, i == 0, lines.count > 1, line.wholeMatch(of: /[A-Z]{3,}[.:]?/) != nil { continue }
            // "a b, c d, e f" on one line is three searches; a lone word among them is dropped.
            var pieces = line.split(separator: ",").map(searchWords).filter { !$0.isEmpty }
            if pieces.contains(where: { $0.contains(" ") }) {
                pieces.removeAll { !$0.contains(" ") }
            } else if pieces.count > 1 {
                pieces = [pieces.joined(separator: " ")]
            }
            for s in pieces where s.count <= 60 && s.split(separator: " ").count <= 7 && !searches.contains(s) {
                searches.append(s)
            }
        }
        return (kind, Array(searches.prefix(3)))
    }

    /// A search as plain lowercase words: quotes, brackets and sentence punctuation removed.
    private static func searchWords(_ text: some StringProtocol) -> String {
        text.lowercased().replacing(/[^\p{L}\p{N}'’-]+/, with: " ").split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-'’")) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// How much of a passage an excerpt may hold. Passages are cut at about 1,500 characters when the library is
    /// built, so this is nearly always the whole passage.
    static let excerptCharacters = 1_500
    /// How many passages each keyword search and the meaning search give, and how many candidates come of them
    /// (`net`) for the ranker to order. With 6, 8 and 10 an excerpt that answers the question was among the
    /// candidates for 56% of the test questions; with 12, 16 and 20 for 77% (and for 67% of the long-tail ones).
    static let perKeywordSearch = 12
    static let perMeaningSearch = 16
    static let net = 20
    /// How many passages one article may give to the candidates.
    static let passagesPerArticle = 2
    /// What an article's second passage keeps of its score: it comes after other articles' best passages unless it
    /// is found by several searches itself.
    static let secondPassageShare = 0.6
    /// How much of what an article's other passages scored counts toward each of its passages.
    static let articleShare = 0.5

    /// Up to `limit` passages from the question and the model's searches, merged by reciprocal rank fusion:
    /// a passage near the top of several searches beats one that tops a single search.
    /// `dense` is the meaning-based search's list (SearchModels), fused as one more ranked list: it finds articles
    /// that answer the question in other words ("engine won't fire" for "snowmobile isn't starting").
    /// In a follow-up, `context` is the question before it plus this one, searched as one more list, and `carried`
    /// is what the last answer was written from: "he's stopped shivering" alone finds articles on alcohol, and the
    /// planner's searches for it did too.
    ///
    /// Three rules here were chosen by trying them on everything the searches found for 142 test questions and
    /// having every excerpt judged (`scout-tools pool`, tools/grade-answers/pool_eval.py, docs/answer-quality.md).
    /// The share of questions with an excerpt among the first four that answers them:
    /// - 20% with one 700-character window per article, as it was;
    /// - 35% with the passage whole (`excerptCharacters`): a window cut procedures off mid-step;
    /// - 41% with a forum thread shown by its best answer and not by the question that matched
    ///   (`Library.bestAnswer`);
    /// - 44% with two passages allowed from one article, the second ranked lower (`passagesPerArticle`,
    ///   `secondPassageShare`): a manual's chapter and a long medical article are each one article. For medical
    ///   questions that was 20 of 47 against 13.
    /// Three passages an article and more hits per search made no difference worth having. Weighting field
    /// sources up and household forums down moved four more questions' answers into the first four.
    static func candidates(question: String, searches: [String], dense: [Passage] = [], context: String? = nil,
                           carried: [Passage] = [], library: Library, limit: Int = 10) -> [Passage] {
        let found = signalled(question: question, searches: searches, dense: dense, context: context,
                              carried: carried, library: library, limit: max(net, limit))
        return Ranker.ordered(found).prefix(limit).map(\.passage)
    }

    /// A candidate with what search knows about it before anything reads it (`Signals`).
    struct Candidate: Sendable {
        let passage: Passage
        let signals: Signals
    }

    /// The candidates in rank-fusion order, each with its signals. `candidates` orders them with `Ranker`;
    /// `scout-tools pool` saves them so the ranker's weights can be fitted to judged excerpts.
    /// - Parameter perSearch: how many passages each keyword search gives.
    static func signalled(question: String, searches: [String], dense: [Passage] = [], context: String? = nil,
                          carried: [Passage] = [], library: Library, perSearch: Int = perKeywordSearch,
                          limit: Int = 10) -> [Candidate] {
        let keyword = [question] + searches + [context].compactMap { $0 }
        let keywordLists = keyword.map {
            library.search($0, limit: perSearch, maxChars: excerptCharacters, perArticle: passagesPerArticle, whole: true)
        }
        let lists = keywordLists + [dense, carried]
        // Each passage's own score, and the passage itself (the copy that covers most of its search's words).
        var own: [Int64: Double] = [:]
        var byID: [Int64: Passage] = [:]
        for list in lists {
            for (i, p) in list.enumerated() {
                own[p.id, default: 0] += 1 / Double(8 + i)
                if (byID[p.id]?.coverage ?? -1) < (p.coverage ?? 0) { byID[p.id] = p }
            }
        }
        var article: [Int64: Double] = [:]
        for (id, value) in own { article[byID[id]!.docID, default: 0] += value }
        func score(_ id: Int64) -> Double { own[id]! + articleShare * (article[byID[id]!.docID]! - own[id]!) }
        func before(_ a: (Int64, Double), _ b: (Int64, Double)) -> Bool {
            a.1 != b.1 ? a.1 > b.1 : own[a.0]! != own[b.0]! ? own[a.0]! > own[b.0]! : a.0 < b.0
        }
        // An article's second passage keeps part of its score, then everything is ranked again.
        var seen: [Int64: Int] = [:]
        let ranked = own.keys.map { ($0, score($0)) }.sorted(by: before).map { id, value -> (Int64, Double) in
            let nth = seen[byID[id]!.docID, default: 0]
            seen[byID[id]!.docID] = nth + 1
            return (id, nth == 0 ? value : value * secondPassageShare)
        }.sorted(by: before)
        // The words a passage is checked for: this message's first, then the earlier message's. (Together as one
        // text the first twelve are nearly all the earlier message's, and "should I pop the blisters?" after a
        // long account of the burn was ranked by the account alone.)
        var words = Library.queryWords(question)
        for word in Library.queryWords(context ?? "") where !words.contains(word) && words.count < 16 { words.append(word) }
        var out: [Candidate] = [], taken: [Int64: Int] = [:], shown = Set<Int64>()
        for (id, _) in ranked {
            let hit = byID[id]!
            guard taken[hit.docID, default: 0] < passagesPerArticle else { continue }
            let passage = library.bestAnswer(for: hit, maxChars: excerptCharacters)
            guard shown.insert(passage.id).inserted else { continue }
            // Where the searches found it: the hit, which for a forum thread may be the question it was found by.
            var places = keywordLists.compactMap { list in list.firstIndex { $0.id == id } }
            var densePlace = dense.firstIndex { $0.id == id }
            var coverage = hit.coverage ?? 0
            // What the last answer was written from was found for the message before this one, so this
            // message's searches may not find it again, and with no place in any of them the ranker would drop
            // it: 13 of 29 follow-ups kept an answering excerpt, against 18 when Apple's model chose. It is
            // scored as if a search had found it a quarter of the way down, with the share of the words of both
            // messages it holds: what it says still has to fit.
            if places.isEmpty, densePlace == nil, carried.contains(where: { $0.id == id }) {
                places = [perSearch / 4]
                densePlace = max(dense.count, 1) / 4
                let text = passage.text.lowercased()
                coverage = words.isEmpty ? 0 : Double(words.filter { text.contains($0) }.count) / Double(words.count)
            }
            out.append(Candidate(passage: passage, signals: Signals(
                position: out.count, of: limit, keywordPlaces: places, keywordSearches: keywordLists.count,
                perSearch: perSearch, densePlace: densePlace, denseCount: max(dense.count, 1),
                coverage: coverage, words: words, passage: passage,
                isSecond: taken[hit.docID, default: 0] > 0)))
            taken[hit.docID, default: 0] += 1
            if out.count >= limit { break }
        }
        return out
    }

    /// What search knows about a candidate without reading it, as numbers between 0 and 1. `Ranker` weighs them.
    struct Signals: Sendable {
        static let names = ["position", "searches", "keyword_place", "dense_place", "coverage", "title_words",
                            "text_words", "forum", "household", "field", "answer_score", "second", "length"]
        /// In the order of `names`.
        let values: [Double]

        init(position: Int, of limit: Int, keywordPlaces: [Int], keywordSearches: Int, perSearch: Int,
             densePlace: Int?, denseCount: Int, coverage: Double, words: [String], passage: Passage, isSecond: Bool) {
            let title = passage.title.lowercased(), text = passage.text.lowercased()
            func share(in body: String) -> Double {
                words.isEmpty ? 0 : Double(words.filter { body.contains($0) }.count) / Double(words.count)
            }
            // A forum answer says how it was voted: "Answer by Ryley (score 10, accepted) …".
            let votes = passage.text.prefixMatch(of: /Answer(?: by [^()]{1,60})? \(score (-?\d+)/).flatMap { Double($0.1) } ?? 0
            values = [
                Double(position) / Double(max(limit, 1)),                        // place in rank-fusion order
                Double(keywordPlaces.count) / Double(max(keywordSearches, 1)),   // share of the keyword searches that found it
                Double(keywordPlaces.min() ?? perSearch) / Double(max(perSearch, 1)),  // its best place in one (1 = in none)
                Double(densePlace ?? denseCount) / Double(denseCount),           // its place in the meaning search (1 = not there)
                coverage,                                                        // share of a search's words it holds
                share(in: title), share(in: text),                               // share of the question's words in each
                passage.sourceKey.hasPrefix("se-") ? 1 : 0,
                Library.household.contains(passage.sourceKey) ? 1 : 0,
                Library.field.contains(passage.sourceKey) ? 1 : 0,
                Foundation.log(1 + max(votes, 0)) / 5,
                isSecond ? 1 : 0,                                                // an article's second passage
                Double(min(passage.text.count, excerptCharacters)) / Double(excerptCharacters),
            ]
        }
    }

    /// Orders the candidates by a weighted sum of their signals. The weights are fitted offline to excerpts the
    /// judge has scored (tools/grade-answers/fit_ranker.py reads the signals `scout-tools pool` saves), so that
    /// the excerpts most likely to answer the question come first. Without weights the order is rank fusion's.
    enum Ranker {
        /// One weight per `Signals.names`, and the constant term; nil for rank fusion's order. Fitted 2026-11-16
        /// to 5,420 judged candidates of 271 questions (the test questions, every conversation turn, and
        /// library/questions-longtail.tsv). What weighs most: how many of the question's words the passage holds,
        /// its place in the meaning search, and how many of the keyword searches found it.
        static let weights: [Double]? = [-0.321, 0.437, 0.296, -0.591, 0.390, 0.288, 1.047, -0.053, -0.227, 0.162,
                                         0.123, 0.310, 0.161]
        static let constant = 0.570

        /// The judge's score this candidate is expected to get, 0 (unrelated) to 3 (answers it).
        static func score(_ signals: Signals) -> Double? {
            guard let weights, weights.count == signals.values.count else { return nil }
            return zip(weights, signals.values).reduce(constant) { $0 + $1.0 * $1.1 }
        }

        /// The lowest score worth giving the answer model. At 1.0 ("a near miss") a question keeps 3.6 of its
        /// 4 best candidates on average and about one question in 50 keeps none.
        static let minimum = 1.0
        /// Added for a passage of a document the person put in themselves: it is there because they wanted it
        /// used. Not measured: no test question has a document of its own.
        static let ownDocument = 0.5

        static func value(_ candidate: Candidate) -> Double {
            (score(candidate.signals) ?? 0) + (candidate.passage.isMine ? ownDocument : 0)
        }

        static func ordered(_ candidates: [Candidate]) -> [Candidate] {
            guard weights != nil else { return candidates }
            return candidates.enumerated().sorted {
                let a = value($0.element), b = value($1.element)
                return a != b ? a > b : $0.offset < $1.offset
            }.map(\.element)
        }

        /// The excerpts to write the answer from: the best `limit` of the ordered candidates that reach `minimum`.
        /// - Parameter cutoff: off when meaning search didn't run (the simulator, a library without vectors):
        ///   every score is then lower by what that signal would have added.
        static func keep(_ ordered: [Candidate], limit: Int = 4, cutoff: Bool = true) -> [Candidate] {
            guard weights != nil else { return Array(ordered.prefix(limit)) }
            return Array(ordered.filter { !cutoff || value($0) >= minimum }.prefix(limit))
        }
    }

    /// Scores question–excerpt pairs from 0 (no help) to 1, in the excerpts' order; nil when it can't run.
    typealias Scorer = @Sendable (_ query: String, _ excerpts: [String]) async -> [Double]?

    /// The lowest reranker score that counts as helping. Set from a handful of questions with Qwen3-Reranker-0.6B,
    /// where on-topic articles scored 0.6 to 0.9 and off-topic ones under 0.1; scripts/check-answers.sh prints
    /// every score, so check it against library/questions.tsv on the full library, and again if the reranker changes.
    static let minimumRelevance = 0.3

    /// The candidates a reranker scores at `minimumRelevance` or more, best first; nil when it can't run. A
    /// reranker is a model trained only to judge whether a passage answers a question (SearchModels); a library
    /// pack may carry one. Measured on 129 long-tail questions, Qwen3-Reranker-0.6B put an answering excerpt in
    /// the answer's four for 57% against the ranker's 53%, with less noise (45% of excerpts against 52%): not much
    /// for 1.2 GB, so the released pack has none and the ranker chooses.
    static func rerank(question: String, history: [Turn] = [], candidates: [Passage], scorer: Scorer,
                       limit: Int = 4) async -> (kept: [Passage], scores: [Double])? {
        guard !candidates.isEmpty else { return ([], []) }
        let asked = situation(question, history: history) ?? question
        let words = Library.queryWords(asked)
        guard let scores = await scorer(asked, candidates.map {
            "\($0.title) (\($0.source))\n\(Library.window($0.text, words: words, width: 600))"
        }), scores.count == candidates.count else { return nil }
        for (p, s) in zip(candidates, scores) { log.notice("rerank \(String(format: "%.2f", s)) \(p.title)") }
        return (zip(candidates, scores).filter { $0.1 >= minimumRelevance }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0),
                scores)
    }

    static let pickInstructions = """
    You check library excerpts for a field guide. For each excerpt write one line: its number, a few words on what \
    it is about, then YES if it helps with the task or question the person asked, or NO if it doesn't. Sharing a \
    word is not enough: an excerpt about 3D-printing a snowmobile part doesn't help someone add oil to a \
    snowmobile, and a football "line" doesn't help with a downed power line. An excerpt that answers part of the \
    question does help.
    """

    /// Apple's model says YES or NO to each candidate; those it says yes to, in the order given. Nil when the
    /// model can't say (its guardrails refuse some medical prompts, and it fails outright when memory is short).
    ///
    /// The ranker orders candidates by what search knows of them, and words in common are most of that: left to
    /// choose alone it handed a cooking thread ("when a recipe asks you to add…") to someone adding oil to a
    /// snowmobile. Reading is what tells those apart, so the model reads the ranker's first ten.
    static func modelPick(question: String, history: [Turn], from candidates: [Passage],
                          model: SystemLanguageModel) async -> [Passage]? {
        guard !candidates.isEmpty else { return [] }
        // A follow-up ("should I go uphill?") only makes sense with the situation it follows.
        var prompt = earlier(in: history).map { "Their situation (from an earlier question): \($0)\n" } ?? ""
        prompt += "Question: \(question)\n\nExcerpts:\n"
        // The part of each passage around the question's words: a whole passage is too much to read ten of.
        let words = Library.queryWords(situation(question, history: history) ?? question)
        for (i, p) in candidates.enumerated() {
            prompt += "[\(i + 1)] \(p.title) (\(p.source)): \(Library.window(p.text, words: words, width: 320))\n\n"
        }
        prompt += "One line per excerpt: number, what it's about, YES or NO."
        let session = LanguageModelSession(model: model, instructions: pickInstructions)
        guard let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                            maximumResponseTokens: 300))
        else { return nil }
        var helps = Set<Int>()
        for line in reply.content.split(whereSeparator: \.isNewline) {
            guard let m = line.firstMatch(of: /^\W*(\d+)/), let n = Int(m.1), (1...candidates.count).contains(n)
            else { continue }
            let said = line.uppercased().split(whereSeparator: { !$0.isLetter })
            if said.last(where: { $0 == "YES" || $0 == "NO" }) == "YES" { helps.insert(n) }
        }
        return candidates.enumerated().filter { helps.contains($0.offset + 1) }.map(\.element)
    }

    // MARK: - The whole search

    /// What retrieval decided for one question, with enough detail for logs and scripts/check-answers.sh.
    struct Found: Sendable {
        var kind: Kind
        /// The excerpts for the answer model, best first.
        var sources: [Passage] = []
        /// The message is small talk: there is nothing to look up.
        var isChat = false
        /// The excerpts are the last answer's own, because the question is about that answer.
        var reusedLastSources = false
        var searches: [String] = []
        var dense: [Passage] = []
        var candidates: [Passage] = []
        /// Each candidate's score: the ranker's (0 to 3, `Ranker.minimum` to be kept), or a reranker model's
        /// (0 to 1, `minimumRelevance` to be kept) when the library has one (`reranked`).
        var scores: [Double]? = nil
        var reranked = false
        var planSeconds = 0.0, searchSeconds = 0.0, pickSeconds = 0.0, cardSeconds = 0.0
        /// The field cards that fit the question (usually one): they are the first sources.
        var cards: [String] = []
    }

    /// How many library excerpts go with a field card. The card is the answer; the excerpts add what it leaves out.
    static let cardCompanions = 2

    /// Asks Apple's model whether a field card fits a message (CardMatcher's second step). Nil when it won't say.
    static func confirmCard(_ card: FieldCard, question: String, earlier: String?, model: SystemLanguageModel) async -> Bool? {
        let session = LanguageModelSession(model: model, instructions: CardMatcher.confirmInstructions)
        let prompt = CardMatcher.confirmPrompt(card, question: question, earlier: earlier)
        guard let reply = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0,
                                                                                         maximumResponseTokens: 5))
        else { return nil }
        return CardMatcher.readConfirmation(reply.content)
    }

    /// Finds the excerpts for one question the way the app does: plan, search, rank. The app (Assistant) and
    /// `scout-tools check` both call this, so the check measures what ships.
    /// - Parameters:
    ///   - dense, rerank: off only in the check tool, to measure what each adds.
    ///   - onPicking: called when searching is done and the candidates are being read.
    @MainActor
    static func find(question: String, history: [Turn], library: Library, model: SystemLanguageModel,
                     dense useDense: Bool = true, rerank: Bool = true,
                     onPicking: @MainActor () -> Void = {}) async -> Found {
        var found = Found(kind: Kind.guess(question))
        // "Explain step 1 more" has nothing to search for: it is answered from what the last answer was written
        // from, with that answer in the prompt, and skips the planner and the picker.
        if let last = history.last, asksAboutLastAnswer(question) {
            found.kind = .howTo
            found.sources = last.sources
            found.reusedLastSources = true
            return found
        }
        var clock = Date()
        func lap() -> Double {
            defer { clock = Date() }
            return Date().timeIntervalSince(clock)
        }
        guard let plan = await plan(for: question, history: history, model: model) else {
            found.isChat = true
            return found
        }
        found.kind = plan.kind
        found.searches = plan.searches
        found.planSeconds = lap()
        // A follow-up is searched together with what they said before, so "should I go uphill?" still knows
        // they're lost; what the last answer was written from stays in the running too. "Tell me more" is the
        // exception: it wants what the last answer didn't have, so those excerpts are left out.
        let context = situation(question, history: history)
        let more = !history.isEmpty && asksForMore(question)
        let used = Set((history.last?.sources ?? []).map(\.docID))
        let carried = more ? [] : history.last?.sources ?? []
        let denseHits = useDense ? await SearchModels.shared.denseSearch(
            context ?? question, library: library, limit: perMeaningSearch, perArticle: passagesPerArticle,
            whole: true, maxChars: excerptCharacters) : []
        found.dense = denseHits
        // The ranker orders everything the searches found (`net` candidates); Apple's model reads the first ten
        // and says yes or no to each; the first four it says yes to are the answer's excerpts. (Docs: "Choosing
        // excerpts". The ranker's own best four had an answering excerpt more often, 53% of long-tail questions
        // against 47%, but more excerpts that only share the question's words, and both answer models wrote
        // worse answers from them: 2.55 to 2.37 overall for Qwen.)
        let ranked = await Task.detached(priority: .userInitiated) {
            Ranker.ordered(Retrieval.signalled(question: question, searches: plan.searches, dense: denseHits,
                                               context: context, carried: carried, library: library,
                                               limit: more ? net + used.count : net))
                .filter { !more || !used.contains($0.passage.docID) }
        }.value
        found.candidates = ranked.prefix(10).map(\.passage)
        found.scores = ranked.prefix(10).map(Ranker.value)
        found.searchSeconds = lap()
        onPicking()
        if rerank, let scorer = SearchModels.shared.scorer,
           let judged = await Retrieval.rerank(question: question, history: history, candidates: found.candidates,
                                               scorer: scorer) {
            // A library pack with a reranker model lets it choose instead.
            found.sources = judged.kept
            found.scores = judged.scores
            found.reranked = true
        } else if let picked = await modelPick(question: question, history: history, from: found.candidates, model: model) {
            found.sources = Array(picked.prefix(4))
        } else {
            // The model couldn't read them: the ranker's own best four that are worth having.
            found.sources = Ranker.keep(ranked, cutoff: !denseHits.isEmpty).map(\.passage)
        }
        found.pickSeconds = lap()
        // A field card about this situation goes first, ahead of whatever search found. Not for "tell me more",
        // which wants what the last answer (and its card) didn't say.
        if !more {
            let matches = await CardMatcher.match(question, earlier: earlier(in: history)) { card, q, e in
                await confirmCard(card, question: q, earlier: e, model: model)
            }
            if !matches.isEmpty {
                let cards = matches.map(\.card.passage)
                found.cards = matches.map(\.card.id)
                found.sources = cards + found.sources.filter { p in !cards.contains { $0.docID == p.docID } }
                    .prefix(cardCompanions)
            }
        }
        found.cardSeconds = lap()
        return found
    }

    // MARK: - Answer

    /// The instructions for writing an answer. Two things the model used to be asked to judge are decided in code
    /// instead, because it judged them badly: whether an answer is "not from the library" (it is when no excerpt
    /// reached the prompt, and the app says so itself: AssistantTurn), and whether this is an emergency (`Urgency`,
    /// see `emergencyShape`).
    /// Everything is shared except how the steps are asked for, which
    /// leans against each model's own habit (`StepHabit`). Measured on the 52 answers of library/answer-questions.tsv
    /// and library/conversations.tsv: told that "two to four steps is typical", Apple's model wrote exactly two in
    /// 50 of them; asked for the complete procedure and shown one, it wrote four in 40. Qwen, asked the second way,
    /// filled six steps by repeating itself and graded no better, so it keeps the first.
    /// - Parameters:
    ///   - emergency: `Urgency.needsHelpNow` for the question. It swaps one line: every other answer is
    ///   told never to bring up 911. In the prompt alone ("This is an emergency", `emergencyShape`) the line was
    ///   enough for Qwen (911 in the first two steps of 7 answers of 7) but not for Apple's model, which held to
    ///   "never mention" (0 to 2 of 18); with the line here as well it was 18 of 18.
    ///   - followUp: `carriesOn` for the question. A follow-up adds to an answer they already have, so the model
    ///     that stops early is asked the short way too, with no finished answer to copy: asked for the complete
    ///     procedure it wrote four steps again, most of them the last answer's (27 follow-ups, twice each: "no
    ///     repeating" 2.37 of 4 the long way, 2.81 the short way, completeness the same). An emergency always
    ///     gets the whole procedure.
    ///   - stakes: `Stakes.of` the question. A dose or an identification the library covers gets one more line:
    ///     the model may give only what the excerpts state (`Stakes.care`). One it doesn't cover never gets here
    ///     (`declines`).
    static func instructions(for habit: StepHabit, emergency: Bool = false, followUp: Bool = false,
                             stakes: Stakes = .ordinary) -> String {
        let whole = habit == .stopsEarly && (emergency || !followUp)
        let text = template.replacing("{steps}", with: whole ? completeProcedure : onlyWhatIsNeeded)
            .replacing("{help}", with: emergency ? callForHelp : neverMentionHelp)
            .replacing("{care}", with: stakes.care.map { " " + $0 } ?? "")
        return whole ? text + "\n" + example : text
    }

    private static let neverMentionHelp = """
    Never mention 911, SOS or emergency services unless the message says it is an emergency.
    """

    private static let callForHelp = """
    This is an emergency. Open with the most urgent thing to do right now, and make calling or texting 911, or \
    using SOS on a satellite messenger, one of the first two steps.
    """

    private static let onlyWhatIsNeeded = """
    give only the numbered steps this situation needs, one sentence each, with no sub-points. Two to four steps is \
    typical; never add a step just to have more, and never more than five.
    """

    private static let completeProcedure = """
    give the complete procedure as numbered steps, one sentence each, with no sub-points: every action they need, \
    in order, from first to last. Most situations need four to six steps.
    """

    /// One finished answer, for the model that stops early: the instruction alone moved it from two steps to
    /// three, the example with it to four. A topic no test question asks about, so nothing of it is worth copying.
    private static let example = """
    Here is the shape of a good answer, for a different question ("How do I patch a punctured bike tube on the \
    trail?"):
    Patch it in about ten minutes with a patch kit, a pump and tire levers.
    1. Take the wheel off and lever one side of the tire off the rim.
    2. Pull the tube out, pump it up and find the hole by listening or feeling for air.
    3. Roughen the area around the hole with the sandpaper from the kit.
    4. Spread a thin layer of glue, wait until it is tacky, then press the patch on firmly for a minute.
    5. Check inside the tire for the thorn or glass that caused it, then refit the tube and pump it up.
    """

    private static let template = """
    You are Scout, an offline field guide on a phone for backcountry trips, outdoor work, vehicles, gear and \
    emergencies. Answer the exact question the person asked. Only their own words describe their situation: what \
    they have, what they tried, where they are. Questions are often dictated, so a word that makes no sense may be \
    a misheard product or place name; work out what they meant.
    Answer like an expert guide, from what you know plus the library articles. The articles are search results \
    written by other people about other situations, vehicles and products. They never tell you what this person \
    has, where they are or what happened: never say "you have" anything that only appears in an article. Use only \
    the facts that fit their situation and cite them inline like [1]. When no article fits, answer from what you \
    know.
    Open with one sentence that answers the question. Then, if there is something to do, {steps} Be concrete \
    (amounts, times, sizes, what to look for). Stop after the last step: no closing note, summary or disclaimer.
    If you don't know a specific fact (a model's oil type, a dose, whether a plant is edible), say so in one \
    sentence instead of making it up.{care} Don't list things you don't know about their situation.
    You have no internet: no live weather, forecasts, news, maps or locations. If they ask for those, say so in one \
    sentence, give what general guidance fits, and suggest saving a forecast or map (a screenshot or PDF) to Your \
    documents in the Offline library before they lose signal, so you can read it later.
    {help}
    In a follow-up, answer only the new question. Don't repeat or reword what you already told them. If they say \
    they don't have something or a step didn't work, never suggest it again: work with what they have.
    """

    /// One earlier question and Scout's answer, for follow-ups.
    struct Turn: Sendable {
        let question: String
        let answer: String
        /// The excerpts that answer was written from.
        var sources: [Passage] = []
        /// What kind of question it was: a follow-up in a troubleshooting conversation is troubleshooting too.
        var kind: Kind? = nil
    }

    /// Whether a follow-up is about Scout's last answer ("explain step 1 more", "what if that doesn't work?",
    /// "tell me more") and not new information about the situation ("I don't have a map", "it cranks fine").
    /// Only the first kind is shown the last answer and answered from its excerpts: see `prompt`.
    static func asksAboutLastAnswer(_ question: String) -> Bool {
        let q = question.lowercased().replacing(/[’‘]/, with: "'")
        if q.contains(/\bsteps?\s*(\d+|one|two|three|four|five|six|seven|eight)\b/) { return true }
        if q.contains(/\b(the|that) (first|second|third|fourth|fifth|last) (one|step|thing|part)\b/) { return true }
        if q.contains(/\b(explain|elaborate|clarify)\b/) { return true }
        if q.contains(/\bwhat (do|did) you mean\b|\bwhat does that mean\b/) { return true }
        if q.contains(/\bwhat if (that|this|it|those|they|none of (that|those|it))\b.{0,24}\b(doesn't|don't|didn't|won't|fails?|not)\b/) {
            return true
        }
        return q.contains(/^(why|how come)\b/) && q.split(separator: " ").count <= 6
    }

    /// Whether a follow-up just asks for more on the same subject ("tell me more", "anything else?"). Shown its last
    /// answer, the model writes it again, so it gets the next-best excerpts and no last answer: see `find`.
    static func asksForMore(_ question: String) -> Bool {
        let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard q.split(separator: " ").count <= 6 else { return false }
        return q.contains(/\b(tell|say|give) (me )?(some )?more\b|^more( details?| info)?( please)?$|\b(anything|what) else\b|\bgo on\b|\bkeep going\b/)
    }

    /// Whether a message in a conversation is a question of its own ("How do I get a fire going in the rain?"
    /// typed under yesterday's question about a stove) and not more about the situation so far ("I don't have a
    /// map", "What can I use to wrap it?"): it asks how to do something and points back at nothing. When in
    /// doubt it is a question of its own, which gets the whole procedure (`instructions`).
    static func standsAlone(_ question: String) -> Bool {
        let q = question.lowercased().replacing(/[’‘]/, with: "'")
        guard Kind.asksHow(q), q.split(separator: " ").count >= 5 else { return false }
        // "it's raining" points at nothing; "wrap it" does.
        let dummyIt = q.replacing(/\bit('s| is| was| gets| starts| has)\b/, with: "")
        return !dummyIt.contains(/\b(it|that|this|those|these|them|they|him|her|he|she|instead|still|then|else|another|again|same|either)\b/)
    }

    /// Whether this message carries on the conversation so far: any message after the first that isn't a question
    /// of its own.
    static func carriesOn(_ question: String, history: [Turn]) -> Bool {
        !history.isEmpty && !standsAlone(question)
    }

    /// The last earlier message that says anything about their situation ("explain step 1 more" and "tell me
    /// more" don't).
    static func earlier(in history: [Turn]) -> String? {
        (history.last { !asksAboutLastAnswer($0.question) && !asksForMore($0.question) } ?? history.last)?.question
    }

    /// What the person has said about their situation, for searching a follow-up: that earlier message, then the
    /// new one.
    static func situation(_ question: String, history: [Turn]) -> String? {
        earlier(in: history).map { "\($0) \(question)" }
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

    /// Added to the prompt when `Urgency.needsHelpNow` says someone is hurt, sick or in danger right now. The
    /// instructions tell the model to mention 911 or SOS only when the message says so, and this is where it says so.
    static let emergencyShape = """
    This is an emergency. Open with the most urgent thing to do right now, and make getting help (calling or \
    texting 911, or SOS on a satellite messenger) one of the first two steps.
    """

    static func prompt(question: String, sources: [Passage], history: [Turn], kind: Kind = .howTo) -> String {
        // Their words and the library's are kept apart and labelled, so a small model doesn't mistake an article's
        // subject (a "choke lever" in a title) for something they have. The question comes first and last: a small
        // model otherwise drifts to whatever the articles are about.
        var p = "WHAT THEY TOLD YOU (only this describes their situation):\n"
        if let last = history.last {
            // Earlier turns are what the person said, not what Scout answered. Shown its own earlier answer, a
            // small model copies it: cut at 500 characters it copied the cut ("4. Verify that your T-C"), and
            // whole it still repeated earlier lines in most follow-ups (Apple's model in 16 of 21). Their own
            // words carry what matters for the next answer: the situation, what they lack, what they tried.
            for t in history { p += "Earlier they said: \(t.question)\n" }
            if asksAboutLastAnswer(question) {
                // Unless the question is about that answer ("explain step 1 more"): then it can't be answered
                // without it. Whole lines only, so nothing ends mid-sentence.
                p += "Your last answer, which they are asking about:\n\(wholeLines(last.answer, upTo: 1200))\n"
                p += "This is a follow-up about that answer. Answer what they ask now.\n"
            } else {
                p += "This is a follow-up in the same situation. Answer the new question.\n"
            }
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
        if Urgency.needsHelpNow(question) {
            p += emergencyShape + "\n\n"
        } else if kind == .troubleshoot {
            p += troubleshootShape + "\n\n"
        }
        p += "Now answer their question: \(question)"
        return p
    }
}

extension Retrieval {
    /// The start of `text` up to `limit` characters, ending at the end of a line: a list is shortened by whole
    /// steps, never mid-sentence. Always at least the first line.
    static func wholeLines(_ text: String, upTo limit: Int) -> String {
        var out: [Substring] = [], size = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if !out.isEmpty && size + line.count + 1 > limit { break }
            out.append(line)
            size += line.count + 1
        }
        return out.joined(separator: "\n")
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
