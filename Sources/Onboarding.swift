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
    case meet, goodToKnow, pack, documents
    var id: Int { rawValue }
}

/// Four short pages: meet Scout, the honest caveats (everyone sees the battery one), the downloads, and the
/// person's own documents.
struct OnboardingView: View {
    var isReplay = false
    var onFinish: () -> Void

    @Environment(LibraryStore.self) private var store
    @State private var step: OnboardingStep = .meet
    @State private var better = BetterModel.shared

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
                    DocumentsPage().tag(OnboardingStep.documents)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                bottomBar
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(!isReplay)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { s in
                    Capsule()
                        .fill(s == step ? Theme.accent : Theme.inkSoft.opacity(0.3))
                        .frame(width: s == step ? 22 : 7, height: 7)
                }
            }
            .animation(.bouncy, value: step)
            .accessibilityElement()
            .accessibilityLabel("Page \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            if step == .pack && !packStarted {
                Button("I'll do this later", action: advance).buttonStyle(SecondaryButtonStyle())
            } else if step == .documents && store.myDocuments.isEmpty && !store.isImporting {
                Button("Skip for now", action: onFinish).buttonStyle(SecondaryButtonStyle())
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
        case .pack: packDownloading ? "Continue while it downloads" : "Next"
        case .documents: "Let's go"
        }
    }

    private var modelDownloading: Bool { if case .downloading = better.state { true } else { false } }
    private var packDownloading: Bool { store.isWorking || modelDownloading }
    private var packStarted: Bool { store.hasPack || better.isDownloaded || packDownloading }

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
                    feature("text.quote", "Shows its\nsources", Theme.accent)
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
            point("checkmark.shield.fill", Theme.accent, "I can be wrong",
                  "Each step shows the article it came from, like [1]. Tap a step to read the source before you act.")
            point("sos", Theme.danger, "Emergencies: call 911 first",
                  "No signal? On iPhone 14 or later, calling 911 offers Emergency SOS via satellite. The red SOS button is always on the home screen.")
            point("battery.25percent", Theme.sun, "Answers use real battery",
                  "I think on this iPhone's chip, which works hard while I write. Searching and reading the library is instant and nearly free, and so is rereading a saved chat. Carry a battery pack.")
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
    @State private var better = BetterModel.shared

    private var essentials: LibraryPack? { store.packs.first { $0.id == "lite" } ?? store.packs.first }
    private var needsGuides: Bool { !store.hasPack && !store.isWorking }
    /// The larger model is the default wherever it runs; only phones that can't run it skip it.
    private var needsModel: Bool { BetterModel.isSupported && better.state == .notDownloaded }
    private var modelDownloading: Bool { if case .downloading = better.state { true } else { false } }
    private var isFailed: Bool { if case .failed = store.phase { true } else { false } }

    var body: some View {
        OnboardingPage(mood: store.hasPack && better.isDownloaded ? .happy : .idle, title: "Pack me for the trip",
                       subtitle: "Do this on Wi-Fi, before you lose signal.") {
            aiCard
            libraryCard
            if BetterModel.isOffered { modelCard }
            downloadButtons
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
        .task { await better.refreshSize() }
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
                stepIcon(done: store.hasPack, symbol: "books.vertical.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Offline field guides").font(.headline).foregroundStyle(Theme.ink)
                    if store.hasPack {
                        Text("Ready. \(store.articleCount.formatted()) articles on this iPhone.").font(.subheadline).foregroundStyle(Theme.moss)
                    } else if let pack = essentials {
                        Text("First aid, survival, weather and park safety guides, "
                             + "\(pack.articles.formatted(.number.notation(.compactName))) articles. "
                             + "With no signal, this is what I look things up in, so my answers come from real sources. "
                             + Self.gb(pack.downloadBytes) + ".")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .card(padding: 14)
        }
    }

    private var modelCard: some View {
        HStack(alignment: .top, spacing: 12) {
            stepIcon(done: better.isDownloaded, symbol: "brain.head.profile")
            VStack(alignment: .leading, spacing: 4) {
                Text("Larger AI model").font(.headline).foregroundStyle(Theme.ink)
                switch better.state {
                case .downloading(let f):
                    ProgressView(value: f) {
                        Text(f > 0 ? "Downloading " + f.formatted(.percent.precision(.fractionLength(0)))
                                   : "Starting the download…")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .tint(Theme.accent)
                    Button("Cancel", role: .cancel) { better.cancelDownload() }.font(.subheadline.weight(.semibold))
                case .failed(let message) where !better.isDownloaded:
                    Text(message).font(.subheadline).foregroundStyle(Theme.danger)
                    Button("Try again") { better.download() }.font(.subheadline.weight(.semibold))
                default:
                    if better.isDownloaded {
                        Text("Ready. It writes my answers.").font(.subheadline).foregroundStyle(Theme.moss)
                    } else {
                        Text("Writes my answers, with more accurate, specific steps than Apple's built-in model. "
                             + "It runs on this iPhone too. " + Self.gb(better.downloadBytes) + ".")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        if !BetterModel.isSupported {
                            Text("Needs a real iPhone; the simulator can't run it.").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
        .animation(.bouncy, value: better.state)
    }

    /// One button gets everything. The guides alone are for phones short on space.
    @ViewBuilder private var downloadButtons: some View {
        if needsGuides, let pack = essentials {
            VStack(spacing: 6) {
                Button {
                    store.install(pack)
                    if needsModel { better.download() }
                } label: {
                    Label(needsModel ? "Download both · " + Self.gb(pack.downloadBytes + better.downloadBytes)
                                     : "Download guides · " + Self.gb(pack.downloadBytes),
                          systemImage: "arrow.down")
                }
                .buttonStyle(PrimaryButtonStyle())
                if needsModel {
                    Button("Short on space? Get just the guides (\(Self.gb(pack.downloadBytes)))") { store.install(pack) }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .padding(.vertical, 6)
                }
            }
        } else if needsModel {
            Button { better.download() } label: {
                Label("Download the model · " + Self.gb(better.downloadBytes), systemImage: "arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private static func gb(_ bytes: Int64) -> String { String(format: "%.1f GB", Double(bytes) / 1e9) }

    private func stepIcon(done: Bool, symbol: String) -> some View {
        Image(systemName: done ? "checkmark" : symbol)
            .font(.headline.weight(.bold))
            .foregroundStyle(done ? .white : Theme.accent)
            .frame(width: 38, height: 38)
            .background(done ? AnyShapeStyle(Theme.moss) : AnyShapeStyle(Theme.accent.opacity(0.14)), in: .circle)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// The person's own manuals and notes, searched along with the guides.
private struct DocumentsPage: View {
    var body: some View {
        OnboardingPage(mood: .idle, title: "Add your manuals",
                       subtitle: "Your snowmobile manual, a mountain bike repair guide, the trip plan. I index them and search them along with the library.") {
            MyDocumentsCard()
        }
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
