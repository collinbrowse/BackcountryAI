import Foundation

/// Whether a message sounds like an emergency. Two answers, for two uses:
/// - `isUrgent`: someone may be in danger. Wide on purpose: it shows the SOS banner, which costs nothing when wrong.
/// - `needsHelpNow`: someone is hurt, sick or in danger right now. Narrow: it puts "call 911" into the answer
///   itself (`Retrieval.prompt`), where a false alarm reads as bad advice.
/// The answer model used to make the second call itself. Qwen told people to call 911 about a stove burn and a dog
/// with porcupine quills, and left it out of 3 of 7 real emergencies; told by the prompt, it got 7 of 7 and no
/// false alarms.
enum Urgency {
    static let words: [String] = ["bleed", "blood", "not breathing", "unconscious", "unresponsive", "cpr", "heart attack",
        "chest pain", "stroke", "seizure", "anaphyla", "can't breathe", "cant breathe", "trouble breathing", "choking",
        "hypothermi", "heat stroke", "snake", "overdose", "poisoned", "poisoning", "broken", "fracture", "head injury", "avalanche",
        "drown", "severe", "emergency", "dying", "allergic",
        // Emergencies described by what people see, not by name. Bears, storms and floods are left out on purpose:
        // there the first move is to act (back away, get off the ridge, climb), not to call.
        "slurr", "confused", "passed out", "fainted", "won't wake", "wont wake", "not waking",
        "cut their", "cut my", "cut his", "cut her", "deep cut", "badly cut", "burned", "badly burn",
        "fell off", "a bad fall", "took a fall", "fell from",
        "i'm lost", "im lost", "i am lost", "we're lost", "we are lost", "got lost", "are lost",
        "struck by lightning", "lightning hit", "convuls", "baby is coming"]

    /// Words in `words` that are said of things as often as of people: a dying engine, a broken tent pole, severe
    /// weather. They count only when the message is about someone.
    private static let alsoSaidOfThings: Set<String> = ["broken", "dying", "severe"]

    static func isUrgent(_ text: String) -> Bool {
        let t = text.lowercased()
        let someone = Retrieval.Kind.isAboutABody(text)
        return words.contains { t.contains($0) && (someone || !alsoSaidOfThings.contains($0)) } || needsHelpNow(text)
    }

    /// Someone is hurt, sick or in danger as they write: something is happening ("is bleeding", "has stopped
    /// sweating", "bit my friend"), not being asked about ("what are the signs of a stroke?", "what do I do if I
    /// fall through ice?"). Being lost counts, as it always has for the banner.
    static func needsHelpNow(_ text: String) -> Bool {
        let t = text.lowercased().replacing(/[’‘]/, with: "'")
        if lost.contains(where: { t.contains($0) }) { return true }
        // Bleeding that is going on, or a wound described as bad.
        if t.contains(/\b(is|are|it's|still|keeps?) bleeding\b|\bbleeding (a lot|badly|heavily|hard|out|everywhere)\b|\bwon't stop bleeding\b|\bspurting\b/) { return true }
        if t.contains(/\b(deep|bad|badly|severe|severely) (cut|gash|wound|burn)\w*\b|\bcut \w+ (\w+ )?(badly|deep|deeply|open)\b|\bbone (is )?(sticking|showing|poking)\b/) { return true }
        // Breathing and airway.
        if t.contains(/\b(not|isn't|aren't|stopped|can't|cant|cannot|trouble|difficulty|struggling to|hard to) breath(e|ing)\b|\bchoking\b/) { return true }
        if t.contains(/\b(throat|lips?|tongue|face|airway) (is |are )?(swelling|swollen|closing)\b|\btrouble swallowing\b|\banaphyla\w*/) { return true }
        // Not awake, or not themselves.
        if t.contains(/\bunconscious\b|\bunresponsive\b|\bpassed out\b|\bfainted\b|\bcollapsed\b|\b(won't|wont|isn't|not) (wake|waking|responding|responsive|moving)\b/) { return true }
        if t.contains(/(\b(is|are|seems?|acting|getting|and)\s+|,\s*)(confused|disoriented|incoherent)\b|\bslurr\w*/) { return true }
        if t.contains(/\bcan't (feel|move) (my|his|her|their) (legs?|arms?|feet|toes|fingers)\b/) { return true }
        // Something is happening to them now.
        if t.contains(/\bhaving an? (seizure|heart attack|stroke|asthma attack|(severe )?allergic reaction)\b|\b(is|are) seizing\b|\bchest pain\b/) { return true }
        if t.contains(/\b(face|mouth|smile) (is |looks )?(drooping|droopy|lopsided)\b|\bconvuls\w*|\b(body|arms|legs|limbs|he|she|they)('s| is| are| started| keeps?| won't stop) (jerking|twitching|shaking uncontrollably)\b/) { return true }
        if t.contains(/\bstopped (sweating|shivering)\b|\b(not|isn't|no longer) (sweating|shivering)\b/) { return true }
        if t.contains(/\b(snake|rattlesnake|rattler|copperhead|cottonmouth|viper)\b.{0,30}\b(bit|bite|bitten|struck)\b|\b(bit|bitten|struck) by an? (\w+ )?(snake|rattlesnake|rattler|copperhead|cottonmouth|viper)\b/) { return true }
        if t.contains(/\bgoing into labou?r\b|\bin labou?r\b|\bwater (just )?broke\b|\bbaby is (coming|crowning)\b/) { return true }
        if t.contains(/\boverdos\w*\b|\b(was|been|got|is) poisoned\b/) { return true }
        if t.contains(/\b(is|was|got|been|were) (drowning|buried|struck)\b|\bfell through (the |thin )?ice\b|\bstruck by lightning\b|\blightning (hit|struck)\b/) { return true }
        // Danger closing in.
        if t.contains(/\bpower line\b.{0,25}\bdown\b|\bdowned power line\b/) { return true }
        return t.contains(/\b(wild)?fire\b.{0,40}\b(getting close|closing in|coming (toward|at) us|surround\w*|trapped)\b/)
    }

    private static let lost = ["i'm lost", "im lost", "i am lost", "we're lost", "we are lost", "got lost", "are lost"]
}
