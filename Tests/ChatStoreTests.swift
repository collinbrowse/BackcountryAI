import Foundation
import Testing
@testable import BackcountryGuide

@MainActor
struct ChatStoreTests {
    /// Each test gets its own file, so tests never touch the app's real chats or each other's.
    let file = URL.temporaryDirectory.appending(path: "chats-\(UUID().uuidString).json")

    private func turn(_ q: String, _ a: String = "An answer.") -> [ChatMessage] {
        [ChatMessage(role: .user, text: q), ChatMessage(role: .assistant, text: a, question: q)]
    }

    @Test func savesAndReloadsFromDisk() {
        let store = ChatStore(file: file)
        let id = UUID()
        store.save(id: id, messages: turn("How do I treat a blister?"))

        let reloaded = ChatStore(file: file)
        #expect(reloaded.conversations.count == 1)
        #expect(reloaded.conversation(id)?.title == "How do I treat a blister?")
        #expect(reloaded.conversation(id)?.messages.count == 2)
    }

    @Test func savingAgainUpdatesInPlaceAndMovesToTop() {
        let store = ChatStore(file: file)
        let a = UUID(), b = UUID()
        store.save(id: a, messages: turn("First"))
        store.save(id: b, messages: turn("Second"))
        store.save(id: a, messages: turn("First") + turn("Follow-up"))

        #expect(store.conversations.map(\.id) == [a, b])
        #expect(store.conversation(a)?.questionCount == 2)
    }

    @Test func skipsUnfinishedAnswersAndEmptyChats() {
        let store = ChatStore(file: file)
        var working = ChatMessage(role: .assistant, text: "", status: "Searching the library…")
        working.question = "Q"
        store.save(id: UUID(), messages: [working])
        #expect(store.conversations.isEmpty)

        let id = UUID()
        store.save(id: id, messages: [ChatMessage(role: .user, text: "Q"), working])
        #expect(store.conversation(id)?.messages.map(\.role) == [.user])
    }

    @Test func deletesOneChatOnly() {
        let store = ChatStore(file: file)
        let a = UUID(), b = UUID()
        store.save(id: a, messages: turn("A"))
        store.save(id: b, messages: turn("B"))
        store.delete(a)

        #expect(store.conversations.map(\.id) == [b])
        #expect(ChatStore(file: file).conversations.map(\.id) == [b])
    }

    @Test func bulkDeleteRemovesOnlySelectedAndReportsCount() {
        let store = ChatStore(file: file)
        let ids = (0..<4).map { _ in UUID() }
        for (i, id) in ids.enumerated() { store.save(id: id, messages: turn("Q\(i)")) }

        let removed = store.delete([ids[0], ids[2], UUID()])  // an unknown id is ignored
        #expect(removed == 2)
        #expect(Set(store.conversations.map(\.id)) == [ids[1], ids[3]])
        #expect(Set(ChatStore(file: file).conversations.map(\.id)) == [ids[1], ids[3]])
    }

    @Test func deleteAllEmptiesThisStoreButNotAnother() {
        let otherFile = URL.temporaryDirectory.appending(path: "chats-\(UUID().uuidString).json")
        let mine = ChatStore(file: file), other = ChatStore(file: otherFile)
        mine.save(id: UUID(), messages: turn("Mine"))
        other.save(id: UUID(), messages: turn("Someone else's"))

        mine.deleteAll()
        #expect(ChatStore(file: file).conversations.isEmpty)
        #expect(ChatStore(file: otherFile).conversations.count == 1)
    }

    @Test func assistantForgetsCurrentChatOnlyWhenItWasDeleted() {
        let store = ChatStore(file: file)
        let a = UUID(), b = UUID()
        store.save(id: a, messages: turn("A"))
        store.save(id: b, messages: turn("B"))
        let assistant = Assistant(chats: store)

        assistant.open(store.conversation(a)!)
        assistant.forget([b])
        #expect(assistant.conversationID == a)
        #expect(assistant.messages.count == 2)

        assistant.forget([a])
        #expect(assistant.conversationID == nil)
        #expect(assistant.messages.isEmpty)
    }

    @Test func savedMessagesDropTransientStatus() throws {
        var m = ChatMessage(role: .assistant, text: "Done", status: "Writing…", question: "Q", urgent: true)
        m.failed = true
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(m))
        #expect(decoded.id == m.id)
        #expect(decoded.status == nil)
        #expect(decoded.urgent && decoded.failed && decoded.question == "Q")
    }
}
