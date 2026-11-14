import FoundationModels
import SwiftUI
import UIKit

/// The "Better answers" option on the library screen: what it gives you, what it costs, and one clear choice.
/// The technical side is one tap away, on BetterAnswersDetailsView.
struct BetterAnswersCard: View {
    @State private var better = BetterModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Better answers", systemImage: "sparkles")
                    .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Theme.ink)
                    .labelStyle(.titleAndIcon)
                Spacer()
                if better.isDownloaded {
                    // On: the larger model writes answers. Off: Apple's built-in model does; the download stays.
                    Toggle("Better answers", isOn: $better.useForAnswers)
                        .labelsHidden()
                        .tint(Theme.moss)
                        .disabled(!BetterModel.isSupported)
                } else {
                    Text("Optional").font(.caption2.weight(.bold)).foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.14), in: .capsule)
                }
            }
            Text("Scout can write answers with a larger AI model that lives on this iPhone. It follows your situation more closely and gives more accurate, specific steps. It still works with no signal.")
                .font(.subheadline).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                if !better.isDownloaded { chip("arrow.down.circle", "\(gb(better.downloadBytes)) download") }
                chip("timer", "~10 s answers")
                chip("battery.50percent", "More battery")
            }
            action
            NavigationLink { BetterAnswersDetailsView() } label: {
                HStack {
                    Text("How it works")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentDeep)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .card()
        .overlay {
            if better.isActive {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.moss.opacity(0.6), lineWidth: 1.5)
            }
        }
        .animation(.bouncy, value: better.state)
        .task { await better.refreshSize() }
        // Load it now so the next answer doesn't wait, or give the memory back right away.
        .onChange(of: better.useForAnswers) { _, on in if on { better.warmUp() } else { better.unload() } }
    }

    @ViewBuilder private var action: some View {
        switch better.state {
        case .downloading(let f):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: f) {
                    Text(f > 0 ? "Downloading… \(Int(f * 100))%" : "Starting the download…").font(.footnote.weight(.semibold))
                }
                .tint(Theme.accent)
                Button("Cancel", role: .cancel) { better.cancelDownload() }.font(.subheadline.weight(.semibold))
            }
        case .failed(let message) where !better.isDownloaded:
            Text(message).font(.footnote).foregroundStyle(Theme.danger)
            Button { better.download() } label: { Label("Try again", systemImage: "arrow.clockwise") }
                .buttonStyle(SecondaryButtonStyle())
        default:
            if !better.isDownloaded {
                Button { better.download() } label: { Label("Download better answers", systemImage: "arrow.down") }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!BetterModel.isSupported)
                Text(BetterModel.isSupported
                     ? "Use Wi-Fi. Needs about \(gb(better.downloadBytes + BetterModel.unpackedBytes)) free while it installs."
                     : "Needs a real iPhone; the simulator can't run it.")
                    .font(.caption).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity)
            }
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Theme.cardRaised, in: .capsule)
    }

    private func gb(_ bytes: Int64) -> String { String(format: "%.1f GB", Double(bytes) / 1e9) }
}

