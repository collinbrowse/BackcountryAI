import CryptoKit
import Foundation
import Observation
import UIKit
import ZIPFoundation

struct LibraryPack: Codable, Identifiable, Hashable, Sendable {
    struct Part: Codable, Hashable, Sendable { let url: URL; let bytes: Int64; let sha256: String }
    let id: String
    let label: String
    let gb: Double
    let articles: Int
    let version: String
    let install_bytes: Int64
    let parts: [Part]

    var downloadBytes: Int64 { parts.reduce(0) { $0 + $1.bytes } }
    var title: String { id == "lite" ? "Essentials" : id == "full" ? "Everything" : id.capitalized }
    var blurb: String {
        switch id {
        case "lite": "First aid and medicine, FEMA, U.S. Army survival and cold-weather manuals, wikiHow, "
            + "outdoors, vehicle repair and home-repair Q&A."
        case "full": "Essentials plus about 930,000 Wikipedia articles (skiing, avalanches, weather, wildlife, "
            + "plants) and iFixit repair guides."
        default: label
        }
    }
}

/// The library packs Survival LLM publishes (github.com/anonnerdfrenzy/survival-llm, docs/library-packs.json).
enum PackCatalog {
    static let remote = URL(string:
        "https://raw.githubusercontent.com/anonnerdfrenzy/survival-llm/main/docs/library-packs.json")!

    static let builtIn: [LibraryPack] = {
        let base = "https://github.com/anonnerdfrenzy/survival-llm/releases/download/library-2026-10-28/"
        func part(_ name: String, _ bytes: Int64, _ sha: String) -> LibraryPack.Part {
            .init(url: URL(string: base + name)!, bytes: bytes, sha256: sha)
        }
        return [
            LibraryPack(id: "lite", label: "Essentials", gb: 1.3, articles: 494_574, version: "2026-10-28",
                        install_bytes: 4_509_641_710, parts: [
                part("library-lite.zip.000", 1_275_477_229,
                     "0e9fc46df8288c1aa9a81b87386acd224963b8a1b2fd44d51078089d3dee8686")]),
            LibraryPack(id: "full", label: "Everything", gb: 8.7, articles: 1_507_306, version: "2026-10-28",
                        install_bytes: 22_332_537_074, parts: [
                part("library-full.zip.000", 1_900_000_000, "57bfb07c449bde58034ebac34aa09035bfde161a1a4bbe141833d42f9048aaeb"),
                part("library-full.zip.001", 1_900_000_000, "9bfe149c963d090b2c9d1d393beb4da7c8f61b17b13f192b417d25fb860d363b"),
                part("library-full.zip.002", 1_900_000_000, "88c9b8e5d8abf5d8f84d7509edb8305024da18dc43ee1e8be5a01bb0af1668de"),
                part("library-full.zip.003", 1_900_000_000, "da87c3b7e1a49fe35cf1c2a5084104e284f70d0b4dd6faebc0d6e5107b5c126c"),
                part("library-full.zip.004", 1_056_720_766, "75f8107d419fe5891296de3342bd2798d749001c10651fe4e593bca13bfe0a26"),
            ]),
        ]
    }()

    static func load() async -> [LibraryPack] {
        struct File: Codable { let packs: [LibraryPack] }
        guard let (data, _) = try? await URLSession.shared.data(from: remote),
              let file = try? JSONDecoder().decode(File.self, from: data), !file.packs.isEmpty
        else { return builtIn }
        return file.packs
    }
}

@MainActor
@Observable
final class LibraryStore {
    enum Phase: Equatable {
        case idle
        case downloading(part: Int, of: Int, fraction: Double, detail: String)
        case verifying
        case unpacking(fraction: Double)
        case failed(String)
    }

    var library: Library?
    var installedPackID: String?
    var phase: Phase = .idle
    var packs: [LibraryPack] = PackCatalog.builtIn
    var articleCount = 0

    private var work: Task<Void, Never>?

