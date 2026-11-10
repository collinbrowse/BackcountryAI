import SwiftUI

@main
struct BackcountryApp: App {
    @State private var store = LibraryStore()
    @State private var assistant = Assistant()
    @State private var saved = SavedStore()
    @AppStorage(Onboarding.completedKey) private var completedOnboarding = false
    @AppStorage(Onboarding.legacyBatteryNoticeKey) private var seenBatteryNotice = false

    /// First run only. People who saw the old battery notice count as onboarded.
    private var needsOnboarding: Bool { !completedOnboarding && !seenBatteryNotice }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(assistant)
                .environment(saved)
                .tint(Theme.accent)
                .fullScreenCover(isPresented: .constant(needsOnboarding)) {
                    OnboardingView { completedOnboarding = true }
                        .environment(store)
                        .environment(assistant)
                }
        }
    }
}
