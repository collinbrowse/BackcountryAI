import Testing
@testable import BackcountryAI

/// The Model Lab's benchmark questions: which ones lead with the SOS banner.
struct UrgencyTests {
    @Test(arguments: [
        "Someone cut their arm badly and it is bleeding a lot. What do I do?",
        "My friend is shivering and slurring words after we got soaked in a cold rain. We have a tent and stove. What now?",
        "I'm lost but have half a phone battery and no signal. What should I do?",
    ])
    func emergencies(_ question: String) {
        #expect(Urgency.isUrgent(question))
    }

    @Test(arguments: [
        "Is the water from this standing pond safe to filter with my Kathryn be free filter?",
        "I only have a Sawyer Squeeze. Is that enough for river water downstream from a cattle ranch?",
        "I have a blister forming but still have 8 miles to hike. What should I do?",
        "How do I add oil on my snowmobile?",
        "My truck won't start and just clicks. What do I check?",
        "My jet boil won't light. How do I fix it?",
        "A black bear is walking toward our campsite and we have bear spray. What do we do?",
        "What should I do if a flash flood comes while I'm in a canyon?",
        "A thunderstorm is coming and we are above treeline. What do we do?",
        "How do I set a snare to catch small game?",
        "How do I tell if a wild mushroom is poisonous?",
        "Is it safe to take ibuprofen that expired two years ago?",
        "What is the difference between GMRS and FRS radios?",
        "I lost my lighter. How else can I start a fire?",
        "How do I cut firewood without an axe?",
    ])
    func notEmergencies(_ question: String) {
        #expect(!Urgency.isUrgent(question))
    }
}
