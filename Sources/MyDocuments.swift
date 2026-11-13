import Foundation
import SQLite3

/// Documents the person adds themselves (gear manuals, PDFs, notes), indexed on this iPhone in the library's own
/// format so search, answers and browsing cover them too (see `Library.combining`). One source per file: key
/// `mine-…` in `sources`, its text in `text/<key>.md`, doc and passage ids from `Library.mineIDBase` up.
/// Nothing leaves the phone.
final class MyDocuments: @unchecked Sendable {
    struct Item: Identifiable, Hashable, Sendable {
        let key: String
        let title: String
        let filename: String
        let sections: Int
        let added: Date
        var id: String { key }
    }

    static let license = "Your document, kept on this iPhone"
    static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "MyDocuments", directoryHint: .isDirectory)
    }

    let folder: URL
    private var db: OpaquePointer?
    private let lock = NSLock()

    init(folder: URL = defaultFolder) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder.appending(path: "text"), withIntermediateDirectories: true)
        let path = folder.appending(path: "index.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK
        else { throw Library.LibraryError.cannotOpen }
        // The same tables as library/build_library.py, plus when each file was added.
        try exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS sources(id INTEGER PRIMARY KEY, key TEXT UNIQUE, label TEXT, topic TEXT,
                                               origin TEXT, docs INT DEFAULT 0, done INT DEFAULT 0, license TEXT,
                                               added REAL);
            CREATE TABLE IF NOT EXISTS files(id INTEGER PRIMARY KEY, path TEXT UNIQUE);
            CREATE TABLE IF NOT EXISTS docs(id INTEGER PRIMARY KEY, source_id INT, title TEXT, url TEXT,
                                            file_id INT, offset INT, length INT);
            CREATE INDEX IF NOT EXISTS docs_title ON docs(title COLLATE NOCASE);
            CREATE TABLE IF NOT EXISTS passages(id INTEGER PRIMARY KEY, doc_id INT, offset INT, length INT);
            CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(title, body, content='', contentless_delete=1,
                                                              tokenize='porter unicode61 remove_diacritics 2');
            """)
    }

    deinit { sqlite3_close(db) }

    /// A reader over these documents, or nil while there are none.
    func library() -> Library? {
        guard !items().isEmpty else { return nil }
        let folder = folder
        return try? Library(locate: { folder.appending(path: $0) }, immutable: false)
    }

    /// Newest first.
    func items() -> [Item] {
        (try? rows("SELECT key, label, origin, docs, added FROM sources WHERE done=1 ORDER BY added DESC") { s in
            Item(key: Self.text(s, 0), title: Self.text(s, 1), filename: Self.text(s, 2),
                 sections: Int(sqlite3_column_int64(s, 3)),
                 added: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)))
        }) ?? []
    }

    /// Indexes one document's sections as a new source. A file added again under the same name replaces the old one.
    @discardableResult
    func add(title: String, filename: String, sections: [DocumentReader.Section]) throws -> Item {
        if let old = items().first(where: { $0.filename == filename }) { try remove(key: old.key) }
        lock.lock(); defer { lock.unlock() }
        let key = Library.minePrefix + UUID().uuidString.prefix(8).lowercased()
        let rel = "\(key).md"
        let added = Date()
        try execLocked("BEGIN")
        do {
            let sourceID = try insert("INSERT INTO sources(key, label, topic, origin, docs, done, license, added) "
                                      + "VALUES(?,?,'mine',?,0,0,?,?)", [key, title, filename, Self.license, added.timeIntervalSince1970])
            let fileID = try insert("INSERT INTO files(path) VALUES(?)", [rel])
            var docID = try nextID("docs"), passageID = try nextID("passages")
            var out = Data()
            func write(_ s: String) -> Int64 {
                let start = Int64(out.count)
                out.append(Data(s.utf8))
                return Int64(out.count) - start
            }
            var docs = 0
            for section in sections {
                let start = Int64(out.count)
                _ = write("# \(section.title)\nSource: \(title)\n\n")
                var passages: [(offset: Int64, length: Int64, heading: String, text: String)] = []
                for (heading, chunk) in Self.passages(section.text) {
                    let offset = Int64(out.count)
                    passages.append((offset, write(chunk), heading, chunk))
                    _ = write("\n\n")
                }
                _ = write("---\n\n")
                guard !passages.isEmpty else { continue }
                _ = try insert("INSERT INTO docs(id, source_id, title, url, file_id, offset, length) VALUES(?,?,?,?,?,?,?)",
                               [docID, sourceID, section.title, "", fileID, start, Int64(out.count) - start])
                for p in passages {
                    _ = try insert("INSERT INTO passages(id, doc_id, offset, length) VALUES(?,?,?,?)",
                                   [passageID, docID, p.offset, p.length])
                    let ftsTitle = section.title == p.heading || p.heading.isEmpty
                        ? section.title : "\(section.title) \(p.heading)"
                    _ = try insert("INSERT INTO fts(rowid, title, body) VALUES(?,?,?)", [passageID, ftsTitle, p.text])
                    passageID += 1
                }
                docID += 1
                docs += 1
            }
            guard docs > 0 else { throw DocumentReader.ReadError.noText }
            try out.write(to: folder.appending(path: "text/\(rel)"), options: .atomic)
            _ = try insert("UPDATE sources SET docs=?, done=1 WHERE id=?", [Int64(docs), sourceID])
            try execLocked("COMMIT")
            return Item(key: key, title: title, filename: filename, sections: docs, added: added)
        } catch {
            try? execLocked("ROLLBACK")
            try? FileManager.default.removeItem(at: folder.appending(path: "text/\(rel)"))
            throw error
        }
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        try execLocked("BEGIN")
        do {
            let inSource = "SELECT d.id FROM docs d JOIN sources s ON s.id = d.source_id WHERE s.key = ?"
            _ = try insert("DELETE FROM fts WHERE rowid IN (SELECT id FROM passages WHERE doc_id IN (\(inSource)))", [key])
            _ = try insert("DELETE FROM passages WHERE doc_id IN (\(inSource))", [key])
            _ = try insert("DELETE FROM docs WHERE id IN (\(inSource))", [key])
            _ = try insert("DELETE FROM files WHERE path = ?", ["\(key).md"])
            _ = try insert("DELETE FROM sources WHERE key = ?", [key])
            try execLocked("COMMIT")
        } catch {
            try? execLocked("ROLLBACK")
            throw error
        }
        try? FileManager.default.removeItem(at: folder.appending(path: "text/\(key).md"))
    }

    // MARK: - Passages

    /// Cuts text into ~1,500-character passages on paragraph boundaries, like library/passages.py, so a person's
    /// documents are found the same way as the library. Returns (heading, passage).
    static func passages(_ text: String, target: Int = 1500, hard: Int = 3000) -> [(heading: String, text: String)] {
        var out: [(String, String)] = [], buf: [String] = [], size = 0, heading = "", bufHeading = ""
        for raw in text.split(separator: /\n{2,}/) {
            var para = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if para.isEmpty { continue }
            if para.hasPrefix("#") {
                if !buf.isEmpty && size > 200 {
                    out.append((bufHeading, buf.joined(separator: "\n\n")))
                    buf = []; size = 0
                }
                heading = para.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if buf.isEmpty { bufHeading = heading }
                buf.append(para)
                size += para.count + 2
                continue
            }
            var pieces: [String] = []
            while para.count > hard {  // a very long paragraph: cut after a sentence
                let chars = Array(para)
                var cut = hard
                if let dot = stride(from: hard - 2, through: target / 2, by: -1)
                    .first(where: { chars[$0] == "." && chars[$0 + 1] == " " }) { cut = dot + 1 }
                pieces.append(String(chars[..<cut]).trimmingCharacters(in: .whitespaces))
                para = String(chars[cut...]).trimmingCharacters(in: .whitespaces)
            }
            pieces.append(para)
            for piece in pieces {
                if !buf.isEmpty && size + piece.count > target {
                    out.append((bufHeading, buf.joined(separator: "\n\n")))
                    buf = []; size = 0; bufHeading = heading
                }
                buf.append(piece)
                size += piece.count + 2
            }
        }
        if !buf.isEmpty { out.append((bufHeading, buf.joined(separator: "\n\n"))) }
        return out
    }

    // MARK: - SQLite

    /// Ids continue from the highest so far, starting at `Library.mineIDBase`.
    private func nextID(_ table: String) throws -> Int64 {
        let max = try rowsLocked("SELECT MAX(id) FROM \(table)") { s in
            sqlite3_column_type(s, 0) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 0)
        }.first ?? nil
        return Swift.max(Library.mineIDBase, (max ?? 0) + 1)
    }

    private func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        try execLocked(sql)
    }

    private func execLocked(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw Library.LibraryError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func insert(_ sql: String, _ args: [Any]) throws -> Int64 {
        _ = try rowsLocked(sql, args) { _ in () }
        return sqlite3_last_insert_rowid(db)
    }

    private func rows<T>(_ sql: String, _ args: [Any] = [], _ row: (OpaquePointer?) -> T) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        return try rowsLocked(sql, args, row)
    }

    private func rowsLocked<T>(_ sql: String, _ args: [Any] = [], _ row: (OpaquePointer?) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Library.LibraryError.sql(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, transient)
            default: sqlite3_bind_null(stmt, idx)
            }
        }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(row(stmt)) }
            else if rc == SQLITE_DONE { break }
            else { throw Library.LibraryError.sql(String(cString: sqlite3_errmsg(db))) }
        }
        return out
    }

    private static func text(_ s: OpaquePointer?, _ i: Int32) -> String {
        sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
    }
}
