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

    static let instructions = """
    You are a backcountry and survival field guide running offline on a phone. The person may be far from help, \
    cold, injured or with a broken vehicle or piece of gear. Answer from the numbered library excerpts you are given \
    and cite them inline like [1] or [2]. Lead with what to do right now, as short numbered steps. Be concrete and \
    brief. Only if the excerpts don't cover the question, say so plainly, then give careful general guidance under \
    the heading "Not from the library:". Never end with that heading alone. For a life-threatening emergency, start with the most urgent actions and say to call or \
    text 911 or use an SOS/satellite messenger if there is any way to.
    """

    func ask(_ question: String, library: Library?) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isBusy else { return }
        let previous = messages.last(where: { $0.role == .user })?.text
        let previousAnswer = messages.last(where: { $0.role == .assistant && !$0.failed })?.text
        messages.append(ChatMessage(role: .user, text: q))
        messages.append(ChatMessage(role: .assistant, text: "", status: "Searching the library…"))
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

            // 1. Search the library (off the main thread).
            var sources: [Passage] = []
            if let library {
                sources = await Task.detached(priority: .userInitiated) {
                    var hits = library.search(q, limit: 5)
                    if hits.count < 2, let previous {  // a short follow-up like "what about kids?"
                        hits = library.search(previous + " " + q, limit: 5)
                    }
                    return hits
                }.value
            }
            messages[index].sources = sources
            log.notice("search found \(sources.count) passages")

            // 2. Ask the on-device model.
            if let problem = availabilityProblem {
                messages[index].text = problem + (sources.isEmpty ? "" : "\n\nThe best library matches are below.")
                messages[index].failed = true
                return
            }
            messages[index].status = "Thinking (on this phone, no internet)…"
            do {
                let prompt = try await fittingPrompt(question: q, sources: &sources,
                                                     previous: previous, previousAnswer: previousAnswer)
                messages[index].sources = sources
                let session = LanguageModelSession(model: model, instructions: Self.instructions)
                let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 700)
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    try Task.checkCancellation()
                    messages[index].status = nil
                    messages[index].text = snapshot.content
                }
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
        let instructionTokens = (try? await model.tokenCount(for: Instructions(Self.instructions))) ?? 250
        while true {
            let prompt = Self.prompt(question: question, sources: sources, previous: previous,
                                     previousAnswer: previousAnswer)
            let counted = try? await model.tokenCount(for: prompt)
            let n = sources.count
            let tokens = counted ?? prompt.count / 3
            log.notice("context \(window) instructions \(instructionTokens) prompt \(tokens) (counted: \(counted != nil)) sources \(n)")
            if instructionTokens + tokens + reserve <= window || sources.count <= 2 { return prompt }
            sources.removeLast()
        }
    }

    static func prompt(question: String, sources: [Passage], previous: String?, previousAnswer: String?) -> String {
        var p = ""
        if let previous, let previousAnswer, !previousAnswer.isEmpty {
            p += "Earlier in this conversation they asked: \(previous)\n"
            p += "You answered (shortened): \(previousAnswer.prefix(500))\n\n"
        }
        if sources.isEmpty {
            p += "No library excerpts matched this question.\n\n"
        } else {
            p += "Library excerpts:\n"
            for (i, s) in sources.enumerated() {
                p += "[\(i + 1)] \(s.title) (\(s.source))\n\(s.text)\n\n"
            }
        }
        p += "Question: \(question)"
        return p
    }
}
