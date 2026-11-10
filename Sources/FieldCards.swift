import SwiftUI

/// Quick reference cards that work with no AI and almost no battery.
/// Content is general wilderness first-aid guidance written for this app. It must be reviewed by a qualified
/// wilderness medicine instructor before release. Each card links to library searches for the source manuals.
struct FieldCard: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    let recognize: [String]
    let treat: [String]
    let evacuateIf: [String]
    let searches: [String]   // library queries for the source material

    /// The quick card that goes with a Guide topic, if there is one.
    static func forTopic(_ id: String) -> FieldCard? {
        let map = ["bleed": "bleeding", "shock": "shock", "fracture": "fracture", "head": "head", "burns": "burns",
                   "allergy": "anaphylaxis", "cpr": "cpr", "hypo": "hypothermia", "frost": "frostbite", "heat": "heat",
                   "altitude": "altitude", "lightning": "lightning", "bites": nil, "assess": nil]
        guard let key = map[id] ?? nil else { return nil }
        return all.first { $0.id == key }
    }

    static let all: [FieldCard] = [
        FieldCard(id: "cpr", title: "CPR", icon: "heart.text.square", tint: Theme.danger,
            recognize: ["Unresponsive and not breathing normally (gasping doesn't count).",
                        "Check for no more than 10 seconds."],
            treat: ["Make sure the scene is safe. Send for help or trigger SOS if you can.",
                    "Start chest compressions: center of chest, at least 5 cm (2 in) deep, 100–120 per minute.",
                    "If trained, give 2 rescue breaths after every 30 compressions.",
                    "Hypothermia, lightning and cold-water drowning: keep going longer than usual. These patients can survive prolonged CPR.",
                    "Far from help with no response after about 30 minutes of CPR, stopping is generally accepted (except in the cases above)."],
            evacuateIf: ["Anyone who needed CPR or rescue breaths: evacuate urgently."],
            searches: ["cardiopulmonary resuscitation", "rescue breathing first aid"]),

        FieldCard(id: "bleeding", title: "Severe bleeding", icon: "drop.fill", tint: Theme.danger,
            recognize: ["Blood spurting or pooling, or soaking through dressings."],
            treat: ["Press hard directly on the wound with gauze or cloth. Hold for at least 10 minutes without peeking.",
                    "Pack deep wounds tightly with gauze, then press.",
                    "Arm or leg still bleeding through pressure: apply a tourniquet 5–8 cm (2–3 in) above the wound, not over a joint. Tighten until the bleeding stops. Write down the time.",
                    "Don't loosen or remove a tourniquet in the field.",
                    "Treat for shock and keep them warm."],
            evacuateIf: ["A tourniquet was used, bleeding isn't controlled, or there are signs of shock: urgently."],
            searches: ["tourniquet application", "control severe bleeding wound packing"]),

        FieldCard(id: "shock", title: "Shock", icon: "waveform.path.ecg", tint: Theme.danger,
            recognize: ["Rising heart rate, fast shallow breathing.",
                        "Pale, cool, clammy skin. Thirst, anxiety, then confusion.",
                        "Level of responsiveness dropping."],
            treat: ["Fix the cause first: stop bleeding, treat anaphylaxis.",
                    "Lay them flat, insulate from the ground, keep them warm.",
                    "Reassure them and keep them still.",
                    "Give only small sips of water, and only if fully alert."],
            evacuateIf: ["Any signs of shock: urgently."],
            searches: ["hypovolemic shock first aid", "shock signs treatment"]),

        FieldCard(id: "anaphylaxis", title: "Allergic reaction", icon: "allergens", tint: Theme.danger,
            recognize: ["After a sting, food or medicine: hives or swelling plus trouble breathing, wheezing or a tight throat.",
                        "Or faintness, vomiting, pale and clammy skin."],
            treat: ["Give epinephrine (auto-injector into the outer thigh) right away. Don't wait for it to get worse.",
                    "If not improving after 5–15 minutes and a second dose is available, give it.",
                    "Sit them up if breathing is hard. Lay them flat if they feel faint.",
                    "An antihistamine can help with itching and hives but does not replace epinephrine."],
            evacuateIf: ["Anyone who needed epinephrine: urgently. Symptoms can come back hours later."],
            searches: ["anaphylaxis epinephrine", "allergic reaction bee sting"]),

        FieldCard(id: "hypothermia", title: "Hypothermia", icon: "thermometer.snowflake", tint: Theme.sky,
            recognize: ["Mild: shivering, cold, clumsy, mumbling, poor judgment.",
                        "Severe: shivering stops, confused, drowsy, then unresponsive."],
            treat: ["Get them out of wind and wet. Replace wet clothes with dry ones.",
                    "Insulate from the ground and wrap them: sleeping bag, then a waterproof layer (a hypothermia wrap).",
                    "Put warm bottles or heat packs on the chest, armpits and back, with cloth between them and the skin.",
                    "Give warm, sweet drinks and food only if they're alert and can swallow.",
                    "Severe: handle gently and keep them horizontal. Check for a pulse for up to a minute before starting CPR."],
            evacuateIf: ["Not shivering, confused, or not rewarming: urgently.",
                         "Mild and fully rewarmed with food and dry gear: they may be able to continue."],
            searches: ["hypothermia treatment cold weather", "hypothermia wrap rewarming"]),

        FieldCard(id: "frostbite", title: "Frostbite", icon: "snowflake", tint: Theme.sky,
            recognize: ["Frostnip: numb and pale, but the skin is soft and recovers fully when warmed.",
                        "Frostbite: white, gray or waxy, hard and numb."],
            treat: ["Treat hypothermia first.",
                    "Frostnip: warm with skin-to-skin contact (armpit, belly). Don't rub.",
                    "Only thaw frostbite if it won't freeze again. Refreezing does more damage.",
                    "If you can thaw: water at 37–39 °C (99–102 °F) for about 30 minutes, until the skin is soft and color returns.",
                    "Pad and protect thawed tissue. Don't pop blisters. Ibuprofen helps with pain if they can take it.",
                    "Walking on frozen feet may be needed to get out. Avoid walking on them once they've thawed."],
            evacuateIf: ["Any frostbite beyond frostnip: evacuate. Urgently for large areas or with hypothermia."],
            searches: ["frostbite rewarming", "cold weather injuries frostbite"]),

        FieldCard(id: "heat", title: "Heat illness", icon: "sun.max.trianglebadge.exclamationmark", tint: Theme.sun,
            recognize: ["Heat exhaustion: heavy sweating, weakness, headache, nausea. Thinking normally.",
                        "Heat stroke: confusion, odd behavior or collapse with a hot body. They may still be sweating.",
                        "Low sodium: confusion after drinking lots of plain water with little food or salt."],
            treat: ["Heat exhaustion: rest in shade, cool them, give fluids with electrolytes and salty food.",
                    "Heat stroke is an emergency: cool them immediately and hard. Cold-water immersion is best. Otherwise soak them and fan, with cold packs on the neck, armpits and groin.",
                    "Suspected low sodium: don't push more plain water. Salty food helps if they're alert."],
            evacuateIf: ["Heat stroke or any confusion: urgently."],
            searches: ["heat stroke cooling", "heat injury prevention treatment", "hyponatremia exercise"]),

        FieldCard(id: "altitude", title: "Altitude illness", icon: "mountain.2", tint: Theme.sky,
            recognize: ["Mild (AMS): headache plus nausea, fatigue or poor sleep after going higher.",
                        "Brain swelling (HACE): stumbling (heel-to-toe walk test), confusion, drowsiness.",
                        "Lung fluid (HAPE): breathless at rest, cough, can't keep up."],
            treat: ["AMS: don't go higher. Rest and drink. Go down if it gets worse.",
                    "HACE or HAPE: go down now, at least 300–1,000 m (1,000–3,000 ft). Give oxygen if you have it. Keep them warm and limit their exertion."],
            evacuateIf: ["HACE or HAPE: urgently, by going down."],
            searches: ["acute mountain sickness", "high altitude pulmonary edema", "high altitude cerebral edema"]),

        FieldCard(id: "head", title: "Head injury", icon: "brain.head.profile", tint: Theme.pine,
            recognize: ["Red flags: knocked out, getting less responsive, worsening headache, repeated vomiting, confusion or memory loss, seizure, unequal pupils, fluid from the nose or ears, bruising around the eyes or behind the ears."],
            treat: ["With a big fall or impact, assume a spine injury too.",
                    "Check level of responsiveness every 15 minutes and write it down (use Vitals).",
                    "Keep them warm. If they vomit, roll them onto their side keeping the spine in line."],
            evacuateIf: ["Any red flag: urgently.",
                         "Brief knockout with a full recovery: evacuate and monitor for 24 hours."],
            searches: ["traumatic brain injury signs", "concussion head injury first aid"]),

        FieldCard(id: "spine", title: "Spine injury", icon: "figure.fall", tint: Theme.pine,
            recognize: ["A big mechanism: a fall from height, a high-speed crash, a dive, a heavy blow to the head."],
            treat: ["Hold the head in line with the body and keep them still.",
                    "Move them only to protect them from danger or the cold, using a log roll with helpers.",
                    "Insulate them from the ground.",
                    "Trained responders use a focused spine assessment. Only rule out a spine injury if you've been trained to, and the patient is fully alert and sober, has no distracting injury, has no spine pain or tenderness, and has normal feeling and movement in hands and feet."],
            evacuateIf: ["Numbness, tingling or weakness: urgently.",
                         "Spine injury not ruled out: evacuate with spine protection."],
            searches: ["spinal injury immobilization", "log roll spine"]),

        FieldCard(id: "fracture", title: "Fractures", icon: "bandage", tint: Theme.moss,
            recognize: ["Deformity, point tenderness, swelling, grating, can't bear weight or use the limb."],
            treat: ["Check circulation, sensation and movement past the injury, before and after splinting.",
                    "Cover open wounds first.",
                    "Splint to include the joints above and below a broken bone (or the bones above and below an injured joint). Pad well.",
                    "If trained, gently straighten an angled long-bone fracture to restore circulation.",
                    "Sprains: rest, cold, compression, elevation. Check whether they can use it before moving on."],
            evacuateIf: ["Open fracture, suspected thigh-bone (femur) or pelvis fracture, or poor circulation past the injury: urgently.",
                         "Other suspected fractures: non-urgent."],
            searches: ["splinting fractures improvised", "sprain ankle first aid"]),

        FieldCard(id: "wounds", title: "Wounds", icon: "cross.case", tint: Theme.moss,
            recognize: ["Signs of infection: spreading redness, heat, swelling, pus, red streaks, fever."],
            treat: ["Control the bleeding first.",
                    "Clean with plenty of clean water under pressure (a bag with a pinhole works). Remove debris.",
                    "Cover with a clean dressing and change it daily. Don't tightly close dirty wounds.",
                    "Impaled object: don't remove it. Stabilize it in place."],
            evacuateIf: ["Deep, gaping, over a joint, an animal bite, an impaled object, or spreading infection: evacuate."],
            searches: ["wound irrigation cleaning", "wound infection signs"]),

        FieldCard(id: "burns", title: "Burns", icon: "flame", tint: Theme.sun,
            recognize: ["Red and painful (superficial), blisters (partial thickness), white, leathery or charred (full thickness).",
                        "Airway burns: singed nostrils, soot around the mouth, hoarse voice."],
            treat: ["Stop the burning. Cool with cool (not icy) water for 10–20 minutes.",
                    "Remove rings and watches before swelling starts.",
                    "Cover loosely with a clean, dry dressing. Don't pop blisters.",
                    "Watch for hypothermia, especially with large burns."],
            evacuateIf: ["Airway burns: urgently.",
                         "Burns to the face, hands, feet or genitals, burns all the way around a limb, or large or deep burns: evacuate."],
            searches: ["burn first aid cooling", "burns classification treatment"]),

        FieldCard(id: "lightning", title: "Lightning", icon: "cloud.bolt", tint: Theme.sun,
            recognize: ["Strikes can cause cardiac arrest, burns, confusion and hearing or vision problems."],
            treat: ["Victims are safe to touch.",
                    "With several victims, help the ones who appear dead first (CPR). Those still moving will usually survive.",
                    "Move everyone off ridges and summits. Spread out."],
            evacuateIf: ["Everyone who was struck."],
            searches: ["lightning safety injuries", "lightning strike first aid"]),

        FieldCard(id: "chest", title: "Chest pain", icon: "heart", tint: Theme.danger,
            recognize: ["Possible heart attack: pressure or squeezing in the chest, pain spreading to the arm, jaw or back, sweating, shortness of breath, nausea."],
            treat: ["Stop all exertion. Rest in the most comfortable position, often sitting.",
                    "Chewable aspirin (162–325 mg) if they aren't allergic and have no bleeding problems.",
                    "Don't let them walk out."],
            evacuateIf: ["Suspected heart attack: urgently, carried out if possible."],
            searches: ["heart attack symptoms aspirin", "chest pain first aid"]),
    ]
}

