import SwiftUI
import Observation
import UIKit

enum Route: Hashable {
    case conversation
    case saved(SavedAnswer)
    case savedList
}

/// The one screen people open the app to. Type and the library answers instantly (no AI, no battery);
/// send and Scout writes a step-by-step answer. Emergencies are one tap away.
struct HomeView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(SavedStore.self) private var saved
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var path: [Route] = []
    @State private var query = ""
    @State private var results: [Passage] = []
    @State private var searching = false
    @State private var openArticle: Passage?
    @State private var showLibrary = false
    @State private var showSOS = false
    @State private var showGuide = false
    @State private var showOfflineTip = false
    @State private var aiProblem: String?? = nil
    @State private var confetti = 0
    @State private var scroll = ScrollOffset()
    @FocusState private var focused: Bool

    @AppStorage(Readiness.askedKey) private var asked = false
    @AppStorage(Readiness.offlineKey) private var testedOffline = false
    @AppStorage(Readiness.celebratedKey) private var celebrated = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var aiReady: Bool { aiProblem == .some(nil) }
    private var readiness: [Readiness.Item] {
        Readiness.items(libraryReady: store.library != nil, aiReady: aiReady, asked: asked, offline: testedOffline)
    }
    private var readyCount: Int { readiness.filter(\.done).count }

    private var mood: Scout.Mood {
        if confetti > 0 && readyCount == readiness.count { return .happy }
        if store.library == nil && !store.isWorking { return .sleepy }
        if !trimmed.isEmpty { return .thinking }
        return .idle
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if trimmed.count >= 2 {
                        liveResults
                    } else {
                        if readyCount < readiness.count { ReadinessCard(items: readiness, act: act).riseIn(1) }
                        if !assistant.messages.isEmpty { continueCard.riseIn(2) }
                        urgentSection.riseIn(2)
                        campSection.riseIn(3)
                        if !saved.items.isEmpty { savedSection.riseIn(4) }
                        footerNote
                    }
                }
                .padding(.bottom, 30)
                .animation(.bouncy, value: trimmed.count >= 2)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) {
                scroll.y = $1
            }
            .background { HomeBackdrop(scroll: scroll) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .conversation: ConversationView()
                case let .saved(item): SavedAnswerView(item: item)
                case .savedList: SavedListView()
                }
            }
            .overlay { ConfettiBurst(trigger: confetti) }
        }
        .tint(Theme.ember)
        .sheet(isPresented: $showLibrary) { LibraryView() }
        .sheet(isPresented: $showSOS) { SOSSheet { ask($0.question) } }
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
        .fullScreenCover(isPresented: $showGuide) { OnboardingView(isReplay: true) { showGuide = false } }
        .alert("Test it in Airplane Mode", isPresented: $showOfflineTip) {
            Button("OK") {}
        } message: {
            Text("Swipe down from the top-right corner, turn on Airplane Mode, then ask Scout anything. "
                 + "If you get an answer, you're set for the backcountry.")
        }
        .task(id: scenePhase) { await watchAI() }
        .task(id: trimmed) { await search() }
        .onChange(of: readyCount) { old, new in
            if new == readiness.count && old < new && !celebrated {
                celebrated = true
                confetti += 1
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        Group {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(heroInk.opacity(0.8))
                        Text("What's going on?")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(heroInk)
                    }
                    Spacer()
                    Scout(mood: mood, size: 96).offset(y: 18)
                }
                .padding(.top, 34)
                askField
            }
            .padding(.horizontal, 16)
        }
    }

    /// Text over the sky: dark by day, light at night.
    private var heroInk: Color { Color(light: 0x16241D, dark: 0xF4F1EA) }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<21: "Good evening"
        default: "Late night out there"
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            statusPill
            Spacer()
            Button { showSOS = true } label: {
                Text("SOS")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.danger, in: .capsule)
            }
            .buttonStyle(SquishyButtonStyle(scale: 0.9))
            .accessibilityLabel("Emergency help")
            Menu {
                Button { showLibrary = true } label: { Label("Offline library", systemImage: "books.vertical") }
                Button { path.append(.savedList) } label: { Label("Saved answers", systemImage: "bookmark") }
                Button { showGuide = true } label: { Label("How Scout works", systemImage: "questionmark.circle") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(heroInk)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("More")
        }
        .padding(.top, 6)
    }

    private var statusPill: some View {
        let online = NetworkMonitor.shared.isOnline
        let (text, symbol, tint): (String, String, Color) =
            store.library == nil ? ("No library yet", "books.vertical", Theme.danger)
            : online ? ("\(store.articleCount.formatted(.number.notation(.compactName))) articles · offline-ready", "checkmark.circle.fill", Theme.pine)
            : ("No signal · Scout still works", "antenna.radiowaves.left.and.right.slash", Theme.pine)
        return HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption.weight(.bold))
            Text(text).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .onTapGesture { showLibrary = true }
    }

    private var askField: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft).padding(.bottom, 3)
            TextField("Describe what's happening…", text: $query, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { ask(trimmed) }
                .foregroundStyle(Theme.ink)
            if !trimmed.isEmpty {
                Button { ask(trimmed) } label: {
                    Image(systemName: "arrow.up").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Theme.emberGradient, in: .circle)
                }
                .buttonStyle(SquishyButtonStyle(scale: 0.85))
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Ask Scout")
            }
        }
        .animation(.bouncy, value: trimmed.isEmpty)
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .frame(minHeight: 54)
        .background(Theme.card, in: .rect(cornerRadius: 27, style: .continuous))
        .shadow(color: .black.opacity(focused ? 0.16 : 0.1), radius: focused ? 18 : 12, y: 6)
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous)
            .strokeBorder(focused ? Theme.ember.opacity(0.6) : Theme.hairline, lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    // MARK: Live search

    private var liveResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { ask(trimmed) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title3).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(Theme.emberGradient, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aiReady ? "Ask Scout for step-by-step help" : "Ask Scout")
                            .font(.headline).foregroundStyle(Theme.ink)
                        Text(aiReady ? "Written on this phone from the library · uses some battery"
                             : "Apple Intelligence isn't ready, so Scout will show library matches")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
                }
                .card(padding: 12)
            }
            .buttonStyle(SquishyButtonStyle(scale: 0.97))

            HStack {
                Text("In the library · instant, no AI").sectionLabel()
                if searching { ProgressView().controlSize(.mini) }
            }
            .padding(.top, 4)

            if store.library == nil {
                Button { showLibrary = true } label: {
                    Label("Download the library to search it", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            } else if results.isEmpty && !searching {
                Text("No matches. Try other words, like what you see or feel.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { i, p in
                Button { openArticle = p } label: { SearchResultRow(passage: p) }
                    .buttonStyle(SquishyButtonStyle(scale: 0.98))
                    .riseIn(i)
            }
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }

    private func search() async {
        let q = trimmed
        guard q.count >= 2, let lib = store.library else { results = []; return }
        try? await Task.sleep(for: .milliseconds(220))  // wait for typing to pause
        guard !Task.isCancelled else { return }
        searching = true
        let hits = await Task.detached(priority: .userInitiated) { lib.search(q, limit: 12, maxChars: 220) }.value
        guard !Task.isCancelled else { return }
        searching = false
        withAnimation(.bouncy) { results = hits }
    }

    // MARK: Sections

    private var continueCard: some View {
        Button { path.append(.conversation) } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .foregroundStyle(Theme.pine)
                    .frame(width: 40, height: 40)
                    .background(Theme.pine.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick up where you left off").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                    Text(assistant.messages.last(where: { $0.role == .user })?.text ?? "")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
            }
            .card(padding: 12)
        }
        .buttonStyle(SquishyButtonStyle(scale: 0.97))
        .padding(.horizontal, 16)
    }

    private var urgentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Theme.danger).frame(width: 7, height: 7)
                Text("First aid").sectionLabel()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Topic.urgent) { t in
                    Button { ask(t.question) } label: { TopicTile(topic: t) }
                        .buttonStyle(SquishyButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var campSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Out here").sectionLabel().padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Topic.camp) { t in
                        Button { ask(t.question) } label: { TopicChip(topic: t) }
                            .buttonStyle(SquishyButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved · free to reread").sectionLabel()
                Spacer()
                if saved.items.count > 3 {
                    Button("See all") { path.append(.savedList) }.font(.footnote.weight(.semibold))
                }
            }
            ForEach(saved.items.prefix(3)) { item in
                Button { path.append(.saved(item)) } label: { SavedRow(item: item) }
                    .buttonStyle(SquishyButtonStyle(scale: 0.98))
            }
        }
        .padding(.horizontal, 16)
    }

    private var footerNote: some View {
        Text("Scout can be wrong. Check the sources, and call 911 if a life is at risk.")
            .font(.caption).foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
    }

    // MARK: Actions

    private func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !assistant.isBusy else { return }
        showSOS = false
        focused = false
        assistant.startNew(q, library: store.library)
        query = ""
        path = [.conversation]
    }

    private func act(_ item: Readiness.Item) {
        switch item.id {
        case "library": showLibrary = true
        case "ai": if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case "asked": ask(Topic.camp[1].question)
        default: showOfflineTip = true
        }
    }

    /// The model's state isn't observable, so poll it while it isn't ready (it may be downloading).
    private func watchAI() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            let p = assistant.availabilityProblem
            if aiProblem != .some(p) { withAnimation(.bouncy) { aiProblem = .some(p) } }
            if p == nil { return }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}

// MARK: - Pieces

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
                .lineLimit(1)
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
            Text(passage.source).font(.caption2.weight(.semibold)).foregroundStyle(Theme.ember)
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
                            .stroke(Theme.emberGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
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
                .foregroundStyle(item.done ? Theme.moss : Theme.ember)
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
         [Theme.ember, Theme.gold, Theme.sky, Theme.moss, Theme.danger][i % 5])
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
