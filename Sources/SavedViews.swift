import SwiftUI

/// Chats the person saved from the chat's top bar.
struct SavedListView: View {
    @Environment(ChatStore.self) private var chats

    var body: some View {
        List {
            ForEach(chats.saved) { chat in
                NavigationLink(value: Route.savedChat(chat.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(subtitle(chat)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Theme.card)
                .swipeActions {
                    Button { chats.setSaved(chat.id, false) } label: { Label("Unsave", systemImage: "bookmark.slash") }
                        .tint(Theme.sun)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if chats.saved.isEmpty {
                ContentUnavailableView("Nothing saved yet", systemImage: "bookmark",
                                       description: Text("Tap the bookmark at the top of a chat to keep it here. Open it later to reread it or keep asking."))
            }
        }
        .navigationTitle("Saved")
    }

    private func subtitle(_ chat: Conversation) -> String {
        let n = chat.questionCount
        return (n > 1 ? "\(n) questions · " : "") + chat.updated.formatted(.dateTime.month().day().year())
    }
}

/// A saved chat to reread, with a way back into it.
struct SavedChatView: View {
    let chatID: UUID
    @Environment(ChatStore.self) private var chats
    @Environment(Assistant.self) private var assistant
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var openArticle: Passage?
    @State private var confirmDelete = false

    var body: some View {
        if let chat = chats.conversation(chatID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(chat.messages) { m in
                        if m.role == .user { UserBubble(text: m.text) }
                        else { AssistantTurn(message: m, isLive: false, open: { openArticle = $0 }) }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                Button {
                    assistant.open(chat)
                    router.showChat()
                } label: {
                    Label("Keep asking", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(assistant.isBusy)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ChatTranscript.text(title: chat.topic, messages: chat.messages),
                              preview: SharePreview(chat.title)) {
                        Label("Share chat", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        .tint(Theme.danger)
                }
            }
            .confirmationDialog("Delete this chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    chats.delete(chatID)
                    assistant.forget([chatID])
                    dismiss()
                }
            } message: {
                Text("It's removed from Saved and your chat history.")
            }
            .sheet(item: $openArticle) { ArticleView(passage: $0) }
        } else {
            ContentUnavailableView("This chat was deleted", systemImage: "bookmark.slash")
        }
    }
}

/// The SOS button for a top bar, with its sheet. On the chat list and the Guide; a chat has it in its menu.
struct SOSToolbarButton: View {
    @Environment(Router.self) private var router
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            // An HStack, not a Label: toolbars drop a Label's title and recolor it.
            HStack(spacing: 4) {
                Image(systemName: "staroflife.fill").font(.caption.weight(.bold))
                Text("SOS")
            }
            .font(.system(.subheadline, design: .rounded).weight(.heavy))
            .foregroundStyle(Theme.danger)
            .fixedSize()
            .padding(.horizontal, 6)
        }
        .tint(Theme.danger)
        .accessibilityLabel("Emergency help")
        .sheet(isPresented: $showing) {
            SOSSheet(ask: { showing = false; router.ask($0.question) },
                     openField: { showing = false; router.showField() })
        }
    }
}

/// Emergency help, one tap from the home screen.
struct SOSSheet: View {
    var ask: (Topic) -> Void
    var openField: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Scout(mood: .alert, size: 70)
                        Text("Stay calm. Get help first, then I'll walk you through it.")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    SOSBanner()
                    VStack(alignment: .leading, spacing: 10) {
                        tip("location.fill", "Share where you are",
                            "Tell the dispatcher your trail, landmarks and GPS coordinates (Compass app shows them).")
                        tip("battery.25percent", "Save battery",
                            "Turn on Low Power Mode. Text instead of calling if your signal keeps dropping.")
                        tip("figure.stand", "Stay put if you're lost",
                            "Rescuers find people faster when they stop moving.")
                    }
                    .card()
                    FieldStartCard(title: "Treating someone?", button: "Open Field mode", action: openField)
                    Text("Walk me through it").sectionLabel()
                    ForEach(Topic.urgent) { t in
                        Button { ask(t) } label: { TopicTile(topic: t) }
                            .buttonStyle(SquishyButtonStyle(scale: 0.97))
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Emergency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { dismiss() } }
        }
        .tint(Theme.accent)
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.footnote).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}
