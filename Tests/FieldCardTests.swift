import Foundation
import Testing
@testable import BackcountryAI

struct FieldCardTests {
    @Test func everyCardIsWholeAndHasItsOwnId() {
        let cards = FieldCard.all
        #expect(cards.count == FieldCard.firstAid.count + FieldCard.situations.count)
        #expect(cards.count == 52)
        #expect(Set(cards.map(\.id)).count == cards.count)
        for card in cards {
            #expect(!card.title.isEmpty && !card.recognize.isEmpty && card.treat.count >= 2, "\(card.id)")
            #expect(card.asks.count >= 8, "\(card.id) needs phrases to be found by")
            #expect(card.avoid.allSatisfy { $0.hasPrefix("Don't") }, "\(card.id)")
            // Short enough to be one source among others: the prompt has room for about 3,000 tokens.
            #expect(card.promptText.count < 1_400, "\(card.id) is \(card.promptText.count) characters")
        }
    }

    @Test func fieldModeStillListsTheFirstAidCards() {
        #expect(FieldCard.firstAid.count == 15)
        #expect(FieldCard.firstAid.allSatisfy { $0.area == .medical })
        #expect(FieldCard.forTopic("hypo")?.id == "hypothermia")
    }

    @Test func aCardReadsAsStepsForTheModel() throws {
        let card = try #require(FieldCard.card(id: "hypothermia"))
        let text = card.promptText
        #expect(text.hasPrefix("Recognize: Mild: shivering"))
        #expect(text.contains("\nTreat:\n1. Get them out of wind and wet."))
        #expect(text.contains("\nEvacuate if: "))
        let lost = try #require(FieldCard.card(id: "lost"))
        #expect(lost.promptText.hasPrefix("Know: "))
        #expect(lost.promptText.contains("\nDo:\n1. Stop as soon as you think you're lost."))
        #expect(lost.promptText.contains("\nDon't: Don't keep wandering"))
    }

    @Test func aCardIsASourceLikeAnyPassage() throws {
        let card = try #require(FieldCard.card(id: "bleeding"))
        let passage = card.passage
        #expect(passage.isCard && !passage.isMine && !passage.official)
        #expect(passage.source == "Scout field card")
        #expect(passage.id >= Library.mineIDBase * 2)
        #expect(FieldCard.card(passageID: passage.docID)?.id == "bleeding")
        #expect(FieldCard.card(passageID: 12) == nil)
        #expect(FieldCard.card(passageID: Library.mineIDBase + 3) == nil)
        // In the prompt it is one more numbered article.
        let p = Retrieval.prompt(question: "Someone is bleeding badly", sources: [passage], history: [])
        #expect(p.contains("[1] Severe bleeding (Scout field card)\nRecognize: Blood spurting"))
        // And it opens as an article, with the caution it carries everywhere.
        #expect(card.articleBody.contains("## Treat\n\n1. Press hard directly on the wound"))
        #expect(card.articleBody.hasSuffix(FieldCard.disclaimer))
    }
}

struct CardMatcherTests {
    @Test func theModelsAnswerIsReadAsYesOrNo() {
        #expect(CardMatcher.readConfirmation("YES.") == true)
        #expect(CardMatcher.readConfirmation(" no") == false)
        #expect(CardMatcher.readConfirmation("Yes, the card fits.") == true)
        #expect(CardMatcher.readConfirmation("I can't help with that.") == nil)
        #expect(CardMatcher.readConfirmation("") == nil)
    }

    @Test func theQuestionPutToTheModelNamesTheCardAndWhatCameBefore() throws {
        let card = try #require(FieldCard.card(id: "hypothermia"))
        let p = CardMatcher.confirmPrompt(card, question: "He's stopped shivering now", earlier: "My friend fell in a creek")
        #expect(p.hasPrefix("Earlier they said: My friend fell in a creek\nTheir message: He's stopped shivering now\n\n"))
        #expect(p.contains("Card: Hypothermia. Mild: shivering"))
        #expect(!CardMatcher.confirmPrompt(card, question: "q", earlier: nil).contains("Earlier"))
    }

    // Without the library's embedder (as here, in the simulator) a card is matched by shared words: rarely wrong,
    // and it finds only what is said in a card's own words.
    @Test func withoutTheEmbedderACardNeedsItsOwnWords() async {
        let said = await CardMatcher.match("my truck just clicks when I turn the key") { _, _, _ in nil }
        #expect(said.map(\.card.id) == ["vehiclestart"])
        let unrelated = await CardMatcher.match("How do I bake bread in a dutch oven?") { _, _, _ in true }
        #expect(unrelated.isEmpty)
        let inOtherWords = await CardMatcher.match("the pickup is being difficult this morning") { _, _, _ in true }
        #expect(inOtherWords.isEmpty)
    }

    @Test func aMessageNearerToWhatACardDoesNotAnswerIsANearMiss() throws {
        let heat = try #require(FieldCard.card(id: "heat"))
        #expect(CardMatcher.Match(card: heat, score: 0.8, nearest: 0.82, rival: 0.85).isNearMiss)
        #expect(!CardMatcher.Match(card: heat, score: 0.8, nearest: 0.82, rival: 0.74).isNearMiss)
        #expect(CardMatcher.whenClose == .none)
    }

    @Test func wordsAreComparedWithoutTheirEndings() {
        #expect(CardMatcher.words("He's bleeding and the bleeds won't stop") == ["he", "bleed", "bleed", "won't", "stop"])
    }
}
