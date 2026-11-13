import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

/// Turns a file the person adds into titled sections of plain text (Markdown headings allowed), all on the phone.
/// PDFs split at their bookmarks, like library/build_library.py does for the bundled manuals, so a hit reads
/// "Replacing the Filter" instead of one more piece of a 90-page manual. Scanned pages and photos are read with
/// Apple's on-device text recognition.
enum DocumentReader {
    struct Section: Sendable, Equatable {
        var title: String
        var text: String
    }

    struct Document: Sendable {
        let title: String
        let sections: [Section]
    }

    enum ReadError: LocalizedError {
        case unsupported, locked, unreadable, noText
        var errorDescription: String? {
            switch self {
            case .unsupported: "This kind of file isn't supported. Try a PDF, a photo, or a text, Markdown, RTF or web page file."
            case .locked: "This PDF is password-protected. Remove the password, then add it again."
            case .unreadable: "This file couldn't be opened."
            case .noText: "No text was found in this file."
            }
        }
    }

    static let markdown = UTType(filenameExtension: "md") ?? .plainText
    /// What the file picker offers.
    static let types: [UTType] = [.pdf, .image, .plainText, markdown, .rtf, .html]

    /// About this many characters per section when a document has no bookmarks to split at.
    static let sectionChars = 12_000
    /// Sections shorter than this join the next one (a bookmark for a half-empty page).
    static let minChars = 300

