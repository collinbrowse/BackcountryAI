import CryptoKit
import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon
import MLXRerankers
import os

/// Two small models that make search understand meaning, not just words. Both ship inside the library pack (built by
/// `scout-tools embed`, see docs/answer-quality.md), so they always match the library's vectors:
/// - an embedder (bge-small-en-v1.5, 33M parameters) that turns text into a vector, so "my snowmobile isn't
///   starting" finds "engine cranks but won't fire" even with no words in common, and
/// - a reranker (Qwen3-Reranker-0.6B), a model trained only to judge whether a passage answers a question.
///   It scores every candidate before the answer is written, and weak ones are dropped (Retrieval.pick).
///   Full precision, about 1.2 GB: the 4-bit copy scored a good passage 0.09 where this one says 0.92.
/// Without them (the simulator, a library built before them, or too little free memory) search falls back to
/// keywords and Apple's model.
@MainActor
final class SearchModels {
    static let shared = SearchModels()

    static let embedderFolder = "models/embedder"
    static let rerankerFolder = "models/reranker"
    /// What `scout-tools embed` copies into the library.
    static let embedderID = "BAAI/bge-small-en-v1.5"
    static let rerankerID = "Qwen/Qwen3-Reranker-0.6B"
    /// Memory to leave free when loading the reranker: what the answer model still needs if it isn't loaded yet
    /// (the app sets this before each question).
    var reserveBytes: Int64 = 300_000_000
    /// bge models find passages best when the query (not the passage) starts with this.
    static let queryPrefix = "Represent this sentence for searching relevant passages: "

    private var embedder: EmbedderModelContainer?
    private var reranker: RerankerContainer?
    private var vectors: VectorIndex?
    private var loadedFor: ObjectIdentifier?
    private var loading: Task<Void, Never>?

