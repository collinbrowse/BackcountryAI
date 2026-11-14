// scout-tools embed: puts the search models into a library folder and writes its passage vectors, so the app can
// search by meaning (SearchModels.swift). Run it after building a library and before packaging it:
//   scripts/embed-library.sh library.noindex/library-lite
// The models go in models/embedder and models/reranker, the vectors in vectors.bin. Re-running replaces them.
import Foundation
import MLXEmbedders
import MLXLMCommon

@MainActor
enum Embed {
    static func run(_ args: [String]) async throws {
        guard let path = args.first else { throw ToolError.usage("embed <library-folder> [--limit N]") }
        let folder = URL(fileURLWithPath: path)
        let limit = args.firstIndex(of: "--limit").map { Int(args[$0 + 1]) ?? .max } ?? .max
        let library = try Library(folder: folder)

        // 1. The models, copied into the library so they ship (and stay matched) with its vectors.
        for (id, sub, patterns) in [
            (SearchModels.embedderID, SearchModels.embedderFolder, ["*.safetensors", "*.json", "vocab.txt", "1_Pooling/*"]),
            (SearchModels.rerankerID, SearchModels.rerankerFolder, ["*.safetensors", "*.json", "*.txt", "*.jinja"]),
        ] {
            let dest = folder.appending(path: sub)
            if FileManager.default.fileExists(atPath: dest.appending(path: "config.json").path) {
                print("\(sub): already there")
                continue
            }
            print("\(sub): downloading \(id)…")
            let snapshot = try await HubDownloader().download(id: id, revision: nil, matching: patterns, useLatest: false) { _ in }
            try copyResolvingLinks(snapshot, to: dest)
            print("\(sub): \(size(dest))")
        }

        // 2. Every passage's vector, from the copy that ships.
        let embedder = try await EmbedderModelFactory.shared.loadContainer(
            from: folder.appending(path: SearchModels.embedderFolder), using: TransformersTokenizerLoader())
        let total = try library.passageCount()
        print("embedding \(min(total, limit)) passages…")
        var ids: [Int64] = [], codes = Data(), dimensions = 0
        let start = Date()
        var after: Int64 = 0
        while ids.count < limit {
            let batch = try library.passageBatch(after: after, limit: 64)
            guard let last = batch.last else { break }
            after = last.id
            let vectors = try await SearchModels.embed(batch.map(\.text), with: embedder)
            dimensions = vectors.first?.count ?? dimensions
            for (row, v) in zip(batch, vectors) {
                ids.append(row.id)
                codes.append(contentsOf: VectorIndex.code(v))
            }
            if ids.count % 6400 < 64 {
                let rate = Double(ids.count) / Date().timeIntervalSince(start)
                let left = Double(min(total, limit) - ids.count) / max(rate, 1)
                print(String(format: "  %d / %d  (%.0f/s, %.0f min left)", ids.count, total, rate, left / 60))
                fflush(stdout)
            }
        }
        let out = folder.appending(path: VectorIndex.file)
        try VectorIndex.write(to: out, modelID: await SearchModels.modelName(embedder), dimensions: dimensions, ids: ids, codes: codes)
        print("wrote \(out.path): \(ids.count) vectors, \(size(out)), \(Int(Date().timeIntervalSince(start)))s")
    }

    /// Hugging Face snapshots are symlinks into a blob cache; the library needs real files.
    static func copyResolvingLinks(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: to)
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        let items = fm.enumerator(at: from, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        for item in items {
            let rel = String(item.path.dropFirst(from.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let real = item.resolvingSymlinksInPath()
            var isDir: ObjCBool = false
            fm.fileExists(atPath: real.path, isDirectory: &isDir)
            let target = to.appending(path: rel)
            if isDir.boolValue {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: real, to: target)
            }
        }
    }

    static func size(_ url: URL) -> String {
        let fm = FileManager.default
        var bytes: Int64 = 0
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
           let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e { bytes += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        } else {
            bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    var description: String { switch self { case .usage(let u): "usage: scout-tools \(u)" } }
}
