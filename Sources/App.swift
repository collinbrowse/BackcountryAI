import SwiftUI

@main
struct BackcountryAIApp: App {
    @State private var store: LibraryStore
    @State private var chats: ChatStore
    @State private var assistant: Assistant
    @State private var field = FieldStore()
    init() {
        let store = LibraryStore()
        let chats = ChatStore()
        chats.importLegacySavedAnswers()
        ScreenshotMode.seed(chats: chats, library: store.library)
        _store = State(initialValue: store)
        _chats = State(initialValue: chats)
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
