import Foundation
import Observation

/// One past conversation with Scout, kept on this phone.
struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    var messages: [ChatMessage]
    var updated = Date.now
    /// When it was saved, if it is. Saved chats are listed in the Saved tab.
    var savedAt: Date? = nil
    /// A short name, like "Sprained ankle on the trail" (see ChatTopic). Nil for small talk and older chats.
    var topic: String? = nil

    /// The first question asked, which is what people remember a chat by.
    var title: String { topic ?? messages.first(where: { $0.role == .user })?.text ?? "New chat" }
    var questionCount: Int { messages.filter { $0.role == .user }.count }
}

/// Every chat, kept automatically after each answer. It is one JSON file in this
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
    func save(id: UUID, messages: [ChatMessage], topic: String? = nil) {
        let kept = messages.filter { $0.role == .user || $0.isFinished || $0.failed }
        guard kept.contains(where: { $0.role == .user }) else { return }
        let old = conversation(id)
        conversations.removeAll { $0.id == id }
        conversations.insert(Conversation(id: id, messages: kept, savedAt: old?.savedAt,
                                          topic: topic ?? old?.topic), at: 0)
        persist()
    }

    /// Saved chats, most recently saved first.
    var saved: [Conversation] {
        conversations.filter { $0.savedAt != nil }.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
    }

    func isSaved(_ id: UUID?) -> Bool { id.flatMap(conversation)?.savedAt != nil }

    func setSaved(_ id: UUID, _ on: Bool) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].savedAt = on ? .now : nil
        persist()
    }

    /// Saved answers used to be kept apart from chats, one question and answer each. Folds them in as saved chats
    /// (the chat they came from, when it's still here), then removes the old file.
    func importLegacySavedAnswers(from legacy: URL = URL.applicationSupportDirectory.appending(path: "saved-answers.json")) {
        struct Legacy: Decodable {
            let question: String, answer: String, sources: [Passage]
            let date: Date
            let chatID: UUID?
        }
        guard let data = try? Data(contentsOf: legacy) else { return }
        for item in (try? JSONDecoder().decode([Legacy].self, from: data)) ?? [] {
            if let id = item.chatID, let i = conversations.firstIndex(where: { $0.id == id }) {
                if conversations[i].savedAt == nil { conversations[i].savedAt = item.date }
            } else {
                conversations.append(Conversation(messages: [
                    ChatMessage(role: .user, text: item.question),
                    ChatMessage(role: .assistant, text: item.answer, sources: item.sources, question: item.question),
                ], updated: item.date, savedAt: item.date))
            }
        }
        conversations.sort { $0.updated > $1.updated }
        persist()
        try? FileManager.default.removeItem(at: legacy)
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
