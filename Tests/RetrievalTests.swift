import Foundation
import Testing
@testable import BackcountryAI

struct ClarifyTests {
    @Test func turnsTheClosingQuestionIntoChoices() {
        let r = Clarify.split("Likely fuel or spark.\n1. Check the kill switch.\nAsk: Does the engine turn over? [Yes, it cranks | No, nothing | It just clicks]")
        #expect(r.choices == ["Yes, it cranks", "No, nothing", "It just clicks"])
        #expect(r.text.hasSuffix("Does the engine turn over?"))
        #expect(!r.text.contains("["))
    }

    @Test func hidesHalfWrittenOptionsWhileStreaming() {
        let r = Clarify.split("1. Check fuel.\nAsk: Does it crank? [Yes | N")
        #expect(r.choices.isEmpty)
        #expect(!r.text.contains("["))
    }

    @Test func leavesCitationsAndPlainAnswersAlone() {
        #expect(Clarify.split("Boil water for one minute [1].").text == "Boil water for one minute [1].")
        let r = Clarify.split("Ask: Is it a two-stroke [2]?")
        #expect(r.choices.isEmpty)
        #expect(r.text.contains("[2]"))
    }
}

struct QuestionKindTests {
    @Test(arguments: ["My snowmobile isn't starting", "the stove won't light", "Generator keeps stalling",
                      "truck is dead this morning"])
    func brokenThingsAreTroubleshooting(_ q: String) {
        #expect(Retrieval.Kind.guess(q) == .troubleshoot)
    }

    @Test(arguments: ["How do I treat a blister?", "I'm lost in the backcountry. What should I do first?",
                      "What is giardia?"])
    func otherQuestionsAreNot(_ q: String) {
        #expect(Retrieval.Kind.guess(q) != .troubleshoot)
    }
}

struct PromptTests {
    @Test func keepsTheirWordsApartFromArticles() {
        let source = Passage(id: 1, docID: 1, title: "Arctic Cat Snowmobile Choke Lever", source: "Appropedia",
                             sourceKey: "appropedia", official: false, text: "A replacement lever.")
        let p = Retrieval.prompt(question: "My snowmobile isn't starting", sources: [source], history: [],
                                 kind: .troubleshoot)
        let theirs = p.range(of: "WHAT THEY TOLD YOU")!.lowerBound
        let articles = p.range(of: "LIBRARY ARTICLES")!.lowerBound
        #expect(theirs < articles)
        #expect(p[theirs..<articles].contains("My snowmobile isn't starting"))
        #expect(!p[theirs..<articles].contains("Choke Lever"))
        #expect(p.contains("Ask:"))
        #expect(p.hasSuffix("Now answer their question: My snowmobile isn't starting"))
    }

    @Test func followUpsCarryEarlierTurnsAsContext() {
        let p = Retrieval.prompt(question: "I don't have a map", sources: [],
                                 history: [.init(question: "I'm lost", answer: "Use your map.")])
        #expect(p.contains("Earlier they asked: I'm lost"))
        #expect(p.contains("don't repeat"))
        #expect(!p.contains("Ask:"))
    }
}

struct VectorIndexTests {
    @Test func findsTheNearestVector() throws {
        var generator = SystemRandomNumberGenerator()
        let vectors = (0..<50).map { _ in (0..<64).map { _ in Float.random(in: -1...1, using: &generator) } }
        var codes = Data()
        for v in vectors { codes.append(contentsOf: VectorIndex.code(v)) }
        let url = FileManager.default.temporaryDirectory.appending(path: "vectors-\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try VectorIndex.write(to: url, modelID: "test", dimensions: 64, ids: (0..<50).map { Int64(100 + $0) }, codes: codes)
        let index = try VectorIndex(url: url)
        #expect(index.count == 50)
        #expect(index.modelID == "test")
        #expect(index.search(vectors[17], limit: 3).first?.id == 117)
    }
}

struct TranscriptTests {
    @Test func sharesTheWholeChatWithSources() {
        let source = Passage(id: 1, docID: 1, title: "Blisters", source: "NPS", sourceKey: "nps", official: true, text: "")
        let text = ChatTranscript.text(title: "Blister care", messages: [
            ChatMessage(role: .user, text: "How do I treat a blister?"),
            ChatMessage(role: .assistant, text: "Cover it [1].", sources: [source]),
            ChatMessage(role: .user, text: "And if it pops?"),
            ChatMessage(role: .assistant, text: "Clean it."),
        ])
        #expect(text.hasPrefix("Blister care"))
        #expect(text.contains("Q: How do I treat a blister?"))
        #expect(text.contains("[1] Blisters (NPS)"))
        #expect(text.contains("Q: And if it pops?"))
        #expect(text.contains("Scout: Clean it."))
    }
}
