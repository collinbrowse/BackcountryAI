import SwiftUI

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
    @Environment(LibraryStore.self) private var store

    private var mood: Scout.Mood {
        if message.status != nil { return .thinking }
        if isLive { return .writing }
        if message.urgent { return .alert }
        return message.failed ? .idle : .happy
    }

    /// No library source backs this answer: said once, in the line beside Scout, not inside the answer.
    private var isGeneral: Bool {
        message.isFinished && (message.sources.isEmpty || AnswerBlock.isGeneral(message.text))
    }

    private static let noGuides = "Note that field guides have not been downloaded yet"

    private var headline: String {
        if let status = message.status { return message.isCasual ? "" : status }
        if isLive { return "Writing…" }
        if message.failed { return "I couldn't write an answer" }
        if message.urgent {
            // Still say when no library source backs it: it matters most in an emergency.
            if isGeneral { return store.hasPack ? "Act fast. Not from the library." : Self.noGuides }
            return "Act fast. Here's what to do."
        }
        if isGeneral {
            // Say why when it's fixable: without the field guides, only the person's own documents are searched.
            return store.hasPack ? "General guidance, not from the library"
                : Self.noGuides
        }
        return "Here's what I found"
    }

    var body: some View {
        if message.isCasual && message.status == nil { casualReply } else { answer }
    }

    /// Small talk: Scout just talks, like any chat app.
    private var casualReply: some View {
        HStack(alignment: .top, spacing: 10) {
            Scout(mood: isLive ? .writing : .happy, size: 36)
            Text(message.text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Scout(mood: mood, size: 46)
                HStack(spacing: 5) {
                    if isGeneral && !isLive {
                        Image(systemName: "info.circle").foregroundStyle(Theme.sun)
                    }
                    Text(headline)
                }
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

    /// Share, and how long the answer took. Saving is for the whole chat, from the top bar.
    private var footer: some View {
        HStack(spacing: 8) {
            if !message.failed {
                ShareLink(item: message.question + "\n\n" + message.text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Spacer()
            if message.engine != nil {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    .accessibilityLabel("Written with better answers")
            }
            if let b = message.battery {
                Label(String(format: "%.0fs", b.seconds), systemImage: "timer")
                    .accessibilityLabel(String(format: "Took %.0f seconds", b.seconds))
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
    @Environment(\.openURL) private var openURL
    @State private var confirmCall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("If a life may be at risk, get help first", systemImage: "sos")
                .font(.subheadline.weight(.bold))
            Text("No cell signal? On iPhone 14 or later, call 911 anyway to start Emergency SOS via satellite.")
                .font(.footnote)
                .opacity(0.9)
            // Two confirmations before a real emergency call: this one, then iOS's own "Call 911?".
            Button { confirmCall = true } label: {
                Label("Call 911", systemImage: "phone.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white, in: .capsule)
            }
            .alert("Call 911 now?", isPresented: $confirmCall) {
                Button("Call 911", role: .destructive) { openURL(URL(string: "tel://911")!) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This places a real emergency call. Use it when someone needs help now.")
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
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: 22, height: 22)
                    .background(Theme.accent.opacity(0.16), in: .circle)
                if passage.official { OfficialBadge() } else if passage.isMine { MineBadge() }
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

/// On passages from a document the person added themselves.
struct MineBadge: View {
    var body: some View {
        Label("Yours", systemImage: "person.crop.square.filled.and.at.rectangle")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.accentDeep)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.accent.opacity(0.14), in: .capsule)
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
