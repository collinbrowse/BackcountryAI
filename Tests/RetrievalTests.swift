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
                      "truck is dead this morning", "My camp stove won't light. How do I fix it?",
                      "My friend's truck won't start and just clicks"])
    func brokenThingsAreTroubleshooting(_ q: String) {
        #expect(Retrieval.Kind.guess(q) == .troubleshoot)
    }

    @Test(arguments: ["How do I treat a blister?", "I'm lost in the backcountry. What should I do first?",
                      "What is giardia?"])
    func otherQuestionsAreNot(_ q: String) {
        #expect(Retrieval.Kind.guess(q) != .troubleshoot)
    }

    // "Broken" and "isn't … heat" are in the fault patterns; a body is not a machine.
    @Test(arguments: ["How do I splint a broken leg in the backcountry?",
                      "I think I sprained my ankle hiking. How do I tell if it is broken and how do I splint it?",
                      "He isn't breathing right after working in the heat all day",
                      "My dog is not running or eating since the hike"])
    func injuriesAreNotTroubleshooting(_ q: String) {
        #expect(Retrieval.Kind.decide(question: q, model: .troubleshoot) == .howTo)
    }

    // They know what is wrong and want the repair: steps, not a list of causes and a question back.
    @Test(arguments: ["How do I repair a broken tent pole in the field?", "How do I patch a flat bike tire on the trail?",
                      "How do I fix a leak in my inflatable sleeping pad?", "How do I replace the spark plug on my chainsaw?"])
    func repairsTheyAskedHowToDoAreHowTo(_ q: String) {
        #expect(Retrieval.Kind.decide(question: q, model: .troubleshoot) == .howTo)
    }

    // The planner says FIX for all sorts of things. It is believed when gear is named…
    @Test(arguments: ["My handheld Baofeng isn't picking anything up on the repeater I programmed.",
                      "The outboard on my jon boat keeps dying when I give it throttle."])
    func theModelIsBelievedAboutGear(_ q: String) {
        #expect(Retrieval.Kind.guess(q) != .troubleshoot)
        #expect(Retrieval.Kind.decide(question: q, model: .troubleshoot) == .troubleshoot)
        #expect(Retrieval.Kind.decide(question: q, model: .howTo) == .howTo)
    }

    // …and not otherwise.
    @Test(arguments: ["Someone cut their arm badly and it is bleeding a lot. What do I do?",
                      "A power line is down in my front yard. What should I do?",
                      "The water is off and the toilet won't flush. What can I do for a toilet?"])
    func theModelIsNotBelievedWithoutGear(_ q: String) {
        #expect(Retrieval.Kind.decide(question: q, model: .troubleshoot) == .howTo)
    }

    @Test func aFollowUpIsTroubleshootingOnlyInsideATroubleshootingConversation() {
        let catches = "It's electric start and it cranks fine, it just won't catch."
        #expect(Retrieval.Kind.decide(question: catches, model: .troubleshoot, previous: .troubleshoot, isFollowUp: true)
                == .troubleshoot)
        let lighter = "I've got a lighter but no fire starters or cotton balls."
        #expect(Retrieval.Kind.decide(question: lighter, model: .troubleshoot, previous: .howTo, isFollowUp: true)
                == .howTo)
        // The words still win in a follow-up.
        #expect(Retrieval.Kind.decide(question: "Now the stove won't light at all", model: .howTo, previous: .howTo,
                                      isFollowUp: true) == .troubleshoot)
    }

    @Test func theModelsOtherLabelsStand() {
        #expect(Retrieval.Kind.decide(question: "How long do I boil water?", model: .fact) == .fact)
        #expect(Retrieval.Kind.decide(question: "How long do I boil water?", model: nil) == .howTo)
    }
}

/// Replies Apple's model really gave to the planning prompt, old format and new.
struct PlanParsingTests {
    private func searches(_ reply: String) -> [String] { Retrieval.parsePlan(reply)?.searches ?? ["<chat>"] }

