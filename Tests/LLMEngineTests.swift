import Foundation
import Testing
@testable import BackcountryAI

struct StopSequenceFilterTests {
    private func run(_ pieces: [String], stops: [String]) -> (shown: [String], final: String, stopped: Bool) {
        var filter = StopSequenceFilter(stops)
        var shown: [String] = []
        for piece in pieces where filter.append(piece) { shown.append(filter.text) }
        if filter.finish() { shown.append(filter.text) }
        return (shown, filter.text, filter.stopped)
    }

    @Test func passesTextThroughWithoutStops() {
        let r = run(["Boil ", "the water."], stops: [])
        #expect(r.shown == ["Boil ", "Boil the water."])
        #expect(!r.stopped)
    }

    @Test func cutsAtAStopInsideOnePiece() {
        let r = run(["Boil it.<|im_end|>junk"], stops: ["<|im_end|>"])
        #expect(r.final == "Boil it.")
        #expect(r.stopped)
    }

    @Test func neverShowsAStopSplitAcrossPieces() {
        let r = run(["Boil it.", "<|im", "_end|>", " more"], stops: ["<|im_end|>"])
        #expect(r.final == "Boil it.")
        #expect(r.shown.allSatisfy { !$0.contains("<") })
        #expect(r.stopped)
    }

    @Test func releasesHeldTextThatWasNotAStop() {
        let r = run(["a <", "b> c"], stops: ["<|im_end|>"])
        #expect(r.shown == ["a ", "a <b> c"])
        #expect(!r.stopped)
    }

    @Test func keepsHeldTextWhenTheModelEnds() {
        let r = run(["Use 2 <"], stops: ["<|im_end|>"])
        #expect(r.final == "Use 2 <")
    }

    @Test func usesTheEarliestOfSeveralStops() {
        let r = run(["one\n\nQuestion: two STOP three"], stops: ["STOP", "\n\nQuestion:"])
        #expect(r.final == "one")
    }

    @Test func ignoresTextAfterStopping() {
        var filter = StopSequenceFilter(["END"])
        _ = filter.append("doneEND")
        let changed = filter.append("more")
        #expect(!changed)
        #expect(filter.text == "done")
    }
}

struct GenerationConfigTests {
    @Test func promptLimitLeavesRoomForTheAnswer() {
        #expect(GenerationConfig(maxTokens: 700, contextTokens: 4096).promptTokenLimit == 3396)
        #expect(GenerationConfig(maxTokens: 900, contextTokens: 512).promptTokenLimit == 0)
    }
}

/// A scripted engine: the tests for everything above the engine use it, since MLX can't run in the simulator.
actor MockEngine: LLMEngine {
    let name = "mock"
    var pieces: [String]
    var delay: Duration
    private(set) var isLoaded = false
    private(set) var loads = 0
    private(set) var cancels = 0
    private(set) var finishedNormally = 0
    var loadError: LLMError?
    private var task: Task<Void, Never>?

    init(pieces: [String], delay: Duration = .zero) {
        self.pieces = pieces
        self.delay = delay
    }

    func failLoads(with error: LLMError?) { loadError = error }
    func contextTokens(for config: GenerationConfig) -> Int { config.contextTokens }
    func tokenCount(_ messages: [LLMMessage]) -> Int? { messages.reduce(0) { $0 + $1.content.split(separator: " ").count } }

    func load() throws {
        if let loadError { throw loadError }
        loads += 1
        isLoaded = true
    }

    func generate(_ messages: [LLMMessage], config: GenerationConfig) -> AsyncThrowingStream<LLMEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<LLMEvent, Error>.makeStream()
        guard isLoaded else {
            continuation.finish(throwing: LLMError.notLoaded)
            return stream
        }
        let pieces = pieces, delay = delay
        let task = Task {
            var filter = StopSequenceFilter(config.stopSequences)
            var stats = LLMStats()
            for piece in pieces.prefix(config.maxTokens) {
                if delay > .zero { try? await Task.sleep(for: delay) }
                if Task.isCancelled { continuation.finish(throwing: CancellationError()); return }
                stats.answerTokens += 1
                if filter.append(piece) { continuation.yield(.text(filter.text)) }
                if filter.stopped { stats.stopReason = .stopSequence; break }
            }
            if filter.finish() { continuation.yield(.text(filter.text)) }
            if !filter.stopped, pieces.count > config.maxTokens { stats.stopReason = .maxTokens }
            continuation.yield(.finished(stats))
            continuation.finish()
            self.noteFinished()
        }
        self.task = task
        continuation.onTermination = { if case .cancelled = $0 { task.cancel() } }
        return stream
    }

    private func noteFinished() { finishedNormally += 1 }

    func cancel() async {
        guard let task else { return }
        cancels += 1
        task.cancel()
        await task.value
        self.task = nil
    }

    func unload() async {
        await cancel()
        isLoaded = false
    }
}

@MainActor
struct LLMEngineContractTests {
    @Test func answerStreamsTheWholeTextSoFar() async throws {
        let engine = MockEngine(pieces: ["Filter ", "then ", "boil."])
        try await engine.load()
        var seen: [String] = []
        let stats = try await engine.answer([.user("water?")], config: .answers) { seen.append($0) }
        #expect(seen == ["Filter ", "Filter then ", "Filter then boil."])
        #expect(stats.answerTokens == 3)
        #expect(stats.stopReason == .endOfTurn)
    }

