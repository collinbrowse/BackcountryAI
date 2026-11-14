import SwiftUI

/// Your chats, newest first: the bottom of the Scout tab's stack, so back from a chat (or a swipe from the left
/// edge) lands here. Tap one to push it in; delete one, several, or all of them.
struct ChatListView: View {
    @Environment(ChatStore.self) private var chats
    @Environment(Assistant.self) private var assistant
    @Environment(Router.self) private var router

    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var pending: PendingDelete?

    /// What the confirmation dialog is about to delete.
    enum PendingDelete: Identifiable {
        case one(Conversation), selected(Set<UUID>), all(Int)
        var id: String {
            switch self {
            case .one(let c): "one-\(c.id)"
            case .selected(let ids): "selected-\(ids.count)"
            case .all(let n): "all-\(n)"
            }
        }
    }

    var body: some View {
        List {
            ForEach(chats.conversations) { chat in
                row(chat)
                    .listRowBackground(chat.id == assistant.conversationID ? Theme.accent.opacity(0.12) : Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if chats.conversations.isEmpty {
                ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.text.bubble.right",
                                       description: Text("Your chats with Scout are kept here automatically."))
            }
        }
        .navigationTitle(selecting && !selection.isEmpty ? "\(selection.count) selected" : "Chats")
        .navigationBarTitleDisplayMode(selecting ? .inline : .large)
        .toolbar { toolbar }
        .confirmationDialog(dialogTitle, isPresented: isConfirming, titleVisibility: .visible,
                            presenting: pending) { p in
            Button(deleteLabel(p), role: .destructive) { perform(p) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func row(_ chat: Conversation) -> some View {
        let isSelected = selection.contains(chat.id)
        return HStack(spacing: 12) {
            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.inkSoft)
                    .accessibilityHidden(true)
            }
            Button { selecting ? toggle(chat) : open(chat) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(chat.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                        Spacer(minLength: 0)
                        if chat.savedAt != nil {
                            Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(Theme.accent)
                                .accessibilityLabel("Saved")
                        }
                    }
                    Text("\(chat.updated.formatted(.relative(presentation: .named))) · "
                         + (chat.questionCount == 1 ? "1 question" : "\(chat.questionCount) questions"))
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityAddTraits(selecting && isSelected ? .isSelected : [])
        }
        .buttonStyle(.borderless)
        .swipeActions {
            if !selecting {
                Button(role: .destructive) { pending = .one(chat) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(selection.count == chats.conversations.count ? "Deselect All" : "Select All") {
                    selection = selection.count == chats.conversations.count ? [] : Set(chats.conversations.map(\.id))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.isEmpty ? "Delete" : "Delete (\(selection.count))", role: .destructive) {
                    pending = .selected(selection)
                }
                .disabled(selection.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { withAnimation { selecting = false; selection = [] } }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) { SOSToolbarButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !chats.conversations.isEmpty {
                        Section {
                            Button { withAnimation { selecting = true } } label: {
                                Label("Select", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) { pending = .all(chats.conversations.count) } label: {
                                Label("Delete All Chats", systemImage: "trash")
                            }
                        }
                    }
                    AppMenuSection()
                } label: { AppMenuLabel() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newChat() } label: { Image(systemName: "square.and.pencil") }
                    .disabled(assistant.isBusy)
                    .accessibilityLabel("New chat")
            }
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var dialogTitle: String {
        switch pending {
        case .one: "Delete this chat?"
        case .selected(let ids): ids.count == 1 ? "Delete 1 chat?" : "Delete \(ids.count) chats?"
        case .all(let n): n == 1 ? "Delete your 1 chat?" : "Delete all \(n) chats?"
        case nil: ""
        }
    }

    private func deleteLabel(_ p: PendingDelete) -> String {
        switch p {
        case .one: "Delete Chat"
        case .selected(let ids): ids.count == 1 ? "Delete 1 Chat" : "Delete \(ids.count) Chats"
        case .all(let n): n == 1 ? "Delete 1 Chat" : "Delete All \(n) Chats"
        }
    }

    private func perform(_ p: PendingDelete) {
        let ids: Set<UUID>
        switch p {
        case .one(let c): ids = [c.id]
        case .selected(let s): ids = s
        case .all: ids = Set(chats.conversations.map(\.id))
        }
        withAnimation {
            if case .all = p { chats.deleteAll() } else { chats.delete(ids) }
            assistant.forget(ids)
            selection.subtract(ids)
            if chats.conversations.isEmpty { selecting = false }
        }
    }

    private func toggle(_ chat: Conversation) {
        if selection.contains(chat.id) { selection.remove(chat.id) } else { selection.insert(chat.id) }
    }

    private func open(_ chat: Conversation) {
        if chat.id != assistant.conversationID { assistant.open(chat) }
        router.chatPath = [.chat]
    }

    private func newChat() {
        assistant.clear()
        router.chatPath = [.chat]
    }
}