    @Test func readsTheLabelledLinesItIsAskedFor() {
        let plan = Retrieval.parsePlan("""
            KIND: HOWTO
            SEARCH: hypothermia confusion treatment
            SEARCH: cold stress disorientation care
            SEARCH: frostbite disorientation body temperature
            """)
        #expect(plan?.kind == .howTo)
        #expect(plan?.searches == ["hypothermia confusion treatment", "cold stress disorientation care",
                                   "frostbite disorientation body temperature"])
    }

    @Test func smallTalkHasNoPlan() {
        #expect(Retrieval.parsePlan("CHAT") == nil)
        #expect(Retrieval.parsePlan(" Chat.\n") == nil)
    }

    @Test func aLabelAloneHasNoSearches() {
        let plan = Retrieval.parsePlan("FACT")
        #expect(plan?.kind == .fact)
        #expect(plan?.searches == [])
    }

    @Test func aLabelRunIntoTheSearchesIsSplitOff() {
        let plan = Retrieval.parsePlan("FACT freezer temperature, perishable food, power outage")
        #expect(plan?.kind == .fact)
        #expect(plan?.searches == ["freezer temperature", "perishable food", "power outage"])
        let fix = Retrieval.parsePlan("FIX. Battery connection\nbattery connection\nalternator issue")
        #expect(fix?.kind == .troubleshoot)
        #expect(fix?.searches == ["battery connection", "alternator issue"])
        #expect(searches("FACT: perishable food time\nFACT: temperature stability storage") ==
                ["perishable food time", "temperature stability storage"])
    }

    @Test func anInventedLabelIsNotSearchedFor() {
        #expect(searches("FIXTURE\ngarage generator safety\ngas generator ventilation") ==
                ["garage generator safety", "gas generator ventilation"])
        #expect(searches("TOOL\nspark plug chainsaw replacement") == ["spark plug chainsaw replacement"])
        // Two words in capitals are a search like any other.
        #expect(searches("ELECTRICAL HAZARD.\npower line downed yard") == ["electrical hazard", "power line downed yard"])
    }

    @Test func wordsAboutSearchingAreDropped() {
        #expect(searches("Keyword searches:\nHand burn first aid treatment\nMinor burn stove injury care") ==
                ["hand burn first aid treatment", "minor burn stove injury care"])
        #expect(searches("Injury blister hiking. Search for:\npainful sore foot wound") ==
                ["injury blister hiking", "painful sore foot wound"])
        #expect(searches("FIX. SEARCH: \"add oil to snowmobile engine") == ["add oil to snowmobile engine"])
        #expect(searches("injury bleeding arm. medical name: laceration") == ["injury bleeding arm laceration"])
        #expect(searches("**Keyword searches:**\n\n1. navigation no GPS\n2. trail navigation no map") ==
                ["navigation no gps", "trail navigation no map"])
    }

    @Test func numberedListsAndSentencesAreTidied() {
        let plan = Retrieval.parsePlan("FACT.\n\n1. Hypothermia symptoms confusion shivering\n2. Cold stress disorientation")
        #expect(plan?.kind == .fact)
        #expect(plan?.searches == ["hypothermia symptoms confusion shivering", "cold stress disorientation"])
        // A whole sentence is not a search.
        #expect(searches("FIRST AID ASTHMA ATTACK. SEARCH FOR: emergency inhaler alternative. RELAXATION ASTHMA RELIEF. "
                         + "SEARCH FOR: calm breathing techniques.") == [])
    }

    @Test func keepsAtMostThree() {
        #expect(searches("SEARCH: a b\nSEARCH: c d\nSEARCH: e f\nSEARCH: g h").count == 3)
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

    @Test func followUpsCarryWhatTheySaidNotWhatScoutSaid() {
        let p = Retrieval.prompt(question: "I don't have a map", sources: [],
                                 history: [.init(question: "I'm lost", answer: "Use your map.\n1. Unfold it.")])
        #expect(p.contains("Earlier they said: I'm lost"))
        #expect(p.contains("follow-up in the same situation"))
        #expect(!p.contains("Use your map"))
        #expect(!p.contains("Ask:"))
    }

    @Test func aQuestionAboutTheLastAnswerGetsThatAnswerWhole() {
        let answer = "Boil it.\n1. Fill the pot.\n2. Bring it to a rolling boil for one minute.\n3. Let it cool."
        let p = Retrieval.prompt(question: "Explain step 2 more", sources: [],
                                 history: [.init(question: "Is this creek safe?", answer: answer)])
        #expect(p.contains("Earlier they said: Is this creek safe?"))
        #expect(p.contains("Your last answer, which they are asking about:\n" + answer))
        #expect(p.contains("follow-up about that answer"))
    }

    @Test func aLongLastAnswerIsShortenedByWholeLines() {
        let steps = (1...30).map { "\($0). Do the thing numbered \($0), carefully and completely, then check it." }
        let shown = Retrieval.wholeLines(steps.joined(separator: "\n"), upTo: 300)
        #expect(shown.count <= 300)
        #expect(shown.hasSuffix("then check it."))
        #expect(shown.split(separator: "\n").count < 30)
        #expect(Retrieval.wholeLines(String(repeating: "x", count: 900), upTo: 300).count == 900)
    }
}

