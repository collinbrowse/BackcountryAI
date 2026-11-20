import Foundation

/// What a wrong answer to a message could cost, read from its words.
///
/// When the library has nothing for a question about gear, a vehicle or a skill, Scout answers from what the model
/// knows and says so ("not from the library"). It doesn't do that for anything about a body, and it doesn't state a
/// dose or say what a plant, mushroom or snake is unless one of its own field cards covers it: there it says so,
/// and what is safe to do instead (`Retrieval.declines`). Like the emergency line (`Urgency`), this is decided in code and not left to the
/// model's judgement.
enum Stakes: String, Sendable {
    /// How much of a medicine, how often, with what, for whom, or whether to take it at all. Not how to store
    /// one, and not drops of bleach in water: the water card and the government guides state those.
    case dose
    /// Whether a plant, berry, mushroom, snake, spider or water source is the safe kind.
    case identify
    /// Anything else about a body: an injury, an illness, a symptom.
    case medical
    /// Gear, vehicles, skills, weather, food storage, facts.
    case ordinary

    /// - Parameter earlier: what they said before, in a follow-up, so "how much can I give him?" keeps the
    ///   medicine named a message earlier.
    static func of(_ question: String, earlier: String? = nil) -> Stakes {
        let q = normal(question)
        let all = earlier.map { normal($0) + " " + q } ?? q
        if all.contains(medicine), q.contains(taking) || q.contains(amount) { return .dose }
        // "Is this one safe?" of something in front of them. "Which wild plants are edible?" and "how do I tell
        // if a mushroom is poisonous?" are questions the manuals answer.
        if q.contains(wildThing), q.contains(isItSafe), q.contains(pointing) { return .identify }
        if q.contains(drinkingIt), q.contains(oddWater) { return .identify }
        return isMedical(q) || (earlier.map { isMedical(normal($0)) } ?? false) && q.contains(/\b(he|she|him|her|it|they|them)\b/)
            ? .medical : .ordinary
    }

    /// Whether these excerpts are enough to answer from. A dose or an identification is answered only from a field
    /// card or the person's own document. Library excerpts aren't enough, even official ones: an excerpt from a
    /// medicine leaflet says the search found the medicine, not that it states this dose for this person, and
    /// telling the two apart takes reading. Left to answer 16 dose questions from library excerpts, Apple's
    /// model stated a dose in 15 and 6 of those were in no excerpt; of 10 identifications it made 5, none
    /// supported. Anything else medical needs some excerpt; everything else needs none.
    /// - Parameter keepsWarnings: whether the model that will answer carries a card's warnings into what it
    ///   writes (`LLMEngine.keepsWarnings`). With one that doesn't, a card is not enough for a dose: the reply
    ///   is the fixed one, with the card under it to read.
    func isCovered(by sources: [Passage], keepsWarnings: Bool = true) -> Bool {
        switch self {
        case .ordinary: true
        case .medical: !sources.isEmpty
        case .dose: sources.contains { $0.isMine || $0.isCard && keepsWarnings }
        case .identify: sources.contains { $0.isCard || $0.isMine }
        }
    }

    /// What Scout says in place of an answer when the library doesn't cover a question with these stakes. Fixed
    /// words: a small model told to decline writes a dose anyway about as often as not.
    /// - Parameter hasArticles: the library's closest articles are shown under the reply, for the person to read.
    func declining(emergency: Bool, hasArticles: Bool = false) -> String? {
        let help = emergency ? " If this is an emergency, call or text 911 or use SOS on a satellite messenger now." : ""
        let read = hasArticles ? "\nThe library's closest articles are below. Read what they say before you rely on them." : ""
        switch self {
        case .ordinary:
            return nil
        case .dose:
            return """
            I won't state a dose or say whether a medicine is safe for someone: I can't check it well enough to \
            be trusted with that.\(help)
            1. Read the label on the package: it gives the dose by age or weight and the most to take in a day.
            2. If the label doesn't cover this person, this animal or this mix of medicines, don't give it until \
            you can ask a pharmacist, a doctor or a vet.
            3. If too much may already have been taken, call Poison Control (1-800-222-1222 in the U.S.) or 911 \
            as soon as you have signal.\(read)
            """
        case .identify:
            return """
            I can't tell what that is from a description, and I won't guess whether it is safe.\(help)
            1. Don't eat it, drink it or handle it unless someone who knows the species or the source has \
            identified it for certain.
            2. If someone has already eaten it or been bitten, note the time, keep a photo or a sample, and get \
            help: Poison Control (1-800-222-1222 in the U.S.) or 911.\(read)
            """
        case .medical:
            return """
            I don't have a reliable source for that in the library, and I won't guess about someone's health.\(help)
            1. If it is getting worse, or they have trouble breathing, heavy bleeding, chest pain, confusion or \
            severe pain, treat it as an emergency and get help.
            2. Otherwise keep them resting, warm and drinking, write down what changed and when, and ask a doctor \
            or nurse line as soon as you have signal.
            """
        }
    }

