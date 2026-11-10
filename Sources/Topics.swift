import SwiftUI

/// One-tap starting points. Each asks a question phrased the way the guide answers best:
/// a situation, not a keyword.
struct Topic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let question: String

    static let urgent: [Topic] = [
        Topic(id: "bleeding", title: "Heavy bleeding", symbol: "drop.fill", tint: Theme.danger,
              question: "Someone is bleeding heavily from a wound. What do I do right now to stop it?"),
        Topic(id: "hypothermia", title: "Hypothermia", symbol: "thermometer.snowflake", tint: Theme.sky,
              question: "Someone is shivering hard, slurring and confused in the cold. How do I treat hypothermia?"),
        Topic(id: "frostbite", title: "Frostbite", symbol: "snowflake", tint: Theme.sky,
              question: "Toes or fingers are white, hard and numb after the cold. How do I treat frostbite?"),
        Topic(id: "burn", title: "Burns", symbol: "flame.fill", tint: Theme.ember,
              question: "Someone got burned by a campfire or stove. How do I treat the burn?"),
        Topic(id: "fracture", title: "Sprain or break", symbol: "figure.fall", tint: Theme.gold,
              question: "Someone hurt their ankle or leg and may have a sprain or broken bone. How do I splint it and move them?"),
        Topic(id: "allergy", title: "Allergic reaction", symbol: "allergens", tint: Theme.danger,
              question: "Someone has swelling, hives and trouble breathing after a sting or food. What do I do?"),
        Topic(id: "snake", title: "Snakebite", symbol: "lizard.fill", tint: Theme.moss,
              question: "Someone was bitten by a snake. What should I do and not do?"),
        Topic(id: "heat", title: "Heat illness", symbol: "sun.max.fill", tint: Theme.gold,
              question: "Someone is dizzy, nauseous and overheated on a hot day. Is it heat exhaustion or heat stroke, and what do I do?"),
    ]

    static let camp: [Topic] = [
        Topic(id: "lost", title: "I'm lost", symbol: "location.slash.fill", tint: Theme.ember,
              question: "I'm lost in the backcountry. What should I do first?"),
        Topic(id: "water", title: "Safe water", symbol: "drop.halffull", tint: Theme.sky,
              question: "How do I make water from a stream or lake safe to drink?"),
        Topic(id: "fire", title: "Start a fire", symbol: "flame", tint: Theme.ember,
              question: "How do I start a fire, even with damp wood?"),
        Topic(id: "shelter", title: "Shelter", symbol: "tent.fill", tint: Theme.moss,
              question: "I need to spend the night out unexpectedly. How do I build an emergency shelter and stay warm?"),
        Topic(id: "car", title: "Car won't start", symbol: "car.fill", tint: Theme.inkSoft,
              question: "My car won't start and just clicks. What can I check and fix on the spot?"),
        Topic(id: "storm", title: "Storm coming", symbol: "cloud.bolt.rain.fill", tint: Theme.sky,
              question: "A thunderstorm is coming and I'm exposed on a trail. How do I stay safe from lightning?"),
        Topic(id: "signal", title: "Signal for help", symbol: "light.beacon.max.fill", tint: Theme.danger,
              question: "How do I signal for rescue with what I have, day and night?"),
        Topic(id: "wildlife", title: "Bear encounter", symbol: "pawprint.fill", tint: Theme.moss,
              question: "I see a bear close by. What should I do?"),
    ]
}

/// Words that mean someone may be in danger. Answers to these lead with the SOS banner.
enum Urgency {
    static let words: [String] = ["bleed", "blood", "not breathing", "unconscious", "unresponsive", "cpr", "heart attack",
        "chest pain", "stroke", "seizure", "anaphyla", "can't breathe", "cant breathe", "trouble breathing", "choking",
        "hypothermi", "heat stroke", "snake", "overdose", "poison", "broken", "fracture", "head injury", "avalanche",
        "drown", "severe", "emergency", "dying", "allergic"]

    static func isUrgent(_ text: String) -> Bool {
        let t = text.lowercased()
        return words.contains { t.contains($0) }
    }
}
