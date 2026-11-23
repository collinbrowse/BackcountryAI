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

    // A dying engine and a broken pole are not emergencies; a broken leg still is.
    @Test func wordsSaidOfGearDontRaiseTheBanner() {
        #expect(!Urgency.isUrgent("The outboard on my jon boat keeps dying when I give it throttle."))
        #expect(!Urgency.isUrgent("How do I repair a broken tent pole in the field?"))
        #expect(Urgency.isUrgent("I think his leg is broken"))
        #expect(Urgency.isUrgent("My ankle might be broken"))
        #expect(Urgency.isUrgent("My friend is dying"))
        #expect(Urgency.isUrgent("Someone is having a severe allergic reaction to a bee sting. What do I do?"))
    }
}

/// `needsHelpNow` decides whether the answer itself says to call 911 (Retrieval.emergencyShape), so it has to be
/// right both ways. The questions are the test lists' own (library/*.tsv) and the app's topic buttons.
struct NeedsHelpNowTests {
    @Test(arguments: [
        "Someone cut their arm badly and it is bleeding a lot. What do I do?",
        "Someone is bleeding heavily from a wound. What do I do right now to stop it?",
        "Someone is shivering hard and acting confused after being out in the cold. What do I do?",
        "Someone is shivering hard, slurring and confused in the cold. How do I treat hypothermia?",
        "My friend is shivering and slurring words after we got soaked in a cold rain. We have a tent and stove. What now?",
        "He's stopped shivering and he's slurring his words now.",
        "Someone working in the heat is confused, very hot and has stopped sweating. What do I do?",
        "My hiking partner is dizzy and nauseous in the heat and has stopped sweating.",
        "A rattlesnake bit my friend's ankle on the trail. What should we do?",
        "Someone was bitten by a snake. What should I do and not do?",
        "Someone is having a severe allergic reaction to a bee sting. What do I do?",
        "Someone has swelling, hives and trouble breathing after a sting or food. What do I do?",
        "Someone is choking and can't breathe. What do I do?",
        "My friend hit his head skiing and seems confused. What should I watch for?",
        "A diabetic hiker is shaky and confused. What do I do?",
        "Someone is having an asthma attack and has no inhaler. What can we do?",
        "A woman is going into labor and we can't get to a hospital. What do I do?",
        "Someone is having a seizure. What do I do?",
        "She just dropped and her whole body is jerking",
        "Half his face is drooping and he can't lift his arm",
        "The baby is coming and we're two hours from the road",
        "A power line is down in my front yard. What should I do?",
        "A wildfire is getting close to our campsite. What should we do?",
        "I'm lost but have half a phone battery and no signal. What should I do?",
        "I think I’m lost on a trail in the woods and it's getting dark. What should I do?",
        "I am lost in the woods. Should I stay put or try to walk out?",
    ])
    func someoneIsInTroubleNow(_ question: String) {
        #expect(Urgency.needsHelpNow(question))
        #expect(Urgency.isUrgent(question))
    }

    @Test(arguments: [
        // Hurt, but not a call for rescue.
        "I burned my hand on the stove. How should I treat it?",
        "I burned my forearm on the camp stove. It's red and it really hurts.",
        "I spilled boiling water on my hand making dinner at camp. It's red and blistering.",
        "How do I treat early frostbite on my toes?",
        "I rolled my ankle on a rock 5 miles from the car. It's swollen but I can put some weight on it.",
        "I got something in my eye and it won't come out. What do I do?",
        "A dog bit me. Do I need to worry about rabies?",
        "My dog just got a face full of porcupine quills on a hike.",
        // Asking about a danger, not in one.
        "What are the signs of a stroke?",
        "What are the signs of a heart attack and what should I do?",
        "What are the signs of carbon monoxide poisoning and what should I do?",
        "How do I do CPR on an adult?",
        "What do I do if I fall through ice on a lake?",
        "What should I do if a flash flood comes while I'm in a canyon?",
        "What should I do if I meet a grizzly bear on the trail?",
        "What should I do if a mountain lion follows me?",
        "How do I know if a slope is likely to avalanche?",
        "How do I tell if a wild mushroom is poisonous?",
        "Is it safe to take ibuprofen that expired two years ago?",
        "What should I do if a tornado comes while we're camping?",
        "My rod tip keeps jerking but nothing is on the line",
        "The leaves on my tomato plants are drooping",
        // Danger where the move is to act, not to call (as the banner's word list already treats them).
        "A thunderstorm is coming and we are above treeline. What do we do?",
        "A black bear is walking toward our campsite and we have bear spray. What do we do?",
        // The word "emergency", and gear.
        "How much water should I store per person for an emergency?",
        "How do I build an emergency shelter for one night in the snow?",
        "The outboard on my jon boat keeps dying when I give it throttle.",
        "How do I repair a broken tent pole in the field?",
        "My truck won't start and just clicks. What do I check?",
        "I'm confused about which fuel my stove takes",
        "What if it gets worse?",
    ])
    func noOneNeedsRescuingYet(_ question: String) {
        #expect(!Urgency.needsHelpNow(question))
    }
}

struct EmergencyPromptTests {
    @Test func anEmergencyIsToldToTheModelAndNothingElseIs() {
        let bleeding = Retrieval.prompt(question: "Someone cut their arm badly and it is bleeding a lot. What do I do?",
                                        sources: [], history: [])
        #expect(bleeding.contains("This is an emergency."))
        let stove = Retrieval.prompt(question: "I burned my forearm on the camp stove. It's red and it really hurts.",
                                     sources: [], history: [])
        #expect(!stove.contains("emergency"))
        for habit in [StepHabit.stopsEarly, .runsLong] {
            let text = Retrieval.instructions(for: habit)
            #expect(text.contains("Never mention 911, SOS or emergency services unless the message says it is an emergency."))
            #expect(!text.contains("Not from the library"))
            #expect(!text.contains("{help}"))
            // In an emergency the same line says the opposite, and nothing tells the model never to.
            let urgent = Retrieval.instructions(for: habit, emergency: true)
            #expect(urgent.contains("make calling or texting 911, or using SOS on a satellite messenger, one of the first two steps"))
            #expect(!urgent.contains("Never mention 911"))
            #expect(!urgent.contains("{help}"))
        }
    }

    @Test func anEmergencyIsNotTroubleshooting() {
        let p = Retrieval.prompt(question: "He's unconscious next to the generator, which won't start", sources: [],
                                 history: [], kind: .troubleshoot)
        #expect(p.contains("This is an emergency."))
        #expect(!p.contains("Ask:"))
    }
}
