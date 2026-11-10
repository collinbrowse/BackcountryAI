import SwiftUI

/// Persistence for first-run onboarding.
enum Onboarding {
    /// Set when the onboarding has been finished or skipped.
    static let completedKey = "completedOnboarding"
    /// The single-screen battery notice that onboarding replaced. Anyone who saw it already knows
    /// the battery warning, so they are not sent through onboarding again.
    static let legacyBatteryNoticeKey = "seenBatteryNotice"
}

/// The pages, in order.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, howToAsk, battery, appleIntelligence, library
    var id: Int { rawValue }
}

/// A short paged introduction. Everything after the battery page can be skipped.
struct OnboardingView: View {
    /// Pass true when replaying from the menu: the battery page has been seen, so Skip shows from the start.
    var isReplay = false
    var onFinish: () -> Void

    @Environment(LibraryStore.self) private var store
    @State private var step: OnboardingStep = .welcome
    @State private var sawBattery = false

    private var canSkip: Bool { (isReplay || sawBattery) && step != .library }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $step) {
                ForEach(OnboardingStep.allCases) { s in
                    page(s).tag(s)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
        .tint(.orange)
        .interactiveDismissDisabled(!isReplay)
        .onChange(of: step, initial: true) {
            if step.rawValue >= OnboardingStep.battery.rawValue { sawBattery = true }
        }
    }

    @ViewBuilder private func page(_ s: OnboardingStep) -> some View {
        switch s {
        case .welcome: WelcomePage()
        case .howToAsk: HowToAskPage()
        case .battery: BatteryPage()
        case .appleIntelligence: AppleIntelligencePage()
        case .library: LibraryPage()
        }
    }

    private var topBar: some View {
        HStack {
            if isReplay {
                Button("Close", action: onFinish)
            }
            Spacer()
            if canSkip && !isReplay {
                Button("Skip", action: onFinish)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            PageDots(count: OnboardingStep.allCases.count, current: step.rawValue)
            let button = Button(action: advance) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            // On the library page "Later" shouldn't compete with the Download button above it.
            if isLaterChoice {
                button.buttonStyle(.bordered)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    private var primaryTitle: String {
        switch step {
        case .battery: "Got it"
        case .library:
            store.library != nil ? "Start" : store.isWorking ? "Continue while it downloads" : "Later"
        default: "Continue"
        }
    }

    private var isLaterChoice: Bool { step == .library && store.library == nil && !store.isWorking }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return onFinish() }
        withAnimation { step = next }
    }
}

/// Small, restylable page indicator (the TabView's own dots are hidden so they sit above the button).
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.orange : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Shared page layout

/// Icon, title, optional subtitle, then the page's content. All pages use this so a redesign
/// only has to change one place.
struct OnboardingPage<Content: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.largeTitle.bold())
                    if let subtitle {
                        Text(subtitle).font(.title3).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 18) { content }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One explained point: icon, short bold heading, a sentence or two.
struct OnboardingPoint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A tinted callout box for warnings and status.
struct OnboardingCallout<Content: View>: View {
    var tint: Color = .orange
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}