/// The technical details most people skip: how the two models split the work, what was measured, the model and
/// its license, this iPhone's memory, and a benchmark to compare both models here.
struct BetterAnswersDetailsView: View {
    @Environment(LibraryStore.self) private var store
    @State private var better = BetterModel.shared
    @State private var bench = LabBenchmark()
    @State private var memoryNow = MemoryProbe.footprintGB
    @State private var availableNow = MemoryProbe.availableGB
    @State private var confirmDelete = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                howItWorks
                measured
                modelInfo
                device
                benchmark
                if better.isDownloaded {
                    Button("Remove \(BetterModel.displayName) from this iPhone", role: .destructive) { confirmDelete = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("How better answers work")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { _ in
            memoryNow = MemoryProbe.footprintGB
            availableNow = MemoryProbe.availableGB
        }
        .confirmationDialog("Remove \(BetterModel.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { better.delete() }
        } message: {
            Text("Scout goes back to Apple's built-in model. You'll need Wi-Fi to download it again.")
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Two models, one answer").font(.headline)
            step(1, "Apple's built-in model turns your question into library searches and keeps only the passages that fit.")
            step(2, "The larger model reads those passages and writes the answer. It's better at following details like the gear you have and what you already tried.")
            step(3, "Both run entirely on this iPhone. Nothing you ask leaves it, and it works in Airplane Mode.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var measured: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What we measured").font(.headline)
            Text("16 backcountry questions with the same library passages. Each answer was scored 0 (wrong or unsafe), 1 (vague) or 2 (right and specific), and each model's 16 scores were added up, out of 32 points. Times and memory are from an 8 GB iPhone.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Built-in").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                    Text("Better").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                    Text("")
                }
                GridRow {
                    Text("Answer quality").foregroundStyle(Theme.inkSoft)
                    Text("9 pts").monospacedDigit()
                    Text("23 pts").monospacedDigit().fontWeight(.semibold)
                    Text("32 pts possible").font(.caption).foregroundStyle(Theme.inkSoft)
                }
                compare("First words", "1.6 s", "3.3 s")
                compare("Full answer", "3.5 s", "10 s")
                compare("Memory in use", "part of iOS", "3.4 GB")
            }
            .font(.subheadline)
            Text("It runs on the graphics chip, so each answer uses more battery than the built-in model, and the phone can get warm during long sessions.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var modelInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The model").font(.headline)
            row("Name", BetterModel.displayName)
            row("Made by", "Qwen team, Alibaba Cloud")
            row("Format", "4-bit, text only, MLX")
            row("Download", String(format: "%.1f GB", Double(better.downloadBytes) / 1e9))
            row("On this iPhone", String(format: "%.1f GB", Double(BetterModel.unpackedBytes) / 1e9))
            HStack {
                Text("License").foregroundStyle(Theme.inkSoft)
                Spacer()
                Link("Apache 2.0", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This iPhone").font(.headline)
            row("Memory (RAM)", String(format: "%.1f GB", MemoryProbe.deviceGB))
            row("App is using", String(format: "%.2f GB", memoryNow))
            row("iOS allows this app more", String(format: "%.2f GB", availableNow))
            HStack {
                Text("Larger model").foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(modelStatus)
                if better.isReady {
                    Button { better.unload() } label: { Label("Unload", systemImage: "eject") }
                        .buttonStyle(.bordered).tint(Theme.inkSoft).font(.subheadline)
                        .accessibilityLabel("Unload from memory")
                }
            }
            .font(.subheadline)
            Text("It loads when you open Scout and unloads when you leave the app, so other apps get the memory back.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
            if !BetterModel.isSupported {
                Text("This device can't run it: the simulator has no GPU for it, or the iPhone has under 8 GB.")
                    .font(.footnote).foregroundStyle(Theme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var modelStatus: String {
        switch better.state {
        case .notDownloaded: "Not downloaded"
        case .downloading(let f): "Downloading \(Int(f * 100))%"
        case .onDisk: "Not in memory"
        case .loading: "Loading…"
        case .ready: "In memory"
        case .failed: "Didn't load"
        }
    }

    /// Why the benchmark can't run here, if it can't.
    private var benchmarkBlocker: String? {
        if !BetterModel.isSupported { return "This device can't run \(BetterModel.displayName), so it can't run the benchmark." }
        if store.library == nil { return "Download the field guides first to run the benchmark." }
        if !better.isDownloaded { return "Download \(BetterModel.displayName) first to run the benchmark." }
        return nil
    }

    private var benchmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compare on this iPhone").font(.headline)
            Text("Runs \(LabBenchmark.questions.count) test questions through the library search once, then has each model write the answers. Unplug the phone first so battery use can be measured. Takes 5–15 minutes.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
            if bench.isRunning {
                ProgressView(value: bench.progress) { Text(bench.status).font(.footnote) }
                Button("Stop", role: .cancel) { bench.stop() }
            } else if let blocker = benchmarkBlocker {
                // Instead of a button that can't be tapped: why it can't run.
                Text(blocker).font(.footnote).foregroundStyle(Theme.danger)
            } else {
                Button("Run benchmark") { bench.run(library: store.library) }
                    .buttonStyle(SecondaryButtonStyle())
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

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.caption.weight(.heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Theme.accent, in: .circle)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compare(_ label: String, _ builtIn: String, _ better: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.inkSoft)
            Text(builtIn).monospacedDigit()
            Text(better).monospacedDigit().fontWeight(.semibold)
        }
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
                let searches = await Retrieval.searches(for: q, previous: nil, model: apple) ?? []
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
            let model: any LLMEngine = engine == "Apple" ? FoundationEngine(model: apple) : BetterModel.shared.engine
            let stats = try await model.answer([.system(Retrieval.instructions), .user(prompt)],
                                               config: .answers) { text = $0 }
            first = stats.secondsToFirstToken
            r.promptTokens = stats.promptTokens
            r.answerTokens = stats.answerTokens
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
