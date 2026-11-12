import SwiftUI

/// Past chats, newest first. Tap one to reopen it; delete one, several, or all of them.
struct ChatHistoryView: View {
    @Environment(ChatStore.self) private var chats
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss

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
        NavigationStack {
            List {
                ForEach(chats.conversations) { chat in
                    row(chat)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if chats.conversations.isEmpty {
                    ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.text.bubble.right",
                                           description: Text("Your chats with Scout save here automatically."))
                }
            }
            .navigationTitle(selecting && !selection.isEmpty ? "\(selection.count) selected" : "Chat history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(dialogTitle, isPresented: isConfirming, titleVisibility: .visible,
                                presenting: pending) { p in
                Button(deleteLabel(p), role: .destructive) { perform(p) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This can't be undone.")
            }
        }
        .tint(Theme.accent)
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
                    Text(chat.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                    Text("\(chat.updated.formatted(.relative(presentation: .named))) · "
                         + (chat.questionCount == 1 ? "1 question" : "\(chat.questionCount) questions"))
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityAddTraits(selecting && isSelected ? .isSelected : [])
            if !selecting {
                Button(role: .destructive) { pending = .one(chat) } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.danger)
                }
                .accessibilityLabel("Delete chat")
            }
        }
        .buttonStyle(.borderless)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if selecting {
                Button(selection.count == chats.conversations.count ? "Deselect All" : "Select All") {
                    selection = selection.count == chats.conversations.count ? [] : Set(chats.conversations.map(\.id))
                }
            } else {
                Button("Done") { dismiss() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(selecting ? "Cancel" : "Select") {
                withAnimation {
                    selecting.toggle()
                    selection = []
                }
            }
            .disabled(chats.conversations.isEmpty)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if !chats.conversations.isEmpty {
                Button("Delete All", role: .destructive) { pending = .all(chats.conversations.count) }
                    .foregroundStyle(Theme.danger)
                Spacer()
                if selecting {
                    Button(selection.isEmpty ? "Delete" : "Delete (\(selection.count))", role: .destructive) {
                        pending = .selected(selection)
                    }
                        .foregroundStyle(selection.isEmpty ? Theme.inkSoft : Theme.danger)
                        .disabled(selection.isEmpty)
                }
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
        assistant.open(chat)
        dismiss()
    }
}
