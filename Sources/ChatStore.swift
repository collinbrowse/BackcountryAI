import Foundation
import Observation

/// One past conversation with Scout, kept on this phone.
struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    var messages: [ChatMessage]
    var updated = Date.now

    /// The first question asked, which is what people remember a chat by.
    var title: String { messages.first(where: { $0.role == .user })?.text ?? "New chat" }
    var questionCount: Int { messages.filter { $0.role == .user }.count }
}

/// Every chat, saved automatically after each answer. Like `SavedStore`, it is one JSON file in this
/// app's own Application Support folder, so it only ever holds (and deletes) this phone's chats.
@MainActor
@Observable
final class ChatStore {
    /// Most recently updated first.
    private(set) var conversations: [Conversation] = []

    private let file: URL

    static var defaultFile: URL { URL.applicationSupportDirectory.appending(path: "chats.json") }

    init(file: URL = ChatStore.defaultFile) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded.sorted { $0.updated > $1.updated }
        }
    }

    func conversation(_ id: UUID) -> Conversation? { conversations.first { $0.id == id } }

    /// Creates or replaces a conversation and moves it to the top. Unfinished or empty turns are skipped.
    func save(id: UUID, messages: [ChatMessage]) {
        let kept = messages.filter { $0.role == .user || $0.isFinished || $0.failed }
        guard kept.contains(where: { $0.role == .user }) else { return }
        conversations.removeAll { $0.id == id }
        conversations.insert(Conversation(id: id, messages: kept), at: 0)
        persist()
    }

    func delete(_ id: UUID) { delete([id]) }

    /// Deletes only the given chats. Returns how many were actually removed.
    @discardableResult
    func delete(_ ids: Set<UUID>) -> Int {
        let before = conversations.count
        conversations.removeAll { ids.contains($0.id) }
        let removed = before - conversations.count
        if removed > 0 { persist() }
        return removed
    }

    func deleteAll() {
        guard !conversations.isEmpty else { return }
        conversations.removeAll()
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(conversations).write(to: file, options: .atomic)
    }
}