    /// `progress` gets short status lines ("Reading page 3 of 40").
    static func read(_ url: URL, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Document {
        let title = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        let sections: [Section]
        if type?.conforms(to: .pdf) == true {
            sections = try await pdf(url, title: title, progress: progress)
        } else if type?.conforms(to: .image) == true {
            progress("Reading the text in the photo")
            sections = split(try await recognize(url: url), title: title)
        } else if type?.conforms(to: .rtf) == true {
            let s = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                           documentAttributes: nil)
            sections = split(s.string, title: title)
        } else if type?.conforms(to: .html) == true {
            let data = try Data(contentsOf: url)
            // The HTML importer uses WebKit, which wants the main thread.
            let text = try await MainActor.run {
                try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                             .characterEncoding: String.Encoding.utf8.rawValue],
                                       documentAttributes: nil).string
            }
            sections = split(text, title: title)
        } else if type?.conforms(to: .plainText) == true || ["md", "markdown", "txt", "text"].contains(ext) {
            var encoding = String.Encoding.utf8
            let text = try (try? String(contentsOf: url, usedEncoding: &encoding))
                ?? String(decoding: Data(contentsOf: url), as: UTF8.self)
            sections = split(text, title: title)
        } else {
            throw ReadError.unsupported
        }
        guard sections.contains(where: { $0.text.contains(where: \.isLetter) }) else { throw ReadError.noText }
        return Document(title: title, sections: sections)
    }

    // MARK: - Plain text

    /// One section for a short text; for a long one, sections of about `sectionChars` on paragraph boundaries,
    /// each titled by its first heading or numbered.
    static func split(_ text: String, title: String) -> [Section] {
        let clean = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        if clean.count <= sectionChars * 3 / 2 { return [Section(title: title, text: clean)] }
        var out: [Section] = [], buf: [String] = [], size = 0
        func flush() {
            guard !buf.isEmpty else { return }
            let heading = buf.first(where: { $0.hasPrefix("#") })
                .map { $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            out.append(Section(title: heading.map { "\($0) (\(title))" } ?? "\(title), part \(out.count + 1)",
                               text: buf.joined(separator: "\n\n")))
            buf = []; size = 0
        }
        for para in clean.split(separator: /\n{2,}/).map(String.init) {
            // Start a new section at a heading once this one is big enough, or anywhere once it's too big.
            if size > sectionChars || (size > sectionChars / 2 && para.hasPrefix("#")) { flush() }
            buf.append(para)
            size += para.count + 2
        }
        flush()
        return out
    }

    // MARK: - PDF

    static func pdf(_ url: URL, title: String, progress: @escaping @Sendable (String) -> Void) async throws -> [Section] {
        guard let doc = PDFDocument(url: url) else { throw ReadError.unreadable }
        if doc.isLocked && !doc.unlock(withPassword: "") { throw ReadError.locked }
        let count = doc.pageCount
        var pages: [String] = []
        for i in 0..<count {
            try Task.checkCancellation()
            guard let page = doc.page(at: i) else { pages.append(""); continue }
            let text = page.string ?? ""
            if text.filter(\.isLetter).count >= 40 {
                if i % 10 == 0 { progress("Reading page \(i + 1) of \(count)") }
                pages.append(text)
            } else {  // a scanned page, or only a picture
                progress("Scanning page \(i + 1) of \(count)")
                let scanned = (try? await recognize(page: page)) ?? ""
                pages.append(scanned.filter(\.isLetter).count > text.filter(\.isLetter).count ? scanned : text)
            }
        }
        return sections(pages: pages, marks: bookmarks(doc), title: title)
    }

    /// Bookmarks as (page index, depth, title), in order. Figures, tables and the like are left out; contents and
    /// index pages come back with an empty title, meaning "drop these pages" (index lines match every search).
    static func bookmarks(_ doc: PDFDocument) -> [(page: Int, depth: Int, title: String)] {
        var out: [(Int, Int, String)] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let label = (child.label ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if let page = child.destination?.page, !label.isEmpty {
                    if label.wholeMatch(of: backMatter) != nil {
                        out.append((doc.index(for: page), depth, ""))
                    } else if label.firstMatch(of: junkBookmark) == nil {
                        out.append((doc.index(for: page), depth, label))
                    }
                }
                walk(child, depth: depth + 1)
            }
        }
        if let root = doc.outlineRoot { walk(root, depth: 0) }
        // One bookmark wrapping the whole document isn't a chapter.
        if out.filter({ $0.1 == 0 }).count == 1 { out = out.filter { $0.1 > 0 }.map { ($0.0, $0.1 - 1, $0.2) } }
        return out
    }

    nonisolated(unsafe) static let junkBookmark = /(?i)^(figure|table)\b|^(cover|figures|tables|glossary|references|notes)$/
    nonisolated(unsafe) static let backMatter = /(?i)contents|table of contents|index/

    /// Sections from PDF pages: one per page where a bookmark starts (titled by its most specific bookmark and its
    /// chapter), or, without enough bookmarks, runs of pages of about `sectionChars`.
    static func sections(pages: [String], marks: [(page: Int, depth: Int, title: String)], title: String) -> [Section] {
        let running = runningLines(pages)
        if marks.filter({ !$0.title.isEmpty }).count >= 3 {
            var chain: [Int: String] = [:], starts: [Int: String] = [:]
            for m in marks where m.page >= 0 && m.page < pages.count {
                if m.title.isEmpty { starts[m.page] = ""; continue }  // contents or index: dropped below
                chain = chain.filter { $0.key < m.depth }
                chain[m.depth] = m.title
                let names = chain.keys.sorted().map { chain[$0]! }
                starts[m.page] = names.count == 1 ? names[0] : "\(names.last!) (\(names[0]))"
            }
            var cuts = starts.keys.sorted()
            if cuts.first != 0 { cuts.insert(0, at: 0); starts[0] = title }
            var out: [Section] = [], pending = ""
            for (i, start) in cuts.enumerated() {
                let end = i + 1 < cuts.count ? cuts[i + 1] : pages.count
                if starts[start] == "" { continue }
                let text = (pending.isEmpty ? "" : pending + "\n\n") + pagesToText(pages[start..<end], running: running)
                if text.count < minChars && end < pages.count { pending = text; continue }  // too short alone
                pending = ""
                out.append(Section(title: starts[start] ?? title, text: text))
            }
            return out.filter { !$0.text.isEmpty }
        }
        // No useful bookmarks: the document's own table of contents, if its entries can be found as headings.
        if let found = contentsSections(pages: pages, running: running, title: title) { return found }
        // Nothing to go on: runs of pages, titled by their page numbers.
        var out: [Section] = [], first = 0, buf: [String] = [], size = 0
        func flush(through last: Int) {
            let text = buf.joined(separator: "\n\n")
            if !text.isEmpty {
                out.append(Section(title: first == last ? "\(title), page \(first + 1)"
                                   : "\(title), pages \(first + 1)–\(last + 1)", text: text))
            }
            buf = []; size = 0; first = last + 1
        }
        for i in pages.indices {
            let text = pagesToText(pages[i...i], running: running)
            buf.append(text)
            size += text.count
            if size >= sectionChars { flush(through: i) }
        }
        if !buf.isEmpty { flush(through: pages.count - 1) }
        if out.count == 1 { out[0].title = title }
        return out
    }

    // MARK: - Table of contents

    /// A contents line: a title, dot leaders, maybe a page number ("Lightning Injuries ........ 166").
    nonisolated(unsafe) static let contentsLine = /(.*?[A-Za-z].*?)\s*(?:\.\s?){4,}\s*\d*\s*/
    nonisolated(unsafe) static let chapterLine = /(?i)chapter\s+\d+\s*[:.\-–]?\s*(.+)/

    /// Sections from a PDF without bookmarks, using its contents pages: each contents entry starts a section where
    /// its title stands alone as a line later on (case and word order aside, "Frost Bite" = "Frostbite").
    /// Contents pages themselves are left out. Nil when fewer than three entries are found.
    static func contentsSections(pages: [String], running: Set<String>, title: String) -> [Section]? {
        // Entries in order, each with the chapter it's listed under.
        var entries: [(title: String, chapter: String?)] = [], chapter: String?, contentsPages = Set<Int>()
        for (i, page) in pages.enumerated() {
            let lines = page.split(separator: "\n").map(normalize)
            let leaders = lines.compactMap { $0.wholeMatch(of: contentsLine).map { String($0.1) } }
            guard leaders.count >= 3 else { continue }
            contentsPages.insert(i)
            for line in lines {
                if let m = line.wholeMatch(of: chapterLine), line.wholeMatch(of: contentsLine) == nil {
                    chapter = String(m.1).trimmingCharacters(in: .whitespaces)
                } else if let m = line.wholeMatch(of: contentsLine) {
                    var t = String(m.1).trimmingCharacters(in: .whitespaces)
                    if let c = t.wholeMatch(of: chapterLine) { chapter = String(c.1); t = String(c.1) ; continue }
                    entries.append((t, chapter))
                }
            }
        }
        guard entries.count >= 3 else { return nil }
        var byKey: [String: Int] = [:]
        for (i, e) in entries.enumerated() {
            for k in matchKeys(e.title) where byKey[k] == nil { byKey[k] = i }
        }
        func entry(_ line: String) -> Int? {
            guard line.count < 80 else { return nil }
            return matchKeys(line).lazy.compactMap { byKey[$0] }.first
        }
        // Every standalone line naming an entry, except in a list of entries (a chapter's opening page).
        var candidates: [(page: Int, line: Int, entry: Int)] = []
        let pageLines = pages.map { $0.split(separator: "\n").map(normalize).filter { !$0.isEmpty } }
        for (p, lines) in pageLines.enumerated() where !contentsPages.contains(p) {
            for (i, line) in lines.enumerated() {
                guard let n = entry(line) else { continue }
                let neighbors = [i - 1, i + 1].filter(lines.indices.contains).map { lines[$0] }
                if !neighbors.contains(where: { entry($0) != nil }) { candidates.append((p, i, n)) }
            }
        }
        // Entries come in contents order, so keep the longest run of candidates in that order: a passing
        // mention of a later topic, or a running header, then can't start a section early.
        var best = [Int](repeating: 1, count: candidates.count), prev = [Int](repeating: -1, count: candidates.count)
        for i in candidates.indices {
            for j in 0..<i where candidates[j].entry < candidates[i].entry && best[j] + 1 > best[i] {
                best[i] = best[j] + 1; prev[i] = j
            }
        }
        var starts: [Int: [Int: Int]] = [:]  // page → line → entry
        var k = best.indices.max { best[$0] < best[$1] }
        while let i = k, i >= 0 {
            starts[candidates[i].page, default: [:]][candidates[i].line] = candidates[i].entry
            k = prev[i] >= 0 ? prev[i] : nil
        }
        guard starts.values.reduce(0, { $0 + $1.count }) >= 3 else { return nil }

        var out: [Section] = [], label = title, buf: [String] = [], current: Int?
        var headerKeys = Set<String>()  // the current entry and chapter, alone or together: running headers
        func flush() {
            let text = buf.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buf = []
            guard text.contains(where: \.isLetter) else { return }
            if text.count < minChars {  // too short alone: part of the one before, or front-matter scraps
                if var last = out.popLast() { last.text += "\n\n" + text; out.append(last) }
            } else {
                out.append(Section(title: label, text: text))
            }
        }
        for (p, lines) in pageLines.enumerated() where !contentsPages.contains(p) {
            var chunk: [String] = []
            for (i, line) in lines.enumerated() {
                if let n = starts[p]?[i] {
                    buf.append(pagesToText([chunk.joined(separator: "\n")], running: running))
                    chunk = []
                    flush()
                    current = n
                    let e = entries[n]
                    label = e.chapter.map { "\(e.title) (\($0.capitalizedIfShouting))" } ?? e.title
                    headerKeys = Set([e.title, e.chapter ?? "", "\(e.chapter ?? "") \(e.title)", "\(e.title) \(e.chapter ?? "")"]
                        .flatMap(matchKeys))
                    buf.append("## " + e.title)
                } else if current != nil && line.count < 80 && !matchKeys(line).filter(headerKeys.contains).isEmpty {
                    continue
                } else {
                    chunk.append(line)
                }
            }
            buf.append(pagesToText([chunk.joined(separator: "\n")], running: running))
        }
        flush()
        // A very long entry (a whole chapter with no listed parts) still gets cut into readable pieces.
        return out.flatMap { s -> [Section] in
            guard s.text.count > sectionChars * 3 / 2 else { return [s] }
            return split(s.text, title: s.title).enumerated().map { i, piece in
                Section(title: i == 0 ? s.title : "\(s.title), part \(i + 1)", text: piece.text)
            }
        }
    }

    /// Ways a heading can be written and still be the same entry: word order and spacing aside.
    static func matchKeys(_ s: String) -> [String] {
        let words = s.lowercased().replacingOccurrences(of: "&", with: " and ")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard words.joined().count >= 4 else { return [] }
        return [words.sorted().joined(separator: " "), words.joined()]
    }

    /// Short lines repeated on many pages: running headers and footers. Lines at the top or bottom of a page also
    /// count with their numbers blanked ("30 September 2025 TC 21-3 57"), since footers carry the page number.
    static func runningLines(_ pages: [String]) -> Set<String> {
        guard pages.count >= 5 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            let lines = page.split(separator: "\n").map(normalize).filter { !$0.isEmpty }
            var keys = Set(lines.filter { $0.count < 70 })
            for (i, line) in lines.enumerated() where line.count < 70 && (i < edgeLines || i >= lines.count - edgeLines) {
                keys.insert(numbersBlanked(line))
            }
            for key in keys { counts[key, default: 0] += 1 }
        }
        let floor = max(5, pages.count / 10)
        return Set(counts.filter { $0.value >= floor }.keys)
    }

    /// Paragraphs from PDF page text, which comes as hard-wrapped lines. A line ends a paragraph when it's short
    /// and ends a sentence; lines in capitals on their own ("REPLACING THE FILTER") become headings; contents
    /// lines ("Filter ........ 12") and running headers go.
    static func pagesToText(_ pages: ArraySlice<String>, running: Set<String>) -> String {
        var out: [String] = []
        for page in pages {
            let lines = page.split(separator: "\n", omittingEmptySubsequences: false).map(normalize)
            let lengths = lines.map(\.count).filter { $0 > 0 }.sorted()
            let typical = lengths.isEmpty ? 0 : lengths[lengths.count * 4 / 5]
            var buf = ""
            func flush() {
                if !buf.isEmpty && buf.firstMatch(of: tocLeader) == nil { out.append(buf) }
                buf = ""
            }
            let nonEmpty = lines.indices.filter { !lines[$0].isEmpty }
            let edges = Set(nonEmpty.prefix(edgeLines) + nonEmpty.suffix(edgeLines))
            for (i, line) in lines.enumerated() {
                if line.isEmpty { flush(); continue }
                if running.contains(line) || (edges.contains(i) && running.contains(numbersBlanked(line)))
                    || line.wholeMatch(of: /\d{1,4}|page \d+( of \d+)?/.ignoresCase()) != nil {
                    continue
                }
                let letters = line.filter(\.isLetter)
                if letters.count >= 5, line.count < 70, letters.allSatisfy(\.isUppercase) {
                    flush()
                    out.append("## " + line.capitalized)
                    continue
                }
                if buf.hasSuffix("-"), line.first?.isLowercase == true {
                    buf.removeLast()  // a word hyphenated across lines
                    buf += line
                } else {
                    buf += buf.isEmpty ? line : " " + line
                }
                if line.last.map({ ".!?:".contains($0) }) == true && Double(line.count) < Double(typical) * 0.8 {
                    flush()
                }
            }
            flush()
        }
        return out.joined(separator: "\n\n")
    }

    /// How many lines at the top and bottom of a page can be a header or footer.
    static let edgeLines = 2

    static func numbersBlanked(_ line: String) -> String {
        "#" + line.replacing(/\d+/, with: "#")
    }

    nonisolated(unsafe) static let tocLeader = /\.{5,}\s*\d+|(\. ){4,}\s*\d+/

    private static func normalize<S: StringProtocol>(_ line: S) -> String {
        line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Text recognition

    static func recognize(page: PDFPage) async throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2200 / max(bounds.width, bounds.height, 1)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        guard let cg = image.cgImage else { return "" }
        return paragraphs(try await request().perform(on: cg))
    }

    /// A photo, turned upright from its EXIF orientation.
    static func recognize(url: URL) async throws -> String {
        paragraphs(try await request().perform(on: url))
    }

    private static func request() -> RecognizeTextRequest {
        var r = RecognizeTextRequest()
        r.recognitionLevel = .accurate
        r.usesLanguageCorrection = true
        return r
    }

    /// Recognized lines in reading order, a blank line wherever the gap above a line is bigger than a line.
    private static func paragraphs(_ lines: [RecognizedTextObservation]) -> String {
        var out = "", previous: CGRect?
        for line in lines {
            guard let text = line.topCandidates(1).first?.string else { continue }
            let box = line.boundingBox.cgRect  // normalized, origin at the bottom left
            if let previous {
                let gap = previous.minY - box.maxY
                out += gap > max(previous.height, box.height) * 0.9 || gap < -previous.height ? "\n\n" : "\n"
            }
            out += text
            previous = box
        }
        return out
    }
}

private extension String {
    /// "ENVIRONMENTAL MEDICINE" → "Environmental Medicine"; anything with lowercase letters stays as it is.
    var capitalizedIfShouting: String {
        let letters = filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase) ? capitalized : self
    }
}
