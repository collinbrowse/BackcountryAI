import SwiftUI

@main
struct BackcountryAIApp: App {
    @State private var store: LibraryStore
    @State private var chats: ChatStore
    @State private var assistant: Assistant
    @State private var saved: SavedStore
    @State private var field = FieldStore()
    init() {
        let store = LibraryStore()
        let chats = ChatStore()
        let saved = SavedStore()
        ScreenshotMode.seed(chats: chats, saved: saved, library: store.library)
        _store = State(initialValue: store)
        _chats = State(initialValue: chats)
        _saved = State(initialValue: saved)
        _assistant = State(initialValue: Assistant(chats: chats))
    }

    @AppStorage(Onboarding.completedKey) private var completedOnboarding = false
    @AppStorage(Onboarding.legacyBatteryNoticeKey) private var seenBatteryNotice = false

    /// First run only. People who saw the old battery notice count as onboarded.
    private var needsOnboarding: Bool { !completedOnboarding && !seenBatteryNotice }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(assistant)
                .environment(chats)
                .environment(saved)
                .environment(field)
                .tint(Theme.accent)
                .fullScreenCover(isPresented: .constant(needsOnboarding)) {
                    OnboardingView { completedOnboarding = true }
                        .environment(store)
                        .environment(assistant)
                }
        }
    }
}
