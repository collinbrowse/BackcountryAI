import Foundation
import SQLite3

/// One search hit: the best passage of one article.
struct Passage: Identifiable, Hashable, Codable, Sendable {
    let id: Int64          // passage id
    let docID: Int64
    let title: String
    let source: String     // human label, e.g. "Ready.gov (FEMA)"
    let sourceKey: String
    let official: Bool
    let text: String       // passage text, trimmed for the model
    var coverage: Double? = nil  // share of the search's words this passage contains (optional: saved passages lack it)

    /// From a document the person added themselves (see MyDocuments), not from the downloaded library.
    var isMine: Bool { sourceKey.hasPrefix(Library.minePrefix) }
    /// One of the app's own field cards (FieldCardData.swift), not a library article.
    var isCard: Bool { sourceKey == FieldCard.sourceKey }
}

struct Article: Sendable {
    let title: String
    let source: String
    let url: String
    let license: String
    let body: String
}

/// Read-only search over a Survival LLM library folder: `index.sqlite` (SQLite FTS5 over ~1,500-character
/// passages) plus `text/<source>/NNNN.md` shards. Same format and ranking as survival-llm's library/search.py.
/// The person's own documents (MyDocuments) are a second index in the same format; `combining` attaches it, and
/// every public method then covers both.
final class Library: @unchecked Sendable {
    private let locate: @Sendable (String) -> URL?
    private var db: OpaquePointer?
    private let lock = NSLock()
    /// The person's own documents, searched along with this library. Set once, before the library is shared.
    private(set) var mine: Library?

    /// Doc and passage ids from the person's own documents start here, so an id alone says which index it's from.
    static let mineIDBase: Int64 = 1 << 40
    /// Source keys of the person's own documents start with this.
    static let minePrefix = "mine-"

    /// The downloaded library with the person's documents attached; either one alone if the other is missing.
    static func combining(pack: Library?, mine: Library?) -> Library? {
        guard let pack else { return mine }
        pack.mine = mine
        return pack
    }

    static let official: Set<String> = ["ready-gov", "cdc-travel", "medlineplus",
        "military-medicine", "wikem", "medical-library", "water", "post-disaster", "food-prep",
        "survival-manuals", "first-aid-guides", "usda-canning", "risk"]
    /// Sources by how close they are to what Scout is for (Retrieval.Signals): guidance for the field and for
    /// emergencies, and forums about houses, kitchens and gardens.
    static let field: Set<String> = ["survival-manuals", "military-medicine", "gov-guides", "ready-gov", "cdc-travel",
                                     "medlineplus", "risk", "se-outdoors", "usda-canning"]
    static let household: Set<String> = ["se-diy", "se-cooking", "se-gardening", "se-lifehacks", "se-sustainability",
                                         "se-pets"]
    static let officialLabel: Set<String> = ["ready-gov", "cdc-travel", "medlineplus", "military-medicine",
        "survival-manuals", "first-aid-guides", "usda-canning"]
    static let stopwords: Set<String> = Set("""
    a about above after again against all am an and any are as at be because been before being below between both but \
    by can could did do does doing down during each few for from further had has have having he her here hers herself \
    him himself his how i if in into is it its itself just me more most my myself no nor not now of off on once only or \
    other our ours ourselves out over own same she should so some such than that the their theirs them themselves then \
    there these they this those through to too under until up very was we were what when where which while who whom why \
    will with would you your yours yourself yourselves
    """.split(separator: " ").map(String.init))

    /// A library unpacked into a folder (for example one copied in with Finder).
    convenience init(folder: URL) throws {
        try self.init { folder.appending(path: $0) }
    }

