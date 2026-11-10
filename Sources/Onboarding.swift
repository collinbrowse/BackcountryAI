import SwiftUI
import UIKit

/// Persistence for first-run onboarding.
enum Onboarding {
    /// Set when the onboarding has been finished.
    static let completedKey = "completedOnboarding"
    /// The single-screen battery notice that onboarding replaced. Anyone who saw it already knows
    /// the battery warning, so they are not sent through onboarding again.
    static let legacyBatteryNoticeKey = "seenBatteryNotice"
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case meet, goodToKnow, pack
    var id: Int { rawValue }
}

/// Three short pages: meet Scout, the honest caveats (everyone sees the battery one), and setup.
struct OnboardingView: View {
    var isReplay = false
    var onFinish: () -> Void

    @Environment(LibraryStore.self) private var store
    @State private var step: OnboardingStep = .meet

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            Scenery()
                .frame(height: 360)
                .ignoresSafeArea(edges: .top)
                .opacity(step == .meet ? 1 : 0)
                .offset(y: step == .meet ? 0 : -60)
                .animation(.easeInOut(duration: 0.5), value: step)
            VStack(spacing: 0) {
                HStack {
                    if isReplay { Button("Close", action: onFinish).fontWeight(.semibold) }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 44)
                TabView(selection: $step) {
                    MeetPage().tag(OnboardingStep.meet)
                    GoodToKnowPage().tag(OnboardingStep.goodToKnow)
                    PackPage().tag(OnboardingStep.pack)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                bottomBar
            }
        }
        .tint(Theme.ember)
        .interactiveDismissDisabled(!isReplay)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { s in
                    Capsule()
                        .fill(s == step ? Theme.ember : Theme.inkSoft.opacity(0.3))
                        .frame(width: s == step ? 22 : 7, height: 7)
                }
            }
            .animation(.bouncy, value: step)
            .accessibilityElement()
            .accessibilityLabel("Page \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            if step == .pack && store.library == nil && !store.isWorking {
                Button("I'll do this later", action: onFinish).buttonStyle(SecondaryButtonStyle())
            } else {
                Button(primaryTitle, action: advance).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var primaryTitle: String {
        switch step {
        case .meet: "Nice to meet you"
        case .goodToKnow: "Got it"
        case .pack: store.library != nil ? "Let's go" : "Continue while it downloads"
        }
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return onFinish() }
        withAnimation(.bouncy) { step = next }
    }
}

// MARK: - Pages

private struct MeetPage: View {
    @State private var waved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Scout(mood: waved ? .happy : .idle, size: 170)
                    .padding(.top, 70)
                    .onTapGesture { waved.toggle() }
                    .sensoryFeedback(.impact(weight: .light), trigger: waved)
                VStack(spacing: 8) {
                    Text("Hi, I'm Scout")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Tell me what's happening out there and I'll tell you what to do, from a library of survival, first aid and repair guides on this iPhone.")
                        .font(.body).foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    feature("antenna.radiowaves.left.and.right.slash", "No signal\nneeded", Theme.sky)
                    feature("text.quote", "Shows its\nsources", Theme.ember)
                    feature("lock.fill", "Nothing leaves\nyour phone", Theme.moss)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            try? await Task.sleep(for: .seconds(0.8))
            waved = true
            try? await Task.sleep(for: .seconds(1.6))
            waved = false
        }
    }

    private func feature(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 44, height: 44).background(tint.opacity(0.14), in: .circle)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 12, radius: 18)
    }
}

private struct GoodToKnowPage: View {
    var body: some View {
        OnboardingPage(mood: .alert, title: "A few honest things") {
            point("checkmark.shield.fill", Theme.ember, "I can be wrong",
                  "Each step shows the article it came from, like [1]. Tap a step to read the source before you act.")
            point("sos", Theme.danger, "Emergencies: call 911 first",
                  "No signal? On iPhone 14 or later, calling 911 offers Emergency SOS via satellite. The red SOS button is always on the home screen.")
            point("battery.25percent", Theme.gold, "Answers use real battery",
                  "I think on this iPhone's chip, which works hard while I write. Searching and reading the library is instant and nearly free, saved answers cost nothing, and you'll see what each answer used. Carry a battery pack.")
        }
    }

    private func point(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 42, height: 42).background(tint.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(text).font(.subheadline).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct PackPage: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var problem: String?? = nil

    private var essentials: LibraryPack? { store.packs.first { $0.id == "lite" } ?? store.packs.first }

    var body: some View {
        OnboardingPage(mood: store.library != nil ? .happy : .idle, title: "Pack me for the trip",
                       subtitle: "Do this on Wi-Fi, before you lose signal.") {
            aiCard
            libraryCard
            Label("Then try me in Airplane Mode, so you know I work before you need me.", systemImage: "airplane")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                problem = .some(assistant.availabilityProblem)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var aiCard: some View {
        HStack(alignment: .top, spacing: 12) {
            stepIcon(done: problem == .some(nil), symbol: "sparkles")
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Intelligence").font(.headline).foregroundStyle(Theme.ink)
                switch problem {
                case .none: Text("Checking…").font(.subheadline).foregroundStyle(Theme.inkSoft)
                case .some(.none): Text("Ready. The model is on this iPhone.").font(.subheadline).foregroundStyle(Theme.moss)
                case let .some(.some(text)):
                    Text(text).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline.weight(.semibold))
                    Text("Without it you can still search and read the whole library.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
        .animation(.bouncy, value: problem == .some(nil))
    }

    @ViewBuilder private var libraryCard: some View {
        if store.isWorking || isFailed {
            DownloadProgressCard()
        } else {
            HStack(alignment: .top, spacing: 12) {
                stepIcon(done: store.library != nil, symbol: "books.vertical.fill")
                VStack(alignment: .leading, spacing: 6) {
                    Text("The library").font(.headline).foregroundStyle(Theme.ink)
                    if store.library != nil {
                        Text("\(store.articleCount.formatted()) articles installed.").font(.subheadline).foregroundStyle(Theme.moss)
                    } else if let pack = essentials {
                        Text("\(pack.title): \(pack.articles.formatted(.number.notation(.compactName))) articles, "
                             + String(format: "%.1f GB download.", Double(pack.downloadBytes) / 1e9)
                             + " You can pick a bigger one later.")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        Button { store.install(pack) } label: {
                            Label("Download \(pack.title)", systemImage: "arrow.down")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .card(padding: 14)
        }
    }

    private var isFailed: Bool { if case .failed = store.phase { true } else { false } }

    private func stepIcon(done: Bool, symbol: String) -> some View {
        Image(systemName: done ? "checkmark" : symbol)
            .font(.headline.weight(.bold))
            .foregroundStyle(done ? .white : Theme.ember)
            .frame(width: 38, height: 38)
            .background(done ? AnyShapeStyle(Theme.moss) : AnyShapeStyle(Theme.ember.opacity(0.14)), in: .circle)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Scout, a title, then the page's content.
private struct OnboardingPage<Content: View>: View {
    let mood: Scout.Mood
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft) }
                    }
                    Spacer(minLength: 0)
                    Scout(mood: mood, size: 84)
                }
                .padding(.top, 24)
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
