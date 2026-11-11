import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Observation
import Tokenizers

/// PROTOTYPE: an optional bigger on-device model (Qwen 3.5 4B, 4-bit, run with MLX on the GPU) that writes answers
/// instead of Apple's model. Apple's model still plans the searches and checks the excerpts. The point is to measure
/// speed, memory and battery on real iPhones before deciding to ship it (docs/on-device-model-comparison.md).
/// For testing it downloads from Hugging Face; a shipped version would come as an Apple-hosted asset pack.
@MainActor
@Observable
final class BetterModel {
    static let shared = BetterModel()
    static let modelID = "mlx-community/Qwen3.5-4B-MLX-4bit"
    static let approximateDownload = "about 3 GB"

    enum State: Equatable {
        case notDownloaded
        case onDisk          // downloaded, not loaded into memory
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    var state: State
    /// Use it for answers when it's downloaded. Off by default.
    var useForAnswers: Bool {
        didSet { UserDefaults.standard.set(useForAnswers, forKey: "betterModel.useForAnswers") }
    }

    private var container: ModelContainer?
    private var loadTask: Task<Void, Never>?

    private init() {
        useForAnswers = UserDefaults.standard.bool(forKey: "betterModel.useForAnswers")
        state = UserDefaults.standard.bool(forKey: "betterModel.downloaded") ? .onDisk : .notDownloaded
    }

    /// MLX needs a real GPU; the simulator can't run it. Apple Intelligence iPhones all have 8 GB or more.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ProcessInfo.processInfo.physicalMemory >= 7_000_000_000
        #endif
    }

    var isDownloaded: Bool { UserDefaults.standard.bool(forKey: "betterModel.downloaded") }
    var isReady: Bool { state == .ready }

    /// Downloads the model if needed and loads it into memory.
    func prepare() {
        guard Self.isSupported, container == nil, loadTask == nil else { return }
        state = isDownloaded ? .loading : .downloading(0)
        loadTask = Task {
            defer { loadTask = nil }
            do {
                // Cap MLX's buffer cache so it doesn't hold on to memory iOS wants back.
                Memory.cacheLimit = 256 * 1024 * 1024
                let c = try await loadModelContainer(
                    from: HubDownloader(), using: TransformersTokenizerLoader(),
                    configuration: ModelConfiguration(id: Self.modelID, extraEOSTokens: ["<|im_end|>"])
                ) { progress in
                    Task { @MainActor in
                        let f = progress.fractionCompleted
                        if case .downloading = BetterModel.shared.state {
                            BetterModel.shared.state = f >= 1 ? .loading : .downloading(f)
                        }
                    }
                }
                container = c
                UserDefaults.standard.set(true, forKey: "betterModel.downloaded")
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
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
        container = nil
        Memory.clearCache()
        state = isDownloaded ? .onDisk : .notDownloaded
    }

    /// Deletes the downloaded files.
    func delete() {
        unload()
        let cache = HubCache.default
        if let repo = Repo.ID(rawValue: Self.modelID) {
            try? FileManager.default.removeItem(at: cache.repoDirectory(repo: repo, kind: .model))
        }
        UserDefaults.standard.set(false, forKey: "betterModel.downloaded")
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

/// How much memory the app is using and how much more iOS will allow before it stops the app.
enum MemoryProbe {
    static var footprintGB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1e9 : 0
    }

    static var availableGB: Double { Double(os_proc_available_memory()) / 1e9 }
    static var deviceGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1e9 }
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