/// One quick card: recognize, treat, evacuate if. Readable at a glance with gloves on.
struct FieldCardBody: View {
    let card: FieldCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Recognize", "eye.fill", Theme.ink, card.recognize, numbered: false)
            section("Treat", "hand.raised.fill", Theme.accentDeep, card.treat, numbered: true)
            section("Evacuate if", "arrow.up.forward.circle.fill", Theme.danger, card.evacuateIf, numbered: false)
        }
    }

    private func section(_ title: String, _ icon: String, _ color: Color, _ items: [String], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.subheadline.weight(.bold)).foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if numbered {
                        Text("\(i + 1)").font(.caption.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Theme.accentGradient, in: .circle)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
                    } else {
                        Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6).offset(y: -2)
                    }
                    Text(item).font(.callout).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }
}

struct FieldCardView: View {
    let card: FieldCard
    var search: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: card.icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(card.tint.gradient, in: .rect(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick card").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(Theme.inkSoft)
                        Text(card.title).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Theme.ink)
                    }
                }
                FieldCardBody(card: card)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Read the source manuals").sectionLabel()
                    FlowLayout {
                        ForEach(card.searches, id: \.self) { q in
                            Button { search(q) } label: { SuggestionChip(title: q.capitalized, symbol: "magnifyingglass") }
                                .buttonStyle(SquishyButtonStyle(scale: 0.94))
                        }
                    }
                }
                FieldDisclaimer()
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FieldDisclaimer: View {
    var body: some View {
        Label("General wilderness first-aid guidance. It is not a substitute for training such as a WFR "
              + "course. If you can reach help (911, or SOS by satellite), do.", systemImage: "info.circle")
            .font(.footnote).foregroundStyle(Theme.inkSoft)
    }
}