    /// `locate` turns a path inside the library ("index.sqlite", "text/…") into a readable file URL,
    /// so the same code reads a plain folder or Apple-hosted asset packs.
    /// `immutable` is for the downloaded library, which never changes while open; the person's documents do.
    init(locate: @escaping @Sendable (String) -> URL?, immutable: Bool = true) throws {
        self.locate = locate
        guard let path = locate("index.sqlite")?.path else { throw LibraryError.cannotOpen }
        let opened = immutable
            ? sqlite3_open_v2("file:\(path)?immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
            : sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK else { throw LibraryError.cannotOpen }
        _ = try query("SELECT 1 FROM sources LIMIT 1") { _ in () }
    }

    deinit { sqlite3_close(db) }

    enum LibraryError: LocalizedError {
        case cannotOpen, sql(String)
        var errorDescription: String? {
            switch self {
            case .cannotOpen: "The library could not be opened."
            case .sql(let m): "Library error: \(m)"
            }
        }
    }

    // MARK: - Public

    func stats() -> (articles: Int, sources: Int) {
        let own = (try? query("SELECT COALESCE(SUM(docs),0), COUNT(*) FROM sources WHERE done=1") { s in
            (Int(sqlite3_column_int64(s, 0)), Int(sqlite3_column_int64(s, 1)))
        }.first) ?? (0, 0)
        let theirs = mine?.stats() ?? (0, 0)
        return (own.0 + theirs.0, own.1 + theirs.1)
    }

    func sourceLabels() -> [String] {
        (mine?.sourceLabels() ?? [])
            + ((try? query("SELECT label FROM sources WHERE done=1 ORDER BY docs DESC") { Self.text($0, 0) }) ?? [])
    }

    struct SourceInfo: Identifiable, Hashable, Sendable {
        let key: String
        let label: String
        let docs: Int
        var id: String { key }
        var official: Bool { Library.officialLabel.contains(key) }
    }

    /// The person's own documents first, then the library's sources, largest first.
    func sources() -> [SourceInfo] {
        (mine?.sources() ?? []) + ((try? query("SELECT key, label, docs FROM sources WHERE done=1 AND docs>0 ORDER BY docs DESC") { s in
            SourceInfo(key: Self.text(s, 0), label: Self.text(s, 1), docs: Int(sqlite3_column_int64(s, 2)))
        }) ?? [])
    }

    /// Article titles from one source, alphabetical, for browsing. Returned as text-less passages so
    /// they open in the same article view as search hits.
    func titles(sourceKey: String, offset: Int, limit: Int) -> [Passage] {
        if sourceKey.hasPrefix(Self.minePrefix), let mine {
            return mine.titles(sourceKey: sourceKey, offset: offset, limit: limit)
        }
        return (try? query("""
            SELECT d.id, d.title, s.label FROM docs d JOIN sources s ON s.id = d.source_id
            WHERE s.key = ? ORDER BY d.title COLLATE NOCASE LIMIT ? OFFSET ?
            """, [sourceKey, limit, offset]) { s in
            Passage(id: -sqlite3_column_int64(s, 0), docID: sqlite3_column_int64(s, 0), title: Self.text(s, 1),
                    source: Self.text(s, 2), sourceKey: sourceKey, official: Self.officialLabel.contains(sourceKey), text: "")
        }) ?? []
    }

    static func queryWords(_ q: String) -> [String] {
        let lower = q.lowercased()
        let regex = /[\w']+/
        return lower.matches(of: regex).map { String($0.output) }
            .filter { $0.count > 1 && !stopwords.contains($0) }
            .prefix(12).map { $0 }
    }

    /// Best passages for a question, official sources ranked up. Each passage's coverage is the share of the
    /// question's words it contains. Ranking is BM25 times coverage, so when nothing has every word, a passage
    /// with most of them beats one that only repeats the rarest word.
    /// - Parameters:
    ///   - perArticle: how many passages one article may give. One for a list of articles to read; the answer's
    ///     search takes two (Retrieval.candidates), because a manual's chapter is one article of a hundred passages.
    ///   - whole: the passage whole (up to `maxChars`, ending on a sentence) and not a window around the first
    ///     matching word. A window cuts a procedure off mid-step.
    func search(_ question: String, limit: Int = 5, maxChars: Int = 900, only keys: Set<String>? = nil,
                perArticle: Int = 1, whole: Bool = false) -> [Passage] {
        let own = searchOwn(question, limit: limit, maxChars: maxChars, only: keys, perArticle: perArticle, whole: whole)
        guard let mine else { return own }
        let theirs = mine.search(question, limit: limit, maxChars: maxChars, only: keys, perArticle: perArticle,
                                 whole: whole)
        return Self.merge(own, mine: theirs, limit: limit)
    }

    /// Library hits and hits from the person's documents in one list. The two indexes rank on different scales, so
    /// they merge on coverage: a passage of theirs goes ahead of every library passage that covers no more of the
    /// question's words. Each list keeps its own order.
    static func merge(_ library: [Passage], mine: [Passage], limit: Int) -> [Passage] {
        var out: [Passage] = [], rest = mine[...]
        for p in library {
            while let m = rest.first, (m.coverage ?? 0) >= (p.coverage ?? 0) {
                out.append(m)
                rest = rest.dropFirst()
            }
            out.append(p)
        }
        out += rest
        return Array(out.prefix(limit))
    }

    private func searchOwn(_ question: String, limit: Int, maxChars: Int, only keys: Set<String>?,
                           perArticle: Int, whole: Bool) -> [Passage] {
        let (ordered, words) = keywordRows(question)
        var out: [Passage] = [], taken: [Int64: Int] = [:], seenText = Set<String>()
        for r in ordered {
            if let keys, !keys.contains(r.key) { continue }
            guard taken[r.doc, default: 0] < perArticle, !Self.isTranslation(r.title, key: r.key) else { continue }
            taken[r.doc, default: 0] += 1
            guard let raw = readText(fileID: r.file, offset: r.off, length: r.len) else { continue }
            let flat = Self.flatten(raw)
            guard !seenText.contains(flat) else { continue }
            seenText.insert(flat)
            out.append(Passage(id: r.pid, docID: r.doc, title: r.title, source: r.label, sourceKey: r.key,
                               official: Self.officialLabel.contains(r.key),
                               text: whole ? Self.whole(flat, upTo: maxChars)
                                   : Self.window(flat, words: words, width: maxChars),
                               coverage: r.coverage))
            if out.count >= limit { break }
        }
        return out
    }

    private struct KeywordRow {
        let pid, doc: Int64
        let title, label, key: String
        let file, off, len: Int64
        /// BM25 × the source's weight × coverage. BM25 ranks are negative, so lower is better.
        var score = 0.0
        var coverage = 0.0
    }

    /// Every passage of this library that a question's words match, best first, before the one-per-article rule.
    private func keywordRows(_ question: String) -> (rows: [KeywordRow], words: [String]) {
        let words = Self.queryWords(question)
        guard !words.isEmpty else { return ([], words) }
        let terms = words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "") + "\"" }
        func ranked(_ match: String, limit: Int) -> [(Int64, Double)] {
            (try? query("SELECT rowid, rank FROM fts WHERE fts MATCH ? AND rank MATCH 'bm25(4.0, 1.0)' "
                        + "ORDER BY rank LIMIT \(limit)", [match]) { s in
                (sqlite3_column_int64(s, 0), sqlite3_column_double(s, 1))
            }) ?? []
        }
        var hits = ranked(terms.joined(separator: " "), limit: 300)
        var cover = Dictionary(hits.map { ($0.0, 1.0) }, uniquingKeysWith: { a, _ in a })
        if hits.count < 3 && terms.count > 2 {  // nothing has every word: try every word but one (fast)
            for skip in terms.indices {
                let rest = terms.enumerated().filter { $0.offset != skip }.map(\.element)
                for h in ranked(rest.joined(separator: " "), limit: 100) where cover[h.0] == nil {
                    hits.append(h)
                    cover[h.0] = Double(rest.count) / Double(terms.count)
                }
            }
        }
        if hits.count < 3 && terms.count > 1 {  // still too little: take any word, then count matches
            hits = ranked(terms.joined(separator: " OR "), limit: 200)
            let ids = hits.map { String($0.0) }.joined(separator: ",")
            cover = Dictionary(hits.map { ($0.0, 0.0) }, uniquingKeysWith: { a, _ in a })
            for t in terms {
                let matched = (try? query("SELECT rowid FROM fts WHERE fts MATCH ? AND rowid IN (\(ids))", [t]) {
                    sqlite3_column_int64($0, 0)
                }) ?? []
                for id in matched { cover[id, default: 0] += 1 / Double(terms.count) }
            }
        }
        guard !hits.isEmpty else { return ([], words) }
        let rank = Dictionary(hits, uniquingKeysWith: { a, _ in a })
        let ids = hits.map { String($0.0) }.joined(separator: ",")
        // BM25 ranks are negative (lower is better), so a weight above 1 moves a source up.
        func weight(_ k: String) -> Double { Self.official.contains(k) ? 1.3 : (k == "wikipedia" || k == "wikimed") ? 1.15 : 1 }
        let rows: [KeywordRow] = (try? query("""
            SELECT p.id, d.id, d.title, s.label, s.key, d.file_id, p.offset, p.length
            FROM passages p JOIN docs d ON d.id = p.doc_id JOIN sources s ON s.id = d.source_id
            WHERE p.id IN (\(ids))
            """) { s -> KeywordRow in
            let pid = sqlite3_column_int64(s, 0), key = Self.text(s, 4), covered = cover[pid] ?? 0
            return KeywordRow(pid: pid, doc: sqlite3_column_int64(s, 1), title: Self.text(s, 2),
                              label: Self.text(s, 3), key: key, file: sqlite3_column_int64(s, 5),
                              off: sqlite3_column_int64(s, 6), len: sqlite3_column_int64(s, 7),
                              score: (rank[pid] ?? 0) * weight(key) * covered, coverage: covered)
        }) ?? []
        let ordered = rows.sorted { $0.score < $1.score }
        return (ordered, words)
    }

