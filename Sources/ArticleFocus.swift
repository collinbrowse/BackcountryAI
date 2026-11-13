import Foundation

/// The part of an article a search hit is about: the heading section holding the matched passage, split into
/// what comes before the passage, the passage itself and what follows. Works the same for library articles and
/// the person's own documents, since both are Markdown with `#` headings and passages cut from that same text.
struct ArticleFocus: Equatable, Sendable {
    /// The section's heading, or nil when the focus is the whole article.
    var heading: String?
    var before: String
    var match: String
    var after: String
    var isWhole: Bool { heading == nil }

    /// Articles this short are shown whole: they're already about one thing.
    static let wholeUpTo = 5_000
    /// A section smaller than this widens to its parent section, so a hit isn't cut down to a lone sub-heading.
    static let minSection = 700

    /// `passage` is the stored passage text (see `Library.passageText`). With `narrow` false, or when the passage
    /// can't be found, the focus is the whole article.
    static func make(body: String, passage: String?, narrow: Bool = true) -> ArticleFocus {
        let paras = body.components(separatedBy: "\n\n")
        let whole = ArticleFocus(heading: nil, before: body, match: "", after: "")
        let wanted = (passage ?? "").components(separatedBy: "\n\n").map(key).filter { !$0.isEmpty }
        guard let first = wanted.first, let last = wanted.last else { return whole }
        let keys = paras.map(key)
        guard let s = keys.firstIndex(of: first)
                ?? keys.firstIndex(where: { !$0.isEmpty && ($0.hasSuffix(first) || first.hasSuffix($0)) }) else { return whole }
        let e = keys[s...].firstIndex(of: last) ?? min(paras.count - 1, s + wanted.count - 1)

        var lo = 0, hi = paras.count, heading: String?
        if narrow && body.count > wholeUpTo {
            func level(_ i: Int) -> Int? {
                let t = paras[i].trimmingCharacters(in: .whitespacesAndNewlines)
                let n = t.prefix(while: { $0 == "#" }).count
                return (1...6).contains(n) && t.dropFirst(n).first == " " && !t.contains("\n") ? n : nil
            }
            // The nearest heading at or above the passage, widened to its parent while it's too small.
            var h = (0...s).reversed().first { level($0) != nil }
            while let start = h, let lv = level(start) {
                let end = paras.indices.dropFirst(start + 1).first { (level($0) ?? 99) <= lv } ?? paras.count
                let size = paras[start..<end].reduce(0) { $0 + $1.count + 2 }
                let parent = (0..<start).reversed().first { (level($0) ?? 99) < lv }
                if size >= minSection || parent == nil {
                    lo = start; hi = max(end, e + 1)
                    heading = paras[start].trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "#" }
                        .trimmingCharacters(in: .whitespaces)
                    break
                }
                h = parent
            }
            // A section that's most of the article isn't worth narrowing to.
            let size = paras[lo..<hi].reduce(0) { $0 + $1.count + 2 }
            if Double(size) > Double(body.count) * 0.7 { lo = 0; hi = paras.count; heading = nil }
        }
        func join(_ r: Range<Int>) -> String { r.isEmpty ? "" : paras[r].joined(separator: "\n\n") }
        return ArticleFocus(heading: heading, before: join(lo..<s), match: join(s..<(e + 1)), after: join((e + 1)..<hi))
    }

    /// Paragraph text with whitespace evened out, for matching the passage against the article.
    private static func key(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
