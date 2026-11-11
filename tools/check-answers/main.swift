// Runs library/questions.tsv through the app's own retrieval (Sources/Library.swift, Sources/Retrieval.swift) with
// Apple's on-device model on this Mac, and reports for each question whether a relevant article made it to the
// model, plus what the model searched for and picked. Build and run with scripts/check-answers.sh.
import Foundation
import FoundationModels

@main
struct CheckAnswers {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: check-answers <library-folder> <questions.tsv> [--answers] [--no-library] [--only TEXT]")
            exit(2)
        }
        let library = try Library(folder: URL(fileURLWithPath: args[1]))
        let rows = try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").dropFirst()
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        let noLibrary = args.contains("--no-library")  // answer from the model alone, to see what it knows
        let answers = args.contains("--answers") || noLibrary
        let only = args.firstIndex(of: "--only").map { args[$0 + 1].lowercased() }
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { print("model unavailable: \(model.availability)"); exit(1) }

        var keywordPass = 0, pass = 0, total = 0
        for row in rows where row.count >= 3 {
            let (area, q, about) = (row[0], row[1], try Regex(row[2]).ignoresCase())
            if let only, !q.lowercased().contains(only) { continue }
            total += 1
            let start = Date()
            let plain = library.search(q, limit: 5)
            let searches = await Retrieval.searches(for: q, previous: nil, model: model)
            let planned = Date()
            let candidates = Retrieval.candidates(question: q, searches: searches, library: library)
            let searched = Date()
            let picked = await Retrieval.pick(question: q, from: candidates, model: model)
            let done = Date()
            let kOK = plain.contains { $0.title.contains(about) }
            let ok = picked.contains { $0.title.contains(about) }
            keywordPass += kOK ? 1 : 0
            pass += ok ? 1 : 0
            print("\(ok ? "PASS" : (picked.isEmpty ? "NONE" : "MISS"))\t\(area)\t\(q)")
            print(String(format: "    searches (%.1fs): %@", planned.timeIntervalSince(start),
                         searches.joined(separator: " | ")))
            print(String(format: "    library search %.1fs; picked (%.1fs):", searched.timeIntervalSince(planned),
                         done.timeIntervalSince(searched)))
            for p in picked { print("      [\(p.sourceKey)] \(p.title)") }
            let dropped = candidates.filter { c in !picked.contains { $0.docID == c.docID } }
            if !dropped.isEmpty { print("    dropped: " + dropped.map(\.title).joined(separator: " · ")) }
            if answers {
                let session = LanguageModelSession(model: model, instructions: Retrieval.instructions)
                let prompt = Retrieval.prompt(question: q, sources: noLibrary ? [] : picked, previous: nil, previousAnswer: nil)
                let r = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3,
                                                                                           maximumResponseTokens: 700))
                print("    answer:\n" + (r?.content ?? "(failed)").split(separator: "\n").map { "      " + $0 }
                    .joined(separator: "\n"))
            }
            fflush(stdout)
        }
        print("\nkeyword search alone: \(keywordPass)/\(total); with the model's searches and picks: \(pass)/\(total)")
    }
}
