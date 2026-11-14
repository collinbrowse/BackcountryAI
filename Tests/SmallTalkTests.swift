import Testing
@testable import BackcountryAI

struct SmallTalkTests {
    @Test(arguments: ["Hello", "hi scout!", "Thanks!", "thank you so much", "ok", "What can you do?", "Hey there",
                      "Good morning", "that worked"])
    func smallTalk(_ message: String) {
        #expect(SmallTalk.isObvious(message))
    }

    @Test(arguments: ["Hi, my friend rolled their ankle", "help my stove won't light", "ok what about kids?",
                      "thanks, but what if it gets worse?", "How do I purify water?", "hypothermia"])
    func questions(_ message: String) {
        #expect(!SmallTalk.isObvious(message))
    }
}

struct GeneralAnswerTests {
    @Test func labelIsDetectedAndStripped() {
        let text = "Not from the library: I don't have current weather for your area.\n1. Check the sky."
        #expect(AnswerBlock.isGeneral(text))
        let blocks = AnswerBlock.parse(text)
        #expect(blocks.first == .paragraph("I don't have current weather for your area."))
        #expect(!AnswerBlock.isGeneral("Boil it for one minute [1]."))
    }
}

struct ChatTopicTests {
    @Test func trimsAtAWordAndCleansUp() {
        #expect(ChatTopic.trim("\"Sprained ankle on the trail.\"") == "Sprained ankle on the trail")
        #expect(ChatTopic.trim("Title: snowmobile oil change") == "Snowmobile oil change")
        let long = ChatTopic.trim("Treating a deep cut on the lower leg far from the trailhead after a fall")
        #expect(long.count <= ChatTopic.maxLength)
        #expect(!long.hasSuffix(" "))
        #expect("Treating a deep cut on the lower leg far from the trailhead".hasPrefix(long))
    }
}
