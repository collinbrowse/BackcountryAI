import Foundation
import FoundationModels

/// Apple's on-device model, behind the same interface as the downloaded one. iOS owns its memory, so loading
/// and unloading do nothing here.
actor FoundationEngine: LLMEngine {
    nonisolated let name = "Apple"
    nonisolated let model: SystemLanguageModel
    private var generation: Task<Void, Never>?

    init(model: SystemLanguageModel) { self.model = model }

    var isLoaded: Bool {
        if case .available = model.availability { return true }
        return false
    }

    /// Apple's window, whatever the config asks for. A model that isn't ready yet can report a tiny one.
    func contextTokens(for config: GenerationConfig) -> Int { max(model.contextSize, 4096) }

    func load() throws {
        guard isLoaded else { throw LLMError.loadFailed("Apple Intelligence isn't available") }
    }

    func generate(_ messages: [LLMMessage], config: GenerationConfig) -> AsyncThrowingStream<LLMEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<LLMEvent, Error>.makeStream()
        let model = model
        let (instructions, prompt) = Self.split(messages)
        let previous = generation
        previous?.cancel()
        let task = Task {
            await previous?.value
            do {
                let started = Date()
                var stats = LLMStats(), text = ""
                var filter = StopSequenceFilter(config.stopSequences)
                let session = LanguageModelSession(model: model, instructions: instructions)
                // No top-p here: Apple's default sampling is what the answers were tuned and measured with.
                let options = GenerationOptions(temperature: config.temperature,
                                                maximumResponseTokens: config.maxTokens)
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    try Task.checkCancellation()
                    if text.isEmpty { stats.secondsToFirstToken = Date().timeIntervalSince(started) }
                    // Snapshots hold the whole answer so far, so the filter starts over on each one.
                    filter = StopSequenceFilter(config.stopSequences)
                    _ = filter.append(snapshot.content)
                    if filter.text != text {
                        text = filter.text
                        continuation.yield(.text(text))
                    }
                    if filter.stopped { stats.stopReason = .stopSequence; break }
                }
                try Task.checkCancellation()
                if filter.finish() {
                    text = filter.text
                    continuation.yield(.text(text))
                }
                if #available(iOS 26.4, macOS 26.4, *) {
                    stats.promptTokens = (try? await model.tokenCount(for: prompt)) ?? 0
                    stats.answerTokens = (try? await model.tokenCount(for: text)) ?? 0
                }
                let writing = Date().timeIntervalSince(started) - stats.secondsToFirstToken
                stats.tokensPerSecond = writing > 0 ? Double(stats.answerTokens) / writing : 0
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

    /// Exact counts need iOS 26.4. Before that the callers estimate from the text's length.
    func tokenCount(_ messages: [LLMMessage]) async -> Int? {
        guard #available(iOS 26.4, macOS 26.4, *) else { return nil }
        let (instructions, prompt) = Self.split(messages)
        guard let a = try? await model.tokenCount(for: Instructions(instructions)),
              let b = try? await model.tokenCount(for: prompt) else { return nil }
        return a + b
    }

    func cancel() async {
        generation?.cancel()
        await generation?.value
    }

    func unload() async { await cancel() }

    /// Apple's sessions take instructions and one prompt, so earlier turns are written into the prompt.
    static func split(_ messages: [LLMMessage]) -> (instructions: String, prompt: String) {
        let instructions = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let turns = messages.filter { $0.role != .system }
        guard turns.count > 1, let last = turns.last else { return (instructions, turns.first?.content ?? "") }
        let earlier = turns.dropLast().map { ($0.role == .user ? "They asked: " : "You answered: ") + $0.content }
        return (instructions, earlier.joined(separator: "\n") + "\n\n" + last.content)
    }
}
