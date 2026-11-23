// Mac tools that run the app's own search code (Sources/Library.swift, Retrieval.swift, SearchModels.swift).
// Built by xcodebuild (target ScoutTools); see scripts/check-answers.sh and scripts/embed-library.sh.
import Foundation

@MainActor
func runTool() async {
    var args = Array(CommandLine.arguments.dropFirst())
    let command = args.isEmpty ? "" : args.removeFirst()
    do {
        switch command {
        case "check": try await Check.run(args)
        case "instructions": try Check.instructions(args)
        case "embed": try await Embed.run(args)
        case "rerank": try await RerankTest.run(args)
        case "rescore": try await RerankTest.rescore(args)
        case "cards": try await Cards.run(args)
        case "pool": try await Pool.run(args)
        case "stakes":
            // What `Stakes` makes of every question in the given TSVs (the column headed "question").
            for path in args {
                let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
                guard let column = lines.first?.firstIndex(of: "question") else { continue }
                for row in lines.dropFirst() where row.count > column {
                    print("\(Stakes.of(row[column]).rawValue)\t\(row[column])")
                }
            }
        default:
            print("""
            usage:
              scout-tools check <library-folder> <questions.tsv> [--answers] [--no-library] [--only TEXT] [--json FILE]
                                [--conversations FILE] [--qwen [DIR]] [--no-rerank] [--no-dense]
              scout-tools instructions <records.json> --json FILE [--apple]
              scout-tools embed <library-folder> [--limit N]
              scout-tools cards <library-folder> <messages.tsv> [--json FILE] [--words] [--no-confirm] [--close-ask]
              scout-tools pool <library-folder> <questions.tsv> --json FILE [--conversations FILE] [--depth 40]
              scout-tools rescore <pool.json> <reranker-folder> --json FILE [--whole]
              scout-tools stakes <questions.tsv>...
            """)
            exit(2)
        }
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

await runTool()
