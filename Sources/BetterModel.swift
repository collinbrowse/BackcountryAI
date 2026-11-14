import BackgroundAssets
import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Observation
import System
import Tokenizers
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

    private var container: ModelContainer?
    private var loadTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var progress: Progress?
    private nonisolated static var manager: AssetPackManager { .shared }

    private init() {
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
        guard isActive, container == nil else { return }
        prepare()
    }

    /// Loads the model into memory. In Xcode builds without the pack, downloads it from Hugging Face first.
    func prepare() {
        guard Self.isSupported, container == nil, loadTask == nil else { return }
        let folder = Self.packFolder
        #if !DEBUG
        guard folder != nil else { return }
        #endif
        state = folder != nil || Self.hubDownloaded ? .loading : .downloading(0)
        loadTask = Task {
            defer { loadTask = nil }
            do {
                // Cap MLX's buffer cache so it doesn't hold on to memory iOS wants back.
                Memory.cacheLimit = 256 * 1024 * 1024
                let configuration = folder.map { ModelConfiguration(directory: $0, extraEOSTokens: ["<|im_end|>"]) }
                    ?? ModelConfiguration(id: Self.modelID, extraEOSTokens: ["<|im_end|>"])
                let c = try await loadModelContainer(
                    from: HubDownloader(), using: TransformersTokenizerLoader(), configuration: configuration
                ) { progress in
                    Task { @MainActor in
                        let f = progress.fractionCompleted
                        if case .downloading = BetterModel.shared.state {
                            BetterModel.shared.state = f >= 1 ? .loading : .downloading(f)
                        }
                    }
                }
                if folder == nil { UserDefaults.standard.set(true, forKey: "betterModel.downloaded") }
                guard !Task.isCancelled else { state = .onDisk; return }  // unloaded while it was loading
                container = c
                state = .ready
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
        guard container != nil || state == .loading else { return }
        loadTask?.cancel()
        container = nil
        Memory.clearCache()
        state = isDownloaded ? .onDisk : .notDownloaded
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

    struct Stats: Sendable {
        var promptTokens = 0
        var answerTokens = 0
        var secondsToFirstWord: Double = 0
        var promptTokensPerSecond: Double = 0
        var tokensPerSecond: Double = 0
    }

    /// Streams an answer. `onText` gets the whole answer so far, like LanguageModelSession's snapshots.
    func answer(instructions: String, prompt: String, onText: @MainActor (String) -> Void) async throws -> Stats {
        guard let container else { throw CancellationError() }
        // Qwen 3.x thinks out loud first unless the chat template is told not to.
        let input = UserInput(chat: [.system(instructions), .user(prompt)],
                              additionalContext: ["enable_thinking": false])
        let started = Date()
        let lmInput = try await container.prepare(input: input)
        let stream = try await container.generate(
            input: lmInput, parameters: GenerateParameters(maxTokens: 700, temperature: 0.3, topP: 0.95))
        var text = "", stats = Stats()
        for await event in stream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let s):
                if text.isEmpty { stats.secondsToFirstWord = Date().timeIntervalSince(started) }
                text += s
                onText(text)
            case .info(let info):
                stats.promptTokens = info.promptTokenCount
                stats.answerTokens = info.generationTokenCount
                stats.promptTokensPerSecond = info.promptTokensPerSecond
                stats.tokensPerSecond = info.tokensPerSecond
            default:
                break
            }
        }
        return stats
    }
}

// The adapters MLXHuggingFace's macros would generate, written out so the app doesn't depend on package macros.

/// Downloads model files from Hugging Face into the app's cache.
struct HubDownloader: MLXLMCommon.Downloader {
    private let hub = HubClient()

    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        guard let repo = Repo.ID(rawValue: id) else { throw URLError(.badURL) }
        return try await hub.downloadSnapshot(of: repo, revision: revision ?? "main", matching: patterns,
                                              progressHandler: { @MainActor progress in progressHandler(progress) })
    }
}

/// Loads the model's tokenizer with swift-transformers.
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
