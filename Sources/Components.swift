import SwiftUI
import Observation

/// Kept in a reference so scrolling only redraws the backdrop, not the whole home screen.
@MainActor @Observable final class ScrollOffset { var y: CGFloat = 0 }

/// The landscape behind the home screen: drifts up slower than the content and stretches on pull-down.
struct HomeBackdrop: View {
    let scroll: ScrollOffset
    var body: some View {
        let y = scroll.y
        ZStack(alignment: .top) {
            Theme.background
            Scenery()
                .frame(height: 400 + max(0, -y))
                .offset(y: y > 0 ? -y * 0.55 : 0)
        }
        .ignoresSafeArea()
    }
}

struct TopicTile: View {
    let topic: Topic
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: topic.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(topic.tint)
                .frame(width: 38, height: 38)
                .background(topic.tint.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
            Text(topic.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .card(padding: 10, radius: 18)
    }
}

struct TopicChip: View {
    let topic: Topic
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: topic.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(topic.tint.gradient, in: .circle)
            Text(topic.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
        }
        .frame(width: 112, alignment: .leading)
        .card(padding: 12, radius: 20)
    }
}

struct SearchResultRow: View {
    let passage: Passage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(passage.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                Spacer(minLength: 4)
                if passage.official { OfficialBadge() }
            }
            Text(passage.text).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(3)
            Text(passage.source).font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 18)
    }
}

/// Compact readiness: a ring and the next step, expanding to the full checklist.
struct ReadinessCard: View {
    let items: [Readiness.Item]
    var act: (Readiness.Item) -> Void
    @State private var expanded = false

    private var done: Int { items.filter(\.done).count }
    private var next: Readiness.Item? { items.first { !$0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.bouncy) { expanded.toggle() } } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Theme.hairline, lineWidth: 6)
                        Circle().trim(from: 0, to: CGFloat(done) / CGFloat(items.count))
                            .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(done)/\(items.count)").font(.caption.weight(.heavy)).foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                    }
                    .frame(width: 48, height: 48)
                    .animation(.bouncy, value: done)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get trail ready").font(.headline).foregroundStyle(Theme.ink)
                        if let next {
                            Text("Next: \(next.title)").font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        Button { if !item.done { act(item) } } label: { row(item) }
                            .buttonStyle(.plain)
                            .disabled(item.done)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .card(padding: 14)
        .padding(.horizontal, 16)
    }

    private func row(_ item: Readiness.Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.done ? "checkmark.circle.fill" : item.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.done ? Theme.moss : Theme.accent)
                .frame(width: 30)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.done ? Theme.inkSoft : Theme.ink)
                    .strikethrough(item.done, color: Theme.inkSoft)
                if !item.done { Text(item.detail).font(.caption).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 0)
            if !item.done { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft) }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

/// A short burst of confetti in the app's colors. Runs once per change of `trigger`.
struct ConfettiBurst: View {
    let trigger: Int
    @State private var fired = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pieces: [(x: CGFloat, y: CGFloat, r: Double, c: Color)] = (0..<26).map { i in
        (CGFloat.random(in: -180...180), CGFloat.random(in: -420 ... -120), Double.random(in: -360...360),
         [Theme.accent, Theme.sun, Theme.sky, Theme.moss, Theme.danger][i % 5])
    }

    var body: some View {
        ZStack {
            ForEach(pieces.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(pieces[i].c)
                    .frame(width: 8, height: 12)
                    .rotationEffect(.degrees(fired ? pieces[i].r : 0))
                    .offset(x: fired ? pieces[i].x : 0, y: fired ? pieces[i].y : 0)
                    .opacity(fired ? 0 : 1)
            }
        }
        .opacity(trigger > 0 && !reduceMotion ? 1 : 0)
        .allowsHitTesting(false)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 80)
        .onChange(of: trigger) {
            fired = false
            withAnimation(.easeOut(duration: 1.6)) { fired = true }
        }
        .sensoryFeedback(.success, trigger: trigger)
    }
}

/// Lays children out left to right, wrapping onto new lines like words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let r = rows.count - 1
            rows[r].width += rows[r].items.isEmpty ? size.width : size.width + spacing
            rows[r].height = max(rows[r].height, size.height)
            rows[r].items.append(i)
        }
        return rows
    }
}

/// A quick reply: tap to send it to Scout.
struct SuggestionChip: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.accent
    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.footnote.weight(.bold)).foregroundStyle(tint)
            }
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

/// A selectable filter capsule for the Guide.
struct FilterChip: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(selected ? .white : Theme.ink)
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background {
            if selected { Capsule().fill(Theme.accentGradient) } else { Capsule().fill(Theme.card) }
        }
        .overlay(Capsule().strokeBorder(selected ? .clear : Theme.hairline))
        .animation(.bouncy, value: selected)
    }
}