struct FollowUpTests {
    @Test(arguments: ["Explain step 1 more", "What if that doesn't work?", "why?",
                      "What do you mean by a rolling boil", "can you explain the second step", "Why not ice?"])
    func questionsAboutTheLastAnswer(_ q: String) {
        #expect(Retrieval.asksAboutLastAnswer(q))
    }

    @Test(arguments: ["Tell me more", "tell me more.", "Anything else?", "what else", "More details please", "go on"])
    func requestsForMoreOnTheSameSubject(_ q: String) {
        #expect(Retrieval.asksForMore(q))
        #expect(!Retrieval.asksAboutLastAnswer(q))
    }

    @Test(arguments: ["What gear helps?", "Tell me more about how to treat the blister on my heel so I can hike",
                      "What else could cause a snowmobile to crank but not start in the cold?"])
    func fullQuestionsAreNotRequestsForMore(_ q: String) {
        #expect(!Retrieval.asksForMore(q))
    }

    @Test func aFollowUpIsSearchedWithTheLastMessageThatDescribesTheSituation() {
        let burn = Retrieval.Turn(question: "I burned my forearm on the camp stove.", answer: "Cool it.")
        let chip = Retrieval.Turn(question: "Explain step 1 more", answer: "Hold it under water.")
        #expect(Retrieval.situation("What should I watch out for?", history: [burn, chip])
                == "I burned my forearm on the camp stove. What should I watch out for?")
        #expect(Retrieval.situation("What should I watch out for?", history: [burn])
                == "I burned my forearm on the camp stove. What should I watch out for?")
        #expect(Retrieval.situation("How do I treat a burn?", history: []) == nil)
    }

    @Test(arguments: ["I don't have a map or a compass, just my phone with no signal.",
                      "It's electric start and it cranks fine, it just won't catch.",
                      "He's stopped shivering and he's slurring his words now.", "What gear helps?",
                      "What if it gets worse?", "Should we evacuate?", "What do I tell 911?",
                      "What should I watch out for?", "I'm at about 9,000 feet. Does that change how long I boil it?",
                      "Why is my stove sputtering when the canister is cold and nearly empty?"])
    func newInformationAboutTheSituation(_ q: String) {
        #expect(!Retrieval.asksAboutLastAnswer(q))
    }
}

struct CarriesOnTests {
    static let earlier = [Retrieval.Turn(question: "My stove won't light", answer: "1. Check the fuel.")]

    @Test(arguments: ["How do I get a fire going in the rain?",
                      "What's the best way to cross a river safely?",
                      "How do I stay warm when it's below freezing?",
                      "How can I purify water without a filter?"])
    func aQuestionOfItsOwnStartsOver(_ q: String) {
        #expect(Retrieval.standsAlone(q))
        #expect(!Retrieval.carriesOn(q, history: Self.earlier))
    }

    @Test(arguments: ["I don't have a map or a compass, just my phone with no signal.",
                      "What can I use to wrap it?",
                      "How do I keep him warm?",
                      "How do I do that with one hand?",
                      "How do I fix it?",
                      "What if it gets worse?",
                      "There's fresh gas in it and the kill switch is up. What next?",
                      "How to clean it"])
    func moreAboutTheSituationCarriesOn(_ q: String) {
        #expect(!Retrieval.standsAlone(q))
        #expect(Retrieval.carriesOn(q, history: Self.earlier))
    }

