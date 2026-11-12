import SwiftUI

/// A model answer split into blocks so numbered steps can be shown as steps, not a wall of text.
enum AnswerBlock: Hashable {
    case step(Int, String)
    case bullet(String)
    case heading(String)
    case paragraph(String)
    case notFromLibrary

    static func parse(_ text: String) -> [AnswerBlock] {
        var blocks: [AnswerBlock] = []
        var paragraph: [String] = []
        var notFromLibrary = false
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            let plain = line.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespaces)
            if plain.lowercased().hasPrefix("not from the library") {
                // Small models sometimes put the label mid-answer or last; show it once, as a badge on top.
                flush()
                notFromLibrary = true
                let rest = plain.dropFirst("not from the library".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespaces))
                if !rest.isEmpty { paragraph.append(rest) }
                continue
            }
            if let m = line.wholeMatch(of: /(\d{1,2})[.)]\s+(.+)/) {
                flush(); blocks.append(.step(Int(m.1) ?? 0, String(m.2))); continue
            }
            if let m = line.wholeMatch(of: /[-*•]\s+(.+)/) {
                flush(); blocks.append(.bullet(String(m.1))); continue
            }
            if let m = line.wholeMatch(of: /#{1,6}\s+(.+)/) {
                flush(); blocks.append(.heading(String(m.1))); continue
            }
            if let m = line.wholeMatch(of: /\*\*([^*]+)\*\*:?/) {
                flush(); blocks.append(.heading(String(m.1))); continue
            }
            // An indented continuation of the previous step or bullet.
            if raw.hasPrefix("   ") || raw.hasPrefix("\t"), paragraph.isEmpty, let last = blocks.last {
                switch last {
                case let .step(n, t): blocks[blocks.count - 1] = .step(n, t + " " + line); continue
                case let .bullet(t): blocks[blocks.count - 1] = .bullet(t + " " + line); continue
                default: break
                }
            }
            paragraph.append(line)
        }
        flush()
        if notFromLibrary { blocks.insert(.notFromLibrary, at: 0) }
        return blocks
    }
}

enum Inline {
    /// Inline markdown with [n] citations turned into tappable "cite:n" links styled as chips.
    static func render(_ s: String, citations: Bool = true) -> AttributedString {
        var source = s
        if citations {
            source = s.replacing(/\[(\d{1,2}(?:\s*,\s*\d{1,2})*)\]/) { m in
                m.1.split(separator: ",").map { n in
                    let n = n.trimmingCharacters(in: .whitespaces)
                    return "[\u{202F}\(n)\u{202F}](cite:\(n))"
                }.joined()
            }
        }
        var attr = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        for run in attr.runs {
            guard let url = run.link, url.scheme == "cite" else { continue }
            attr[run.range].foregroundColor = Theme.accentDeep
            attr[run.range].backgroundColor = Theme.accent.opacity(0.16)
            attr[run.range].font = .caption.weight(.heavy)
            attr[run.range].baselineOffset = 2
            attr[run.range].link = nil  // the whole block is the tap target; a 12pt chip is too small
        }
        return attr
    }

    /// The citation numbers in a block, in order.
    static func citations(in s: String) -> [Int] {
        s.matches(of: /\[(\d{1,2}(?:\s*,\s*\d{1,2})*)\]/).flatMap { m in
            m.1.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
    }
}

/// The formatted answer. Tapping a citation calls `onCite` with its 1-based number.
struct AnswerBody: View {
    let text: String
    var failed = false
    var onCite: (Int) -> Void

    var body: some View {
        let blocks = AnswerBlock.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                tappable(block) { view(for: block, first: isFirstStep(i, blocks)) }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            }
        }
        .animation(.bouncy, value: blocks.count)
        .foregroundStyle(failed ? Theme.inkSoft : Theme.ink)
        .tint(Theme.accentDeep)
    }

    /// A block that cites a source opens it when tapped.
    @ViewBuilder private func tappable(_ block: AnswerBlock, @ViewBuilder _ content: () -> some View) -> some View {
        let text: String? = switch block {
        case let .step(_, t), let .bullet(t), let .paragraph(t): t
        default: nil
        }
        if let text, let n = Inline.citations(in: text).first {
            Button { onCite(n) } label: { content().contentShape(.rect) }
                .buttonStyle(SquishyButtonStyle(scale: 0.98))
                .accessibilityHint("Opens source \(n)")
        } else {
            content()
        }
    }

    private func isFirstStep(_ i: Int, _ blocks: [AnswerBlock]) -> Bool {
        guard case .step = blocks[i] else { return false }
        return !blocks[..<i].contains { if case .step = $0 { true } else { false } }
    }

    @ViewBuilder private func view(for block: AnswerBlock, first: Bool) -> some View {
        switch block {
        case let .step(n, t):
            HStack(alignment: .top, spacing: 12) {
                Text("\(n)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(first ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.pine), in: .circle)
                Text(Inline.render(t)).font(.body).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
            }
            .padding(12)
            .background(first ? Theme.accent.opacity(0.10) : Theme.cardRaised, in: .rect(cornerRadius: 16, style: .continuous))
        case let .bullet(t):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(y: -2)
                Text(Inline.render(t)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case let .heading(t):
            Text(Inline.render(t)).font(.system(.headline, design: .rounded)).padding(.top, 4)
        case let .paragraph(t):
            Text(Inline.render(t)).fixedSize(horizontal: false, vertical: true)
        case .notFromLibrary:
            Label("Not from the library: general guidance", systemImage: "exclamationmark.bubble.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.sun)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.sun.opacity(0.14), in: .capsule)
                .padding(.top, 4)
        }
    }
}
