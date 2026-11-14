import BackgroundAssets
import Foundation
import HuggingFace
import Observation
import System
import UIKit

/// "Better answers": an optional bigger on-device model (Qwen 3.5 4B, 4-bit, run with MLX on the GPU) that writes
/// Scout's answers instead of Apple's model. Apple's model still plans the searches and checks the excerpts.
/// It comes as the Apple-hosted asset pack "answers" (scripts/release-model-pack.sh), like the library.
/// Xcode builds fall back to Hugging Face until that pack is on App Store Connect.
@MainActor
@Observable
final class BetterModel {
    static let shared = BetterModel()
    static let assetPackID = "answers"
    static let modelID = "mlx-community/Qwen3.5-4B-MLX-4bit"
    /// The model's name as people see it.
    static let displayName = "Qwen 3.5 4B"
    /// From scripts/release-model-pack.sh; App Store Connect's figure replaces it once known.
    static let estimatedDownloadBytes: Int64 = 2_261_254_682
    static let unpackedBytes: Int64 = 2_394_053_774

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case onDisk          // downloaded, not loaded into memory
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State
    private(set) var downloadBytes = BetterModel.estimatedDownloadBytes
    /// Write Scout's answers with it. Turned on when the download finishes; turning it off keeps the download.
    var useForAnswers: Bool {
        didSet { UserDefaults.standard.set(useForAnswers, forKey: "betterModel.useForAnswers") }
    }

    /// Runs the model. Everything that asks it for text goes through this.
    nonisolated let engine: MLXEngine
    private var loadTask: Task<Void, Never>?
    private var unloadTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var progress: Progress?
    private nonisolated static var manager: AssetPackManager { .shared }