    @Test func theFirstMessageCarriesNothingOn() {
        #expect(!Retrieval.carriesOn("What can I use to wrap it?", history: []))
    }
}

struct InstructionsTests {
    @Test func appleIsAskedForTheWholeProcedureAndShownOne() {
        let text = Retrieval.instructions(for: .stopsEarly)
        #expect(text.contains("complete procedure"))
        #expect(text.contains("5. Check inside the tire"))
        #expect(!text.contains("Two to four steps"))
        #expect(!text.contains("{steps}"))
    }

    @Test func qwenIsToldWhereToStop() {
        let text = Retrieval.instructions(for: .runsLong)
        #expect(text.contains("never more than five"))
        #expect(!text.contains("bike tube"))
        #expect(!text.contains("{steps}"))
    }

    // Asked for the whole procedure in a follow-up, Apple's model wrote the last answer's steps again.
    @Test func aFollowUpIsAskedTheShortWayByBoth() {
        let text = Retrieval.instructions(for: .stopsEarly, followUp: true)
        #expect(text == Retrieval.instructions(for: .runsLong, followUp: true))
        #expect(text == Retrieval.instructions(for: .runsLong))
        #expect(text.contains("never more than five") && !text.contains("bike tube"))
        // An emergency is always the whole procedure.
        let urgent = Retrieval.instructions(for: .stopsEarly, emergency: true, followUp: true)
        #expect(urgent.contains("complete procedure") && urgent.contains("5. Check inside the tire"))
    }

    @Test func aDoseTheLibraryCoversIsGivenOnlyAsTheExcerptsStateIt() {
        let plain = Retrieval.instructions(for: .runsLong)
        let dose = Retrieval.instructions(for: .runsLong, stakes: .dose)
        #expect(!plain.contains("{care}") && !plain.contains("in the article's own numbers"))
        #expect(dose.contains("instead of making it up. Give a dose, a maximum or a timing only if an article states it"))
        #expect(Retrieval.instructions(for: .stopsEarly, stakes: .identify).contains("You can't identify a plant"))
        #expect(Retrieval.instructions(for: .runsLong, stakes: .medical) == plain)
    }

    @Test func bothShareEverythingElse() {
        for habit in [StepHabit.stopsEarly, .runsLong] {
            let text = Retrieval.instructions(for: habit)
            #expect(text.hasPrefix("You are Scout"))
            #expect(text.contains("Open with one sentence that answers the question."))
            #expect(text.contains("Stop after the last step"))
        }
    }