    // MARK: - Every hit (scout-tools pool)

    /// A keyword hit before the one-per-article rule, so other rules can be tried on the same hits.
    struct KeywordHit: Sendable {
        let passageID, docID: Int64
        let sourceKey: String
        /// BM25 × the source's weight × coverage: lower is better.
        let score: Double
        let coverage: Double
    }

    /// The downloaded library's keyword hits for a question, best first (not the person's own documents).
    func keywordHits(_ question: String, limit: Int) -> [KeywordHit] {
        keywordRows(question).rows.filter { !Self.isTranslation($0.title, key: $0.key) }.prefix(limit).map {
            KeywordHit(passageID: $0.pid, docID: $0.doc, sourceKey: $0.key, score: $0.score, coverage: $0.coverage)
        }
    }

    /// Passages by id with their whole text (flattened), in the order given and with no one-per-article rule.
    func wholePassages(ids: [Int64]) -> [Passage] {
        guard !ids.isEmpty else { return [] }
        struct Row { let pid, doc: Int64; let title, label, key: String; let file, off, len: Int64 }
        var byID: [Int64: Row] = [:]
        for start in stride(from: 0, to: ids.count, by: 500) {
            let list = ids[start..<min(start + 500, ids.count)].map(String.init).joined(separator: ",")
            let rows = (try? query("""
                SELECT p.id, d.id, d.title, s.label, s.key, d.file_id, p.offset, p.length
                FROM passages p JOIN docs d ON d.id = p.doc_id JOIN sources s ON s.id = d.source_id
                WHERE p.id IN (\(list))
                """) { s in
                Row(pid: sqlite3_column_int64(s, 0), doc: sqlite3_column_int64(s, 1), title: Self.text(s, 2),
                    label: Self.text(s, 3), key: Self.text(s, 4), file: sqlite3_column_int64(s, 5),
                    off: sqlite3_column_int64(s, 6), len: sqlite3_column_int64(s, 7))
            }) ?? []
            for r in rows { byID[r.pid] = r }
        }
        return ids.compactMap { id in
            guard let r = byID[id], let raw = readText(fileID: r.file, offset: r.off, length: r.len) else { return nil }
            return Passage(id: r.pid, docID: r.doc, title: r.title, source: r.label, sourceKey: r.key,
                           official: Self.officialLabel.contains(r.key), text: Self.flatten(raw), coverage: nil)
        }
    }

