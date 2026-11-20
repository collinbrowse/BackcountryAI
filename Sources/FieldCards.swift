import SwiftUI

/// How the quick reference cards look. Their words are in FieldCardData.swift.
extension FieldCard {
    /// The quick cards that go with a Guide topic, the main one first. None for a topic without one.
    static func forTopic(_ id: String) -> [FieldCard] {
        (topicCards[id] ?? []).compactMap { card(id: $0) }
    }

    private static let topicCards: [String: [String]] = [
        "cpr": ["cpr"], "choking": ["choking"], "bleed": ["bleeding"], "shock": ["shock"], "wounds": ["wounds"],
        "burns": ["burns"], "sprain": ["sprain"], "fracture": ["fracture"], "spine": ["spine"], "head": ["head"],
        "chest": ["chest"], "stroke": ["stroke"], "seizure": ["seizure"], "sugar": ["lowbloodsugar"],
        "asthma": ["asthma"], "allergy": ["anaphylaxis"], "stomach": ["diarrhea"],
        "dehydration": ["dehydration"], "heat": ["heat"], "hypo": ["hypothermia"], "frost": ["frostbite"],
        "altitude": ["altitude"], "bites": ["snakebite", "tick", "animalbite"], "coldwater": ["coldwater"],
        "lightning": ["lightning", "thunderstorm"],
        "eye": ["eye"], "tooth": ["tooth"], "blister": ["blister"],
        "snake": ["snakebite"], "tick": ["tick"],
    ]

    var icon: String { Self.looks[id]?.0 ?? areaLook.0 }
    var tint: Color { Self.looks[id]?.1 ?? areaLook.1 }

    private var areaLook: (String, Color) {
        switch area {
        case .medical: ("cross.case", Theme.moss)
        case .survival: ("tent.fill", Theme.accent)
        case .weather: ("cloud.bolt", Theme.sky)
        case .water: ("drop.halffull", Theme.sky)
        case .wildlife: ("pawprint.fill", Theme.moss)
        case .vehicle: ("car.fill", Theme.inkSoft)
        case .gear: ("wrench.and.screwdriver.fill", Theme.inkSoft)
        case .pets: ("pawprint.fill", Theme.moss)
        }
    }

    private static let looks: [String: (String, Color)] = [
        "cpr": ("heart.text.square", Theme.danger),
        "bleeding": ("drop.fill", Theme.danger),
        "shock": ("waveform.path.ecg", Theme.danger),
        "anaphylaxis": ("allergens", Theme.danger),
        "hypothermia": ("thermometer.snowflake", Theme.sky),
        "frostbite": ("snowflake", Theme.sky),
        "heat": ("sun.max.trianglebadge.exclamationmark", Theme.sun),
        "altitude": ("mountain.2", Theme.sky),
        "head": ("brain.head.profile", Theme.pine),
        "spine": ("figure.fall", Theme.pine),
        "fracture": ("bandage", Theme.moss),
        "wounds": ("cross.case", Theme.moss),
        "burns": ("flame", Theme.sun),
        "lightning": ("cloud.bolt", Theme.sun),
        "chest": ("heart", Theme.danger),
        "lost": ("location.slash.fill", Theme.accent),
        "thunderstorm": ("cloud.bolt.rain.fill", Theme.sky),
        "flashflood": ("water.waves", Theme.sky),
        "bear": ("pawprint.fill", Theme.moss),
        "foodstorage": ("bag.fill", Theme.moss),
        "lion": ("cat.fill", Theme.sun),
        "snakebite": ("lizard.fill", Theme.moss),
        "tick": ("ladybug.fill", Theme.danger),
        "blister": ("bandage.fill", Theme.moss),
        "rivercrossing": ("figure.hiking", Theme.sky),
        "coldwater": ("snowflake", Theme.sky),
        "wildfire": ("flame.fill", Theme.danger),
        "signaling": ("light.beacon.max.fill", Theme.danger),
        "nightout": ("tent.fill", Theme.moss),
        "wetfire": ("flame", Theme.sun),
        "carbonmonoxide": ("aqi.medium", Theme.danger),
        "vehiclestuck": ("snowflake.road.lane", Theme.inkSoft),
        "stove": ("flame.circle", Theme.sun),
        "dehydration": ("drop.degreesign", Theme.sky),
        "avalanche": ("mountain.2.fill", Theme.sky),
        "phonebattery": ("battery.25percent", Theme.inkSoft),
        "dog": ("dog.fill", Theme.moss),
        "sprain": ("figure.fall", Theme.sun),
        "eye": ("eye.fill", Theme.moss),
        "tooth": ("mouth.fill", Theme.moss),
        "choking": ("lungs.fill", Theme.danger),
        "seizure": ("brain", Theme.danger),
        "stroke": ("brain.head.profile", Theme.danger),
        "lowbloodsugar": ("drop.fill", Theme.sun),
        "asthma": ("lungs", Theme.sky),
        "childbirth": ("figure.2.and.child.holdinghands", Theme.danger),
        "tornado": ("tornado", Theme.sky),
        "smallengine": ("engine.combustion.fill", Theme.inkSoft),
    ]
}

/// One quick card: recognize, treat, evacuate if. Readable at a glance with gloves on.
struct FieldCardBody: View {
    let card: FieldCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(card.headings.recognize, "eye.fill", Theme.ink, card.recognize, numbered: false)
            section(card.headings.treat, "hand.raised.fill", Theme.accentDeep, card.treat, numbered: true)
            section(card.headings.avoid, "xmark.octagon.fill", Theme.inkSoft, card.avoid, numbered: false)
            section(card.headings.evacuate, "arrow.up.forward.circle.fill", Theme.danger, card.evacuateIf, numbered: false)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ icon: String, _ color: Color, _ items: [String], numbered: Bool) -> some View {
        if !items.isEmpty { sectionCard(title, icon, color, items, numbered: numbered) }
    }

    private func sectionCard(_ title: String, _ icon: String, _ color: Color, _ items: [String], numbered: Bool) -> some View {
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
