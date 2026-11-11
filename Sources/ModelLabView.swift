import FoundationModels
import SwiftUI
import UIKit

/// PROTOTYPE: download the bigger model, turn it on for answers, and benchmark it against Apple's model on this
/// iPhone (speed, memory, battery, heat). Results can be shared as CSV for docs/on-device-model-comparison.md.
struct ModelLabView: View {
    @Environment(LibraryStore.self) private var store
    @State private var better = BetterModel.shared
    @State private var bench = LabBenchmark()
    @State private var memoryNow = MemoryProbe.footprintGB
    @State private var availableNow = MemoryProbe.availableGB
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Prototype. Tests whether a bigger on-device model (Qwen 3.5 4B) gives better answers, and what it costs this iPhone in speed, memory and battery. Apple's model still does the searching.")
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
                device
                model
                benchmark
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Lab: better answers")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { _ in
            memoryNow = MemoryProbe.footprintGB
            availableNow = MemoryProbe.availableGB
        }
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This iPhone").font(.headline)
            row("Memory (RAM)", String(format: "%.1f GB", MemoryProbe.deviceGB))
            row("App is using", String(format: "%.2f GB", memoryNow))
            row("iOS allows this app more", String(format: "%.2f GB", availableNow))
            if !BetterModel.isSupported {
                Text("This device can't run the bigger model (the simulator has no GPU for it, or the iPhone has under 8 GB).")
                    .font(.footnote).foregroundStyle(Theme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qwen 3.5 4B (4-bit)").font(.headline)
            switch better.state {
            case .notDownloaded:
                Text("Not downloaded. The download is \(BetterModel.approximateDownload) from Hugging Face; use Wi-Fi.")
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
                Button("Download and load") { better.prepare() }.buttonStyle(PrimaryButtonStyle())
                    .disabled(!BetterModel.isSupported)
            case .onDisk:
                Text("Downloaded, not in memory.").font(.footnote).foregroundStyle(Theme.inkSoft)
                Button("Load into memory") { better.prepare() }.buttonStyle(PrimaryButtonStyle())
            case .downloading(let f):
                ProgressView(value: f) { Text("Downloading… \(Int(f * 100))%").font(.footnote) }
            case .loading:
                ProgressView { Text("Loading into memory…").font(.footnote) }
            case .ready:
                Label("Loaded and ready", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.moss)
                Button("Unload from memory") { better.unload() }.font(.subheadline.weight(.semibold))
            case .failed(let m):
                Text("Failed: \(m)").font(.footnote).foregroundStyle(Theme.danger)
                Button("Try again") { better.prepare() }.buttonStyle(SecondaryButtonStyle())
            }
            Toggle("Use it for Scout's answers", isOn: $better.useForAnswers)
                .disabled(!better.isDownloaded && !better.isReady)
            if better.isDownloaded {
                Button("Delete the model", role: .destructive) { better.delete() }.font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var benchmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Benchmark").font(.headline)
            Text("Runs \(LabBenchmark.questions.count) test questions through the library search once, then has each model write the answers. Unplug the phone first so battery use can be measured. Takes 5–15 minutes.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
            if bench.isRunning {
                ProgressView(value: bench.progress) { Text(bench.status).font(.footnote) }
                Button("Stop", role: .cancel) { bench.stop() }
            } else {
                Button("Run benchmark") { bench.run(library: store.library) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(store.library == nil)
                if store.library == nil {
                    Text("Download the library first.").font(.footnote).foregroundStyle(Theme.danger)
                }
            }
            ForEach(bench.summaries, id: \.self) { Text($0).font(.footnote.monospacedDigit()) }
            if !bench.results.isEmpty {
                ShareLink(item: bench.csv, preview: SharePreview("Benchmark results")) {
                    Label("Share results (CSV)", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: bench.answersText, preview: SharePreview("Benchmark answers")) {
                    Label("Share answers (text)", systemImage: "doc.text")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// Runs the same questions through Apple's model and Qwen on this phone and records what each answer cost.
@MainActor
@Observable
final class LabBenchmark {
    static let questions = [
        "Is the water from this standing pond safe to filter with my Kathryn be free filter?",
        "I only have a Sawyer Squeeze. Is that enough for river water downstream from a cattle ranch?",
        "Someone cut their arm badly and it is bleeding a lot. What do I do?",
        "I have a blister forming but still have 8 miles to hike. What should I do?",
        "My friend is shivering and slurring words after we got soaked in a cold rain. We have a tent and stove. What now?",
        "How do I add oil on my snowmobile?",
        "My truck won't start and just clicks. What do I check?",
        "My jet boil won't light. How do I fix it?",
        "A black bear is walking toward our campsite and we have bear spray. What do we do?",
        "A thunderstorm is coming and we are above treeline. What do we do?",
        "What should I do if a flash flood comes while I'm in a canyon?",
        "How do I set a snare to catch small game?",
        "I'm lost but have half a phone battery and no signal. What should I do?",
        "How do I tell if a wild mushroom is poisonous?",
        "Is it safe to take ibuprofen that expired two years ago?",
        "What is the difference between GMRS and FRS radios?",
    ]

    struct Result: Sendable {
        var engine: String
        var question: String
        var answer: String
        var firstWord: Double
        var total: Double
        var promptTokens: Int
        var answerTokens: Int
        var tokensPerSecond: Double
        var peakFootprintGB: Double
        var minAvailableGB: Double
        var thermal: String
    }

    var results: [Result] = []
    var isRunning = false
    var progress = 0.0
    var status = ""
    var summaries: [String] = []
    private var task: Task<Void, Never>?

    func stop() { task?.cancel() }

    func run(library: Library?) {
        guard let library, !isRunning else { return }
        results = []
        summaries = []
        isRunning = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = true  // keep the screen on so iOS doesn't suspend the run
        task = Task {
            defer {
                isRunning = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            let apple = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
            // 1. Retrieval once per question, with Apple's model, so both models get the same prompts.
            var prompts: [(String, String)] = []
            for (i, q) in Self.questions.enumerated() {
                if Task.isCancelled { return }
                status = "Searching the library \(i + 1)/\(Self.questions.count)"
                progress = Double(i) / Double(Self.questions.count * 3)
                let searches = await Retrieval.searches(for: q, previous: nil, model: apple)
                let candidates = await Task.detached { Retrieval.candidates(question: q, searches: searches, library: library) }.value
                let picked = await Retrieval.pick(question: q, from: candidates, model: apple)
                prompts.append((q, Retrieval.prompt(question: q, sources: picked, previous: nil, previousAnswer: nil)))
            }
            // 2. Apple's model, then Qwen, each over all questions, with battery read before and after each pass.
            var engines = ["Apple"]
            if BetterModel.isSupported, BetterModel.shared.isDownloaded || BetterModel.shared.isReady { engines.append("Qwen 3.5 4B") }
            for (pass, engine) in engines.enumerated() {
                if engine != "Apple" {
                    status = "Loading Qwen…"
                    guard await BetterModel.shared.ensureLoaded() else { summaries.append("Qwen didn't load"); continue }
                }
                let battery0 = UIDevice.current.batteryLevel
                let started = Date()
                for (i, (q, prompt)) in prompts.enumerated() {
                    if Task.isCancelled { return }
                    status = "\(engine): question \(i + 1)/\(prompts.count)"
                    progress = Double(Self.questions.count * (pass + 1) + i) / Double(Self.questions.count * 3)
                    if let r = await answer(engine: engine, question: q, prompt: prompt, apple: apple) { results.append(r) }
                }
                let battery1 = UIDevice.current.batteryLevel
                summaries.append(summary(engine: engine, seconds: Date().timeIntervalSince(started),
                                         battery: (battery0, battery1)))
            }
            progress = 1
            status = "Done"
        }
    }

    private func answer(engine: String, question: String, prompt: String, apple: SystemLanguageModel) async -> Result? {
        var peak = MemoryProbe.footprintGB, minAvailable = MemoryProbe.availableGB
        let sampler = Task {
            while !Task.isCancelled {
                peak = max(peak, MemoryProbe.footprintGB)
                minAvailable = min(minAvailable, MemoryProbe.availableGB)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { sampler.cancel() }
        let t0 = Date()
        var first: Double?
        var text = ""
        var r = Result(engine: engine, question: question, answer: "", firstWord: 0, total: 0, promptTokens: 0,
                       answerTokens: 0, tokensPerSecond: 0, peakFootprintGB: 0, minAvailableGB: 0, thermal: "")
        do {
            if engine == "Apple" {
                let session = LanguageModelSession(model: apple, instructions: Retrieval.instructions)
                for try await snap in session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 700)) {
                    if first == nil { first = Date().timeIntervalSince(t0) }
                    text = snap.content
                }
                r.promptTokens = (try? await apple.tokenCount(for: prompt)) ?? 0
                r.answerTokens = (try? await apple.tokenCount(for: text)) ?? 0
            } else {
                let stats = try await BetterModel.shared.answer(instructions: Retrieval.instructions, prompt: prompt) { text = $0 }
                first = stats.secondsToFirstWord
                r.promptTokens = stats.promptTokens
                r.answerTokens = stats.answerTokens
            }
        } catch {
            text = "(failed: \(error.localizedDescription))"
        }
        r.total = Date().timeIntervalSince(t0)
        r.firstWord = first ?? r.total
        r.answer = text
        let writing = r.total - r.firstWord
        r.tokensPerSecond = writing > 0 ? Double(r.answerTokens) / writing : 0
        r.peakFootprintGB = max(peak, MemoryProbe.footprintGB)
        r.minAvailableGB = min(minAvailable, MemoryProbe.availableGB)
        r.thermal = ["nominal", "fair", "serious", "critical"][ProcessInfo.processInfo.thermalState.rawValue]
        return r
    }

    private func summary(engine: String, seconds: Double, battery: (Float, Float)) -> String {
        let rs = results.filter { $0.engine == engine }
        func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }
        var line = String(format: "%@: first word %.1fs, answer %.1fs, %.0f tok/s, peak memory %.2f GB, min free %.2f GB",
                          engine, median(rs.map(\.firstWord)), median(rs.map(\.total)), median(rs.map(\.tokensPerSecond)),
                          rs.map(\.peakFootprintGB).max() ?? 0, rs.map(\.minAvailableGB).min() ?? 0)
        if battery.0 >= 0, battery.1 >= 0, UIDevice.current.batteryState == .unplugged {
            line += String(format: ", battery %.0f%% → %.0f%% over %d answers (%.0fs)", battery.0 * 100, battery.1 * 100,
                           rs.count, seconds)
        }
        line += ", ends \(rs.last?.thermal ?? "?")"
        return line
    }

    var csv: String {
        var s = "engine,question,first_word_s,total_s,prompt_tokens,answer_tokens,tokens_per_s,peak_footprint_gb,min_available_gb,thermal\n"
        for r in results {
            s += "\(r.engine),\"\(r.question)\",\(String(format: "%.2f", r.firstWord)),\(String(format: "%.2f", r.total)),"
                + "\(r.promptTokens),\(r.answerTokens),\(String(format: "%.1f", r.tokensPerSecond)),"
                + "\(String(format: "%.2f", r.peakFootprintGB)),\(String(format: "%.2f", r.minAvailableGB)),\(r.thermal)\n"
        }
        s += "\n# device RAM \(String(format: "%.1f", MemoryProbe.deviceGB)) GB; " + summaries.joined(separator: " | ")
        return s
    }

    var answersText: String {
        results.map { "## \($0.engine): \($0.question)\n\n\($0.answer)\n" }.joined(separator: "\n")
    }
}
