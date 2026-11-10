import Foundation
import FoundationModels
import Observation
import os

let log = Logger(subsystem: "com.collinbrowse.backcountryguide", category: "assistant")

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var status: String? = nil          // "Searching the library…" while working
    var sources: [Passage] = []
    var battery: BatteryReport? = nil
    var batterySession: String? = nil
    var failed = false
    var question = ""                  // for assistant messages: what they answer
    var urgent = false                 // the question sounds like an emergency

    var isFinished: Bool { role == .assistant && status == nil && !text.isEmpty }
}

@MainActor
@Observable
final class Assistant {
    var messages: [ChatMessage] = []
    var isBusy = false
    private var task: Task<Void, Never>?

    // Apple's on-device model. It never uses the network.
    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    var availabilityProblem: String? {
        switch model.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible):
            return "This iPhone can't run Apple's on-device AI. You can still search the library."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri, then reopen the app. "
                + "Do this before you lose signal: the model downloads once."
        case .unavailable(.modelNotReady):
            return "Apple's AI model is still downloading. Stay on Wi-Fi and power for a bit, then try again."
        case .unavailable:
            return "Apple's on-device AI isn't available right now."
        }
    }

    func ask(_ question: String, library: Library?) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isBusy else { return }
        let previous = messages.last(where: { $0.role == .user })?.text
        let previousAnswer = messages.last(where: { $0.role == .assistant && !$0.failed })?.text
        messages.append(ChatMessage(role: .user, text: q))
        messages.append(ChatMessage(role: .assistant, text: "", status: "Searching the library…",
                                    question: q, urgent: Urgency.isUrgent(q)))
        let index = messages.count - 1
        isBusy = true

        task = Task {
            let start = BatteryMeter.shared.begin()
            defer {
                let report = BatteryMeter.shared.end(start)
                messages[index].battery = report
                messages[index].batterySession = BatteryMeter.shared.sessionSummary
                messages[index].status = nil
                isBusy = false
            }

            // 1. Find passages. With the model: it rewrites the question into searches, then keeps only the
            //    candidates that help (see Retrieval). Without it: plain keyword search.
            var sources: [Passage] = []
            let problem = availabilityProblem
            if let library {
                if problem == nil {
                    let searches = await Retrieval.searches(for: q, previous: previous, model: model)
                    log.notice("searches: \(searches.joined(separator: " | "))")
                    let candidates = await Task.detached(priority: .userInitiated) {
                        Retrieval.candidates(question: q, searches: searches, library: library)
                    }.value
                    messages[index].status = "Reading what it found…"
                    sources = await Retrieval.pick(question: q, from: candidates, model: model)
                } else {
                    sources = await Task.detached(priority: .userInitiated) {
                        var hits = library.search(q, limit: 5)
                        if hits.count < 2, let previous {  // a short follow-up like "what about kids?"
                            hits = library.search(previous + " " + q, limit: 5)
                        }
                        return hits
                    }.value
                }
            }
            messages[index].sources = sources
            log.notice("using \(sources.count) passages")

            // 2. Ask the on-device model.
            if let problem {
                messages[index].text = problem + (sources.isEmpty ? "" : "\n\nThe best library matches are below.")
                messages[index].failed = true
                return
            }
            messages[index].status = "Writing an answer on this phone…"
            do {
                let prompt = try await fittingPrompt(question: q, sources: &sources,
                                                     previous: previous, previousAnswer: previousAnswer)
                messages[index].sources = sources
                let session = LanguageModelSession(model: model, instructions: Retrieval.instructions)
                let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 700)
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    try Task.checkCancellation()
                    messages[index].status = nil
                    messages[index].text = snapshot.content
                }
                if !messages[index].text.isEmpty { Readiness.recordAnswer() }
            } catch is CancellationError {
                if messages[index].text.isEmpty { messages[index].text = "Stopped." }
            } catch {
                messages[index].failed = true
                messages[index].text = "The AI couldn't answer this one (\(error.localizedDescription))."
                    + (sources.isEmpty ? "" : " The library matches are below. Tap one to read it.")
            }
        }
    }

    func stop() { task?.cancel() }

    /// Starts a fresh conversation with this question.
    func startNew(_ question: String, library: Library?) {
        guard !isBusy else { return }
        messages.removeAll()
        ask(question, library: library)
    }

    func clear() {
        guard !isBusy else { return }
        messages.removeAll()
    }

    /// Builds the prompt, dropping the weakest excerpts until it fits the model's context window
    /// with room left for the answer.
    private func fittingPrompt(question: String, sources: inout [Passage], previous: String?,
                               previousAnswer: String?) async throws -> String {
        let reserve = 900  // tokens for the answer plus overhead
        // Guard against a not-yet-loaded model reporting a tiny window, which would drop every source.
        let window = max(model.contextSize, 4096)
        let instructionTokens = (try? await model.tokenCount(for: Instructions(Retrieval.instructions))) ?? 250
        while true {
            let prompt = Retrieval.prompt(question: question, sources: sources, previous: previous,
                                     previousAnswer: previousAnswer)
            let counted = try? await model.tokenCount(for: prompt)
            let n = sources.count
            let tokens = counted ?? prompt.count / 3
            log.notice("context \(window) instructions \(instructionTokens) prompt \(tokens) (counted: \(counted != nil)) sources \(n)")
            if instructionTokens + tokens + reserve <= window || sources.count <= 2 { return prompt }
            sources.removeLast()
        }
    }
}
