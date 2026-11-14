import Foundation
import Testing
@testable import BackcountryAI

#if targetEnvironment(simulator)
private let runningOnDevice = false
#else
private let runningOnDevice = true
#endif

/// The real engine with a real, tiny model: Qwen3 0.6B, 4-bit (335 MB, Apache 2.0), downloaded from Hugging Face
/// on the first run. MLX needs a device's GPU, so these are skipped in the simulator and in CI. Run them with an
/// iPhone connected and on Wi-Fi:
///
///     xcodebuild test -project BackcountryAI.xcodeproj -scheme BackcountryAI \
///       -destination "platform=iOS,name=<your iPhone>" -only-testing:BackcountryAITests/MLXEngineDeviceTests
@Suite(.enabled(if: runningOnDevice, "MLX can't run in the simulator"), .serialized)
struct MLXEngineDeviceTests {
    /// One engine for the suite, so the model downloads and loads once.
    static let engine = MLXEngine(
        name: "Qwen3 0.6B (test)",
        weightsBytes: 335_450_584,
        extraEOSTokens: ["<|im_end|>"],
        templateContext: ["enable_thinking": false],
        source: { .hub("mlx-community/Qwen3-0.6B-4bit", revision: "73e3e38d981303bc594367cd910ea6eb48349da8") })

    private var engine: MLXEngine { Self.engine }
    private let question: [LLMMessage] = [.system("You are a helpful assistant. Answer briefly."),
                                          .user("Name three colors.")]

    @Test func loadsAndAnswers() async throws {
        try await engine.load()
        #expect(await engine.isLoaded)
        var snapshots: [String] = []
        let stats = try await engine.answer(question, config: GenerationConfig(maxTokens: 60)) { snapshots.append($0) }
        let answer = try #require(snapshots.last)
        #expect(!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // The chat template was applied and thinking is off: no template or reasoning markers leak into the text.
        #expect(!answer.contains("<|im_") && !answer.contains("<think>"))
        // Each snapshot is the whole answer so far.
        #expect(zip(snapshots, snapshots.dropFirst()).allSatisfy { $1.hasPrefix($0) })
        #expect(stats.promptTokens > 0 && stats.answerTokens > 0)
        #expect(stats.secondsToFirstToken > 0 && stats.tokensPerSecond > 0)
    }

    @Test func countsTokensWithTheChatTemplate() async throws {
        try await engine.load()
        let short = try #require(await engine.tokenCount([.user("Hi")]))
        let long = try #require(await engine.tokenCount(question))
        #expect(short > 1)       // the template adds turn markers around one word
        #expect(long > short)
    }

    @Test func stopsAtMaxTokens() async throws {
        try await engine.load()
        let stats = try await engine.answer([.user("Count from 1 to 200, one number per line.")],
                                            config: GenerationConfig(maxTokens: 12)) { _ in }
        #expect(stats.stopReason == .maxTokens)
        #expect(stats.answerTokens <= 12)
    }

    @Test func stopsAtAStopSequence() async throws {
        try await engine.load()
        var answer = ""
        let config = GenerationConfig(temperature: 0, maxTokens: 80, stopSequences: ["4"])
        let stats = try await engine.answer([.user("Count from 1 to 20 separated by commas, digits only.")],
                                            config: config) { answer = $0 }
        #expect(stats.stopReason == .stopSequence)
        #expect(answer.contains("3") && !answer.contains("4"))
    }

    @Test func refusesAPromptLongerThanTheContext() async throws {
        try await engine.load()
        let long = String(repeating: "water filter stove tent ", count: 400)
        await #expect(throws: LLMError.self) {
            try await engine.answer([.user(long)], config: GenerationConfig(maxTokens: 50, contextTokens: 256)) { _ in }
        }
    }

    @Test func cancellingStopsTheModelPromptly() async throws {
        try await engine.load()
        let engine = engine
        let reader = Task { @MainActor in
            try await engine.answer([.user("Write a very long story about a mountain.")],
                                    config: GenerationConfig(maxTokens: 2000)) { _ in }
        }
        try await Task.sleep(for: .seconds(1))
        let cancelled = Date()
        reader.cancel()
        await #expect(throws: CancellationError.self) { try await reader.value }
        await engine.cancel()
        #expect(Date().timeIntervalSince(cancelled) < 2)
        // And it still answers afterwards.
        let stats = try await engine.answer(question, config: GenerationConfig(maxTokens: 20)) { _ in }
        #expect(stats.answerTokens > 0)
    }

    @Test func unloadFreesTheModelAndLoadBringsItBack() async throws {
        try await engine.load()
        let loaded = MemoryProbe.footprintBytes
        await engine.unload()
        #expect(await !engine.isLoaded)
        // Most of the 335 MB of weights is gone. Give the system a moment to take the pages back.
        var freed: Int64 = 0
        for _ in 0..<20 where freed < 200_000_000 {
            try await Task.sleep(for: .milliseconds(100))
            freed = loaded - MemoryProbe.footprintBytes
        }
        #expect(freed >= 200_000_000, "freed \(freed / 1_048_576) MiB")
        await #expect(throws: LLMError.notLoaded) {
            try await engine.answer(question, config: .answers) { _ in }
        }
        try await engine.load()
        let stats = try await engine.answer(question, config: GenerationConfig(maxTokens: 20)) { _ in }
        #expect(stats.answerTokens > 0)
    }

    @Test func unloadDuringAnAnswerStopsIt() async throws {
        try await engine.load()
        let engine = engine
        let reader = Task { @MainActor in
            try await engine.answer([.user("Write a very long story about a river.")],
                                    config: GenerationConfig(maxTokens: 2000)) { _ in }
        }
        try await Task.sleep(for: .seconds(1))
        await engine.unload()
        await #expect(throws: CancellationError.self) { try await reader.value }
        #expect(await !engine.isLoaded)
    }
}
