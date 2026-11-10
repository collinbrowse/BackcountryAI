import SwiftUI

/// The Guide tab's shelves: the library grouped the way people think about trouble outside,
/// with Wilderness First Responder-style first aid up front.
struct GuideCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let topics: [Topic]

    static let all: [GuideCollection] = [firstAid, environment, lost, camp, wildlife, vehicle]

    static let firstAid = GuideCollection(
        id: "wfr", title: "Wilderness first aid", subtitle: "WFR-style: assess, treat, decide to evacuate",
        symbol: "cross.case.fill", tint: Theme.danger, topics: [
            Topic(id: "assess", title: "Patient assessment", symbol: "stethoscope", tint: Theme.danger,
                  question: "How do I assess an injured person in the backcountry? Walk me through scene safety, the primary survey and what to check next.",
                  terms: "patient assessment airway breathing circulation"),
            Topic(id: "bleed", title: "Bleeding & wounds", symbol: "drop.fill", tint: Theme.danger,
                  question: "How do I stop bleeding and clean and dress a wound in the backcountry?",
                  terms: "bleeding wound tourniquet"),
            Topic(id: "shock", title: "Shock", symbol: "waveform.path.ecg", tint: Theme.danger,
                  question: "What are the signs of shock and how do I treat someone for it far from help?",
                  terms: "shock"),
            Topic(id: "fracture", title: "Fractures & sprains", symbol: "figure.fall", tint: Theme.sun,
                  question: "Someone may have a sprain or broken bone. How do I splint it and move them?",
                  terms: "fracture splint sprain"),
            Topic(id: "head", title: "Head & spine", symbol: "brain.head.profile", tint: Theme.danger,
                  question: "Someone hit their head or may have a spine injury. What should I watch for and do?",
                  terms: "head injury concussion spine"),
            Topic(id: "burns", title: "Burns", symbol: "flame.fill", tint: Theme.danger,
                  question: "Someone got burned by a campfire or stove. How do I treat the burn?",
                  terms: "burn"),
            Topic(id: "allergy", title: "Allergies", symbol: "allergens", tint: Theme.danger,
                  question: "Someone has swelling, hives and trouble breathing after a sting or food. What do I do?",
                  terms: "anaphylaxis allergic reaction epinephrine"),
            Topic(id: "cpr", title: "CPR & choking", symbol: "heart.fill", tint: Theme.danger,
                  question: "Someone isn't breathing or is choking. Walk me through CPR and choking first aid.",
                  terms: "cpr choking"),
            Topic(id: "bites", title: "Bites & stings", symbol: "ant.fill", tint: Theme.moss,
                  question: "How do I treat snake bites, insect stings and tick bites?",
                  terms: "bite sting"),
        ])

    static let environment = GuideCollection(
        id: "env", title: "Weather & environment", subtitle: "Cold, heat, altitude and storms",
        symbol: "cloud.sun.fill", tint: Theme.sky, topics: [
            Topic(id: "hypo", title: "Hypothermia", symbol: "thermometer.snowflake", tint: Theme.sky,
                  question: "Someone is shivering hard, slurring and confused in the cold. How do I treat hypothermia?",
                  terms: "hypothermia"),
            Topic(id: "frost", title: "Frostbite", symbol: "snowflake", tint: Theme.sky,
                  question: "Toes or fingers are white, hard and numb after the cold. How do I treat frostbite?",
                  terms: "frostbite"),
            Topic(id: "heat", title: "Heat illness", symbol: "sun.max.fill", tint: Theme.sun,
                  question: "Someone is dizzy, nauseous and overheated. Is it heat exhaustion or heat stroke, and what do I do?",
                  terms: "heat stroke exhaustion"),
            Topic(id: "altitude", title: "Altitude sickness", symbol: "mountain.2.fill", tint: Theme.sky,
                  question: "Someone has a headache and nausea at high altitude. Is it altitude sickness, and what should we do?",
                  terms: "altitude sickness"),
            Topic(id: "lightning", title: "Lightning", symbol: "cloud.bolt.fill", tint: Theme.sun,
                  question: "A thunderstorm is coming and I'm exposed on a trail. How do I stay safe from lightning?",
                  terms: "lightning thunderstorm"),
            Topic(id: "dehydration", title: "Dehydration", symbol: "drop.degreesign", tint: Theme.sky,
                  question: "How do I tell if someone is dehydrated and how do I treat it?",
                  terms: "dehydration"),
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
