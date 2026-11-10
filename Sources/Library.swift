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
final class Library: @unchecked Sendable {
    let folder: URL
    private var db: OpaquePointer?
    private let lock = NSLock()

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

    init(folder: URL) throws {
        self.folder = folder
        let path = folder.appendingPathComponent("index.sqlite").path
        guard sqlite3_open_v2("file:\(path)?immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
        else { throw LibraryError.cannotOpen }
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
        (try? query("SELECT COALESCE(SUM(docs),0), COUNT(*) FROM sources WHERE done=1") { s in
            (Int(sqlite3_column_int64(s, 0)), Int(sqlite3_column_int64(s, 1)))
        }.first) ?? (0, 0)
    }

    func sourceLabels() -> [String] {
        (try? query("SELECT label FROM sources WHERE done=1 ORDER BY docs DESC") { Self.text($0, 0) }) ?? []
    }

    static func queryWords(_ q: String) -> [String] {
        let lower = q.lowercased()
        let regex = /[\w']+/
        return lower.matches(of: regex).map { String($0.output) }
            .filter { $0.count > 1 && !stopwords.contains($0) }
            .prefix(12).map { $0 }
    }

    /// Best passages for a question, one per article, official sources ranked up.
    func search(_ question: String, limit: Int = 5, maxChars: Int = 900) -> [Passage] {
        let words = Self.queryWords(question)
        guard !words.isEmpty else { return [] }
        let terms = words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "") + "\"" }
        var hits: [(Int64, Double)] = []
        for joiner in [" ", " OR "] {  // all words first; any word if that finds too little
            hits = (try? query("SELECT rowid, rank FROM fts WHERE fts MATCH ? AND rank MATCH 'bm25(4.0, 1.0)' "
                               + "ORDER BY rank LIMIT 300", [terms.joined(separator: joiner)]) { s in
                (sqlite3_column_int64(s, 0), sqlite3_column_double(s, 1))
            }) ?? []
            if hits.count >= 3 || words.count == 1 { break }
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
        let ordered = rows.sorted { (rank[$0.pid] ?? 0) * weight($0.key) < (rank[$1.pid] ?? 0) * weight($1.key) }
        var out: [Passage] = [], seenDocs = Set<Int64>(), seenText = Set<String>()
        for r in ordered {
            guard !seenDocs.contains(r.doc) else { continue }
            seenDocs.insert(r.doc)
            guard let raw = readText(fileID: r.file, offset: r.off, length: r.len) else { continue }
            let flat = Self.flatten(raw)
            guard !seenText.contains(flat) else { continue }
            seenText.insert(flat)
            out.append(Passage(id: r.pid, docID: r.doc, title: r.title, source: r.label, sourceKey: r.key,
                               official: Self.officialLabel.contains(r.key),
                               text: Self.window(flat, words: words, width: maxChars)))
            if out.count >= limit { break }
        }
        return out
    }

    func article(docID: Int64) -> Article? {
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
        let url = folder.appendingPathComponent("text").appendingPathComponent(rel)
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
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
