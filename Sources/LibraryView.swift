import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.library != nil {
                        LabeledContent("Installed", value: installedName)
                        LabeledContent("Articles", value: store.articleCount.formatted())
                    } else {
                        Text("No library yet. Download one on Wi-Fi before your trip. It works fully offline after that.")
                    }
                }

                Section {
                    ForEach(store.packs) { pack in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(pack.title).font(.headline)
                                Spacer()
                                if isInstalled(pack) {
                                    Label("Installed", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                                }
                            }
                            Text(pack.blurb).font(.callout).foregroundStyle(.secondary)
                            Text("\(pack.articles.formatted()) articles · \(Self.gb(pack.downloadBytes)) download, "
                                 + "about \(Self.gb(pack.unpackedBytes)) on the phone once unpacked")
                                .font(.caption).foregroundStyle(.secondary)
                            if isInstalled(pack) {
                                Menu("Options") {
                                    Button("Re-download (repairs a damaged library)") { store.install(pack) }
                                }
                                .font(.caption)
                                .disabled(store.isWorking)
                            } else {
                                Button(store.library == nil ? "Download" : "Switch to \(pack.title)") {
                                    store.install(pack)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.isWorking)
                                Text("Needs about \(Self.gb(pack.install_bytes)) free while it installs.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Libraries")
                } footer: {
                    Text("From the open-source Survival LLM project. Use Wi-Fi and keep the app open while it "
                         + "downloads; the screen stays on, and it resumes if the connection drops.")
                }

                if store.isWorking || isFailed {
                    Section("Progress") { progress }
                }

                if store.library != nil {
                    Section {
                        Button("Delete library", role: .destructive) { confirmDelete = true }
                            .disabled(store.isWorking)
                    }
                }

                Section("Sources and licenses") {
                    Text("Each article shows its source and license. Medical, FEMA, CDC and military sources "
                         + "are public domain; wikiHow, iFixit and WHO material is for non-commercial use only.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Offline library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task { await store.refreshCatalog() }
            .confirmationDialog("Delete the library from this phone?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.deleteLibrary() }
            } message: {
                Text("You'll need Wi-Fi to download it again.")
            }
        }
    }

    private func isInstalled(_ pack: LibraryPack) -> Bool {
        store.library != nil && store.installedPackID == pack.id
    }

    static func gb(_ bytes: Int64) -> String { String(format: "%.1f GB", Double(bytes) / 1e9) }

    private var installedName: String {
        store.packs.first { $0.id == store.installedPackID }?.title ?? "Custom"
    }

    private var isFailed: Bool { if case .failed = store.phase { true } else { false } }

    @ViewBuilder private var progress: some View {
        switch store.phase {
        case let .downloading(part, of, fraction, detail):
            VStack(alignment: .leading, spacing: 6) {
                Text(of > 1 ? "Downloading part \(part) of \(of)" : "Downloading")
                ProgressView(value: fraction)
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel) { store.cancel() }
        case .verifying:
            HStack { ProgressView(); Text("Checking the download…") }
        case let .unpacking(fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text("Unpacking")
                ProgressView(value: fraction)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }
}
