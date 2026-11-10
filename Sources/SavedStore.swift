import Foundation
import Observation

/// An answer pinned for later. Rereading a saved answer costs no battery, unlike asking again.
struct SavedAnswer: Identifiable, Codable, Hashable {
    var id = UUID()
    let question: String
    let answer: String
    let sources: [Passage]
    var date = Date.now
}

@MainActor
@Observable
final class SavedStore {
    private(set) var items: [SavedAnswer] = []

    private static var file: URL { URL.applicationSupportDirectory.appending(path: "saved-answers.json") }

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let decoded = try? JSONDecoder().decode([SavedAnswer].self, from: data) {
            items = decoded
        }
    }

    func isSaved(question: String, answer: String) -> Bool {
        items.contains { $0.question == question && $0.answer == answer }
    }

    func toggle(question: String, answer: String, sources: [Passage]) {
        if let i = items.firstIndex(where: { $0.question == question && $0.answer == answer }) {
            items.remove(at: i)
        } else {
            items.insert(SavedAnswer(question: question, answer: answer, sources: sources), at: 0)
        }
        persist()
    }

    func remove(_ item: SavedAnswer) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: Self.file, options: .atomic)
    }
}
