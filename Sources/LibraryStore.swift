import BackgroundAssets
import Foundation
import Observation
import System

struct LibraryPack: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let articles: Int
    /// The Apple-hosted asset packs (App Store Connect) that make up this library. Their files sit under
    /// `<id>/` in the shared asset-pack namespace, so a large library can be split across several packs.
    let assetPackIDs: [String]
    /// An estimate until App Store Connect reports the real size (see `LibraryStore.refreshSizes`).
    var downloadBytes: Int64
    /// What stays on the phone once iOS has unpacked the download.
    let unpackedBytes: Int64

    /// The peak while installing: the compressed download plus the unpacked files.
    var installBytes: Int64 { downloadBytes + unpackedBytes }
    var title: String { label }
    var blurb: String {
        switch id {
        case "lite": "First aid and medicine, FEMA and CDC guidance, U.S. Army survival and cold-weather manuals, "
            + "plus outdoors, vehicle, bike and home-repair Q&A."
        case "full": "Essentials plus about 930,000 Wikipedia articles (skiing, avalanches, weather, wildlife, "
            + "plants) and the Wikivoyage travel guide."
        default: label
        }
    }
}

/// The libraries the app offers. Each is built into asset packs with scripts/build-asset-packs.sh and
/// uploaded to App Store Connect, which hosts them.
enum PackCatalog {
    static let all: [LibraryPack] = [
        LibraryPack(id: "lite", label: "Essentials", articles: 308_875, assetPackIDs: ["lite"],
                    downloadBytes: 926_728_121, unpackedBytes: 2_205_425_664),
        LibraryPack(id: "full", label: "Everything", articles: 1_272_789, assetPackIDs: ["full"],
                    downloadBytes: 8_656_795_917, unpackedBytes: 20_147_707_904),
    ]
}

@MainActor
@Observable
final class LibraryStore {
    enum Phase: Equatable {
        case idle
        case preparing
        case downloading(fraction: Double, detail: String)
        case failed(String)
    }

    var library: Library?
    var installedPackID: String?
    var phase: Phase = .idle
    var packs: [LibraryPack] = PackCatalog.all
    var articleCount = 0

    private var work: Task<Void, Never>?
    /// Live downloads by asset-pack ID: their Progress objects are how a download is cancelled.
    private var progresses: [String: Progress] = [:]
    private var fractions: [String: Double] = [:]
    private var downloadStart: Date?

    private nonisolated static var manager: AssetPackManager { .shared }

