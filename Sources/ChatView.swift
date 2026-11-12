import SwiftUI
import UIKit

/// The screen the app opens to: a chat with Scout. Empty, it greets you over the landscape with
/// quick replies; once you ask, it becomes the conversation. While you type, matching library
/// articles appear above the keyboard instantly, with no AI and no battery cost.
struct ChatView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var draft = ""
    @State private var peek: [Passage] = []
    @State private var openArticle: Passage?
    @State private var showLibrary = false
    @State private var showHistory = false
    @State private var showSOS = false
    @State private var showHowItWorks = false
    @State private var showOfflineTip = false
    @State private var showReadiness = false
    @State private var aiProblem: String?? = nil
    @State private var confetti = 0
    @State private var sent = 0
    @State private var scroll = ScrollOffset()
    @FocusState private var focused: Bool

    @AppStorage(Readiness.askedKey) private var asked = false
    @AppStorage(Readiness.offlineKey) private var testedOffline = false
    @AppStorage(Readiness.celebratedKey) private var celebrated = false
    @AppStorage("betterAnswers.tipDismissed") private var betterTipDismissed = false

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmpty: Bool { assistant.messages.isEmpty }
    private var aiReady: Bool { aiProblem == .some(nil) }
    private var readiness: [Readiness.Item] {
        Readiness.items(libraryReady: store.library != nil, aiReady: aiReady, asked: asked, offline: testedOffline)
    }
    private var readyCount: Int { readiness.filter(\.done).count }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if isEmpty { welcome.transition(.opacity) } else { thread }
                    }
                    .animation(.bouncy, value: isEmpty)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) {
                    scroll.y = $1
                }
                .onChange(of: assistant.messages.count) {
                    guard let q = assistant.messages.last(where: { $0.role == .user }) else { return }
                    withAnimation(.bouncy) { proxy.scrollTo(q.id, anchor: .top) }
                }
            }
            .background {
                if isEmpty { HomeBackdrop(scroll: scroll).transition(.opacity) } else { Theme.background.ignoresSafeArea() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if !peek.isEmpty && trimmed.count >= 2 { peekStrip.transition(.move(edge: .bottom).combined(with: .opacity)) }
                    composer
                }
                .animation(.bouncy, value: peek.isEmpty || trimmed.count < 2)
                .background {
                    LinearGradient(colors: [Theme.background.opacity(0), Theme.background.opacity(0.92), Theme.background],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.top, -24)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle(isEmpty ? "" : "Scout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay { ConfettiBurst(trigger: confetti) }
        }
        .sheet(isPresented: $showLibrary) { LibraryView() }
        .sheet(isPresented: $showHistory) { ChatHistoryView() }
        .sheet(isPresented: $showReadiness) {
            ReadinessSheet(items: readiness) { item in
                showReadiness = false
                act(item)
            }
        }
        .sheet(isPresented: $showSOS) { SOSSheet(ask: { showSOS = false; send($0.question) },
                                                      openField: { showSOS = false; router.showField() }) }
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
        .fullScreenCover(isPresented: $showHowItWorks) { OnboardingView(isReplay: true) { showHowItWorks = false } }
        .alert("Test it in Airplane Mode", isPresented: $showOfflineTip) {
            Button("OK") {}
        } message: {
            Text("Swipe down from the top-right corner, turn on Airplane Mode, then ask Scout anything. "
                 + "If you get an answer, you're set for the backcountry.")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sent)
        .sensoryFeedback(.success, trigger: assistant.messages.last?.isFinished == true)
        .task(id: scenePhase) { await watchAI() }
        .onChange(of: scenePhase, initial: true) { if scenePhase == .active { BetterModel.shared.warmUp() } }
        .task(id: trimmed) { await searchPeek() }
        .onChange(of: router.pending, initial: true) {
            if let q = router.pending {
                router.pending = nil
                send(q, fresh: true)
            }
        }
        .onChange(of: readyCount) { old, new in
            if new == readiness.count && old < new && !celebrated {
                celebrated = true
                confetti += 1
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { statusPill }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSOS = true } label: {
                Text("SOS")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.danger, in: .capsule)
            }
            .buttonStyle(SquishyButtonStyle(scale: 0.9))
            .accessibilityLabel("Emergency help")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .disabled(assistant.isBusy)
                .accessibilityLabel("Chat history")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isEmpty {
                Menu { menuItems } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
            } else {
                Menu { menuItems } label: { Image(systemName: "square.and.pencil") } primaryAction: { newChat() }
                    .disabled(assistant.isBusy)
                    .accessibilityLabel("New chat")
            }
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button { showReadiness = true } label: {
            Label("Trail-ready checklist · \(readyCount)/\(readiness.count)", systemImage: "checklist")
        }
        Button { showHistory = true } label: { Label("Chat history", systemImage: "clock.arrow.circlepath") }
        Button { showLibrary = true } label: { Label("Offline library", systemImage: "books.vertical") }
        Button { showHowItWorks = true } label: { Label("How Scout works", systemImage: "questionmark.circle") }
    }

    private var statusPill: some View {
        let online = NetworkMonitor.shared.isOnline
        let (text, symbol, tint): (String, String, Color) =
            store.library == nil ? ("No library yet", "books.vertical", Theme.danger)
            : online ? ("Offline-ready", "checkmark.circle.fill", Theme.pine)
            : ("No signal · still works", "antenna.radiowaves.left.and.right.slash", Theme.pine)
        return Button { showLibrary = true } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(text)
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
        }
    }

    // MARK: Welcome

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<21: "Good evening"
        default: "Late night out there"
        }
    }

    private var heroInk: Color { Color(light: 0x16241D, dark: 0xF4F1EA) }

    private var welcomeMood: Scout.Mood {
        if confetti > 0 && readyCount == readiness.count { return .happy }
        if store.library == nil && !store.isWorking { return .sleepy }
        if focused || !trimmed.isEmpty { return .thinking }
        return .idle
    }

    private var welcome: some View {
        VStack(spacing: 6) {
            Scout(mood: welcomeMood, size: 132)
                .padding(.top, 40)
            Text(greeting)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(heroInk.opacity(0.8))
            Text("What's going on?")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(heroInk)
            Spacer(minLength: 24)
            Text(introText)
                .font(.callout)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 8)
                .riseIn(1)
            if store.library == nil {
                Button { showLibrary = true } label: {
                    Label("Get the library", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .riseIn(2)
            } else if showBetterTip {
                betterTip.padding(.top, 16).riseIn(2)
            }
            // Three spacers below, one above: the text sits halfway between the title and dead center.
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical)
    }

    /// Once the library is in, point out the optional larger model, until it's downloaded or dismissed.
    private var showBetterTip: Bool {
        BetterModel.isOffered && BetterModel.shared.state == .notDownloaded && !betterTipDismissed
    }

    private var betterTip: some View {
        HStack(spacing: 4) {
            Button { showLibrary = true } label: {
                Label("Want more accurate answers?", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.leading, 14).padding(.vertical, 9)
            }
            Button { withAnimation { betterTipDismissed = true } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .accessibilityLabel("Hide this tip")
        }
        .background(Theme.card.opacity(0.9), in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private var introText: String {
        if store.library == nil {
            return "I'm Scout. I answer from a library that lives on this phone, so I work with no signal. "
                + "Download it once, before you head out."
        }
        return "I'm Scout. Tell me what's happening in your own words and I'll walk you through it, step by step. "
            + "I work with no signal."
    }

    // MARK: Thread

    private var thread: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(assistant.messages) { m in
                Group {
                    if m.role == .user {
                        UserBubble(text: m.text)
                    } else {
                        AssistantTurn(message: m, isLive: isLive(m), open: { openArticle = $0 })
                    }
                }
                .id(m.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)), removal: .opacity))
            }
            if let last = assistant.messages.last, last.isFinished, !assistant.isBusy, !last.failed {
                followUps(for: last).transition(.opacity.combined(with: .offset(y: 8)))
            }
            Color.clear.frame(height: 260)  // lets the newest question scroll to the top
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.bouncy, value: assistant.messages.count)
        .animation(.bouncy, value: assistant.isBusy)
    }

    private func followUps(for m: ChatMessage) -> some View {
        let replies: [(String, String)] = m.urgent
            ? [("What if it gets worse?", "exclamationmark.triangle"), ("Should we evacuate?", "figure.walk.motion"),
               ("What do I tell 911?", "phone")]
            : [("Explain step 1 more", "text.magnifyingglass"), ("What if that doesn't work?", "arrow.triangle.branch"),
               ("What gear helps?", "backpack")]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Keep going").sectionLabel()
            FlowLayout {
                ForEach(Array(replies.enumerated()), id: \.offset) { i, r in
                    Button { send(r.0) } label: { SuggestionChip(title: r.0, symbol: r.1) }
                        .buttonStyle(SquishyButtonStyle(scale: 0.92))
                        .riseIn(i)
                }
            }
        }
    }

    private func isLive(_ m: ChatMessage) -> Bool {
        assistant.isBusy && m.id == assistant.messages.last?.id
    }

    // MARK: Composer

    private var peekStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Instant from the library", systemImage: "bolt.fill")
                .font(.caption2.weight(.bold)).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(peek) { p in
                        Button { openArticle = p } label: {
                            HStack(spacing: 8) {
                                Image(systemName: p.official ? "checkmark.seal.fill" : "doc.text.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(p.official ? Theme.moss : Theme.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Text(p.source).font(.caption2).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: 220, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(SquishyButtonStyle(scale: 0.95))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(isEmpty ? "Describe what's happening…" : "Ask a follow-up…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send(trimmed) }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 18).padding(.vertical, 13)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 25))
            if assistant.isBusy {
                Button { assistant.stop() } label: {
                    Image(systemName: "stop.fill").font(.headline).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(Theme.ink, in: .circle)
                }
                .accessibilityLabel("Stop")
                .transition(.scale.combined(with: .opacity))
            } else {
                Button { send(trimmed) } label: {
                    Image(systemName: "arrow.up").font(.headline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(Theme.accentGradient, in: .circle)
                        .shadow(color: Theme.accent.opacity(trimmed.isEmpty ? 0 : 0.4), radius: 8, y: 3)
                }
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.4 : 1)
                .scaleEffect(trimmed.isEmpty ? 0.9 : 1)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("composer.send")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .buttonStyle(SquishyButtonStyle(scale: 0.88))
        .animation(.bouncy, value: assistant.isBusy)
        .animation(.bouncy, value: trimmed.isEmpty)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
    }

    // MARK: Actions

    private func send(_ question: String, fresh: Bool = false) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !assistant.isBusy else { return }
        focused = false
        draft = ""
        peek = []
        sent += 1
        if fresh { assistant.startNew(q, library: store.library) } else { assistant.ask(q, library: store.library) }
    }

    private func newChat() {
        withAnimation(.bouncy) { assistant.clear() }
        draft = ""
    }

    private func searchPeek() async {
        let q = trimmed
        guard q.count >= 2, let lib = store.library else { peek = []; return }
        try? await Task.sleep(for: .milliseconds(220))  // wait for typing to pause
        guard !Task.isCancelled else { return }
        let hits = await Task.detached(priority: .userInitiated) { lib.search(q, limit: 6, maxChars: 220) }.value
        guard !Task.isCancelled else { return }
        withAnimation(.bouncy) { peek = hits }
    }

    private func act(_ item: Readiness.Item) {
        switch item.id {
        case "library": Task { try? await Task.sleep(for: .milliseconds(400)); showLibrary = true }
        case "ai": if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case "asked": send(Topic.camp[1].question)
        default: Task { try? await Task.sleep(for: .milliseconds(400)); showOfflineTip = true }
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
