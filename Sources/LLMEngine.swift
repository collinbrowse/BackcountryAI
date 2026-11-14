import Foundation

/// Everything that shapes one answer, in one place: sampling, length, stop sequences and how much context
/// the model may hold.
struct GenerationConfig: Sendable, Equatable {
    var temperature: Double = 0.3
    var topP: Double = 0.95
    /// The longest answer, in tokens.
    var maxTokens = 700
    /// The answer ends just before the first of these appears. The model's own end-of-turn token always ends it.
    var stopSequences: [String] = []
    /// The most tokens the model holds at once: instructions, prompt and answer together. It is also the size
    /// of the key-value cache, which is what grows in memory while an answer is written.
    var contextTokens = 4096

    /// Scout's answers.
    static let answers = GenerationConfig()

    /// Room for the instructions and prompt once the answer's share is set aside.
    var promptTokenLimit: Int { max(0, contextTokens - maxTokens) }
}

struct LLMMessage: Sendable, Equatable {
    enum Role: String, Sendable { case system, user, assistant }
    var role: Role
    var content: String

    static func system(_ text: String) -> LLMMessage { .init(role: .system, content: text) }
    static func user(_ text: String) -> LLMMessage { .init(role: .user, content: text) }
    static func assistant(_ text: String) -> LLMMessage { .init(role: .assistant, content: text) }
}

struct LLMStats: Sendable, Equatable {
    enum StopReason: String, Sendable { case endOfTurn, maxTokens, stopSequence, cancelled }
    var promptTokens = 0
    var answerTokens = 0
    var secondsToFirstToken: Double = 0
    var promptTokensPerSecond: Double = 0
    var tokensPerSecond: Double = 0
    var stopReason: StopReason = .endOfTurn
}

enum LLMEvent: Sendable, Equatable {
    /// The whole answer so far.
    case text(String)
    /// Always the last event of an answer that wasn't cancelled.
    case finished(LLMStats)
}

enum LLMError: LocalizedError, Equatable {
    case notLoaded
    case unsupportedDevice
    case notEnoughMemory(neededBytes: Int64, availableBytes: Int64)
    case promptTooLong(tokens: Int, limit: Int)
    case loadFailed(String)

    var errorDescription: String? {
        let gb = { (b: Int64) in String(format: "%.1f GB", Double(b) / 1e9) }
        return switch self {
        case .notLoaded: "The model isn't loaded."
        case .unsupportedDevice: "This iPhone can't run the model."
        case .notEnoughMemory(let needed, let available):
            "Not enough free memory for the model (needs \(gb(needed)), \(gb(available)) free). "
                + "Closing other apps can help."
        case .promptTooLong(let tokens, let limit):
            "The question and excerpts are too long for the model (\(tokens) tokens, limit \(limit))."
        case .loadFailed(let why): "The model couldn't load (\(why))."
        }
    }
}

/// A language model that runs on the phone. The app talks to models only through this, so the engine
/// underneath (MLX today) can be swapped.
protocol LLMEngine: Sendable {
    /// A short name for logs and benchmark results.
    var name: String { get }
    var isLoaded: Bool { get async }
    /// The most tokens the engine can hold for one answer under `config`.
    func contextTokens(for config: GenerationConfig) async -> Int
    /// Brings the model into memory. Throws instead of letting iOS stop the app when memory is short.
    func load() async throws
    /// Streams one answer. Cancelling the task that reads the stream stops the model.
    func generate(_ messages: [LLMMessage], config: GenerationConfig) async -> AsyncThrowingStream<LLMEvent, Error>
    /// How many tokens these messages take with the model's chat template. Nil if the engine can't say.
    func tokenCount(_ messages: [LLMMessage]) async -> Int?
    /// Stops the answer being written, if any, and waits until the model is idle.
    func cancel() async
    /// Stops any answer and frees the model's memory. `load()` brings it back.
    func unload() async
}