    /// A library copied in with Finder (iPhone › Files › Backcountry) also works.
    static var documentsFolder: URL { URL.documentsDirectory.appending(path: "Library", directoryHint: .isDirectory) }
    /// Where builds before Apple hosting unpacked their GitHub download. Read if present, removed on delete.
    static var legacyFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
    }

    init() {
        open()
        // iOS keeps downloaded packs up to date in the background. Reopen when one finishes.
        Task { [weak self] in
            for await update in await Self.manager.statusUpdates {
                if case .finished = update, self?.isWorking == false { self?.open() }
            }
        }
    }

    func open() {
        let manager = Self.manager
        for pack in packs.reversed()
        where pack.assetPackIDs.allSatisfy({ manager.assetPackIsAvailableLocally(withID: $0) }) {
            let root = pack.id
            if let lib = try? Library(locate: { try? Self.manager.url(for: FilePath("\(root)/\($0)")) }) {
                use(lib, packID: pack.id)
                return
            }
        }
        for folder in [Self.documentsFolder, Self.legacyFolder]
        where FileManager.default.fileExists(atPath: folder.appending(path: "index.sqlite").path) {
            if let lib = try? Library(folder: folder) {
                use(lib, packID: nil)
                return
            }
        }
        library = nil
        installedPackID = nil
        articleCount = 0
    }

    private func use(_ lib: Library, packID: String?) {
        library = lib
        installedPackID = packID
        articleCount = lib.stats().articles
    }

    /// Replaces the size estimates with what App Store Connect reports.
    func refreshSizes() async {
        for i in packs.indices {
            var total: Int64 = 0
            for id in packs[i].assetPackIDs {
                guard let pack = try? await Self.manager.assetPack(withID: id) else { return }
                total += Int64(pack.downloadSize)
            }
            if total > 0 { packs[i].downloadBytes = total }
        }
    }

    var isWorking: Bool {
        switch phase { case .idle, .failed: false; default: true }
    }

    func install(_ pack: LibraryPack) {
        guard !isWorking else { return }
        phase = .preparing
        work = Task {
            do {
                try await download(pack)
                phase = .idle
            } catch {
                phase = Task.isCancelled ? .idle : .failed(Self.message(for: error))
            }
            progresses = [:]
            fractions = [:]
            downloadStart = nil
        }
    }

    func cancel() {
        progresses.values.forEach { $0.cancel() }
        work?.cancel()
    }

    func deleteLibrary() {
        library = nil
        work = Task {
            for pack in packs {
                for id in pack.assetPackIDs where Self.manager.assetPackIsAvailableLocally(withID: id) {
                    try? await Self.manager.remove(assetPackWithID: id)
                }
            }
            try? FileManager.default.removeItem(at: Self.legacyFolder)
            open()
        }
    }

    // MARK: - Download

    private func download(_ pack: LibraryPack) async throws {
        var assetPacks: Set<AssetPack> = []
        for id in pack.assetPackIDs { assetPacks.insert(try await Self.manager.assetPack(withID: id)) }

        let missing = assetPacks.filter { !Self.manager.assetPackIsAvailableLocally(withID: $0.id) }
        let downloadBytes = missing.reduce(Int64(0)) { $0 + Int64($1.downloadSize) }
        let free = (try? URL.applicationSupportDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        let needed = missing.isEmpty ? 0 : downloadBytes + pack.unpackedBytes + 1_000_000_000
        if free > 0 && free < needed {
            throw StoreError.noSpace(needed: needed, free: free)
        }

        let sizes = Dictionary(uniqueKeysWithValues: assetPacks.map { ($0.id, Int64($0.downloadSize)) })
        let watchers = assetPacks.map { assetPack in
            Task { [weak self] in
                for await update in Self.manager.statusUpdates(forAssetPackWithID: assetPack.id) {
                    self?.record(update, sizes: sizes)
                }
            }
        }
        defer { watchers.forEach { $0.cancel() } }

        try await Self.manager.ensureLocalAvailability(of: assetPacks, requireLatestVersions: true)
        try Task.checkCancellation()

        // One library at a time: free the space the other one used.
        for other in packs where other.id != pack.id {
            for id in other.assetPackIDs
            where !pack.assetPackIDs.contains(id) && Self.manager.assetPackIsAvailableLocally(withID: id) {
                try? await Self.manager.remove(assetPackWithID: id)
            }
        }
        library = nil
        try? FileManager.default.removeItem(at: Self.legacyFolder)
        open()
    }

    private func record(_ update: AssetPackManager.DownloadStatusUpdate, sizes: [String: Int64]) {
        switch update {
        case let .downloading(assetPack, progress):
            progresses[assetPack.id] = progress
            fractions[assetPack.id] = progress.fractionCompleted
        case let .finished(assetPack):
            fractions[assetPack.id] = 1
        default:
            return
        }
        let total = max(sizes.values.reduce(0, +), 1)
        let done = sizes.reduce(0.0) { $0 + Double($1.value) * (fractions[$1.key] ?? 0) }
        let start = downloadStart ?? Date()
        downloadStart = start
        let elapsed = Date().timeIntervalSince(start)
        let rate = elapsed > 3 ? done / elapsed : 0
        phase = .downloading(fraction: done / Double(total),
                             detail: Self.progressText(done: Int64(done), total: total, rate: rate))
    }

    enum StoreError: LocalizedError {
        case noSpace(needed: Int64, free: Int64)
        var errorDescription: String? {
            switch self {
            case let .noSpace(needed, free):
                "Not enough free space: this needs about \(Self.gb(needed)) and the phone has \(Self.gb(free)) free."
            }
        }
        static func gb(_ b: Int64) -> String { String(format: "%.1f GB", Double(b) / 1e9) }
    }

    static func message(for error: Error) -> String {
        if error is StoreError { return error.localizedDescription }
        // No pack with that ID on Apple's servers (not uploaded or not approved yet) shows up as a 404.
        if case .assetPackNotFound = error as? ManagedBackgroundAssetsError {
            return "This library isn't available from the App Store yet."
        }
        if error.localizedDescription.localizedCaseInsensitiveContains("not found") {
            return "This library isn't available from the App Store yet."
        }
        return "The download didn't finish (\(error.localizedDescription)). Check Wi-Fi and try again."
    }

    nonisolated static func progressText(done: Int64, total: Int64, rate: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        var s = "\(f.string(fromByteCount: done)) of \(f.string(fromByteCount: total))"
        if rate > 0 {
            let left = Double(total - done) / rate
            s += " · \(f.string(fromByteCount: Int64(rate)))/s"
            if left.isFinite { s += " · " + (left > 90 ? "\(Int(left / 60)) min left" : "\(Int(left)) s left") }
        }
        return s
    }
}
