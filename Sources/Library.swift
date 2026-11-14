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

    static let official: Set<String> = ["ready-gov", "cdc-travel", "medlineplus", "nhs-medicines",
        "military-medicine", "wikem", "medical-library", "water", "post-disaster", "food-prep",
        "survival-manuals", "first-aid-guides", "usda-canning", "risk"]
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

    /// Best passages for a question, one per article, official sources ranked up. Each passage's coverage is
    /// the share of the question's words it contains. Ranking is BM25 times coverage, so when nothing has every
    /// word, a passage with most of them beats one that only repeats the rarest word.
    func search(_ question: String, limit: Int = 5, maxChars: Int = 900, only keys: Set<String>? = nil) -> [Passage] {
        let own = searchOwn(question, limit: limit, maxChars: maxChars, only: keys)
        guard let mine else { return own }
        return Self.merge(own, mine: mine.search(question, limit: limit, maxChars: maxChars, only: keys), limit: limit)
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

    private func searchOwn(_ question: String, limit: Int, maxChars: Int, only keys: Set<String>?) -> [Passage] {
        let words = Self.queryWords(question)
        guard !words.isEmpty else { return [] }
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
        guard !hits.isEmpty else { return [] }
        let rank = Dictionary(hits, uniquingKeysWith: { a, _ in a })
        let ids = hits.map { String($0.0) }.joined(separator: ",")
        struct Row { let pid, doc: Int64; let title, label, key: String; let file, off, len: Int64 }
        let rows = (try? query("""
            SELECT p.id, d.id, d.title, s.label, s.key, d.file_id, p.offset, p.length
            FROM passages p JOIN docs d ON d.id = p.doc_id JOIN sources s ON s.id = d.source_id
            WHERE p.id IN (\(ids))
            """) { s in
            Row(pid: sqlite3_column_int64(s, 0), doc: sqlite3_column_int64(s, 1), title: Self.text(s, 2),
                label: Self.text(s, 3), key: Self.text(s, 4), file: sqlite3_column_int64(s, 5),
                off: sqlite3_column_int64(s, 6), len: sqlite3_column_int64(s, 7))
        }) ?? []
        // BM25 ranks are negative (lower is better), so a weight above 1 moves a source up.
        func weight(_ k: String) -> Double { Self.official.contains(k) ? 1.3 : (k == "wikipedia" || k == "wikimed") ? 1.15 : 1 }
        func score(_ r: Row) -> Double { (rank[r.pid] ?? 0) * weight(r.key) * (cover[r.pid] ?? 0) }
        let ordered = rows.sorted { score($0) < score($1) }
        var out: [Passage] = [], seenDocs = Set<Int64>(), seenText = Set<String>()
        for r in ordered {
            if let keys, !keys.contains(r.key) { continue }
            guard !seenDocs.contains(r.doc), !Self.isTranslation(r.title, key: r.key) else { continue }
            seenDocs.insert(r.doc)
            guard let raw = readText(fileID: r.file, offset: r.off, length: r.len) else { continue }
            let flat = Self.flatten(raw)
            guard !seenText.contains(flat) else { continue }
            seenText.insert(flat)
            out.append(Passage(id: r.pid, docID: r.doc, title: r.title, source: r.label, sourceKey: r.key,
                               official: Self.officialLabel.contains(r.key),
                               text: Self.window(flat, words: words, width: maxChars),
                               coverage: cover[r.pid] ?? 0))
            if out.count >= limit { break }
        }
        return out
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

    /// Passages by id, in the order given, one per article (for meaning-based search, which finds passage ids).
    /// Only this library's own passages: the person's documents have no vectors.
    func passages(ids: [Int64], words: [String], maxChars: Int) -> [Passage] {
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
        var out: [Passage] = [], seenDocs = Set<Int64>()
        for id in ids {
            guard let r = byID[id], !seenDocs.contains(r.doc), !Self.isTranslation(r.title, key: r.key),
                  let raw = readText(fileID: r.file, offset: r.off, length: r.len) else { continue }
            seenDocs.insert(r.doc)
            let flat = Self.flatten(raw)
            out.append(Passage(id: r.pid, docID: r.doc, title: r.title, source: r.label, sourceKey: r.key,
                               official: Self.officialLabel.contains(r.key),
                               text: Self.window(flat, words: words, width: maxChars), coverage: nil))
        }
        return out
    }

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