    /// Application Support/Library — kept out of iCloud backups (it is gigabytes and can be downloaded again).
    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
    }
    /// A library copied in with Finder (iPhone › Files › Backcountry) also works.
    static var documentsFolder: URL { URL.documentsDirectory.appending(path: "Library", directoryHint: .isDirectory) }
    private static var staging: URL { URL.applicationSupportDirectory.appending(path: "Download", directoryHint: .isDirectory) }

    init() { open() }

    func open() {
        for folder in [Self.folder, Self.documentsFolder]
        where FileManager.default.fileExists(atPath: folder.appending(path: "index.sqlite").path) {
            if let lib = try? Library(folder: folder) {
                library = lib
                articleCount = lib.stats().articles
                installedPackID = try? String(contentsOf: folder.appending(path: "pack-id"), encoding: .utf8)
                return
            }
        }
        library = nil
        articleCount = 0
    }

    func refreshCatalog() async { packs = await PackCatalog.load() }

    var isWorking: Bool {
        switch phase { case .idle, .failed: false; default: true }
    }

    func install(_ pack: LibraryPack) {
        guard !isWorking else { return }
        UIApplication.shared.isIdleTimerDisabled = true  // keep the phone awake while it downloads
        work = Task {
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                try await download(pack)
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() { work?.cancel() }

    func deleteLibrary() {
        library = nil
        try? FileManager.default.removeItem(at: Self.folder)
        try? FileManager.default.removeItem(at: Self.staging)
        open()
    }

    // MARK: - Download, verify, unpack

    private func download(_ pack: LibraryPack) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.staging, withIntermediateDirectories: true)
        let free = (try? URL.applicationSupportDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        let needed = pack.downloadBytes + pack.install_bytes + 1_000_000_000
        if free > 0 && free < needed {
            throw StoreError.noSpace(needed: needed, free: free)
        }

        // Each part is a slice of one zip. Parts already downloaded and checked are kept, so a retry resumes.
        let joined = Self.staging.appending(path: "\(pack.id)-\(pack.version).zip")
        var partFiles: [URL] = []
        for (i, part) in pack.parts.enumerated() {
            let dest = Self.staging.appending(path: "\(pack.id)-\(pack.version).part\(i)")
            partFiles.append(dest)
            if fm.fileExists(atPath: dest.path),
               (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int64) == part.bytes { continue }
            try await Downloader.fetch(part.url, to: dest, expected: part.bytes) { [weak self] done, total, rate in
                Task { @MainActor in
                    self?.phase = .downloading(part: i + 1, of: pack.parts.count,
                                               fraction: Double(done) / Double(max(total, 1)),
                                               detail: Self.progressText(done: done, total: total, rate: rate))
                }
            }
            phase = .verifying
            let ok = try await Task.detached { try Self.sha256(of: dest) == part.sha256 }.value
            guard ok else { try? fm.removeItem(at: dest); throw StoreError.badChecksum }
        }

        // Join the parts into one zip (a single part is just renamed).
        try? fm.removeItem(at: joined)
        if partFiles.count == 1 {
            try fm.moveItem(at: partFiles[0], to: joined)
        } else {
            phase = .unpacking(fraction: 0)
            let parts = partFiles
            try await Task.detached { try Self.concatenate(parts, into: joined) }.value
            partFiles.forEach { try? fm.removeItem(at: $0) }
        }

        // Unpack into a fresh folder, then swap it in.
        let unpacked = Self.staging.appending(path: "unpacked", directoryHint: .isDirectory)
        try? fm.removeItem(at: unpacked)
        let report: @Sendable (Double) -> Void = { [weak self] f in
            Task { @MainActor in self?.phase = .unpacking(fraction: f) }
        }
        try await Task.detached { try Self.unzip(joined, to: unpacked, report: report) }.value
        try? fm.removeItem(at: joined)
        try pack.id.write(to: unpacked.appending(path: "pack-id"), atomically: true, encoding: .utf8)

        library = nil
        try? fm.removeItem(at: Self.folder)
        try fm.moveItem(at: unpacked, to: Self.folder)
        var folder = Self.folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        try? fm.removeItem(at: Self.staging)
        open()
    }

    enum StoreError: LocalizedError {
        case badChecksum, noSpace(needed: Int64, free: Int64)
        var errorDescription: String? {
            switch self {
            case .badChecksum: "The download was damaged. Tap Download to try again."
            case let .noSpace(needed, free):
                "Not enough free space: this needs about \(Self.gb(needed)) and the phone has \(Self.gb(free)) free."
            }
        }
        static func gb(_ b: Int64) -> String { String(format: "%.1f GB", Double(b) / 1e9) }
    }

    nonisolated static func progressText(done: Int64, total: Int64, rate: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        var s = "\(f.string(fromByteCount: done)) of \(f.string(fromByteCount: total))"
        if rate > 0 {
            let left = Double(total - done) / rate
            s += " · \(f.string(fromByteCount: Int64(rate)))/s"
            if left.isFinite { s += " · " + (left > 90 ? "\(Int(left / 60)) min left" : "\(Int(left)) s left") }
        }
        return s
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func unzip(_ zip: URL, to dest: URL, report: @escaping @Sendable (Double) -> Void) throws {
        final class Last: @unchecked Sendable { var value = -1.0 }
        let progress = Progress(), last = Last()
        let observer = progress.observe(\.fractionCompleted) { p, _ in
            let f = (p.fractionCompleted * 100).rounded() / 100
            if f != last.value { last.value = f; report(f) }
        }
        defer { observer.invalidate() }
        try FileManager.default.unzipItem(at: zip, to: dest, progress: progress)
    }

    nonisolated static func concatenate(_ parts: [URL], into dest: URL) throws {
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let out = try FileHandle(forWritingTo: dest)
        defer { try? out.close() }
        for p in parts {
            let h = try FileHandle(forReadingFrom: p)
            while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { try out.write(contentsOf: chunk) }
            try h.close()
            try FileManager.default.removeItem(at: p)  // free space as we go
        }
    }
}

/// A download with progress that resumes after a dropped connection.
enum Downloader {
    static func fetch(_ url: URL, to dest: URL, expected: Int64,
                      progress: @escaping @Sendable (Int64, Int64, Double) -> Void) async throws {
        var resumeData: Data?
        var attempts = 0
        while true {
            try Task.checkCancellation()
            let delegate = Delegate(expected: expected, progress: progress)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            do {
                let temp: URL = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { cont in
                        delegate.continuation = cont
                        let task = resumeData.map { session.downloadTask(withResumeData: $0) }
                            ?? session.downloadTask(with: url)
                        delegate.task = task
                        task.resume()
                    }
                } onCancel: {
                    delegate.task?.cancel()
                }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: temp, to: dest)
                return
            } catch {
                if Task.isCancelled { throw CancellationError() }
                attempts += 1
                resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                if attempts > 20 { throw error }
                try await Task.sleep(for: .seconds(min(30, 2 * attempts)))
            }
        }
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let expected: Int64
        let progress: @Sendable (Int64, Int64, Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        var task: URLSessionDownloadTask?
        private var lastBytes: Int64 = 0
        private var lastTime = Date()
        private var rate: Double = 0

        init(expected: Int64, progress: @escaping @Sendable (Int64, Int64, Double) -> Void) {
            self.expected = expected
            self.progress = progress
        }

        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let now = Date()
            let dt = now.timeIntervalSince(lastTime)
            if dt >= 1 {
                let r = Double(totalBytesWritten - lastBytes) / dt
                rate = rate == 0 ? r : rate * 0.7 + r * 0.3
                lastBytes = totalBytesWritten
                lastTime = now
                let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
                progress(totalBytesWritten, total, rate)
            }
        }

        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The temp file is deleted when this returns, so move it somewhere safe first.
            let keep = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            do {
                try FileManager.default.moveItem(at: location, to: keep)
                continuation?.resume(returning: keep)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }

        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { continuation?.resume(throwing: error); continuation = nil }
        }
    }
}
