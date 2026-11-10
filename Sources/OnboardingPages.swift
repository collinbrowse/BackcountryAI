import SwiftUI
import UIKit

// MARK: 1. Welcome

struct WelcomePage: View {
    var body: some View {
        OnboardingPage(symbol: "mountain.2.fill", title: "Backcountry",
                       subtitle: "A field guide you can ask questions, even with no signal.") {
            OnboardingPoint(symbol: "books.vertical",
                            title: "A library on your phone",
                            text: "Survival and cold-weather manuals, first aid and medical references, FEMA and "
                                + "CDC guidance, and outdoor, vehicle and home repair Q&A.")
            OnboardingPoint(symbol: "text.quote",
                            title: "Answers with sources",
                            text: "Answers are written from articles in that library, with numbered "
                                + "sources you can open and read.")
            OnboardingPoint(symbol: "antenna.radiowaves.left.and.right.slash",
                            title: "Works offline",
                            text: "Search and the AI both run on this iPhone. Once it's set up, you don't need "
                                + "cell service or Wi-Fi.")
        }
    }
}

// MARK: 2. How to ask

struct HowToAskPage: View {
    var body: some View {
        OnboardingPage(symbol: "text.bubble", title: "How to ask") {
            OnboardingPoint(symbol: "person.fill.questionmark",
                            title: "Describe the situation",
                            text: "Say what happened, who's affected and what you have with you. \"Friend's "
                                + "toes are white and numb after a wet hike\" works better than \"frostbite\".")
            OnboardingPoint(symbol: "sparkles",
                            title: "Ask AI or Search only",
                            text: "Ask AI writes a short answer from the best matches. Search only lists "
                                + "matching articles without the AI, which saves battery.")
            OnboardingPoint(symbol: "hand.tap",
                            title: "Tap sources to check",
                            text: "Numbers like [1] point to the sources under each answer. Tap one to read "
                                + "the full article.")
            OnboardingCallout(tint: .red) {
                Label {
                    // One literal (not concatenated) so it stays a LocalizedStringKey and the bold renders.
                    Text("**The AI can be wrong.** Check the sources before you act on an answer. In an emergency, call or text 911, or use Emergency SOS via satellite if you can.")
                } icon: {
                    Image(systemName: "sos.circle.fill").foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: 3. Battery (everyone sees this page)

struct BatteryPage: View {
    var body: some View {
        OnboardingPage(symbol: "battery.25percent", title: "This app uses a lot of battery") {
            OnboardingPoint(symbol: "cpu",
                            title: "The AI runs on this iPhone",
                            text: "No internet is involved, so the phone's chip does all the work, and it "
                                + "works hard the whole time it's writing an answer.")
            OnboardingPoint(symbol: "gauge.with.dots.needle.33percent",
                            title: "You'll see what it costs",
                            text: "After each answer you'll see how much battery it used. After a few "
                                + "answers you'll also see an average for the session.")
            OnboardingPoint(symbol: "battery.100percent.bolt",
                            title: "Save power in the field",
                            text: "Carry a battery pack. Use Search only when you don't need a written "
                                + "answer. Reading articles uses very little battery.")
        }
    }
}

// MARK: 4. Apple Intelligence

struct AppleIntelligencePage: View {
    @Environment(Assistant.self) private var assistant
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// nil = not checked yet; .some(nil) = ready; .some(text) = what's wrong.
    @State private var problem: String?? = nil

    var body: some View {
        OnboardingPage(symbol: "sparkles", title: "Apple Intelligence",
                       subtitle: "Ask AI uses Apple's on-device model. Set it up now, while you have Wi-Fi.") {
            status
            OnboardingPoint(symbol: "magnifyingglass",
                            title: "Search works either way",
                            text: "Without Apple Intelligence you can still search and read the whole library.")
        }
        // The model's state can change while this page is open (it downloads, or the user comes back
        // from Settings), so check it now and then rather than once.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                problem = .some(assistant.availabilityProblem)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch problem {
        case .none:
            OnboardingCallout(tint: .secondary) {
                HStack(spacing: 10) { ProgressView(); Text("Checking…") }
            }
        case .some(.none):
            OnboardingCallout(tint: .green) {
                Label {
                    Text("**Ready.** Apple Intelligence is on and the model is on this iPhone.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        case let .some(.some(text)):
            OnboardingCallout(tint: .yellow) {
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: 5. Library

struct LibraryPage: View {
    @Environment(LibraryStore.self) private var store

    private var essentials: LibraryPack? { store.packs.first { $0.id == "lite" } ?? store.packs.first }

    var body: some View {
        OnboardingPage(symbol: "arrow.down.circle", title: "Get the library",
                       subtitle: "Answers come from this library, so download it before you go.") {
            card
            OnboardingPoint(symbol: "wifi",
                            title: "Use Wi-Fi, before your trip",
                            text: "It's a large download. It keeps going if you leave the app, and picks up "
                                + "again if the connection drops.")
            OnboardingPoint(symbol: "airplane",
                            title: "Then test it offline",
                            text: "Turn on Airplane Mode and ask a question, so you know it works before "
                                + "you need it.")
        }
    }

    @ViewBuilder private var card: some View {
        if store.library != nil {
            OnboardingCallout(tint: .green) {
                Label {
                    Text("**Library installed.** \(store.articleCount.formatted()) articles on this phone.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        } else if store.isWorking {
            OnboardingCallout { progress }
        } else if let pack = essentials {
            OnboardingCallout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.title).font(.headline)
                    Text("\(pack.articles.formatted()) articles · "
                         + String(format: "%.1f GB download", Double(pack.downloadBytes) / 1e9))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(pack.blurb).foregroundStyle(.secondary)
                if case let .failed(message) = store.phase {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                Button {
                    store.install(pack)
                } label: {
                    Label(isFailed ? "Try again" : "Download \(pack.title)", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        if store.library == nil {
            Text("You can also do this later from the Library button at the top left.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var isFailed: Bool { if case .failed = store.phase { true } else { false } }

    @ViewBuilder private var progress: some View {
        switch store.phase {
        case let .downloading(fraction, detail):
            Text("Downloading").font(.headline)
            ProgressView(value: fraction)
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button("Cancel", role: .cancel) { store.cancel() }
        case .preparing, .idle, .failed:
            HStack(spacing: 10) { ProgressView(); Text("Starting…") }
        }
    }
}