    private init() {
        engine = MLXEngine(
            name: Self.displayName,
            weightsBytes: Self.unpackedBytes,
            extraEOSTokens: ["<|im_end|>"],
            // Qwen 3.x thinks out loud first unless the chat template is told not to.
            templateContext: ["enable_thinking": false],
            source: {
                await MainActor.run {
                    if let folder = BetterModel.packFolder { return .folder(folder) }
                    #if DEBUG
                    return .hub(BetterModel.modelID)  // not on App Store Connect yet: Xcode builds use Hugging Face
                    #else
                    return nil
                    #endif
                }
            },
            onDownloadProgress: { fraction in
                Task { @MainActor in
                    if case .downloading = BetterModel.shared.state {
                        BetterModel.shared.state = fraction >= 1 ? .loading : .downloading(fraction)
                    }
                }
            })
        useForAnswers = UserDefaults.standard.bool(forKey: "betterModel.useForAnswers")
        state = .notDownloaded  // every stored property needs a value before isDownloaded can be read
        state = isDownloaded ? .onDisk : .notDownloaded
        // iOS stops apps that hold this much memory in the background, so let it go there and when memory runs low.
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didReceiveMemoryWarningNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { BetterModel.shared.unload() }
            }
        }
        // A critically hot phone gives the model's memory and the GPU back; Apple's model answers until it cools.
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let heat = ProcessInfo.processInfo.thermalState
                LLMLog.note("thermal state: \(ThermalPolicy.name(heat))")
                if !ThermalPolicy.allowsLargeModel(heat) { BetterModel.shared.unload() }
            }
        }
    }

    /// MLX needs a real GPU; the simulator can't run it. Apple Intelligence iPhones all have 8 GB or more.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ProcessInfo.processInfo.physicalMemory >= 7_000_000_000
        #endif
    }

    /// Whether to offer it at all. The simulator shows it (without the download) so the screens can be checked.
    static var isOffered: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        isSupported
        #endif
    }

    private static var isLocal: Bool { LibraryStore.isLocal(assetPackID, marker: "config.json") }

    private static var packFolder: URL? {
        guard isLocal,
              let config = try? manager.url(for: FilePath("\(assetPackID)/config.json")) else { return nil }
        return config.deletingLastPathComponent()
    }

    private static var hubDownloaded: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "betterModel.downloaded")
        #else
        false
        #endif
    }

    var isDownloaded: Bool { Self.packFolder != nil || Self.hubDownloaded }
    var isReady: Bool { state == .ready }
    /// It will write the next answer (it may still need a few seconds to load).
    var isActive: Bool { useForAnswers && Self.isSupported && isDownloaded }

    /// Replaces the size estimate with what App Store Connect reports.
    func refreshSize() async {
        if let pack = try? await Self.manager.assetPack(withID: Self.assetPackID), pack.downloadSize > 0 {
            downloadBytes = Int64(pack.downloadSize)
        }
    }

    // MARK: - Download

    func download() {
        guard Self.isSupported, !isDownloaded, downloadTask == nil else { return }
        state = .downloading(0)
        downloadTask = Task {
            defer { downloadTask = nil; progress = nil }
            do {
                try await downloadPack()
                useForAnswers = true
                state = .onDisk
            } catch where Task.isCancelled || (error as? CocoaError)?.code == .userCancelled {
                state = .notDownloaded
            } catch {
                #if DEBUG
                // Not on App Store Connect yet: Xcode builds get the same model from Hugging Face.
                if Self.isMissingPack(error) {
                    log.notice("answers pack not found; downloading from Hugging Face")
                    prepare()
                    useForAnswers = true
                    return
                }
                #endif
                state = .failed(Self.isMissingPack(error)
                    ? "Better answers aren't available from the App Store yet."
                    : "The download didn't finish (\(error.localizedDescription)). Check Wi-Fi and try again.")
            }
        }
    }

    func cancelDownload() {
        progress?.cancel()
        downloadTask?.cancel()
    }

    private func downloadPack() async throws {
        let pack = try await Self.manager.assetPack(withID: Self.assetPackID)
        downloadBytes = Int64(pack.downloadSize)
        let free = (try? URL.applicationSupportDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        let needed = downloadBytes + Self.unpackedBytes + 500_000_000
        if free > 0 && free < needed {
            throw LibraryStore.StoreError.noSpace(needed: needed, free: free)
        }
        let watcher = Task { [weak self] in
            for await update in Self.manager.statusUpdates(forAssetPackWithID: Self.assetPackID) {
                if case let .downloading(_, p) = update {
                    self?.progress = p
                    if case .downloading = self?.state { self?.state = .downloading(p.fractionCompleted) }
                }
            }
        }
        defer { watcher.cancel() }
        if #available(iOS 26.4, *) {
            try await Self.manager.ensureLocalAvailability(of: pack, requireLatestVersion: true)
        } else {
            try await Self.manager.ensureLocalAvailability(of: pack)
        }
        try Task.checkCancellation()
    }

    private static func isMissingPack(_ error: Error) -> Bool {
        if case .assetPackNotFound = error as? ManagedBackgroundAssetsError { return true }
        return error.localizedDescription.localizedCaseInsensitiveContains("not found")
    }

    // MARK: - Memory

    /// Loads it into memory ahead of the next question, so the answer doesn't wait. Only when it's in use.
    func warmUp() {
        guard isActive, state != .ready,
              ThermalPolicy.allowsPreloading(ProcessInfo.processInfo.thermalState) else { return }
        prepare()
    }

    /// Loads the model into memory. In Xcode builds without the pack, downloads it from Hugging Face first.
    func prepare() {
        guard Self.isSupported, state != .ready, loadTask == nil else { return }
        let folder = Self.packFolder
        #if !DEBUG
        guard folder != nil else { return }
        #endif
        state = folder != nil || Self.hubDownloaded ? .loading : .downloading(0)
        loadTask = Task {
            defer { loadTask = nil }
            await unloadTask?.value  // an unload still in progress finishes first, or it would undo this load
            do {
                try await engine.load()
                if folder == nil { UserDefaults.standard.set(true, forKey: "betterModel.downloaded") }
                state = .ready
            } catch is CancellationError {  // unloaded while it was loading
                state = isDownloaded ? .onDisk : .notDownloaded
            } catch LLMError.notEnoughMemory {
                // Not an error to show: Apple's model answers this one, and the next question tries again.
                state = isDownloaded ? .onDisk : .notDownloaded
            } catch where Task.isCancelled {
                state = isDownloaded ? .onDisk : .notDownloaded
            } catch {
                state = .failed("Couldn't load better answers (\(error.localizedDescription)).")
            }
        }
    }

    /// Loads the model if it's downloaded; true once it's ready to answer.
    func ensureLoaded() async -> Bool {
        if isReady { return true }
        guard isDownloaded else { return false }
        prepare()
        await loadTask?.value
        return isReady
    }

    /// Frees the model's memory (it reloads from disk in a few seconds when needed again).
    func unload() {
        guard state == .ready || state == .loading else { return }
        loadTask?.cancel()
        state = isDownloaded ? .onDisk : .notDownloaded
        // Stops an answer in progress first: iOS ends apps that use the GPU in the background.
        unloadTask = Task { [previous = unloadTask] in
            await previous?.value
            await engine.unload()
        }
    }

    /// Deletes the downloaded files and goes back to Apple's model.
    func delete() {
        unload()
        useForAnswers = false
        let cache = HubCache.default
        if let repo = Repo.ID(rawValue: Self.modelID) {
            try? FileManager.default.removeItem(at: cache.repoDirectory(repo: repo, kind: .model))
        }
        UserDefaults.standard.set(false, forKey: "betterModel.downloaded")
        Task {
            if Self.isLocal {
                try? await Self.manager.remove(assetPackWithID: Self.assetPackID)
            }
            state = isDownloaded ? .onDisk : .notDownloaded
        }
        state = .notDownloaded
    }
}