    @Test func answerThrowsWhenNotLoaded() async {
        let engine = MockEngine(pieces: ["x"])
        await #expect(throws: LLMError.notLoaded) {
            try await engine.answer([.user("q")], config: .answers) { _ in }
        }
    }

    @Test func maxTokensAndStopSequencesEndTheAnswer() async throws {
        let engine = MockEngine(pieces: ["a", "b", "c", "d"])
        try await engine.load()
        var text = ""
        var config = GenerationConfig(maxTokens: 2)
        var stats = try await engine.answer([.user("q")], config: config) { text = $0 }
        #expect(text == "ab")
        #expect(stats.stopReason == .maxTokens)
        config = GenerationConfig(stopSequences: ["c"])
        stats = try await engine.answer([.user("q")], config: config) { text = $0 }
        #expect(text == "ab")
        #expect(stats.stopReason == .stopSequence)
    }

    @Test func cancellingTheReaderStopsTheEngine() async throws {
        let engine = MockEngine(pieces: Array(repeating: "word ", count: 500), delay: .milliseconds(5))
        try await engine.load()
        var text = ""
        let reader = Task { @MainActor in
            try await engine.answer([.user("q")], config: GenerationConfig(maxTokens: 500)) { text = $0 }
        }
        try await Task.sleep(for: .milliseconds(60))
        reader.cancel()
        await #expect(throws: CancellationError.self) { try await reader.value }
        await engine.cancel()
        #expect(!text.isEmpty)
        #expect(await engine.finishedNormally == 0)
    }

    @Test func unloadStopsAnAnswerInProgress() async throws {
        let engine = MockEngine(pieces: Array(repeating: "word ", count: 500), delay: .milliseconds(5))
        try await engine.load()
        let reader = Task { @MainActor in
            try await engine.answer([.user("q")], config: GenerationConfig(maxTokens: 500)) { _ in }
        }
        try await Task.sleep(for: .milliseconds(60))
        await engine.unload()
        await #expect(throws: CancellationError.self) { try await reader.value }
        #expect(await !engine.isLoaded)
    }
}

struct MemoryBudgetTests {
    private let qwen4B = MemoryBudget(weightsBytes: 2_394_053_774)

    @Test func needsWeightsPlusWorkingRoomAndAReserve() {
        #expect(qwen4B.neededBytes == 2_394_053_774 + 900_000_000 + 300_000_000)
    }

    @Test func loadsWithTheMemoryAnIPhone17HasAtLaunch() throws {
        try qwen4B.check(availableBytes: 6139 * 1_048_576)  // measured: 6144 MiB limit, 6139 MiB free
    }

    @Test func refusesWhenTooLittleIsFree() {
        #expect(throws: LLMError.notEnoughMemory(neededBytes: qwen4B.neededBytes, availableBytes: 3_000_000_000)) {
            try qwen4B.check(availableBytes: 3_000_000_000)
        }
    }

    @Test func refusesInTheSimulatorWhereNothingIsReported() {
        #expect(throws: LLMError.self) { try qwen4B.check(availableBytes: 0) }
    }
}

struct PromptFitTests {
    /// MockEngine counts one token per word.
    private func fit(_ excerpts: [String], context: Int, maxTokens: Int = 10) async -> [String] {
        let engine = MockEngine(pieces: [])
        let config = GenerationConfig(maxTokens: maxTokens, contextTokens: context)
        return await PromptFit.fit(excerpts, engine: engine, config: config) { kept in
            [.system("be brief"), .user(kept.joined(separator: " "))]
        }.sources
    }

    private let excerpts = (1...5).map { _ in Array(repeating: "word", count: 100).joined(separator: " ") }

    @Test func keepsEverythingThatFits() async {
        #expect(await fit(excerpts, context: 502 + 10 + PromptFit.overheadTokens).count == 5)
    }

    @Test func dropsTheLastExcerptsUntilItFits() async {
        // Room for the instructions, three excerpts, the answer and the overhead, but not four.
        #expect(await fit(excerpts, context: 302 + 10 + PromptFit.overheadTokens).count == 3)
    }

    @Test func leavesRoomForTheAnswer() async {
        #expect(await fit(excerpts, context: 502 + 10 + PromptFit.overheadTokens, maxTokens: 110).count == 4)
    }

    @Test func neverDropsBelowTwoExcerpts() async {
        #expect(await fit(excerpts, context: 50).count == 2)
    }
}

struct ThermalPolicyTests {
    @Test func coolPhonesAnswerAsConfigured() {
        for state in [ProcessInfo.ThermalState.nominal, .fair] {
            #expect(ThermalPolicy.adjusted(.answers, for: state) == .answers)
            #expect(ThermalPolicy.allowsLargeModel(state))
            #expect(ThermalPolicy.allowsPreloading(state))
        }
    }

    @Test func seriousHeatShortensAnswersButKeepsTheModel() {
        let config = ThermalPolicy.adjusted(.answers, for: .serious)
        #expect(config.maxTokens == ThermalPolicy.hotMaxTokens)
        #expect(config.contextTokens == GenerationConfig.answers.contextTokens)
        #expect(ThermalPolicy.allowsLargeModel(.serious))
        #expect(!ThermalPolicy.allowsPreloading(.serious))
    }

    @Test func criticalHeatPausesTheLargeModel() {
        #expect(!ThermalPolicy.allowsLargeModel(.critical))
        #expect(!ThermalPolicy.allowsPreloading(.critical))
    }

    @Test func neverLengthensAnAlreadyShortAnswer() {
        #expect(ThermalPolicy.adjusted(GenerationConfig(maxTokens: 100), for: .critical).maxTokens == 100)
    }
}
