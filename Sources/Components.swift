import SwiftUI
import Observation
import UIKit

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
                if passage.official { OfficialBadge() } else if passage.isMine { MineBadge() }
            }
            Text(passage.text).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(3)
            Text(passage.source).font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 18)
    }
}

/// The trail-ready checklist, opened from Scout's menu: a progress ring and the four steps.
struct ReadinessSheet: View {
    let items: [Readiness.Item]
    var act: (Readiness.Item) -> Void
    @Environment(\.dismiss) private var dismiss

    private var done: Int { items.filter(\.done).count }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Theme.hairline, lineWidth: 7)
                        Circle().trim(from: 0, to: CGFloat(done) / CGFloat(max(items.count, 1)))
                            .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(done)/\(items.count)").font(.subheadline.weight(.heavy)).foregroundStyle(Theme.ink)
                    }
                    .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(done == items.count ? "You're trail ready" : "Get trail ready")
                            .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Theme.ink)
                        Text("Do these before you lose signal.").font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                }
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        Button { if !item.done { act(item) } } label: { row(item) }
                            .buttonStyle(.plain)
                            .disabled(item.done)
                    }
                }
                .card(padding: 12)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.background)
            .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold) }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.accent)
    }

    private func row(_ item: Readiness.Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.done ? "checkmark.circle.fill" : item.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.done ? Theme.moss : Theme.accent)
                .frame(width: 30)
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
    /// Smaller and muted: an outline only, for suggestions that shouldn't compete with what's above them.
    var quiet = false
    var body: some View {
        HStack(spacing: quiet ? 5 : 6) {
            if let symbol {
                Image(systemName: symbol).font(quiet ? .caption : .footnote.weight(.bold))
                    .foregroundStyle(quiet ? Theme.inkSoft : tint)
            }
            Text(title).font(quiet ? .footnote : .subheadline.weight(.semibold))
                .foregroundStyle(quiet ? Theme.inkSoft : Theme.ink).lineLimit(1)
        }
        .padding(.horizontal, quiet ? 12 : 14).padding(.vertical, quiet ? 7 : 10)
        .background(quiet ? .clear : Theme.card, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(quiet ? 0 : 0.05), radius: 4, y: 2)
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

// MARK: - The app's ••• menu

/// The app-wide part of the ••• menu, the same on the chat list and in a chat: the trail-ready checklist, the
/// offline library and how Scout works. RootView presents what they open, so they work from either screen.
struct AppMenuSection: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(Router.self) private var router
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let items = Readiness.current(libraryReady: store.hasPack, aiReady: assistant.availabilityProblem == nil)
        Section {
            Button { router.sheet = .readiness } label: {
                Label("Trail-ready checklist · \(items.filter(\.done).count)/\(items.count)", systemImage: "checklist")
            }
            Button { router.sheet = .library } label: {
                Text("Offline library")
                if let text = libraryStatus.text { Text(text) }
                libraryMenuIcon
            }
            Button { router.showHowItWorks = true } label: { Label("How Scout works", systemImage: "questionmark.circle") }
        }
    }

    private var downloads: Downloads { Downloads(store: store, better: BetterModel.shared) }

    /// The menu row's subtitle. Ready means the field guides are on the phone: the person's own documents alone
    /// don't make Scout trail-ready.
    /// Text only when there's something the ring can't say: a stopped download, missing guides, or "ready".
    /// While downloading with nothing wrong, the ring says it all and there's no text.
    private var libraryStatus: (text: String?, symbol: String) {
        let d = downloads
        if d.stopped > 0 { return (d.stoppedText, "exclamationmark.circle") }
        if d.active { return (nil, "arrow.down.circle") }
        if !store.hasPack { return ("No field guides", "arrow.down.circle") }
        return NetworkMonitor.shared.isOnline
            ? ("Ready offline", "checkmark.circle.fill")
            : ("No signal · still works", "antenna.radiowaves.left.and.right.slash")
    }

    /// The menu row's icon. Menus don't redraw while open, so while downloading this is a picture of the ring at
    /// the moment the menu opened; opening it again draws a fresh one.
    private var libraryMenuIcon: Image {
        let d = downloads
        guard d.active || d.stopped > 0 else { return Image(systemName: libraryStatus.symbol) }
        // Drawn as a picture so the menu keeps its colors: the ring, or a red "!" for a stopped download.
        let renderer = ImageRenderer(content: Group {
            if d.active {
                DownloadRing(fraction: d.fraction ?? 0, alert: d.stopped > 0, lineWidth: 3)
            } else {
                Image(systemName: "exclamationmark.circle.fill").resizable()
                    .symbolRenderingMode(.palette).foregroundStyle(.white, Theme.danger)
            }
        }
            .frame(width: 22, height: 22).padding(1))
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return Image(systemName: libraryStatus.symbol) }
        return Image(uiImage: image).renderingMode(.original)
    }
}

/// The ••• button's face: a small red "!" up and to the right while a download is stopped and nothing is
/// downloading (a download in progress shows its own ring in the chat's top bar).
struct AppMenuLabel: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let d = Downloads(store: store, better: BetterModel.shared)
        Image(systemName: "ellipsis")
            .overlay(alignment: .topTrailing) {
                if d.stopped > 0 && !d.active {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.danger)
                        .offset(x: 8, y: -9)
                }
            }
            .accessibilityLabel(d.stopped > 0 ? "More, \(d.stoppedText)" : "More")
    }
}

/// What the app menu opens: the library, the trail-ready checklist and the "How Scout works" tour. Attached once,
/// in RootView, so the menu works the same from the chat list and from a chat.
struct AppSheets: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.openURL) private var openURL
    @AppStorage(Readiness.askedKey) private var asked = false
    @AppStorage(Readiness.offlineKey) private var testedOffline = false
    @State private var showOfflineTip = false

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .sheet(item: $router.sheet) { sheet in
                switch sheet {
                case .library: LibraryView()
                case .readiness:
                    ReadinessSheet(items: Readiness.items(libraryReady: store.hasPack,
                                                          aiReady: assistant.availabilityProblem == nil,
                                                          asked: asked, offline: testedOffline)) { item in
                        router.sheet = nil
                        act(item)
                    }
                }
            }
            .fullScreenCover(isPresented: $router.showHowItWorks) {
                OnboardingView(isReplay: true) { router.showHowItWorks = false }
            }
            .alert("Test it in Airplane Mode", isPresented: $showOfflineTip) {
                Button("OK") {}
            } message: {
                Text("Swipe down from the top-right corner, turn on Airplane Mode, then ask Scout anything. "
                     + "If you get an answer, you're set for the backcountry.")
            }
    }

    private func act(_ item: Readiness.Item) {
        switch item.id {
        // Wait for the checklist to finish closing before opening the next thing.
        case "library": Task { try? await Task.sleep(for: .milliseconds(400)); router.sheet = .library }
        case "ai": if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case "asked": router.ask(Topic.camp[1].question)
        default: Task { try? await Task.sleep(for: .milliseconds(400)); showOfflineTip = true }
        }
    }
}