    /// A line for the instructions when the library does cover the question: the model still mustn't reach
    /// past what the excerpts say. Nil for everything else.
    var care: String? {
        switch self {
        case .dose:
            "Give a dose, a maximum or a timing only if an article states it for this medicine and this kind of "
                + "person, in the article's own numbers. If the articles don't state it, say the library doesn't "
                + "give that dose and to follow the package label."
        case .identify:
            "You can't identify a plant, berry, mushroom, snake, spider or water source for certain from a "
                + "description: say so in your first sentence. Then give what the articles say about it and what "
                + "it can be confused with, and tell them not to eat, drink or handle it unless it has been "
                + "identified for certain."
        case .medical, .ordinary:
            nil
        }
    }

    // MARK: - Words

    private static func normal(_ text: String) -> String { text.lowercased().replacing(/[’‘]/, with: "'") }

    nonisolated(unsafe) private static let medicine = /\b(ibuprofen|advil|motrin|acetaminophen|paracetamol|tylenol|aspirin|naproxen|aleve|benadryl|diphenhydramine|loperamide|imodium|pepto\w*|bismuth|antihistamines?|cetirizine|zyrtec|loratadine|claritin|epi-?pens?|epinephrine|adrenaline|auto-?injectors?|insulin|glucagon|antibiotics?|amoxicillin|doxycycline|cipro\w*|azithromycin|penicillin|diamox|acetazolamide|dexamethasone|nifedipine|oxycodone|hydrocodone|codeine|tramadol|morphine|opioids?|painkillers?|pain ?relievers?|pain (pills?|meds?|medicine)|sleeping pills?|melatonin|antacids?|laxatives?|steroids?|prednisone|albuterol|inhalers?|nitroglycerin|blood thinners?|warfarin|lisinopril|antidepressants?|medicines?|medications?|meds|pills?|prescriptions?|oral rehydration (salts?|solution)|potassium iodide)\b/
    nonisolated(unsafe) private static let taking = /\b(take|takes|taking|took|taken|give|giving|gave|swallow\w*|inject\w*|stop|stopping|stopped|skip\w*|ran out|expired|work|mix\w*|combin\w*)\b/
    nonisolated(unsafe) private static let amount = /\b(dose|doses|dosage|dosing|how (much|many|often|long between)|the most|maximum|max|too much|overdos\w*|mg|milligrams?|ml|per (liter|litre|quart|gallon))\b/
    nonisolated(unsafe) private static let wildThing = /\b(berr(y|ies)|mushrooms?|toadstools?|fung(us|i)|plants?|shrubs?|vines?|weeds?|leaves|roots?|bulbs?|nuts?|seeds?|flowers?|bark|moss|lichen|seaweed|shellfish|mussels|clams|snakes?|spiders?|scorpions?|caterpillars?)\b/
    nonisolated(unsafe) private static let isItSafe = /\b(safe|edible|poisonous|toxic|venomous|dangerous|harmful|harmless|worried|worry)\b|\bcan (i|we|you|he|she|they) (eat|touch)\b|\b(what|which) (kind|type|species|sort) of\b|\bidentif\w+\b|\bwhat is (this|that)\b|\b(is|are) (it|this|that|they|these) (an?|some) \w+/
    nonisolated(unsafe) private static let pointing = /\b(this|these|that|those|it|its|they|them|i found|we found|i saw|we saw|i see|there's|there is|there are|came across|looks? like)\b/
    nonisolated(unsafe) private static let drinkingIt = /\b(safe|ok|okay|fine) to drink\b|\bcan (i|we) drink\b/
    nonisolated(unsafe) private static let oddWater = /\b(mine|tailings|metallic|oily|sheen|foam\w*|green|algae|bloom|smells?|tastes?|runoff|sewage|chemical\w*|rust\w*)\b/

    /// Words that are only said of a body.
    nonisolated(unsafe) private static let bodily = /\b(pain|painful|hurts?|hurting|aches?|aching|sore|swollen|swelling|swells?|bleed\w*|bruis\w*|rash|itch\w*|fever|vomit\w*|throwing up|threw up|nause\w*|diarrh\w*|constipat\w*|dizz\w*|faint\w*|numb|tingl\w*|infect\w*|pus|wound\w*|blister\w*|stung|bitten|sprain\w*|fractur\w*|dislocat\w*|concuss\w*|headache|migraine|cough\w*|wheez\w*|breathing|allerg\w*|hives|seizure\w*|pregnan\w*|cramps?|dehydrat\w*|hypotherm\w*|frostbit\w*|heat ?stroke|sunburn\w*|symptoms?|illness|injur\w*|first aid|appendi\w*|urine|pee|toenail|fingernail|splinter|leech|parasites?|giardia|rabies|tetanus|hiccups|kneecap|molar|tooth\w*|nosebleed|stitches|tourniquet|cpr|blood pressure|heart attack|my period|unconscious|unresponsive|passed out|choking|overdos\w*|poisoned|poisoning|feel(s|ing)? (sick|ill|faint|weak|dizzy|nauseous|awful|terrible)|shivering|slurring|confused|heart rate|pulse|splint\w*|ticks?|lyme|disease|asthma|inhalers?|labou?r|contractions|giving birth|childbirth|vertigo|(world|room|everything) (is )?spin\w*)\b/
    /// Words said of bodies and of things ("cut the wood", "burn the trash", "a drill bit"): they count with a
    /// part of the body.
    nonisolated(unsafe) private static let maybeBodily = /\b(burn\w*|cuts?|bit|bites?|sting\w*|scrape\w*|bump\w*|hook|spines?|thorns?|quills?|stuck|jammed|crawled|lodged|embedded|popped|red|white|raw|cracked|seized|locked|bug|pounding|throbbing|twisted|rolled|swell\w*|broken|something in)\b/
    nonisolated(unsafe) private static let bodyPart = /\b(hands?|fingers?|thumbs?|arms?|legs?|foot|feet|toes?|ankles?|knees?|thighs?|hips?|back|neck|shoulders?|elbows?|wrists?|head|face|eyes?|ears?|nose|lips?|mouth|jaw|throat|chest|stomach|belly|skin|scalp|gums?|paws?|paw pads?)\b/
    /// "Stroke" and "chest" also name engines and coolers.
    nonisolated(unsafe) private static let machine = /\b(two|2|four|4)[- ]stroke\b|\b(ice|tool) chest\b|\bchest (freezer|rig|strap|harness)\b/

    private static func isMedical(_ q: String) -> Bool {
        let text = q.replacing(machine, with: " ")
        return text.contains(bodily) || text.contains(/\bstroke\b/) && !q.contains(machine)
            || text.contains(maybeBodily) && text.contains(bodyPart)
    }
}

extension Retrieval {
    /// Scout's reply in place of an answer, when the question is one it mustn't answer from memory and the library
    /// doesn't cover it; nil when it should answer as usual (`Stakes`).
    /// - Parameter keepsWarnings: `LLMEngine.keepsWarnings` of the model that would write the answer. With one
    ///   that drops warnings, a question about a medicine that a field card covers gets the card's own words
    ///   (`quoting`) and not an answer written from it.
    static func declines(question: String, history: [Turn], sources: [Passage], keepsWarnings: Bool = true) -> String? {
        let stakes = Stakes.of(question, earlier: earlier(in: history))
        guard !stakes.isCovered(by: sources, keepsWarnings: keepsWarnings) else { return nil }
        let emergency = Urgency.needsHelpNow(question)
        if stakes == .dose, let card = sources.lazy.compactMap({ FieldCard.card(passageID: $0.id) }).first {
            return quoting(card, emergency: emergency)
        }
        return stakes.declining(emergency: emergency, hasArticles: !sources.isEmpty)
    }

    /// A field card's steps and warnings word for word, in place of an answer written from them.
    static func quoting(_ card: FieldCard, emergency: Bool) -> String {
        let help = emergency ? "If this is an emergency, call or text 911 or use SOS on a satellite messenger now.\n" : ""
        let steps = card.treat.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return help + "This is the \(card.title) field card, word for word. About a medicine I won't add to it.\n"
            + (steps + card.avoid).joined(separator: "\n") + "\nThe whole card is below."
    }
}
