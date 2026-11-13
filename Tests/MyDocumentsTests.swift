import Foundation
import PDFKit
import Testing
import UIKit
@testable import BackcountryAI

/// Documents the person adds: reading files, indexing them, and searching them with the library.
struct MyDocumentsTests {
    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "mydocs-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private let filterManual = """
    # Replacing the Filter

    Unscrew the cartridge housing counterclockwise. Pull the old ceramic filter straight out and discard it.

    ## Priming

    Before first use, pump two liters of clean water through the new cartridge to flush carbon dust.
    """

    @Test func indexesSearchesAndRemoves() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let docs = try MyDocuments(folder: folder)
        #expect(docs.library() == nil)

        let item = try docs.add(title: "Katadyn Pocket manual", filename: "pocket.md",
                                sections: [.init(title: "Replacing the Filter", text: filterManual)])
        #expect(item.key.hasPrefix(Library.minePrefix))
        #expect(docs.items().map(\.title) == ["Katadyn Pocket manual"])

        let lib = try #require(docs.library())
        let hits = lib.search("how do I replace the ceramic filter cartridge")
        let hit = try #require(hits.first)
        #expect(hit.isMine && !hit.official)
        #expect(hit.source == "Katadyn Pocket manual")
        #expect(hit.id >= Library.mineIDBase && hit.docID >= Library.mineIDBase)
        #expect(hit.text.contains("ceramic filter"))
        let article = try #require(lib.article(docID: hit.docID))
        #expect(article.body.contains("carbon dust"))
        #expect(lib.sources().first?.key == item.key)
        #expect(lib.titles(sourceKey: item.key, offset: 0, limit: 10).map(\.title) == ["Replacing the Filter"])

        // Adding the same file again replaces it.
        try docs.add(title: "Katadyn Pocket manual", filename: "pocket.md",
                     sections: [.init(title: "Replacing the Filter", text: filterManual)])
        #expect(docs.items().count == 1)

        try docs.remove(key: docs.items()[0].key)
        #expect(docs.items().isEmpty)
        #expect(try Library(locate: { folder.appending(path: $0) }, immutable: false).search("ceramic filter").isEmpty)
    }

    @Test func combinedWithTheLibrary() throws {
        let fixtures = try #require(Bundle.main.url(forResource: "ScreenshotFixtures", withExtension: nil))
        let pack = try Library(folder: fixtures.appending(path: "Library"))
        let packArticles = pack.stats().articles
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let docs = try MyDocuments(folder: folder)
        try docs.add(title: "Katadyn Pocket manual", filename: "pocket.md",
                     sections: [.init(title: "Replacing the Filter", text: filterManual)])
        let lib = try #require(Library.combining(pack: pack, mine: docs.library()))
        #expect(lib.stats().articles == packArticles + 1)
        let hits = lib.search("ceramic filter cartridge priming")
        #expect(hits.first?.isMine == true)
        #expect(lib.article(docID: hits[0].docID)?.title == "Replacing the Filter")
    }

    @Test func mergeKeepsBothOrdersAndPutsFullerMatchesFirst() {
        func p(_ id: Int64, _ cov: Double, mine: Bool = false) -> Passage {
            Passage(id: id, docID: id, title: "\(id)", source: "", sourceKey: mine ? "mine-x" : "ready-gov",
                    official: false, text: "", coverage: cov)
        }
        let merged = Library.merge([p(1, 1), p(2, 0.5), p(3, 0.5)], mine: [p(10, 0.5, mine: true), p(11, 0.2, mine: true)],
                                   limit: 4)
        #expect(merged.map(\.id) == [1, 10, 2, 3])
    }

    @Test func passagesStayNearTheTargetSize() {
        let long = (1...400).map { "Sentence number \($0) about a stove." }.joined(separator: " ")
        let parts = MyDocuments.passages("# Stoves\n\n" + long + "\n\nShort tail.")
        #expect(parts.count > 3)
        #expect(parts.allSatisfy { $0.text.count <= 3000 })
        #expect(parts[0].heading == "Stoves")
        #expect(parts.map(\.text).joined().contains("Short tail."))
    }

    @Test func longTextSplitsAtHeadings() {
        let chapter = (1...150).map { "Paragraph \($0) of plain text about knots and lashings." }.joined(separator: "\n\n")
        let text = "# Knots\n\n\(chapter)\n\n# Shelters\n\n\(chapter)\n\n# Fire\n\n\(chapter)\n\n# Water\n\n\(chapter)"
        let sections = DocumentReader.split(text, title: "Field notes")
        #expect(sections.count > 1)
        #expect(sections[0].title == "Knots (Field notes)")
        #expect(DocumentReader.split("Just a line.", title: "Note") == [.init(title: "Note", text: "Just a line.")])
    }

    @Test func pdfPagesBecomeParagraphsWithoutRunningHeaders() {
        let verbs = ["light", "start", "use", "run", "fire", "test"]
        let page = { (n: Int) in
            "TRAIL STOVE MANUAL\nNever \(verbs[n - 1]) it inside a closed tent.\n"
                + "Step \(n): the burner needs a full canister and the valve turned\nslowly to the left until it hisses.\n"
                + "Keep spare fuel well away from the flame.\nTrail Stove Manual · March 2026 · \(n)"
        }
        let pages = (1...6).map(page)
        let running = DocumentReader.runningLines(pages)
        #expect(running.contains("TRAIL STOVE MANUAL"))
        let text = DocumentReader.pagesToText(pages[0...0], running: running)
        #expect(text.contains("Never light it inside a closed tent."))
        #expect(text.contains("Step 1: the burner needs a full canister and the valve turned"))
        #expect(!text.contains("TRAIL STOVE") && !text.contains("March"))
        #expect(DocumentReader.pagesToText(["IGNITION SYSTEM\nPress the button."], running: [])
            == "## Ignition System\n\nPress the button.")
    }

    @Test func readsATextPDF() async throws {
        let folder = tempFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Stove manual.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { ctx in
            for n in 1...2 {
                ctx.beginPage()
                ("Page \(n). To light the stove, open the fuel valve a quarter turn and press the igniter. "
                    + "Keep the flame low while the burner warms up.")
                    .draw(in: CGRect(x: 50, y: 50, width: 500, height: 600),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        let doc = try await DocumentReader.read(url)
        #expect(doc.title == "Stove manual")
        #expect(doc.sections.count == 1)
        #expect(doc.sections[0].text.contains("fuel valve"))
    }

    @Test func readsAPhotoOfAPage() async throws {
        let folder = tempFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 500)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 500))
            "Close the valve before changing the canister.".draw(
                at: CGPoint(x: 40, y: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor.black])
        }
        let url = folder.appending(path: "page.png")
        try #require(image.pngData()).write(to: url)
        let doc = try await DocumentReader.read(url)
        #expect(doc.sections.first?.text.localizedCaseInsensitiveContains("canister") == true)
    }

    @Test func refusesUnsupportedFiles() async throws {
        let folder = tempFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "archive.zip")
        try Data([0x50, 0x4B, 3, 4]).write(to: url)
        await #expect(throws: DocumentReader.ReadError.self) { try await DocumentReader.read(url) }
    }
}

/// Opening a hit at the part of the article it came from.
struct ArticleFocusTests {
    private func filler(_ topic: String, _ n: Int) -> String {
        (1...n).map { "Paragraph \($0) about \(topic), with enough words to fill out a normal line of text." }
            .joined(separator: "\n\n")
    }

    @Test func narrowsToTheSectionHoldingThePassage() {
        let body = "## Drowning\n\n\(filler("drowning", 30))\n\n## Lightning Injuries\n\n\(filler("lightning", 20))"
            + "\n\n### Types\n\n\(filler("injury types", 4))\n\n## Dental Problems\n\n\(filler("teeth", 30))"
        let passage = "Paragraph 3 about lightning, with enough words to fill out a normal line of text.\n\n"
            + "Paragraph 4 about lightning, with enough words to fill out a normal line of text."
        let f = ArticleFocus.make(body: body, passage: passage)
        #expect(f.heading == "Lightning Injuries")
        #expect(f.before.hasPrefix("## Lightning Injuries"))
        #expect(f.match == passage)
        #expect(f.after.contains("injury types"))  // its own sub-section comes along
        #expect(!(f.before + f.after).contains("teeth") && !(f.before + f.after).contains("drowning"))
        // The whole article, with the same passage marked.
        let whole = ArticleFocus.make(body: body, passage: passage, narrow: false)
        #expect(whole.isWhole && whole.match == passage && whole.after.contains("teeth"))
    }

    @Test func smallSectionsWidenAndShortArticlesStayWhole() {
        let body = "## Lightning Injuries\n\n\(filler("lightning", 40))\n\n### Signs\n\nBurns.\n\n## Dental Problems\n\n"
            + filler("teeth", 40)
        #expect(ArticleFocus.make(body: body, passage: "Burns.").heading == "Lightning Injuries")
        let short = "## A\n\nOne.\n\n## B\n\nTwo."
        #expect(ArticleFocus.make(body: short, passage: "Two.").isWhole)
        #expect(ArticleFocus.make(body: body, passage: "Not in the article.").match.isEmpty)
    }
}

/// PDFs without bookmarks, split at their own table of contents.
struct ContentsSectionsTests {
    @Test func splitsAtContentsEntries() {
        let body = { (topic: String) in
            (1...12).map { "Sentence \($0) on \(topic) care in the field, written out at full length." }
                .joined(separator: "\n")
        }
        var pages = ["TABLE OF CONTENTS\nChapter 8 Environmental Medicine\nDrowning ............\n"
                     + "Lightning Injuries ..........\nChapter 9 Micromedics\nEar/Eye/Nose Problems .......\n"
                     + "Dental Problems ...........\n142\n143\n150\n152"]
        pages.append("Chapter 8\nENVIRONMENTAL MEDICINE\nDrowning\nLightning Injuries\nAn introduction to the chapter.")
        pages.append("DROWNING\n" + body("drowning"))
        pages.append("LIGHTNING INJURIES\n" + body("lightning"))
        pages.append(body("lightning strike"))
        pages.append("Eye/Ear/Nose Problems\n" + body("eye") + "\nDental Problems\n" + body("tooth"))
        let sections = DocumentReader.sections(pages: pages, marks: [], title: "WFR manual")
        #expect(sections.map(\.title) == ["Drowning (Environmental Medicine)", "Lightning Injuries (Environmental Medicine)",
                                          "Ear/Eye/Nose Problems (Micromedics)", "Dental Problems (Micromedics)"])
        let lightning = sections[1].text
        #expect(lightning.contains("lightning strike care") && !lightning.contains("tooth") && !lightning.contains("eye care"))
        #expect(!sections.contains { $0.text.contains("....") })
    }
}
