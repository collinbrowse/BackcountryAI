import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    status
                    if store.isWorking || isFailed { DownloadProgressCard() }
                    if store.packs.count > 1 { Text("Choose a library").sectionLabel() }
                    ForEach(store.packs) { PackCard(pack: $0) }
                    Text("Downloads from the App Store. Use Wi-Fi; it keeps going if you leave the app, and iOS keeps the library up to date.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                    about
                    if store.library != nil {
                        Button("Delete library from this iPhone", role: .destructive) { confirmDelete = true }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .disabled(store.isWorking)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Offline library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold) }
            .task { await store.refreshSizes() }
            .confirmationDialog("Delete the library from this phone?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.deleteLibrary() }
            } message: {
                Text("You'll need Wi-Fi to download it again.")
            }
        }
        .tint(Theme.accent)
    }

    private var isFailed: Bool { if case .failed = store.phase { true } else { false } }

    private var status: some View {
        HStack(spacing: 14) {
            Scout(mood: store.library == nil ? .sleepy : .happy, size: 74)
            VStack(alignment: .leading, spacing: 4) {
                if store.library != nil {
                    Text(store.articleCount.formatted())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text("articles on this iPhone. No signal needed.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("No library yet").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Theme.ink)
                    Text("Scout answers from it, so download one before your trip.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources and licenses").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text("Each article shows its source and license. U.S. government sources (FEMA, CDC, NIH, the National Park Service, National Weather Service, Forest Service, Coast Guard and the military) are public domain. Wikipedia, Stack Exchange and the other wikis are CC BY-SA: their text is shared under the same license.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
        }
        .card()
    }
}

/// One pack with what it costs in space and a single clear action.
struct PackCard: View {
    let pack: LibraryPack
    @Environment(LibraryStore.self) private var store

    private var installed: Bool { store.library != nil && store.installedPackID == pack.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(pack.title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Theme.ink)
                if pack.id == "lite" && !installed && store.packs.count > 1 {
                    Text("Recommended").font(.caption2.weight(.bold)).foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.14), in: .capsule)
                }
                Spacer()
                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.moss)
                }
            }
            Text(pack.blurb).font(.subheadline).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                stat("doc.text", "\(pack.articles.formatted(.number.notation(.compactName))) articles")
                if !installed { stat("arrow.down.circle", "\(gb(pack.downloadBytes)) download") }
                stat("iphone", "\(gb(pack.unpackedBytes)) on phone")
            }
            if !installed {
                let label = Label(store.library == nil || store.packs.count == 1 ? "Download" : "Switch to \(pack.title)",
                              systemImage: "arrow.down")
                Group {
                    if pack.id == "lite" {
                        Button { store.install(pack) } label: { label }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button { store.install(pack) } label: { label }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                .disabled(store.isWorking)
                Text("Needs about \(gb(pack.installBytes)) free while it installs.")
                    .font(.caption).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity)
            }
        }
        .card()
        .overlay {
            if installed {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.moss.opacity(0.6), lineWidth: 1.5)
            }
        }
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Theme.cardRaised, in: .capsule)
    }

    private func gb(_ bytes: Int64) -> String { String(format: "%.1f GB", Double(bytes) / 1e9) }
}

/// Download progress, shared by the library screen and onboarding.
struct DownloadProgressCard: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.hairline, lineWidth: 7)
                    Circle().trim(from: 0, to: fraction ?? 0.08)
                        .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: fraction)
                    if let fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .contentTransition(.numericText())
                    } else if !isFailed {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "exclamationmark").font(.headline.weight(.heavy)).foregroundStyle(Theme.danger)
                    }
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(isFailed ? Theme.danger : Theme.ink)
                    if let detail { Text(detail).font(.caption.monospacedDigit()).foregroundStyle(Theme.inkSoft) }
                }
                Spacer(minLength: 0)
            }
            if case .downloading = store.phase {
                Button("Cancel", role: .cancel) { store.cancel() }.font(.subheadline.weight(.semibold))
            }
        }
        .card()
    }

    private var isFailed: Bool { if case .failed = store.phase { true } else { false } }

    private var fraction: Double? {
        switch store.phase {
        case let .downloading(f, _): f
        default: nil
        }
    }

    private var title: String {
        switch store.phase {
        case .downloading: "Downloading"
        case .preparing: "Getting ready"
        case .failed: "Download stopped"
        case .idle: "Starting"
        }
    }

    private var detail: String? {
        switch store.phase {
        case let .downloading(_, d): d
        case let .failed(m): m
        default: nil
        }
    }
}