    /// The ids of every passage in the same article as `passageID`, in order. An article's passages have
    /// consecutive ids (build_library.py writes them together), so only its neighbours are read.
    func passageIDs(inArticleOf passageID: Int64, reach: Int64 = 150) -> [Int64] {
        let rows = (try? query("SELECT id, doc_id FROM passages WHERE id BETWEEN ? AND ? ORDER BY id",
                               [passageID - reach, passageID + reach]) { s in
            (sqlite3_column_int64(s, 0), sqlite3_column_int64(s, 1))
        }) ?? []
        guard let doc = rows.first(where: { $0.0 == passageID })?.1 else { return [] }
        return rows.filter { $0.1 == doc }.map(\.0)
    }

    /// How many passages the library has (for progress while embedding them).
    func passageCount() throws -> Int {
        try query("SELECT COUNT(*) FROM passages") { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    /// A file inside the library folder or pack ("vectors.bin", "models/…"), if it's there.
    func fileURL(_ path: String) -> URL? {
        guard let url = locate(path), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Passages by id, in the order given, `perArticle` from each article (for meaning-based search, which finds
    /// passage ids). Only this library's own passages: the person's documents have no vectors.
    func passages(ids: [Int64], words: [String], maxChars: Int, perArticle: Int = 1, whole: Bool = false) -> [Passage] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map(String.init).joined(separator: ",")
        struct Row { let pid, doc: Int64; let title, label, key: String; let file, off, len: Int64 }
        let rows = (try? query("""
            SELECT p.id, d.id, d.title, s.label, s.key, d.file_id, p.offset, p.length
            FROM passages p JOIN docs d ON d.id = p.doc_id JOIN sources s ON s.id = d.source_id
            WHERE p.id IN (\(list))
            """) { s in
            Row(pid: sqlite3_column_int64(s, 0), doc: sqlite3_column_int64(s, 1), title: Self.text(s, 2),
                label: Self.text(s, 3), key: Self.text(s, 4), file: sqlite3_column_int64(s, 5),
                off: sqlite3_column_int64(s, 6), len: sqlite3_column_int64(s, 7))
        }) ?? []
        let byID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Passage] = [], taken: [Int64: Int] = [:]
        for id in ids {
            guard let r = byID[id], taken[r.doc, default: 0] < perArticle, !Self.isTranslation(r.title, key: r.key),
                  let raw = readText(fileID: r.file, offset: r.off, length: r.len) else { continue }
            taken[r.doc, default: 0] += 1
            let flat = Self.flatten(raw)
            out.append(Passage(id: r.pid, docID: r.doc, title: r.title, source: r.label, sourceKey: r.key,
                               official: Self.officialLabel.contains(r.key),
                               text: whole ? Self.whole(flat, upTo: maxChars)
                                   : Self.window(flat, words: words, width: maxChars), coverage: nil))
        }
        return out
    }

    /// The passage to show for a hit in a forum thread. A thread is stored as the question, then its answers
    /// best first (build_library.py: "Question by …", then "## Answer by … (score 12, accepted)"), and a search
    /// usually matches the question, which says what went wrong and not what to do: read by the excerpt judge,
    /// a thread shown by its question answered the person's question a third less often than the same thread
    /// shown by its best answer. So a hit on the question becomes the first passage of the best answer; a hit
    /// inside an answer stays. The title already carries the question.
    func bestAnswer(for hit: Passage, maxChars: Int) -> Passage {
        guard hit.sourceKey.hasPrefix("se-"), hit.id < Self.mineIDBase else { return hit }
        // A short question shares its passage with the start of the first answer.
        guard hit.text.firstMatch(of: Self.answerHeading) == nil else { return hit }
        for id in passageIDs(inArticleOf: hit.id) {
            guard let text = passageText(id: id).map(Self.flatten), text.prefixMatch(of: Self.answerHeading) != nil
            else { continue }
            // The first answer starts after this hit: the hit is the question. Otherwise it is part of an answer.
            guard id > hit.id else { return hit }
            return Passage(id: id, docID: hit.docID, title: hit.title, source: hit.source, sourceKey: hit.sourceKey,
                           official: hit.official, text: Self.whole(text, upTo: maxChars), coverage: hit.coverage)
        }
        return hit
    }

    nonisolated(unsafe) private static let answerHeading = /\bAnswer( by [^()]{1,60})? \(score -?\d+/

    /// The next `limit` passages after id `after`, as the text the embedder reads: "Title (Source)" then the passage,
    /// so a passage that only says "Check the plug" still carries what it's about (scout-tools embed).
    func passageBatch(after: Int64, limit: Int = 64, maxChars: Int = 1500) throws -> [(id: Int64, text: String)] {
        struct Row { let pid: Int64; let title, label: String; let file, off, len: Int64 }
        let rows = try query("""
            SELECT p.id, d.title, s.label, d.file_id, p.offset, p.length
            FROM passages p JOIN docs d ON d.id = p.doc_id JOIN sources s ON s.id = d.source_id
            WHERE p.id > \(after) ORDER BY p.id LIMIT \(limit)
            """) { s in
            Row(pid: sqlite3_column_int64(s, 0), title: Self.text(s, 1), label: Self.text(s, 2),
                file: sqlite3_column_int64(s, 3), off: sqlite3_column_int64(s, 4), len: sqlite3_column_int64(s, 5))
        }
        return rows.map { r in
            let text = readText(fileID: r.file, offset: r.off, length: r.len).map(Self.flatten) ?? ""
            return (r.pid, "\(r.title) (\(r.label))\n" + text.prefix(maxChars))
        }
    }

    /// Libraries built before the translation filter hold wiki translations such as "Solar cooker/ru".
    static func isTranslation(_ title: String, key: String) -> Bool {
        (key == "appropedia" || key == "energypedia") && title.contains(/\/[a-z]{2,3}(-[a-z]+)?$/)
    }

    func article(docID: Int64) -> Article? {
        // A field card among an answer's sources opens like an article (FieldCardData.swift).
        if let card = FieldCard.card(passageID: docID) {
            return Article(title: card.title, source: FieldCard.sourceLabel, url: "", license: "Written for this app",
                           body: card.articleBody)
        }
        if docID >= Self.mineIDBase, let mine { return mine.article(docID: docID) }
        struct Row { let title, url, label, license: String; let file, off, len: Int64 }
        guard let r = (try? query("""
            SELECT d.title, COALESCE(d.url,''), s.label, COALESCE(s.license,''), d.file_id, d.offset, d.length
            FROM docs d JOIN sources s ON s.id = d.source_id WHERE d.id = ?
            """, [docID]) { s in
            Row(title: Self.text(s, 0), url: Self.text(s, 1), label: Self.text(s, 2), license: Self.text(s, 3),
                file: sqlite3_column_int64(s, 4), off: sqlite3_column_int64(s, 5), len: sqlite3_column_int64(s, 6))
        })?.first, let body = readText(fileID: r.file, offset: r.off, length: r.len) else { return nil }
        let withoutHeader = body.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        return Article(title: r.title, source: r.label, url: r.url, license: r.license,
                       body: withoutHeader.isEmpty ? body : withoutHeader)
    }

    /// A passage's text as stored, headings and line breaks kept (search results carry a flattened window of it).
    func passageText(id: Int64) -> String? {
        if FieldCard.card(passageID: id) != nil { return nil }  // a card is shown whole
        if id >= Self.mineIDBase, let mine { return mine.passageText(id: id) }
        guard let r = (try? query("""
            SELECT d.file_id, p.offset, p.length FROM passages p JOIN docs d ON d.id = p.doc_id WHERE p.id = ?
            """, [id]) { s in (sqlite3_column_int64(s, 0), sqlite3_column_int64(s, 1), sqlite3_column_int64(s, 2)) })?.first
        else { return nil }
        return readText(fileID: r.0, offset: r.1, length: r.2)
    }

    // MARK: - Helpers

    private var filePaths: [Int64: String] = [:]

    private func readText(fileID: Int64, offset: Int64, length: Int64) -> String? {
        lock.lock()
        let cached = filePaths[fileID]
        lock.unlock()
        let rel: String
        if let cached { rel = cached } else {
            guard let p = (try? query("SELECT path FROM files WHERE id=?", [fileID]) { Self.text($0, 0) })?.first
            else { return nil }
            lock.lock(); filePaths[fileID] = p; lock.unlock()
            rel = p
        }
        guard let url = locate("text/" + rel), let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        try? h.seek(toOffset: UInt64(offset))
        guard let data = try? h.read(upToCount: Int(length)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func flatten(_ text: String) -> String {
        text.split(separator: "\n").map { $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The passage up to about `limit` characters, ending on a sentence. Passages are cut at about 1,500
    /// characters when the library is built (library/passages.py), so most come through whole.
    static func whole(_ flat: String, upTo limit: Int) -> String {
        guard flat.count > limit else { return flat }
        let head = flat.prefix(limit)
        let floor = head.index(head.startIndex, offsetBy: limit / 2)
        let end = [". ", "? ", "! "].compactMap { head.range(of: $0, options: .backwards, range: floor..<head.endIndex)?.lowerBound }.max()
        return (end.map { String(head[...$0]) } ?? String(head)) + " …"
    }

    /// A window of the passage around the first query word it contains.
    static func window(_ flat: String, words: [String], width: Int) -> String {
        guard flat.count > width else { return flat }
        let low = flat.lowercased()
        let first = words.compactMap { low.range(of: $0)?.lowerBound }.min()
        var start = first.map { low.distance(from: low.startIndex, to: $0) } ?? 0
        start = max(0, min(start - 150, flat.count - width))
        let s = flat.index(flat.startIndex, offsetBy: start)
        let e = flat.index(s, offsetBy: width)
        return (start > 0 ? "…" : "") + flat[s..<e] + "…"
    }

    private static func text(_ s: OpaquePointer?, _ i: Int32) -> String {
        sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
    }

    private func query<T>(_ sql: String, _ args: [Any] = [], _ row: (OpaquePointer?) -> T) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw LibraryError.sql(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, transient)
            default: break
            }
        }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(row(stmt)) }
            else if rc == SQLITE_DONE { break }
            else { throw LibraryError.sql(String(cString: sqlite3_errmsg(db))) }
        }
        return out
    }
}
