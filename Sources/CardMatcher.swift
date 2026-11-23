import CryptoKit
import Foundation

/// Finds the field card, if any, that is about what someone asked. A card is short, written for this app and
/// checked, so when one fits it goes to the answer model ahead of anything search found (Retrieval.find).
///
/// A question is matched by meaning to the ways people describe each card's situation (`FieldCard.asks`): "my buddy
/// won't stop shaking and he's talking funny" has no word in common with the hypothermia card. That needs the
/// library's embedder (SearchModels). Without it (the simulator, a library built before meaning search) the match
/// is by shared words, which is rarely wrong and finds about a quarter.
@MainActor
enum CardMatcher {
    struct Match: Sendable {
        let card: FieldCard
        /// How close the message is to the card's `asks` (the mean of the two nearest), 0 to 1.
        let score: Float
        /// How close it is to the single nearest of the card's `asks`.
        var nearest: Float = 0
        /// How close it is to the nearest of the card's `notAsks`: the same words, a different need.
        let rival: Float

        /// The message is nearer to something the card doesn't answer than to anything it does: "someone is
        /// having a seizure" sits nearest the heat card, and nearer still to that card's "not this" phrases.
        var isNearMiss: Bool { rival > nearest }
    }

    /// How the nearest cards become the answer's cards (measured on two sets of 384 messages written without
    /// sight of the cards or their phrases: docs/field-cards.md):
    /// - Below `candidateScore` there is no card, nor when the message is nearer to one of the card's `notAsks`
    ///   than to any of its asks (`Match.isNearMiss`).
    /// - A card that leads the next by `clearLead` is taken as it is from `certainScore` up; between the two
    ///   scores Apple's model is asked one yes-or-no question about it (`confirm`).
    /// - When the top two are closer than that, the nearest is the wrong one about half the time ("soaked by
    ///   sleet, now he's confused" sat between the heat and shock cards, with hypothermia third). What happens
    ///   then is `whenClose`.
    static let candidateScore: Float = 0.70
    static let certainScore: Float = 0.78
    static let clearLead: Float = 0.02
    /// How far a follow-up read alone can lift a card above its score for the whole situation (see `rank`). On
    /// 216 follow-ups in three test sets: no change for the 44 older cards, and for the eight newest 27 right
    /// cards of 40 against 20, with no wrong one against one.
    static let followUpLift: Float = 0.03
    /// The same for matching by shared words (no embedder): the share of an ask's words the message has.
    static let wordScore: Float = 0.75

    enum WhenClose: Sendable {
        /// No card: search answers the question as it would have. A missing card costs nothing that wasn't
        /// already so; a wrong one is a confident answer to another emergency.
        case none
        /// Ask the model about each of the two, and use those it says yes to. On the second test set this found
        /// the right card for 88% of the messages that have one, against 77%, and a wrong one for 5%, against
        /// 1.5%: Apple's model says yes too easily, and the wrong ones were the dangerous kind (the heat card for
        /// someone soaked and stumbling in sleet, the hypothermia card for an overheated dog). Worth another
        /// look with a model that can tell them apart.
        case askBoth
    }
    /// A variable so `scout-tools cards --close-ask` can measure the other way.
    nonisolated(unsafe) static var whenClose = WhenClose.none

    /// The cards for this message: none or one (two only under `WhenClose.askBoth`, when two are close and the
    /// model says both fit).
    /// - Parameters:
    ///   - earlier: what they said before, in a follow-up (Retrieval.earlier), so "he's stopped shivering now"
    ///     is read with "my friend fell in a creek".
    ///   - confirm: asks the model whether a card fits; nil when the model said neither yes nor no.
    static func match(_ question: String, earlier: String? = nil,
                      confirm: (FieldCard, _ question: String, _ earlier: String?) async -> Bool?) async -> [Match] {
        let ranked = await ranked(question, earlier: earlier)
        guard let best = ranked.matches.first else { return [] }
        guard ranked.byMeaning else { return best.score >= wordScore && best.score > best.rival ? [best] : [] }
        guard best.score >= candidateScore, !best.isNearMiss else { return [] }
        let second = ranked.matches.dropFirst().first
        if let second, best.score - second.score < clearLead {
            guard whenClose == .askBoth else { return [] }
            var fits: [Match] = []
            for match in [best, second] where match.score >= candidateScore && !match.isNearMiss {
                if await confirm(match.card, question, earlier) == true { fits.append(match) }
            }
            return fits
        }
        if best.score >= certainScore { return [best] }
        return await confirm(best.card, question, earlier) == true ? [best] : []
    }

    /// Every card with its score for this message, best first, and whether the scores are by meaning.
    static func ranked(_ question: String, earlier: String? = nil) async -> (matches: [Match], byMeaning: Bool) {
        let texts = [question] + [earlier.map { "\($0) \(question)" }].compactMap { $0 }
        if let vectors = await vectors(), let queries = await SearchModels.shared.embedPlain(texts) {
            return (rank(queries: queries, cards: vectors), true)
        }
        return (rankByWords(texts), false)
    }

    // MARK: - Asking the model

    nonisolated static let confirmInstructions = """
    You check whether a quick-reference card fits what a person wrote to a field guide app. Answer YES if the card \
    is about the situation or question in their message. Answer NO if their message is about something else, even \
    when it shares a word with the card. Reply with one word: YES or NO.
    """

    nonisolated static func confirmPrompt(_ card: FieldCard, question: String, earlier: String?) -> String {
        (earlier.map { "Earlier they said: \($0)\n" } ?? "")
            + "Their message: \(question)\n\nCard: \(card.title). \(card.recognize.joined(separator: " "))\n\n"
            + "Is the card about their message? YES or NO."
    }

