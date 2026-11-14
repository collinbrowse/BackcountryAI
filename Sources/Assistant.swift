import Foundation
import FoundationModels
import Observation
import os

let log = Logger(subsystem: "com.collinbrowse.backcountryai", category: "assistant")

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    let role: Role
    var text: String
    var status: String? = nil          // "Searching the library…" while working
    var sources: [Passage] = []
    var battery: BatteryReport? = nil
    var batterySession: String? = nil
    var failed = false
    var question = ""                  // for assistant messages: what they answer
    var urgent = false                 // the question sounds like an emergency
    var engine: String? = nil          // set when the larger model wrote it: its speed and memory (not saved)
    var casual: Bool? = nil            // a chat reply to small talk ("hi", "thanks"): no steps, no sources
    var isCasual: Bool { casual == true }

    var isFinished: Bool { role == .assistant && status == nil && !text.isEmpty }

    // `status` is only meaningful while an answer is being written, so it isn't saved.
    enum CodingKeys: String, CodingKey {
        case id, role, text, sources, battery, batterySession, failed, question, urgent, casual
    }
}

@MainActor
@Observable
final class Assistant {
    var messages: [ChatMessage] = []
    var isBusy = false
    /// The saved chat these messages belong to. Assigned when the first question is asked.
    private(set) var conversationID: UUID?
    /// The chat's short name, once its first real question is answered (see ChatTopic).
    private(set) var topic: String?
    private var task: Task<Void, Never>?
    private let chats: ChatStore?

    init(chats: ChatStore? = nil) {
        self.chats = chats
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        self.model = model
        apple = FoundationEngine(model: model)
    }

    // Apple's on-device model. It never uses the network.
    private let model: SystemLanguageModel
    /// The same model as an engine, for writing answers.
    private let apple: FoundationEngine

    var availabilityProblem: String? {
        if ScreenshotMode.isOn { return nil }
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
        let obviousSmallTalk = SmallTalk.isObvious(q)
        messages.append(ChatMessage(role: .assistant, text: "", status: obviousSmallTalk ? "…" : "Searching the library…",
                                    question: q, urgent: !obviousSmallTalk && Urgency.isUrgent(q)))
        let index = messages.count - 1
        isBusy = true
        if conversationID == nil { conversationID = UUID() }

        task = Task {
            let start = BatteryMeter.shared.begin()
            defer {
                let report = BatteryMeter.shared.end(start)
                messages[index].battery = report
                messages[index].batterySession = BatteryMeter.shared.sessionSummary
                messages[index].status = nil
                isBusy = false
                save()
                if topic == nil, !messages[index].isCasual, !messages[index].failed {
                    Task { await self.nameChat(q) }
                }
            }

            if let script = ScreenshotMode.script(for: q) {
                messages[index].sources = library?.search(q, limit: 3) ?? []
                await ScreenshotMode.play(script, status: { messages[index].status = $0 },
                                          text: { messages[index].text = $0 })
                return
            }

            // 1. Find passages. With the model: it rewrites the question into searches, then keeps only the
            //    candidates that help (see Retrieval). Without it: plain keyword search.
            var sources: [Passage] = []
            let problem = availabilityProblem
            if obviousSmallTalk {
                return await chat(q, at: index, previous: previous, previousAnswer: previousAnswer)
            }
            if let library {
                if problem == nil {
                    guard let searches = await Retrieval.searches(for: q, previous: previous, model: model) else {
                        messages[index].urgent = false
                        return await chat(q, at: index, previous: previous, previousAnswer: previousAnswer)
                    }
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
            let better = BetterModel.shared
            messages[index].status = better.isActive && !better.isReady
                ? "Getting better answers ready…" : "Writing an answer on this phone…"
            do {
                // Better answers: the larger model writes the answer when it's on. If it can't load, Apple's does.
                let useBetter = better.isActive ? await better.ensureLoaded() : false
                let engine: any LLMEngine = useBetter ? better.engine : apple
                messages[index].status = "Writing an answer on this phone…"
                // Drop the weakest excerpts until the prompt fits this model, by its own token count.
                let fitted = await PromptFit.fit(sources, engine: engine, config: .answers) { kept in
                    [.system(Retrieval.instructions),
                     .user(Retrieval.prompt(question: q, sources: kept, previous: previous, previousAnswer: previousAnswer))]
                }
                sources = fitted.sources
                messages[index].sources = sources
                let request = fitted.messages
                let show: @MainActor (String) -> Void = { text in
                    self.messages[index].status = nil
                    self.messages[index].text = text
                }
                do {
                    let stats = try await engine.answer(request, config: .answers, onText: show)
                    if useBetter {
                        messages[index].engine = String(format: "Written with better answers: first words in %.1f s, %.0f tokens/s, %.1f GB memory",
                                                        stats.secondsToFirstToken, stats.tokensPerSecond,
                                                        MemoryProbe.footprintGB)
                    }
                } catch where useBetter && !Task.isCancelled {
                    // The larger model was unloaded mid-answer (low memory, or the app left the screen) or
                    // couldn't take the prompt. The person didn't press Stop, so Apple's model writes it instead.
                    LLMLog.note("better answers gave up (\(error.localizedDescription)); Apple's model answers")
                    messages[index].text = ""
                    messages[index].status = "Writing an answer on this phone…"
                    try await apple.answer(request, config: .answers, onText: show)
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

    /// A short chat reply to small talk, from Apple's model (or a fixed line without it). No library, no steps.
    private func chat(_ message: String, at index: Int, previous: String?, previousAnswer: String?) async {
        messages[index].casual = true
        messages[index].status = "…"
        guard availabilityProblem == nil else {
            messages[index].text = SmallTalk.offlineReply
            return
        }
        let session = LanguageModelSession(model: model, instructions: SmallTalk.instructions)
        let prompt = SmallTalk.prompt(message, previous: previous, previousAnswer: previousAnswer)
        do {
            for try await snapshot in session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.7,
                                                                                                    maximumResponseTokens: 200)) {
                try Task.checkCancellation()
                messages[index].status = nil
                messages[index].text = snapshot.content
            }
        } catch {
            if messages[index].text.isEmpty { messages[index].text = SmallTalk.offlineReply }
        }
    }

    func stop() { task?.cancel() }

    /// Starts a fresh conversation with this question.
    func startNew(_ question: String, library: Library?) {
        guard !isBusy else { return }
        clear()
        ask(question, library: library)
    }

    func clear() {
        guard !isBusy else { return }
        messages.removeAll()
        conversationID = nil
        topic = nil
    }

    /// Reopens a saved chat so you can read it or keep asking.
    func open(_ chat: Conversation) {
        guard !isBusy else { return }
        messages = chat.messages
        conversationID = chat.id
        topic = chat.topic
    }

    /// Names the chat after its first real question. Fast: a few words from Apple's model.
    private func nameChat(_ question: String) async {
        guard let id = conversationID else { return }
        let name = availabilityProblem == nil ? await ChatTopic.make(for: question, model: model)
                                              : ChatTopic.fallback(question)
        guard conversationID == id, topic == nil else { return }
        topic = name
        save()
    }

    /// Call after chats are deleted: if the one on screen was among them, start fresh.
    func forget(_ ids: Set<UUID>) {
        guard let id = conversationID, ids.contains(id) else { return }
        clear()
    }

    /// Chats save automatically after every answer.
    private func save() {
        guard let conversationID else { return }
        chats?.save(id: conversationID, messages: messages, topic: topic)
    }
}
