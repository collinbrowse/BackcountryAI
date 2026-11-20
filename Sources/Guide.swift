import SwiftUI

/// The Guide tab's shelves: the library grouped the way people think about trouble outside. The four first-aid
/// shelves follow the chapters of a Wilderness First Responder course, in its order: assessment, life support and
/// injuries; medical problems; the environment; small problems. Each of their topics opens on its field card.
struct GuideCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let topics: [Topic]

    static let all: [GuideCollection] = [firstAid, medical, environment, small, lost, camp, wildlife, vehicle]

    static let firstAid = GuideCollection(
        id: "wfr", title: "Wilderness first aid", subtitle: "Assess, fix life threats, treat injuries",
        symbol: "cross.case.fill", tint: Theme.danger, topics: [
            Topic(id: "assess", title: "Patient assessment", symbol: "stethoscope", tint: Theme.danger,
                  question: "How do I assess an injured or sick person in the backcountry? Walk me through the scene size-up, the primary assessment and what to check next.",
                  terms: "patient assessment airway breathing circulation"),
            Topic(id: "cpr", title: "CPR", symbol: "heart.fill", tint: Theme.danger,
                  question: "Someone collapsed and isn't breathing. Walk me through CPR.",
                  terms: "cpr resuscitation"),
            Topic(id: "choking", title: "Choking", symbol: "lungs.fill", tint: Theme.danger,
                  question: "Someone is choking on food and can't speak or breathe. What do I do?",
                  terms: "choking airway obstruction"),
            Topic(id: "bleed", title: "Severe bleeding", symbol: "drop.fill", tint: Theme.danger,
                  question: "Someone is bleeding heavily from a wound. What do I do right now to stop it?",
                  terms: "bleeding tourniquet hemorrhage"),
            Topic(id: "shock", title: "Shock", symbol: "waveform.path.ecg", tint: Theme.danger,
                  question: "What are the signs of shock and how do I treat someone for it far from help?",
                  terms: "shock"),
            Topic(id: "wounds", title: "Wounds & infection", symbol: "cross.case", tint: Theme.moss,
                  question: "How do I clean and dress a deep cut in the backcountry, and how do I tell if it's infected?",
                  terms: "wound cleaning infection"),
            Topic(id: "burns", title: "Burns", symbol: "flame.fill", tint: Theme.danger,
                  question: "Someone got burned by a campfire or stove. How do I treat the burn?",
                  terms: "burn"),
            Topic(id: "sprain", title: "Sprains & strains", symbol: "figure.walk", tint: Theme.sun,
                  question: "Someone twisted their ankle on the trail and it's swelling. How do I treat a sprain and can they walk out?",
                  terms: "sprain strain ankle"),
            Topic(id: "fracture", title: "Fractures", symbol: "figure.fall", tint: Theme.sun,
                  question: "Someone may have a broken bone. How do I splint it and move them?",
                  terms: "fracture splint"),
            Topic(id: "spine", title: "Spine injury", symbol: "figure.stand", tint: Theme.danger,
                  question: "Someone fell and their neck or back hurts. How do I protect their spine and what should I watch for?",
                  terms: "spine spinal injury"),
            Topic(id: "head", title: "Head injury", symbol: "brain.head.profile", tint: Theme.danger,
                  question: "Someone hit their head. What should I watch for and do?",
                  terms: "head injury concussion"),
        ])

    static let medical = GuideCollection(
        id: "med", title: "Medical problems", subtitle: "Heart, stroke, breathing, allergy, diabetes",
        symbol: "stethoscope", tint: Theme.danger, topics: [
            Topic(id: "chest", title: "Chest pain", symbol: "heart", tint: Theme.danger,
                  question: "Someone has crushing chest pain and is sweating. Could it be a heart attack, and what do I do?",
                  terms: "chest pain heart attack"),
            Topic(id: "stroke", title: "Stroke", symbol: "brain.head.profile", tint: Theme.danger,
                  question: "Someone's face is drooping on one side and their speech is slurred. Is it a stroke, and what do I do?",
                  terms: "stroke"),
            Topic(id: "seizure", title: "Seizures", symbol: "brain", tint: Theme.danger,
                  question: "Someone is having a seizure. What do I do during it and after?",
                  terms: "seizure"),
            Topic(id: "sugar", title: "Diabetes & low sugar", symbol: "drop.fill", tint: Theme.sun,
                  question: "A diabetic in our group is shaky, sweaty and confused. How do I treat low blood sugar?",
                  terms: "hypoglycemia diabetes blood sugar"),
            Topic(id: "asthma", title: "Asthma", symbol: "lungs", tint: Theme.sky,
                  question: "Someone is having an asthma attack and wheezing badly. How do I help them?",
                  terms: "asthma attack"),
            Topic(id: "allergy", title: "Allergies", symbol: "allergens", tint: Theme.danger,
                  question: "Someone has swelling, hives and trouble breathing after a sting or food. What do I do?",
                  terms: "anaphylaxis allergic reaction epinephrine"),
            Topic(id: "stomach", title: "Diarrhea & stomach bugs", symbol: "cross.vial", tint: Theme.moss,
                  question: "Someone has diarrhea and cramps a few days into the trip. How do I treat it and when is it serious?",
                  terms: "diarrhea gastroenteritis giardia"),
        ])

    static let environment = GuideCollection(
        id: "env", title: "Weather & environment", subtitle: "Heat, cold, altitude, bites and water",
        symbol: "cloud.sun.fill", tint: Theme.sky, topics: [
            Topic(id: "dehydration", title: "Dehydration", symbol: "drop.degreesign", tint: Theme.sky,
                  question: "How do I tell if someone is dehydrated and how do I treat it?",
                  terms: "dehydration"),
            Topic(id: "heat", title: "Heat illness", symbol: "sun.max.fill", tint: Theme.sun,
                  question: "Someone is dizzy, nauseous and overheated. Is it heat exhaustion or heat stroke, and what do I do?",
                  terms: "heat stroke exhaustion"),
            Topic(id: "hypo", title: "Hypothermia", symbol: "thermometer.snowflake", tint: Theme.sky,
                  question: "Someone is shivering hard, slurring and confused in the cold. How do I treat hypothermia?",
                  terms: "hypothermia"),
            Topic(id: "frost", title: "Frostbite", symbol: "snowflake", tint: Theme.sky,
                  question: "Toes or fingers are white, hard and numb after the cold. How do I treat frostbite?",
                  terms: "frostbite"),
            Topic(id: "altitude", title: "Altitude sickness", symbol: "mountain.2.fill", tint: Theme.sky,
                  question: "Someone has a headache and nausea at high altitude. Is it altitude sickness, and what should we do?",
                  terms: "altitude sickness"),
            Topic(id: "bites", title: "Bites & stings", symbol: "ant.fill", tint: Theme.moss,
                  question: "How do I treat snake bites, insect stings and tick bites?",
                  terms: "bite sting"),
            Topic(id: "coldwater", title: "Cold water", symbol: "water.waves", tint: Theme.sky,
                  question: "Someone fell through the ice into cold water. How do we get them out, and what do we do after?",
                  terms: "cold water immersion drowning"),
            Topic(id: "lightning", title: "Lightning", symbol: "cloud.bolt.fill", tint: Theme.sun,
                  question: "A thunderstorm is coming and I'm exposed on a trail. How do I stay safe from lightning?",
                  terms: "lightning thunderstorm"),
        ])

    static let small = GuideCollection(
        id: "small", title: "Small problems", subtitle: "Eyes, teeth and blisters",
        symbol: "bandage.fill", tint: Theme.moss, topics: [
            Topic(id: "eye", title: "Something in the eye", symbol: "eye.fill", tint: Theme.moss,
                  question: "I have something in my eye and it won't come out. How do I get it out safely?",
                  terms: "eye injury foreign object"),
            Topic(id: "tooth", title: "Knocked-out tooth", symbol: "mouth.fill", tint: Theme.moss,
                  question: "Someone got a tooth knocked out. Can it be saved, and what do I do?",
                  terms: "tooth dental"),
            Topic(id: "blister", title: "Blisters", symbol: "bandage.fill", tint: Theme.moss,
                  question: "I have a hot spot turning into a blister on my heel. How do I treat it and keep hiking?",
                  terms: "blister"),
        ])

    static let lost = GuideCollection(
        id: "lost", title: "Lost & rescue", subtitle: "Find your way or get found",
        symbol: "location.north.circle.fill", tint: Theme.accent, topics: [
            Topic(id: "lost", title: "I'm lost", symbol: "location.slash.fill", tint: Theme.accent,
                  question: "I'm lost in the backcountry. What should I do first?", terms: "lost"),
            Topic(id: "nav", title: "Navigate without GPS", symbol: "safari.fill", tint: Theme.accent,
                  question: "How do I find direction and navigate without GPS, using a map, compass, the sun or stars?",
                  terms: "navigation compass map"),
            Topic(id: "signal", title: "Signal for help", symbol: "light.beacon.max.fill", tint: Theme.danger,
                  question: "How do I signal for rescue with what I have, day and night?", terms: "signal rescue"),
            Topic(id: "evac", title: "Evacuate or stay?", symbol: "figure.walk.motion", tint: Theme.accent,
                  question: "When should an injured person be evacuated, and when is it safer to stay and wait for help?",
                  terms: "evacuation rescue"),
        ])

    static let camp = GuideCollection(
        id: "camp", title: "Camp & survival", subtitle: "Water, fire, shelter, food",
        symbol: "tent.fill", tint: Theme.moss, topics: [
            Topic(id: "water", title: "Safe water", symbol: "drop.halffull", tint: Theme.sky,
                  question: "How do I make water from a stream or lake safe to drink?", terms: "purify water"),
            Topic(id: "fire", title: "Fire", symbol: "flame", tint: Theme.sun,
                  question: "How do I start a fire, even with damp wood?", terms: "fire wood"),
            Topic(id: "shelter", title: "Shelter", symbol: "tent.fill", tint: Theme.moss,
                  question: "I need to spend the night out unexpectedly. How do I build an emergency shelter and stay warm?",
                  terms: "shelter"),
            Topic(id: "food", title: "Food & foraging", symbol: "leaf.fill", tint: Theme.moss,
                  question: "How do I find safe food in the wild, and what should I never eat?", terms: "edible plants food"),
            Topic(id: "knots", title: "Knots", symbol: "lasso", tint: Theme.inkSoft,
                  question: "Which knots are most useful outdoors and how do I tie them?", terms: "knot"),
        ])

    static let wildlife = GuideCollection(
        id: "wild", title: "Wildlife", subtitle: "Bears, cats, snakes and ticks",
        symbol: "pawprint.fill", tint: Theme.moss, topics: [
            Topic(id: "bear", title: "Bears", symbol: "pawprint.fill", tint: Theme.moss,
                  question: "I see a bear close by. What should I do?", terms: "bear"),
            Topic(id: "lion", title: "Mountain lions", symbol: "cat.fill", tint: Theme.sun,
                  question: "What do I do if I see a mountain lion?", terms: "mountain lion cougar"),
            Topic(id: "snake", title: "Snakes", symbol: "lizard.fill", tint: Theme.moss,
                  question: "Someone was bitten by a snake. What should I do and not do?", terms: "snake"),
            Topic(id: "tick", title: "Ticks", symbol: "ladybug.fill", tint: Theme.danger,
                  question: "How do I remove a tick and watch for tick-borne illness?", terms: "tick"),
        ])

    static let vehicle = GuideCollection(
        id: "vehicle", title: "Vehicle & gear", subtitle: "Get rolling again",
        symbol: "car.fill", tint: Theme.inkSoft, topics: [
            Topic(id: "battery", title: "Car won't start", symbol: "car.fill", tint: Theme.inkSoft,
                  question: "My car won't start and just clicks. What can I check and fix on the spot?",
                  terms: "car battery start"),
            Topic(id: "tire", title: "Flat tire", symbol: "circle.circle", tint: Theme.inkSoft,
                  question: "How do I change or patch a flat tire on a dirt road?", terms: "tire flat"),
            Topic(id: "stuck", title: "Stuck in mud or snow", symbol: "snowflake.road.lane", tint: Theme.inkSoft,
                  question: "My car is stuck in mud or snow. How do I get it out?", terms: "stuck mud snow"),
            Topic(id: "gear", title: "Gear repair", symbol: "wrench.and.screwdriver.fill", tint: Theme.inkSoft,
                  question: "How can I repair a torn tent, broken pole or leaking stove in the field?",
                  terms: "repair"),
        ])
}