    /// The model's reply as a yes or no; nil for anything else.
    nonisolated static func readConfirmation(_ reply: String) -> Bool? {
        let word = reply.uppercased().split(whereSeparator: { !$0.isLetter }).first
        return word == "YES" ? true : word == "NO" ? false : nil
    }

    // MARK: - By meaning

    private struct CardVectors { let card: FieldCard; let asks: [[Float]]; let notAsks: [[Float]] }
    private static var cached: [CardVectors]?

    /// Every card's phrases as vectors: about 2,000 short texts. Embedding them takes about a second on a Mac and
    /// longer on a phone, so it is done once and kept in the caches folder, under a name made from the embedder and
    /// the phrases: a new library's embedder or an app update with new phrases starts over.
    private static func vectors() async -> [CardVectors]? {
        if let cached { return cached }
        let cards = FieldCard.all
        let texts = cards.flatMap { $0.asks + $0.notAsks }
        guard await SearchModels.shared.embedPlain(["ready"]) != nil,
              let embedder = SearchModels.shared.embedderName else { return nil }
        let file = URL.cachesDirectory.appending(path: "card-phrases-\(fingerprint(embedder, texts)).vectors")
        var all = load(file, count: texts.count) ?? []
        if all.isEmpty {
            for start in stride(from: 0, to: texts.count, by: 64) {
                guard let batch = await SearchModels.shared.embedPlain(Array(texts[start..<min(start + 64, texts.count)]))
                else { return nil }
                all += batch
            }
            save(all, to: file)
        }
        guard all.count == texts.count else { return nil }
        var out: [CardVectors] = [], at = 0
        for card in cards {
            let asks = Array(all[at..<(at + card.asks.count)])
            at += card.asks.count
            let nots = Array(all[at..<(at + card.notAsks.count)])
            at += card.notAsks.count
            out.append(CardVectors(card: card, asks: asks, notAsks: nots))
        }
        cached = out
        return out
    }

    /// A card's score is the mean of its two nearest asks. One near ask is often chance: with about 11 asks a
    /// card, the nearest card by a single ask was right for 80% of the test messages and by two for 88%; with
    /// about 41 asks a card, 95%.
    ///
    /// A follow-up is scored twice, alone and with what came before it (`queries` holds both), and takes the
    /// nearer, but alone it can lift a card only `followUpLift` above what the whole situation gives it. Cards
    /// have fragments among their asks ("should I close it or leave it open?"), and a fragment alone matches the
    /// same fragment on any card: that put the animal bite card on a finger nicked slicing cheese.
    private static func rank(queries: [[Float]], cards: [CardVectors]) -> [Match] {
        func nearest(_ phrases: [[Float]], count: Int, capped: Bool = true) -> Float {
            let each = queries.map { q -> Float in
                let top = phrases.map { dot(q, $0) }.sorted(by: >).prefix(count)
                return top.isEmpty ? 0 : top.reduce(0, +) / Float(top.count)
            }
            guard let best = each.max() else { return 0 }
            guard capped, each.count > 1, let whole = each.last else { return best }
            return min(best, whole + followUpLift)
        }
        return cards.map {
            Match(card: $0.card, score: nearest($0.asks, count: 2), nearest: nearest($0.asks, count: 1),
                  rival: nearest($0.notAsks, count: 1, capped: false))
        }.sorted { $0.score > $1.score }
    }

    private static func fingerprint(_ embedder: String, _ texts: [String]) -> String {
        var hash = SHA256()
        hash.update(data: Data(embedder.utf8))
        for text in texts { hash.update(data: Data(text.utf8 + [0])) }
        return hash.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The file is the vectors' values one after another; every vector has the same length.
    private static func load(_ file: URL, count: Int) -> [[Float]]? {
        guard let data = try? Data(contentsOf: file), count > 0, data.count % (count * 4) == 0, !data.isEmpty
        else { return nil }
        let width = data.count / (count * 4)
        return data.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: Float.self)
            return (0..<count).map { Array(values[($0 * width)..<(($0 + 1) * width)]) }
        }
    }

    private static func save(_ vectors: [[Float]], to file: URL) {
        var data = Data(capacity: vectors.count * (vectors.first?.count ?? 0) * 4)
        for v in vectors { v.withUnsafeBufferPointer { data.append(UnsafeBufferPointer(rebasing: $0[...])) } }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }

    // MARK: - By words

    /// The share of an ask's words that the message has, for the ask that shares most. An ask needs at least two
    /// words that count.
    nonisolated static func rankByWords(_ texts: [String]) -> [Match] {
        let message = Set(texts.flatMap(words))
        func nearest(_ phrases: [String]) -> Float {
            phrases.map { phrase -> Float in
                let w = Set(words(phrase))
                return w.count < 2 ? 0 : Float(w.intersection(message).count) / Float(w.count)
            }.max() ?? 0
        }
        return FieldCard.all.map {
            Match(card: $0, score: nearest($0.asks), nearest: nearest($0.asks), rival: nearest($0.notAsks))
        }.sorted { $0.score > $1.score }
    }

    /// Lowercase words that carry meaning, with plural and verb endings trimmed so "bleeding" meets "bleeds".
    nonisolated static func words(_ text: String) -> [String] {
        Library.queryWords(text.replacing(/[’‘]/, with: "'")).map { word in
            var w = word.replacing(/'s$|'$/, with: "")
            for ending in ["ing", "ed", "es", "s"] where w.count > ending.count + 2 && w.hasSuffix(ending) {
                w = String(w.dropLast(ending.count))
                break
            }
            return w
        }
    }
}