    /// MLX needs a real GPU: the simulator can't run it.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    /// The library's passages closest in meaning to the query, best first. Empty when the library has no vectors.
    func denseSearch(_ query: String, library: Library, limit: Int = 8) async -> [Passage] {
        await load(for: library)
        guard let embedder, let vectors else { return [] }
        do {
            guard let q = try await Self.embed([Self.queryPrefix + query], with: embedder).first else { return [] }
            let hits = await Task.detached(priority: .userInitiated) { vectors.search(q, limit: limit * 3) }.value
            let words = Library.queryWords(query)
            return library.passages(ids: hits.map(\.id), words: words, maxChars: 700).prefix(limit).map { $0 }
        } catch {
            log.error("dense search failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Scores for Retrieval.pick, or nil when there's no reranker (it then asks Apple's model instead).
    var scorer: Retrieval.Scorer? {
        guard Self.isSupported else { return nil }
        return { query, excerpts in
            guard let reranker = await SearchModels.shared.loadedReranker() else { return nil }
            do {
                let response = try await reranker.scores(
                    query: query, documents: excerpts,
                    options: RerankExecutionOptions(maxBatchSize: 4, maxBatchTokens: 4096, truncation: .truncate))
                let byIndex = Dictionary(response.results.map { ($0.index, $0.score) }, uniquingKeysWith: { a, _ in a })
                return excerpts.indices.map { byIndex[$0] ?? 0 }
            } catch {
                log.error("rerank failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func loadedReranker() async -> RerankerContainer? {
        await loading?.value
        return reranker
    }

    /// Loads both models and the vectors for this library, once. Cheap to call before every question.
    func load(for library: Library) async {
        guard Self.isSupported else { return }
        if loadedFor == ObjectIdentifier(library), loading == nil { return }
        if let loading { return await loading.value }
        let id = ObjectIdentifier(library)
        loading = Task {
            defer { loading = nil }
            vectors = library.fileURL(VectorIndex.file).flatMap { try? VectorIndex(url: $0) }
            if embedder == nil { embedder = await Self.loadEmbedder(library) }
            if reranker == nil { reranker = await Self.loadReranker(library, reserveBytes: reserveBytes) }
            // Vectors only mean something next to the embedder that made them.
            if let v = vectors, let e = embedder {
                let name = await Self.modelName(e)
                if v.modelID != name {
                    log.error("vectors were made by \(v.modelID), not \(name); meaning search is off")
                    vectors = nil
                }
            }
            loadedFor = id
            log.notice("search models: embedder \(self.embedder != nil), reranker \(self.reranker != nil), vectors \(self.vectors?.count ?? 0)")
        }
        await loading?.value
    }

    /// Frees the models' memory (about 0.5 GB); they reload from disk when needed.
    func unload() {
        guard loading == nil else { return }
        embedder = nil
        reranker = nil
        vectors = nil
        loadedFor = nil
        Memory.clearCache()
    }

    // MARK: - Loading

    private static func folder(_ path: String, in library: Library) -> URL? {
        library.fileURL(path + "/config.json")?.deletingLastPathComponent()
    }

    private static func loadEmbedder(_ library: Library) async -> EmbedderModelContainer? {
        guard let dir = folder(embedderFolder, in: library) else { return nil }
        do {
            return try await EmbedderModelFactory.shared.loadContainer(from: dir, using: TransformersTokenizerLoader())
        } catch {
            log.error("embedder didn't load: \(error.localizedDescription)")
            return nil
        }
    }

    private static func loadReranker(_ library: Library, reserveBytes: Int64) async -> RerankerContainer? {
        guard let dir = folder(rerankerFolder, in: library) else { return nil }
        // Never start a load iOS would end the app for (as MLXEngine does): the weights, working room, and what
        // the answer model still needs. Too little free: Apple's model checks the excerpts instead.
        let weights = Int64((try? dir.appending(path: "model.safetensors").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        do {
            try MemoryBudget(weightsBytes: weights, workingBytes: 300_000_000, reserveBytes: reserveBytes)
                .check(availableBytes: MemoryProbe.availableBytes)
            // Our own copy of a known reranker, so its folder name needn't say "reranker".
            return try await RerankerModelFactory.shared.loadContainer(
                from: dir, using: TransformersTokenizerLoader(), allowUnverifiedModel: true)
        } catch {
            log.error("reranker didn't load: \(error.localizedDescription)")
            return nil
        }
    }

    /// A fingerprint of the embedder's weights, written into the vectors file: vectors only mean something next to
    /// the exact model that made them.
    nonisolated static func modelName(_ embedder: EmbedderModelContainer) async -> String {
        guard let folder = try? await embedder.modelDirectory else { return "unknown" }
        return fingerprint(folder)
    }

    nonisolated static func fingerprint(_ folder: URL) -> String {
        var hash = SHA256()
        for name in ["config.json", "model.safetensors"] {
            guard let handle = try? FileHandle(forReadingFrom: folder.appending(path: name)) else { continue }
            hash.update(data: (try? handle.read(upToCount: 1 << 20)) ?? Data())
            try? handle.close()
        }
        return "bge-small-" + hash.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Embedding

    /// Unit-length vectors for each text, in order. Passages are cut at 256 tokens (about 1,000 characters, the
    /// title and the passage's start), which keeps embedding a whole library to about an hour; queries are short.
    nonisolated static func embed(_ texts: [String], with embedder: EmbedderModelContainer,
                                  maxTokens: Int = 256) async throws -> [[Float]] {
        try await embedder.perform { context in
            let maxTokens = min(context.model.maxPositionEmbeddings ?? 512, maxTokens)
            let inputs = texts.map { Array(context.tokenizer.encode(text: $0, addSpecialTokens: true).prefix(maxTokens)) }
            let longest = inputs.map(\.count).max() ?? 1
            let pad = 0  // BERT's [PAD]
            let ids = stacked(inputs.map { MLXArray($0 + Array(repeating: pad, count: longest - $0.count)) })
            let mask = stacked(inputs.map { MLXArray(Array(repeating: Int32(1), count: $0.count)
                                                    + Array(repeating: Int32(0), count: longest - $0.count)) })
            let output = context.model(ids, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: ids), attentionMask: mask)
            let pooled = context.pooling(output, mask: mask, normalize: true)
            pooled.eval()
            return (0..<texts.count).map { pooled[$0].asArray(Float.self) }
        }
    }
}

/// The library's passage vectors, one bit per dimension (48 bytes each for a 384-dimension model), so 1.3 million
/// passages fit in about 60 MB and a full scan takes milliseconds. Written by `scout-tools embed`.
///
/// Layout: "SCOUTVEC", UInt32 version (1), UInt32 dimensions, UInt64 count, UInt32 name length, the embedder's name
/// (UTF-8), then `count` Int64 passage ids, then `count` codes of dimensions/8 bytes. Little-endian.
struct VectorIndex: @unchecked Sendable {
    static let file = "vectors.bin"
    static let magic = Array("SCOUTVEC".utf8)

    let modelID: String
    let dimensions: Int
    let count: Int
    private let data: Data
    private let idsOffset: Int
    private let codesOffset: Int

    init(url: URL) throws {
        let d = try Data(contentsOf: url, options: .alwaysMapped)
        guard d.count > 32, Array(d.prefix(8)) == Self.magic else { throw CocoaError(.fileReadCorruptFile) }
        func read<T: FixedWidthInteger>(_ at: Int, _: T.Type) -> T {
            d.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: T.self)) }
        }
        let dims = Int(read(12, UInt32.self)), n = Int(read(16, UInt64.self)), nameLength = Int(read(24, UInt32.self))
        data = d
        dimensions = dims
        count = n
        modelID = String(decoding: d[28..<(28 + nameLength)], as: UTF8.self)
        idsOffset = 28 + nameLength
        codesOffset = 28 + nameLength + n * 8
        guard dims % 64 == 0, d.count >= codesOffset + n * dims / 8 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    static func write(to url: URL, modelID: String, dimensions: Int, ids: [Int64], codes: Data) throws {
        var out = Data(magic)
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        put(UInt32(1)); put(UInt32(dimensions)); put(UInt64(ids.count))
        let name = Data(modelID.utf8)
        put(UInt32(name.count)); out.append(name)
        for id in ids { put(id) }
        out.append(codes)
        try out.write(to: url)
    }

    /// One bit per dimension: set where the value is positive.
    static func code(_ v: [Float]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: v.count / 8)
        for (i, x) in v.enumerated() where x > 0 { bytes[i / 8] |= 1 << (i % 8) }
        return bytes
    }

    /// Passage ids nearest the query: the closest few hundred by bit distance, then re-scored against the query's
    /// full values (more accurate than bits on both sides).
    func search(_ query: [Float], limit: Int, shortlist: Int = 400) -> [(id: Int64, score: Float)] {
        guard query.count == dimensions, count > 0 else { return [] }
        let words = dimensions / 64
        let q = Self.code(query).withUnsafeBytes { Array($0.bindMemory(to: UInt64.self)) }
        return data.withUnsafeBytes { raw -> [(Int64, Float)] in
            let codes = raw.baseAddress!.advanced(by: codesOffset)
            // Bit distance for every passage, then the shortlist by counting sort (distances are 0...dimensions).
            var distance = [UInt16](repeating: 0, count: count)
            var histogram = [Int](repeating: 0, count: dimensions + 1)
            for i in 0..<count {
                let row = codes.advanced(by: i * words * 8)
                var d = 0
                for w in 0..<words { d += (row.loadUnaligned(fromByteOffset: w * 8, as: UInt64.self) ^ q[w]).nonzeroBitCount }
                distance[i] = UInt16(d)
                histogram[d] += 1
            }
            var cutoff = 0, taken = 0
            while cutoff < dimensions && taken + histogram[cutoff] < shortlist { taken += histogram[cutoff]; cutoff += 1 }
            var scored: [(Int64, Float)] = []
            for i in 0..<count where Int(distance[i]) <= cutoff {
                let row = codes.advanced(by: i * words * 8).assumingMemoryBound(to: UInt8.self)
                var s: Float = 0
                for j in 0..<dimensions { s += (row[j / 8] >> (j % 8)) & 1 == 1 ? query[j] : -query[j] }
                let id = raw.loadUnaligned(fromByteOffset: idsOffset + i * 8, as: Int64.self)
                scored.append((Int64(littleEndian: id), s))
            }
            return Array(scored.sorted { $0.1 > $1.1 }.prefix(limit))
        }.map { (id: $0.0, score: $0.1) }
    }
}
