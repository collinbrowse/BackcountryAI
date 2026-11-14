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
        case "embed": try await Embed.run(args)
        case "rerank": try await RerankTest.run(args)
        default:
            print("""
            usage:
              scout-tools check <library-folder> <questions.tsv> [--answers] [--no-library] [--only TEXT] [--json FILE]
                                [--conversations FILE] [--qwen [DIR]] [--no-rerank] [--no-dense]
              scout-tools embed <library-folder> [--limit N]
            """)
            exit(2)
        }
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

await runTool()
