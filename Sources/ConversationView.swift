import SwiftUI

/// One conversation with Scout. New questions scroll to the top so the answer reads from step 1 down,
/// instead of chasing the bottom while it streams.
struct ConversationView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var openArticle: Passage?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                    Color.clear.frame(height: 220)  // lets the last question scroll to the top
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .animation(.bouncy, value: assistant.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: assistant.messages.count, initial: true) {
                guard let q = assistant.messages.last(where: { $0.role == .user }) else { return }
                withAnimation(.bouncy) { proxy.scrollTo(q.id, anchor: .top) }
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("Scout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    assistant.clear()
                    dismiss()
                } label: { Label("New question", systemImage: "square.and.pencil") }
                .disabled(assistant.isBusy)
            }
        }
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
        .sensoryFeedback(.success, trigger: assistant.messages.last?.isFinished == true)
    }

    private func isLive(_ m: ChatMessage) -> Bool {
        assistant.isBusy && m.id == assistant.messages.last?.id
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            if assistant.isBusy {
                Button { assistant.stop() } label: {
                    Image(systemName: "stop.fill").font(.headline).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Theme.ink, in: .circle)
                }
                .accessibilityLabel("Stop")
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.headline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Theme.emberGradient, in: .circle)
                }
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.4 : 1)
                .accessibilityLabel("Send")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .buttonStyle(SquishyButtonStyle(scale: 0.88))
        .animation(.bouncy, value: assistant.isBusy)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        guard !trimmed.isEmpty else { return }
        assistant.ask(trimmed, library: store.library)
        draft = ""
        focused = false
    }
}

struct UserBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.pine, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22,
                                                               bottomTrailingRadius: 6, topTrailingRadius: 22,
                                                               style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
            .textSelection(.enabled)
    }
}

struct AssistantTurn: View {
    let message: ChatMessage
    let isLive: Bool
    var open: (Passage) -> Void
    @Environment(SavedStore.self) private var saved
    @State private var showBattery = false

    private var mood: Scout.Mood {
        if message.status != nil { return .thinking }
        if isLive { return .writing }
        if message.urgent { return .alert }
        return message.failed ? .idle : .happy
    }

    private var headline: String {
        if let status = message.status { return status }
        if isLive { return "Writing…" }
        if message.failed { return "I couldn't write an answer" }
        return message.urgent ? "Act fast. Here's what to do." : "Here's what I found"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Scout(mood: mood, size: 46)
                Text(headline)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: headline)
            }
            if message.urgent { SOSBanner() }
            if !message.text.isEmpty {
                AnswerBody(text: message.text, failed: message.failed) { n in
                    if message.sources.indices.contains(n - 1) { open(message.sources[n - 1]) }
                }
            }
            if !message.sources.isEmpty {
                SourceCarousel(sources: message.sources, open: open)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
            if message.isFinished && !isLive { footer.transition(.opacity) }
        }
        .animation(.bouncy, value: message.sources.count)
        .animation(.bouncy, value: message.isFinished)
    }

    private var footer: some View {
        let isSaved = saved.isSaved(question: message.question, answer: message.text)
        return HStack(spacing: 8) {
            if !message.failed {
                Button {
                    saved.toggle(question: message.question, answer: message.text, sources: message.sources)
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isSaved)
                ShareLink(item: message.question + "\n\n" + message.text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Spacer()
            if let b = message.battery {
                Button { showBattery = true } label: {
                    Label(b.short, systemImage: "bolt.fill")
                }
                .popover(isPresented: $showBattery) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Battery for this answer").font(.headline)
                        Text(b.summary)
                        if let s = message.batterySession { Text(s) }
                        if b.lowPowerMode { Text("Low Power Mode is on, so answers may be slower.") }
                        Text("iOS reports battery in 1% steps, so single answers often read under 1%.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .padding()
                    .frame(width: 290, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.inkSoft)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

/// Shown at the top of answers to questions that sound life-threatening.
struct SOSBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("If a life may be at risk, get help first", systemImage: "sos")
                .font(.subheadline.weight(.bold))
            Text("No cell signal? On iPhone 14 or later, call 911 anyway to start Emergency SOS via satellite.")
                .font(.footnote)
                .opacity(0.9)
            Link(destination: URL(string: "tel://911")!) {
                Label("Call 911", systemImage: "phone.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white, in: .capsule)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LinearGradient(colors: [Theme.danger, Color(hex: 0xB0252B)], startPoint: .topLeading,
                                   endPoint: .bottomTrailing), in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// Numbered source cards that line up with the [n] citations in the answer.
struct SourceCarousel: View {
    let sources: [Passage]
    var open: (Passage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources · tap to read").sectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { i, s in
                        Button { open(s) } label: { SourceCard(number: i + 1, passage: s) }
                            .buttonStyle(SquishyButtonStyle())
                            .riseIn(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

struct SourceCard: View {
    let number: Int
    let passage: Passage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Theme.emberDeep)
                    .frame(width: 22, height: 22)
                    .background(Theme.ember.opacity(0.16), in: .circle)
                if passage.official { OfficialBadge() }
                Spacer(minLength: 0)
            }
            Text(passage.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(passage.source).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
        .frame(width: 210, alignment: .leading)
        .card(padding: 12, radius: 18)
    }
}

struct OfficialBadge: View {
    var body: some View {
        Label("Official", systemImage: "checkmark.seal.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.moss)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.moss.opacity(0.14), in: .capsule)
    }
}
