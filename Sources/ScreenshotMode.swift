import Foundation

/// Puts the app in a fixed state for App Store screenshots and preview videos (UITests/, run by
/// `fastlane screenshots`): the demo library in fastlane/screenshot-fixtures/Library, scripted answers from
/// answers.json, and Apple's model treated as available, so the shots look the same on any Mac or CI runner.
///
/// Only Debug builds can turn it on, and only with the `-ScreenshotMode` launch argument. Release builds
/// (TestFlight and the App Store) compile it to "off".
enum ScreenshotMode {
    struct Script: Decodable {
        let question: String
        let answer: String
        let saved: Bool
    }

    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
    /// Copied into Debug builds only, from fastlane/screenshot-fixtures (see project.yml).
    private static let fixtures: URL? = Bundle.main.url(forResource: "ScreenshotFixtures", withExtension: nil)
    #else
    static let isOn = false
    private static let fixtures: URL? = nil
    #endif

    /// The demo library: a few hundred real articles, with the real library's article counts.
    static var libraryFolder: URL? {
        guard isOn, let folder = fixtures?.appending(path: "Library", directoryHint: .isDirectory),
              FileManager.default.fileExists(atPath: folder.appending(path: "index.sqlite").path) else { return nil }
        return folder
    }

    static let scripts: [Script] = {
        guard isOn, let url = fixtures?.appending(path: "answers.json"), let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder().decode([Script].self, from: data)) ?? []
    }()

    static func script(for question: String) -> Script? {
        let q = question.lowercased()
        return scripts.first { $0.question.lowercased() == q }
    }

    /// Fills chat history and Saved from the scripts, with sources found in the demo library.
    @MainActor static func seed(chats: ChatStore, saved: SavedStore, library: Library?) {
        guard isOn else { return }
        chats.deleteAll()
        for (i, s) in scripts.enumerated().reversed() {
            let sources = library?.search(s.question, limit: 3) ?? []
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i + 1)) ?? UUID()
            chats.save(id: id, messages: [
                ChatMessage(role: .user, text: s.question),
                ChatMessage(role: .assistant, text: s.answer, sources: sources, question: s.question),
            ])
            if s.saved, !saved.isSaved(question: s.question, answer: s.answer) {
                saved.toggle(question: s.question, answer: s.answer, sources: sources)
            }
        }
    }

    /// Plays a scripted answer the way a real one arrives: searching, reading, then words streaming in.
    @MainActor static func play(_ script: Script, status: (String?) -> Void, text: (String) -> Void) async {
        status("Searching the library…")
        try? await Task.sleep(for: .milliseconds(900))
        status("Reading what it found…")
        try? await Task.sleep(for: .milliseconds(700))
        status("Writing an answer on this phone…")
        try? await Task.sleep(for: .milliseconds(500))
        var shown = ""
        for word in script.answer.split(separator: " ", omittingEmptySubsequences: false) {
            shown += (shown.isEmpty ? "" : " ") + word
            status(nil)
            text(shown)
            try? await Task.sleep(for: .milliseconds(28))
        }
    }
}
