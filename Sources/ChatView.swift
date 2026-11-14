import SwiftUI
import UIKit

/// The screen the app opens to: a chat with Scout. Empty, it greets you over the landscape with
/// quick replies; once you ask, it becomes the conversation. While you type, matching library
/// articles appear above the keyboard instantly, with no AI and no battery cost.
struct ChatView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(Router.self) private var router
    @Environment(ChatStore.self) private var chats
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft = ""
    @State private var peek: [Passage] = []
    @State private var openArticle: Passage?
    @State private var showSOS = false
    @State private var aiProblem: String?? = nil
    @State private var confetti = 0
    @State private var sent = 0
    @State private var scroll = ScrollOffset()
    @FocusState private var focused: Bool

    @AppStorage(Readiness.askedKey) private var asked = false
    @AppStorage(Readiness.offlineKey) private var testedOffline = false
    @AppStorage(Readiness.celebratedKey) private var celebrated = false

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmpty: Bool { assistant.messages.isEmpty }
    private var aiReady: Bool { aiProblem == .some(nil) }
    private var readiness: [Readiness.Item] {
        Readiness.items(libraryReady: store.hasPack, aiReady: aiReady, asked: asked, offline: testedOffline)
    }
    private var readyCount: Int { readiness.filter(\.done).count }

    var body: some View {
        Group {
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
                    // Solid behind the composer and library strip so nothing on the page shows through them;
                    // only the 24 pt above fades in.
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                        Theme.background
                    }
                    .padding(.top, -24)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay { ConfettiBurst(trigger: confetti) }
        }
        .sheet(isPresented: $showSOS) { SOSSheet(ask: { showSOS = false; send($0.question) },
                                                      openField: { showSOS = false; router.showField() }) }
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
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
        // Only when the library needs attention; when it's ready, its status is in the menu.
        // Only while something is downloading: a ring that fills, with a red "!" if another download stopped.
        if downloads.active {
            ToolbarItem(placement: .topBarLeading) { statusPill }
        }
        // The chat's topic once it has one ("Scout" until then), up to two lines. ChatTopic keeps it short enough
        // that it never gets cut off.
        if !isEmpty {
            ToolbarItem(placement: .principal) {
                Text(assistant.topic ?? "Scout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: assistant.topic)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu { menuItems } label: { AppMenuLabel() }
        }
    }

    /// Everything else in the top bar: this chat's actions first, then the app's.
    @ViewBuilder private var menuItems: some View {
        Section {
            Button(role: .destructive) { showSOS = true } label: { Label("Emergency help", systemImage: "staroflife.fill") }
        }
        Section {
            Button { newChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                .disabled(isEmpty || assistant.isBusy)
            if !isEmpty {
                let isSaved = chats.isSaved(assistant.conversationID)
                Button {
                    if let id = assistant.conversationID { chats.setSaved(id, !isSaved) }
                } label: {
                    Label(isSaved ? "Unsave chat" : "Save chat", systemImage: isSaved ? "bookmark.slash" : "bookmark")
                }
                .disabled(chats.conversation(assistant.conversationID ?? UUID()) == nil)
                ShareLink(item: ChatTranscript.text(title: assistant.topic, messages: assistant.messages),
                          preview: SharePreview(assistant.topic ?? "Chat with Scout")) {
                    Label("Share chat", systemImage: "square.and.arrow.up")
                }
                .disabled(assistant.isBusy)
            }
        }
        AppMenuSection()
    }

    private var downloads: Downloads { Downloads(store: store, better: BetterModel.shared) }

    /// Top bar status while downloading: just the ring, filling as it goes, with a red "!" if another download
    /// stopped. Opens the library.
    private var statusPill: some View {
        let d = downloads
        return Button { router.sheet = .library } label: {
            DownloadRing(fraction: d.fraction, alert: d.stopped > 0, lineWidth: 3)
                .frame(width: 22, height: 22)
                .padding(.horizontal, 4)
        }
        .accessibilityLabel("Offline library: " + [downloadLabel, d.stopped > 0 ? d.stoppedText : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }

    /// "Downloading 34%" across everything downloading, or "Starting download" before progress arrives.
    private var downloadLabel: String {
        guard let f = downloads.fraction else { return "Starting download" }
        return "Downloading " + f.formatted(.percent.precision(.fractionLength(0)))
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
        if !store.hasPack && !store.isWorking { return .sleepy }
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
            if downloads.active {
                Button { router.sheet = .library } label: {
                    HStack(spacing: 10) {
                        DownloadRing(fraction: downloads.fraction, alert: downloads.stopped > 0).frame(width: 18, height: 18)
                        Text(downloadLabel).monospacedDigit().contentTransition(.numericText())
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.accent.opacity(0.12), in: .capsule)
                }
                .padding(.top, 16)
                .riseIn(2)
            } else if !store.hasPack {
                Button { router.sheet = .library } label: {
                    Label("Get the field guides", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .riseIn(2)
            }
            // Three spacers below, one above: the text sits halfway between the title and dead center.
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical)
    }

    private var introText: String {
        if !store.hasPack && store.isWorking {
            return "I'm Scout. I answer from a library that lives on this phone, so I work with no signal. "
                + "It's downloading now, and keeps going even if you leave the app."
        }
        if !store.hasPack {
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
            if let last = assistant.messages.last, last.isFinished, !assistant.isBusy, !last.failed, !last.isCasual {
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
        // A troubleshooting answer ends with a question: its answers come first, as one tap.
        let choices = (m.choices ?? []).map { ($0, "arrowshape.turn.up.left") }
        let replies: [(String, String)] = !choices.isEmpty ? choices : m.urgent
            ? [("What if it gets worse?", "exclamationmark.triangle"), ("Should we evacuate?", "figure.walk.motion"),
               ("What do I tell 911?", "phone")]
            : AnswerBlock.parse(m.text).contains(where: { if case .step = $0 { true } else { false } })
            ? [("Explain step 1 more", "text.magnifyingglass"), ("What if that doesn't work?", "arrow.triangle.branch"),
               ("What gear helps?", "backpack")]
            // No steps to follow up on: suggestions that fit a short answer.
            : [("Tell me more", "text.magnifyingglass"), ("What should I watch out for?", "eye"),
               ("What gear helps?", "backpack")]
        // One quiet, sideways-scrolling row: there to tap, without competing with the answer.
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(replies.enumerated()), id: \.offset) { i, r in
                    Button { send(r.0) } label: { SuggestionChip(title: r.0, symbol: r.1, quiet: choices.isEmpty) }
                        .buttonStyle(SquishyButtonStyle(scale: 0.92))
                        .riseIn(i)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)  // run edge to edge, past the thread's margins
        .accessibilityLabel("Suggested follow-ups")
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

/// A small progress ring for the library download: fills with the fraction, spins before there is one.
struct DownloadRing: View {
    let fraction: Double?
    /// Another download stopped: a red "!" in the middle.
    var alert = false
    var lineWidth: CGFloat = 2.5
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction.map { max($0, 0.03) } ?? 0.25)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(fraction == nil && spin ? 270 : -90))
                .animation(fraction == nil ? .linear(duration: 1).repeatForever(autoreverses: false) : .easeOut,
                           value: spin)
                .animation(.easeOut, value: fraction)
            if alert {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.danger)
            }
        }
        .onAppear { spin = true }
    }
}

/// Everything downloading or stopped (the field guides and the larger model), as one status.
@MainActor
struct Downloads {
    /// Progress across the active downloads, weighted by size; nil while one is still starting.
    var fraction: Double?
    var active = false
    var stopped = 0

    init(store: LibraryStore, better: BetterModel) {
        var parts: [(f: Double?, bytes: Double)] = []
        if !store.hasPack && store.isWorking {
            let bytes = Double(store.packs.first?.downloadBytes ?? 1)
            parts.append((store.downloadFraction, bytes))
        }
        if case let .downloading(f) = better.state { parts.append((f, Double(better.downloadBytes))) }
        if case .failed = store.phase { stopped += 1 }
        if case .failed = better.state, !better.isDownloaded { stopped += 1 }
        active = !parts.isEmpty
        if active, !parts.contains(where: { $0.f == nil }) {
            let total = parts.reduce(0) { $0 + $1.bytes }
            fraction = parts.reduce(0) { $0 + ($1.f ?? 0) * $1.bytes } / max(total, 1)
        }
    }

    var stoppedText: String { stopped == 1 ? "1 download stopped" : "\(stopped) downloads stopped" }
}