extension LLMEngine {
    /// Runs one answer to the end, calling `onText` with the whole answer so far.
    @discardableResult
    func answer(_ messages: [LLMMessage], config: GenerationConfig,
                onText: @MainActor (String) -> Void) async throws -> LLMStats {
        var stats = LLMStats(stopReason: .cancelled)
        for try await event in await generate(messages, config: config) {
            try Task.checkCancellation()
            switch event {
            case .text(let text): await onText(text)
            case .finished(let s): stats = s
            }
        }
        try Task.checkCancellation()
        return stats
    }
}

/// What to do about heat. The larger model runs the GPU hard; Apple's model is far lighter.
enum ThermalPolicy {
    /// Answers are this short at most while the phone is hot (a typical answer is about 130 tokens).
    static let hotMaxTokens = 400

    /// Whether the larger model may write answers. Not when the phone is critically hot: Apple's model does.
    static func allowsLargeModel(_ state: ProcessInfo.ThermalState) -> Bool { state != .critical }

    /// Whether to load the model ahead of a question. Not while the phone is already hot.
    static func allowsPreloading(_ state: ProcessInfo.ThermalState) -> Bool { state == .nominal || state == .fair }

    /// The config to answer with at this temperature: shorter answers once the phone is seriously hot.
    static func adjusted(_ config: GenerationConfig, for state: ProcessInfo.ThermalState) -> GenerationConfig {
        guard state == .serious || state == .critical else { return config }
        var config = config
        config.maxTokens = min(config.maxTokens, hotMaxTokens)
        return config
    }

    static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// Makes a prompt fit an engine's context: drops the weakest excerpts (the last ones) until the instructions,
/// prompt and answer all fit, counted with that engine's own tokenizer and chat template.
enum PromptFit {
    /// Slack for what the count can miss, such as the tokens that open the answer's turn.
    static let overheadTokens = 200

    /// - Parameters:
    ///   - minimum: never drop below this many excerpts; an answer from too little is worse than a tight fit.
    ///   - messages: builds the conversation from the excerpts that are kept.
    static func fit<Source: Sendable>(_ sources: [Source], minimum: Int = 2, engine: any LLMEngine, config: GenerationConfig,
                            messages: @Sendable ([Source]) -> [LLMMessage]) async -> (sources: [Source], messages: [LLMMessage]) {
        let window = await engine.contextTokens(for: config)
        var kept = sources
        while true {
            let built = messages(kept)
            let counted = await engine.tokenCount(built)
            // Without a tokenizer, guess high: about three characters to a token.
            let tokens = counted ?? built.reduce(0) { $0 + $1.content.count } / 3
            LLMLog.note("\(engine.name): context \(window), prompt \(tokens) tokens (counted: \(counted != nil)), "
                + "answer up to \(config.maxTokens), \(kept.count) excerpts")
            if tokens + config.maxTokens + overheadTokens <= window || kept.count <= minimum { return (kept, built) }
            kept.removeLast()
        }
    }
}

/// Cuts a streamed answer at the first stop sequence. Text that could be the start of one is held back until
/// it's clear whether it is, so a stop sequence never flashes on screen.
struct StopSequenceFilter {
    private let stops: [String]
    private var raw = ""
    /// The answer so far that is safe to show.
    private(set) var text = ""
    private(set) var stopped = false

    init(_ stops: [String]) { self.stops = stops.filter { !$0.isEmpty } }

    /// Adds newly generated text. Returns true when `text` changed.
    mutating func append(_ piece: String) -> Bool {
        guard !stopped, !piece.isEmpty else { return false }
        raw += piece
        let before = text
        if let cut = stops.compactMap({ raw.range(of: $0)?.lowerBound }).min() {
            text = String(raw[..<cut])
            stopped = true
        } else {
            text = String(raw.dropLast(heldBack))
        }
        return text != before
    }

    /// Call when the model ends on its own: nothing more is coming, so held-back text is part of the answer.
    mutating func finish() -> Bool {
        guard !stopped, text != raw else { return false }
        text = raw
        return true
    }

    /// How many trailing characters could still grow into a stop sequence.
    private var heldBack: Int {
        var longest = 0
        for stop in stops {
            var n = min(stop.count - 1, raw.count)
            while n > longest {
                if raw.hasSuffix(stop.prefix(n)) { longest = n; break }
                n -= 1
            }
        }
        return longest
    }
}
