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
                                Text(String(format: "%.1f GB download", Double(pack.downloadBytes) / 1e9))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(pack.blurb).font(.callout).foregroundStyle(.secondary)
                            Text("\(pack.articles.formatted()) articles · "
                                 + String(format: "%.1f GB on the phone", Double(pack.install_bytes) / 1e9))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(store.installedPackID == pack.id ? "Download again" : "Download") {
                                store.install(pack)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isWorking)
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
