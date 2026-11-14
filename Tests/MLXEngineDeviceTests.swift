import Foundation
import Testing
import UIKit
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

/// Measures the model the app ships (Qwen 3.5 4B) on this iPhone, with prompts the size Scout really sends.
/// Skipped unless "Better answers" is already downloaded in this build of the app. The numbers go to the log
/// (lines starting "[llm] benchmark") and into docs/on-device-model-comparison.md by hand.
@Suite(.enabled(if: runningOnDevice, "MLX can't run in the simulator"), .serialized)
@MainActor
struct ShippedModelBenchmark {
    private static let questions = [
        "Someone cut their arm badly and it is bleeding a lot. What do I do?",
        "My friend is shivering and slurring words after we got soaked in a cold rain. We have a tent and stove. What now?",
        "Is the water from this standing pond safe to filter with my Katadyn BeFree filter?",
        "I have a blister forming but still have 8 miles to hike. What should I do?",
        "My truck won't start and just clicks. What do I check?",
        "I'm lost but have half a phone battery and no signal. What should I do?",
    ]

    /// Four excerpts of about 700 characters each, like Retrieval passes along.
    private static func prompt(for question: String) -> String {
        let filler = "Stay calm and assess the scene before acting. Check for hazards to yourself first. "
            + "Use what you carry: a first-aid kit, clean water, a stove, an insulating layer, a light and a "
            + "way to signal. Small problems grow in the backcountry when they are ignored, so treat them early. "
        let passages = (1...4).map {
            Passage(id: Int64($0), docID: Int64($0), title: "Field manual \($0)", source: "Test library",
                    sourceKey: "test", official: true, text: String(String(repeating: filler, count: 3).prefix(700)))
        }
        return Retrieval.prompt(question: question, sources: passages, history: [])
    }

    @Test(.timeLimit(.minutes(10))) func measure() async throws {
        let better = BetterModel.shared
        guard better.isDownloaded else {
            LLMLog.note("benchmark skipped: \(BetterModel.displayName) isn't downloaded in this build")
            return
        }
        // Keep the screen on: a locked phone sends the app to the background, which unloads the model.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        better.unload()  // so the load is timed from cold
        let loadStarted = Date()
        try #require(await better.ensureLoaded())
        let loadSeconds = Date().timeIntervalSince(loadStarted)

        var peak = MemoryProbe.footprintBytes, lowest = MemoryProbe.availableBytes
        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                peak = max(peak, MemoryProbe.footprintBytes)
                lowest = min(lowest, MemoryProbe.availableBytes)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { sampler.cancel() }

        var all: [LLMStats] = [], totals: [Double] = []
        for question in Self.questions {
            let started = Date()
            let stats = try await better.engine.answer(
                [.system(Retrieval.instructions), .user(Self.prompt(for: question))], config: .answers) { _ in }
            all.append(stats)
            totals.append(Date().timeIntervalSince(started))
            #expect(stats.answerTokens > 0)
        }
        let median = { (values: [Double]) in values.sorted()[values.count / 2] }
        LLMLog.note(String(
            format: "benchmark %@: load+warm-up %.1f s, median first token %.2f s, median %.1f tokens/s, "
                + "median prompt speed %.0f tokens/s, median answer %.1f s (worst %.1f s), "
                + "median prompt %d tokens, median answer %d tokens, peak %.2f GB, "
                + "lowest available %.2f GB, thermal at end %@",
            BetterModel.displayName, loadSeconds, median(all.map(\.secondsToFirstToken)),
            median(all.map(\.tokensPerSecond)), median(all.map(\.promptTokensPerSecond)), median(totals),
            totals.max() ?? 0, Int(median(all.map { Double($0.promptTokens) })),
            Int(median(all.map { Double($0.answerTokens) })), Double(peak) / 1e9,
            Double(lowest) / 1e9, ThermalPolicy.name(ProcessInfo.processInfo.thermalState)))
        // The ship criteria: memory stays well clear of the limit, and answers start quickly.
        #expect(lowest > 500_000_000)
        #expect(median(all.map(\.secondsToFirstToken)) < 5)
    }
}
