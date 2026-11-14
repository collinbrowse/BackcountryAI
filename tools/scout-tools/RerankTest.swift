// scout-tools rerank: scores documents against a query with a reranker, to compare rerankers and set
// Retrieval.minimumRelevance. Usage: scout-tools rerank <model-id-or-folder> "<query>" "<doc>" ["<doc>" …]
import Foundation
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
}