    @Test func enginesSayHowTheyWrite() {
        #expect(MockEngine(pieces: []).stepHabit == .runsLong)
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

/// Library.search's rules for the answer's search, on the demo library the screenshots use (real articles).
struct LibrarySearchTests {
    static func demo() throws -> Library {
        let fixtures = try #require(Bundle.main.url(forResource: "ScreenshotFixtures", withExtension: nil))
        return try Library(folder: fixtures.appending(path: "Library"))
    }

    static let asked = "How can I signal for help in the wilderness with a whistle or a mirror?"

    @Test func anArticleGivesOnePassageUnlessAskedForMore() throws {
        let lib = try Self.demo()
        let one = lib.search(Self.asked, limit: 10)
        #expect(!one.isEmpty && Set(one.map(\.docID)).count == one.count)
        let two = lib.search(Self.asked, limit: 10, perArticle: 2)
        #expect(Set(two.map(\.id)).count == two.count)
        #expect(Dictionary(grouping: two, by: \.docID).values.map(\.count).max() == 2)
    }

    @Test func aWholePassageEndsOnASentence() {
        let long = String(repeating: "One sentence here. ", count: 100)
        let cut = Library.whole(long, upTo: 200)
        #expect(cut.count <= 202 && cut.hasSuffix("here. …"))
        #expect(Library.whole("Short.", upTo: 200) == "Short.")
    }

    @Test func aForumThreadIsShownByItsBestAnswer() throws {
        let lib = try Self.demo()
        // The words of a thread's question find the question: it repeats them, and the answers don't.
        let hits = lib.search("What are good knots to know for camping and backpacking?", limit: 3,
                              maxChars: 1_500, whole: true)
        let question = try #require(hits.first { $0.sourceKey.hasPrefix("se-") && $0.text.hasPrefix("Question") })
        let shown = lib.bestAnswer(for: question, maxChars: 1_500)
        #expect(shown.docID == question.docID && shown.id > question.id)
        #expect(shown.text.hasPrefix("Answer"))
        #expect(shown.title == question.title)
        // An answer stays as it is, and so does anything that isn't a forum thread.
        #expect(lib.bestAnswer(for: shown, maxChars: 1_500).id == shown.id)
        let other = try #require(lib.search("hypothermia shivering", limit: 10).first { !$0.sourceKey.hasPrefix("se-") })
        #expect(lib.bestAnswer(for: other, maxChars: 1_500).id == other.id)
    }

    @Test func candidatesAreWholePassagesTwoAnArticleAndAnswersNotQuestions() throws {
        let lib = try Self.demo()
        let found = Retrieval.candidates(question: Self.asked, searches: ["signal mirror", "whistle blasts rescue"],
                                         library: lib)
        #expect(found.count > 3 && found.count <= 10)
        #expect(Set(found.map(\.id)).count == found.count)
        #expect(Dictionary(grouping: found, by: \.docID).values.allSatisfy { $0.count <= Retrieval.passagesPerArticle })
        #expect(found.allSatisfy { $0.text.count <= Retrieval.excerptCharacters + 2 })
        #expect(found.contains { $0.sourceKey.hasPrefix("se-") })
        #expect(!found.contains { $0.sourceKey.hasPrefix("se-") && $0.text.hasPrefix("Question") })
    }
}

/// The ranker orders candidates by what search knows about them, and keeps the ones worth an answer's attention.
struct RankerTests {
    static func candidate(_ id: Int64, key: String = "survival-manuals", text: String, place: Int, words: [String],
                          dense: Int? = nil) -> Retrieval.Candidate {
        let p = Passage(id: id, docID: id, title: "Title \(id)", source: "s", sourceKey: key, official: false, text: text)
        return Retrieval.Candidate(passage: p, signals: Retrieval.Signals(
            position: place, of: 20, keywordPlaces: dense == nil ? [] : [place], keywordSearches: 4, perSearch: 12,
            densePlace: dense, denseCount: 16, coverage: dense == nil ? 0 : 1, words: words, passage: p, isSecond: false))
    }

    @Test func aPassageWithTheQuestionsWordsComesBeforeOneWithout() {
        let words = ["splint", "broken", "leg"]
        let off = Self.candidate(1, key: "se-cooking", text: "How long to rest a roast before carving.", place: 0, words: words)
        let on = Self.candidate(2, text: "To splint a broken leg, pad the splint and tie it above and below the break.",
                                place: 9, words: words, dense: 0)
        let ordered = Retrieval.Ranker.ordered([off, on])
        #expect(ordered.map(\.passage.id) == [2, 1])
        #expect(Retrieval.Ranker.value(on) > Retrieval.Ranker.minimum)
        #expect(Retrieval.Ranker.value(off) < Retrieval.Ranker.minimum)
        // Only what is worth having is kept, unless meaning search didn't run and the scores can't say.
        #expect(Retrieval.Ranker.keep(ordered).map(\.passage.id) == [2])
        #expect(Retrieval.Ranker.keep(ordered, cutoff: false).map(\.passage.id) == [2, 1])
    }

    @Test func signalsAreNamedAndWeighedOneForOne() {
        let c = Self.candidate(1, text: "x", place: 0, words: ["x"])
        #expect(c.signals.values.count == Retrieval.Signals.names.count)
        #expect(Retrieval.Ranker.weights?.count == Retrieval.Signals.names.count)
        #expect(c.signals.values.allSatisfy { (0...1).contains($0) })
    }

    @Test func thePersonsOwnDocumentGetsAHeadStart() {
        let words = ["filter", "cartridge"]
        let theirs = Self.candidate(1, key: Library.minePrefix + "manual", text: "Replace the filter cartridge yearly.",
                                    place: 3, words: words, dense: 4)
        let library = Self.candidate(2, key: "se-diy", text: "Replace the filter cartridge yearly.", place: 3,
                                     words: words, dense: 4)
        #expect(Retrieval.Ranker.value(theirs) > Retrieval.Ranker.value(library))
    }
}
