import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs a model with MLX on the GPU. It needs a real device: the simulator has no Metal support MLX can use.
actor MLXEngine: LLMEngine {
    /// Where the weights are: a folder on the phone, or a Hugging Face repository to download first.
    enum Source: Sendable {
        case folder(URL)
        case hub(String, revision: String = "main")
    }

    nonisolated let name: String
    private let weightsBytes: Int64
    private let source: @Sendable () async -> Source?
    private let extraEOSTokens: Set<String>
    private let templateContext: [String: any Sendable]
    private let onDownloadProgress: @Sendable (Double) -> Void

    private var container: ModelContainer?
    private var generation: Task<Void, Never>?
    /// Goes up on every unload, so a load that finishes after an unload knows to throw its model away.
    private var epoch = 0

    /// - Parameters:
    ///   - weightsBytes: the size of the weights, for the memory check when they aren't on the phone yet.
    ///   - source: asked at each load, so a model downloaded since the last try is found.
    ///   - extraEOSTokens: end-of-turn tokens the tokenizer's config doesn't list.
    ///   - templateContext: extra values for the model's chat template.
    init(name: String, weightsBytes: Int64, extraEOSTokens: Set<String> = [], templateContext: [String: any Sendable] = [:],
         source: @escaping @Sendable () async -> Source?,
         onDownloadProgress: @escaping @Sendable (Double) -> Void = { _ in }) {
        self.name = name
        self.weightsBytes = weightsBytes
        self.extraEOSTokens = extraEOSTokens
        self.templateContext = templateContext
        self.source = source
        self.onDownloadProgress = onDownloadProgress
    }

    var isLoaded: Bool { container != nil }

    func contextTokens(for config: GenerationConfig) -> Int { config.contextTokens }

    func load() async throws {
        guard container == nil else { return }
        guard let source = await source() else { throw LLMError.loadFailed("it isn't downloaded") }
        // Never start a load iOS would end the app for: check what's free first.
        var budget = MemoryBudget(weightsBytes: weightsBytes)
        if case .folder(let url) = source, let onDisk = Self.weightsOnDisk(in: url) { budget.weightsBytes = onDisk }
        do {
            try budget.check(availableBytes: MemoryProbe.availableBytes)
        } catch {
            LLMLog.note("\(name): not loading, \(error.localizedDescription) \(MemoryProbe.report("refused load"))")
            throw error
        }
        let epoch = epoch
        let started = Date()
        // Cap MLX's buffer cache so it doesn't hold on to memory iOS wants back.
        Memory.cacheLimit = 256 * 1024 * 1024
        let configuration = switch source {
        case .folder(let url): ModelConfiguration(directory: url, extraEOSTokens: extraEOSTokens)
        case .hub(let id, let revision): ModelConfiguration(id: id, revision: revision, extraEOSTokens: extraEOSTokens)
        }
        let progress = onDownloadProgress
        let loaded = try await loadModelContainer(
            from: HubDownloader(), using: TransformersTokenizerLoader(), configuration: configuration
        ) { progress($0.fractionCompleted) }
        // Unloaded or cancelled while the weights were being read: let them go again.
        guard epoch == self.epoch, !Task.isCancelled else {
            Memory.clearCache()
            throw CancellationError()
        }
        let loadSeconds = Date().timeIntervalSince(started)
        // The first answer after a load is slow: Metal compiles its shaders and the weights are touched for the
        // first time. One throwaway token pays that now, not while someone waits for an answer.
        let warmStarted = Date()
        _ = try? await Self.run(loaded, [.user("Hi")], GenerationConfig(temperature: 0, maxTokens: 1), templateContext) { _ in }
        guard epoch == self.epoch, !Task.isCancelled else {
            Memory.clearCache()
            throw CancellationError()
        }
        if container == nil { container = loaded }
        LLMLog.note(String(format: "%@: loaded in %.1f s, warmed up in %.1f s. ", name, loadSeconds,
                           Date().timeIntervalSince(warmStarted)) + MemoryProbe.report("after load"))
    }

    private static func weightsOnDisk(in folder: URL) -> Int64? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let sizes = files.filter { $0.pathExtension == "safetensors" }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        return sizes.isEmpty ? nil : Int64(sizes.reduce(0, +))
    }

    func generate(_ messages: [LLMMessage], config: GenerationConfig) -> AsyncThrowingStream<LLMEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<LLMEvent, Error>.makeStream()
        guard let container else {
            continuation.finish(throwing: LLMError.notLoaded)
            return stream
        }
        // One answer at a time: the GPU and the memory budget are sized for one.
        let previous = generation
        previous?.cancel()
        let context = templateContext
        let task = Task {
            await previous?.value
            do {
                let stats = try await Self.run(container, messages, config, context) { continuation.yield(.text($0)) }
                continuation.yield(.finished(stats))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        generation = task
        continuation.onTermination = { if case .cancelled = $0 { task.cancel() } }
        return stream
    }

    private static func run(_ container: ModelContainer, _ messages: [LLMMessage], _ config: GenerationConfig,
                            _ templateContext: [String: any Sendable],
                            onText: (String) -> Void) async throws -> LLMStats {
        let chat = messages.map { message -> Chat.Message in
            switch message.role {
            case .system: .system(message.content)
            case .user: .user(message.content)
            case .assistant: .assistant(message.content)
            }
        }
        let started = Date()
        let input = try await container.prepare(input: UserInput(chat: chat, additionalContext: templateContext))
        try Task.checkCancellation()
        // The cache below keeps only the newest `contextTokens` tokens. A longer prompt would silently lose its
        // start (the instructions), so refuse it instead.
        let promptTokens = input.text.tokens.size
        guard promptTokens <= config.promptTokenLimit else {
            throw LLMError.promptTooLong(tokens: promptTokens, limit: config.promptTokenLimit)
        }
        // maxKVSize caps the key-value cache, the part of memory that grows with every token.
        let parameters = GenerateParameters(maxTokens: config.maxTokens, maxKVSize: config.contextTokens,
                                            temperature: Float(config.temperature),
                                            topP: Float(config.topP))
        let stream = try await container.generate(input: input, parameters: parameters)
        var filter = StopSequenceFilter(config.stopSequences)
        var stats = LLMStats(), pieces = 0
        events: for await event in stream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let piece):
                if pieces == 0 { stats.secondsToFirstToken = Date().timeIntervalSince(started) }
                pieces += 1
                if filter.append(piece) { onText(filter.text) }
                // Leaving the loop ends the stream, which stops the model.
                if filter.stopped { break events }
            case .info(let info):
                stats.promptTokens = info.promptTokenCount
                stats.answerTokens = info.generationTokenCount
                stats.promptTokensPerSecond = info.promptTokensPerSecond
                stats.tokensPerSecond = info.tokensPerSecond
                stats.stopReason = switch info.stopReason {
                case .stop: .endOfTurn
                case .length: .maxTokens
                case .cancelled: .cancelled
                }
            default:
                break
            }
        }
        try Task.checkCancellation()
        if filter.stopped {
            // The model was cut off before it could report, so these come from the clock.
            let writing = Date().timeIntervalSince(started) - stats.secondsToFirstToken
            stats.answerTokens = pieces
            stats.tokensPerSecond = writing > 0 ? Double(pieces) / writing : 0
            stats.stopReason = .stopSequence
        } else if filter.finish() {
            onText(filter.text)
        }
        return stats
    }

    func tokenCount(_ messages: [LLMMessage]) async -> Int? {
        guard let container else { return nil }
        let tokenizer = await container.tokenizer
        let turns: [[String: any Sendable]] = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        return try? tokenizer.applyChatTemplate(messages: turns, tools: nil, additionalContext: templateContext).count
    }

    func cancel() async {
        generation?.cancel()
        await generation?.value
    }

    func unload() async {
        epoch += 1
        await cancel()
        generation = nil
        guard container != nil else { return }
        let before = MemoryProbe.footprintBytes
        container = nil
        Memory.clearCache()
        LLMLog.note("\(name): unloaded, freed \((before - MemoryProbe.footprintBytes) / 1_048_576) MiB. "
            + "MLX active \(Memory.activeMemory / 1_048_576) MiB, cache \(Memory.cacheMemory / 1_048_576) MiB. "
            + MemoryProbe.report("after unload"))
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
