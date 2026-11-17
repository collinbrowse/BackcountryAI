// scout-tools rerank: scores documents against a query with a reranker, to compare rerankers and set
// Retrieval.minimumRelevance. Usage: scout-tools rerank <model-id-or-folder> "<query>" "<doc>" ["<doc>" …]
import Foundation
import MLX
import MLXLMCommon
import MLXRerankers

@MainActor
enum RerankTest {
    static func run(_ args: [String]) async throws {
        guard args.count >= 3 else { throw ToolError.usage("rerank <model-id-or-folder> <query> <doc>…") }
        let model = args[0]
        let reranker = FileManager.default.fileExists(atPath: model)
            ? try await RerankerModelFactory.shared.loadContainer(from: URL(fileURLWithPath: model),
                                                                  using: TransformersTokenizerLoader(), allowUnverifiedModel: true)
            : try await RerankerModelFactory.shared.loadContainer(from: HubDownloader(), using: TransformersTokenizerLoader(), id: model)
        let docs = Array(args.dropFirst(2))
        let instruction = ProcessInfo.processInfo.environment["INSTRUCTION"]
        let r = try await reranker.scores(query: args[1], documents: docs, instruction: instruction)
        for result in r.results { print(String(format: "%.3f  %@", result.score, docs[result.index])) }
    }

    /// scout-tools rescore <pool.json> <reranker-folder> --json FILE [--whole]: a reranker's score for every
    /// candidate in a pool (scout-tools pool), read as Retrieval.rerank hands them over (the title and the 600
    /// characters around the question's words; --whole gives it the whole excerpt). With the judge's scores for
    /// the same candidates this says what a reranker would add (tools/grade-answers/fit_ranker.py --scores).
    /// FILE: [{question, history, scores: [[passage id, score]]}].
    static func rescore(_ args: [String]) async throws {
        guard args.count >= 4, let flag = args.firstIndex(of: "--json"), flag + 1 < args.count else {
            throw ToolError.usage("rescore <pool.json> <reranker-folder> --json FILE [--whole]")
        }
        let pool = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[0]))) as? [String: Any]
        guard let records = pool?["records"] as? [[String: Any]], let passages = pool?["passages"] as? [String: [String: Any]]
        else { throw ToolError.usage("rescore: \(args[0]) is not a pool from scout-tools pool") }
        let reranker = try await RerankerModelFactory.shared.loadContainer(
            from: URL(fileURLWithPath: args[1]), using: TransformersTokenizerLoader(), allowUnverifiedModel: true)
        let whole = args.contains("--whole")
        // MLX keeps every buffer it has used for reuse. With 20 long documents a question that reached 49 GB
        // and starved Apple's model of memory, so the cache is capped and emptied after each question.
        GPU.set(cacheLimit: 1 << 30)
        var out: [[String: Any]] = []
        let began = Date()
        for r in records {
            guard let app = r["app"] as? [[String: Any]], let question = r["question"] as? String else { continue }
            let history = (r["history"] as? [String] ?? []).map { Retrieval.Turn(question: $0, answer: "") }
            let asked = Retrieval.situation(question, history: history) ?? question
            let words = Library.queryWords(asked)
            var ids: [Int64] = [], docs: [String] = []
            for c in app {
                guard let id = (c["id"] as? NSNumber)?.int64Value, let p = passages[String(id)],
                      let text = c["text"] as? String else { continue }
                ids.append(id)
                docs.append("\(p["title"] as? String ?? "") (\(p["source"] as? String ?? ""))\n"
                    + (whole ? text : Library.window(text, words: words, width: 600)))
            }
            let response = try await reranker.scores(
                query: asked, documents: docs,
                options: RerankExecutionOptions(maxBatchSize: 4, maxBatchTokens: 4096, truncation: .truncate))
            let byIndex = Dictionary(response.results.map { ($0.index, Double($0.score)) }, uniquingKeysWith: { a, _ in a })
            out.append(["question": question, "history": r["history"] ?? [],
                        "scores": ids.enumerated().map { [$0.element, byIndex[$0.offset] ?? 0] as [Any] }])
            GPU.clearCache()
        }
        try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: args[flag + 1]))
        print(String(format: "%d questions in %.0f s -> %@", out.count, Date().timeIntervalSince(began), args[flag + 1]))
    }
}
