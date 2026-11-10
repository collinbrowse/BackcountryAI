import SwiftUI
import UIKit

/// Field mode: a WFR-style patient assessment, vitals log, SOAP note and quick cards.
/// Everything here works without the AI, so it costs almost no battery. Lives in the Guide tab.
struct FieldView: View {
    @Environment(FieldStore.self) private var field
    @Environment(Router.self) private var router
    @State private var searchQuery: SearchRequest?
    @State private var confirmDiscard = false

    struct SearchRequest: Identifiable { let query: String; var id: String { query } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                patientSection
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Quick cards").sectionLabel()
                        Spacer()
                        Text("No AI · almost no battery").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(FieldCard.all.enumerated()), id: \.element.id) { i, card in
                            NavigationLink(value: card) { CardTile(card: card) }
                                .buttonStyle(SquishyButtonStyle())
                                .riseIn(i)
                        }
                    }
                }
                NavigationLink { EvacGuideView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.forward.circle.fill").font(.title2).foregroundStyle(Theme.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Should we evacuate?").font(.headline).foregroundStyle(Theme.ink)
                            Text("Urgent, non-urgent, or treat in the field").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
                    }
                    .card(padding: 14)
                }
                .buttonStyle(SquishyButtonStyle(scale: 0.97))
                FieldDisclaimer()
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Field mode")
        .navigationDestination(for: FieldCard.self) { card in
            FieldCardView(card: card) { searchQuery = SearchRequest(query: $0) }
        }
        .sheet(item: $searchQuery) { req in LibrarySearchSheet(query: req.query) }
        .confirmationDialog("Delete this patient record?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { withAnimation(.bouncy) { field.discard() } }
        } message: {
            Text("Copy or share the SOAP note first if you need it.")
        }
    }

    @ViewBuilder private var patientSection: some View {
        if let patient = field.patient {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current patient").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.white.opacity(0.75))
                        Text(patient.title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                        Text("Started \(patient.started.formatted(date: .omitted, time: .shortened)) · "
                             + "\(patient.vitals.count) vital \(patient.vitals.count == 1 ? "set" : "sets") · \(patient.evac.rawValue)")
                            .font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Menu {
                        Button("Delete patient record", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.headline).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(.white.opacity(0.15), in: .circle)
                    }
                }
                if !patient.redFlags.isEmpty {
                    Label(patient.redFlags.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.danger, in: .rect(cornerRadius: 12, style: .continuous))
                }
                VStack(spacing: 6) {
                    ForEach(AssessmentStep.allCases) { step in
                        NavigationLink { AssessmentStepView(step: step) } label: {
                            StepRow(step: step, done: step.isDone(patient),
                                    detail: step == .vitals ? "\(patient.vitals.count)" : nil)
                        }
                        .buttonStyle(SquishyButtonStyle(scale: 0.98))
                    }
                }
                NavigationLink { SOAPView() } label: {
                    Label("SOAP note & SOS message", systemImage: "doc.text.fill")
                        .font(.headline).foregroundStyle(Theme.pine)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(SquishyButtonStyle(scale: 0.97))
            }
            .padding(16)
            .background(LinearGradient(colors: [Theme.pine, Color(hex: 0x13786A)], startPoint: .topLeading,
                                       endPoint: .bottomTrailing), in: .rect(cornerRadius: 26, style: .continuous))
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            FieldStartCard(action: { withAnimation(.bouncy) { field.startNew() } })
                .transition(.opacity)
        }
    }
}

/// The empty state: one big button to start an assessment.
struct FieldStartCard: View {
    var title = "Treating someone?"
    var button = "Start patient assessment"
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "stethoscope").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.18), in: .rect(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                    Text("Step from scene to plan. The SOAP note fills itself in as you go.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                }
            }
            Button(action: action) {
                Label(button, systemImage: "plus")
                    .font(.headline).foregroundStyle(Theme.pine)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(SquishyButtonStyle(scale: 0.97))
        }
        .padding(16)
        .background(LinearGradient(colors: [Theme.pine, Color(hex: 0x13786A)], startPoint: .topLeading,
                                   endPoint: .bottomTrailing), in: .rect(cornerRadius: 26, style: .continuous))
    }
}

private struct StepRow: View {
    let step: AssessmentStep
    let done: Bool
    let detail: String?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : step.icon)
                .font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
            Text(step.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Spacer()
            if let detail { Text(detail).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8)) }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(.white.opacity(done ? 0.2 : 0.1), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct CardTile: View {
    let card: FieldCard
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: card.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(card.tint)
                .frame(width: 34, height: 34)
                .background(card.tint.opacity(0.14), in: .rect(cornerRadius: 11, style: .continuous))
            Text(card.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .card(padding: 10, radius: 16)
    }
}

// MARK: - Assessment steps

enum AssessmentStep: String, CaseIterable, Identifiable {
    case scene, primary, history, exam, vitals, plan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scene: "1. Scene size-up"
        case .primary: "2. Primary survey (ABCs)"
        case .history: "3. Patient and history"
        case .exam: "4. Head-to-toe exam"
        case .vitals: "5. Vital signs"
        case .plan: "6. Assessment and plan"
        }
    }
    func isDone(_ p: Patient) -> Bool {
        switch self {
        case .scene: p.sceneSafe != .unknown || !p.mechanism.isEmpty
        case .primary: p.airway != .unknown && p.breathing != .unknown && p.circulation != .unknown
        case .history: !p.chiefComplaint.isEmpty
        case .exam: !p.examFindings.isEmpty
        case .vitals: !p.vitals.isEmpty
        case .plan: !p.problems.isEmpty && p.evac != .undecided
        }
    }
    var icon: String {
        switch self {
        case .scene: "exclamationmark.shield"
        case .primary: "lungs"
        case .history: "person.text.rectangle"
        case .exam: "figure.stand"
        case .vitals: "waveform.path.ecg"
        case .plan: "list.clipboard"
        }
    }
}

/// A non-optional binding to the current patient (the views only show while one exists).
private extension FieldStore {
    var binding: Binding<Patient> {
        Binding(get: { self.patient ?? Patient() }, set: { self.patient = $0 })
    }
}

struct AssessmentStepView: View {
    let step: AssessmentStep
    @Environment(FieldStore.self) private var field

    var body: some View {
        let p = field.binding
        Form {
            switch step {
            case .scene:
                Section {
                    Picker("Scene safe for you?", selection: p.sceneSafe) {
                        ForEach(Check.allCases) { Text($0 == .ok ? "Yes" : $0 == .problem ? "No" : "Not checked").tag($0) }
                    }
                    if p.wrappedValue.sceneSafe == .problem {
                        Text("Don't become a second patient. Make it safe or move away before you treat.")
                            .font(.callout).foregroundStyle(Theme.danger)
                    }
                    TextField("What happened? (fall 5 m, rockfall, lost 2 days…)", text: p.mechanism, axis: .vertical)
                    TextField("Number of patients", text: p.patientCount).keyboardType(.numberPad)
                    TextField("Hazards, weather, resources, location", text: p.sceneNotes, axis: .vertical)
                } footer: {
                    Text("Wear gloves if you have them. Think about weather and nightfall early.")
                }
            case .primary:
                Section("Responsiveness") {
                    Picker("Level", selection: p.avpu) {
                        ForEach(AVPU.allCases) { Text("\($0.rawValue) · \($0.label)").tag($0) }
                    }
                }
                Section {
                    checkRow("A · Airway open and clear", p.airway)
                    checkRow("B · Breathing adequate", p.breathing)
                    checkRow("C · Pulse present, no severe bleeding", p.circulation)
                    Toggle("Severe bleeding", isOn: p.severeBleeding)
                    Toggle("D · Possible spine injury (mechanism)", isOn: p.spineConcern)
                    TextField("Notes", text: p.primaryNotes, axis: .vertical)
                } header: {
                    Text("ABCs: fix problems as you find them")
                } footer: {
                    Text("Problems here are life threats. Treat them before moving on (see the CPR, bleeding and "
                         + "spine cards). E: protect them from the environment early.")
                }
            case .history:
                Section("Patient") {
                    TextField("Age", text: p.age).keyboardType(.numberPad)
                    TextField("Sex", text: p.sex)
                    TextField("Chief complaint (what's wrong, in their words)", text: p.chiefComplaint, axis: .vertical)
                }
                Section {
                    TextField("S · Symptoms (for pain: onset, triggers, quality, spread, severity 0–10, time)",
                              text: p.symptoms, axis: .vertical)
                    TextField("A · Allergies", text: p.allergies)
                    TextField("M · Medications", text: p.medications)
                    TextField("P · Pertinent medical history", text: p.history, axis: .vertical)
                    TextField("L · Last food, water, urine, bowel movement", text: p.lastInOut, axis: .vertical)
                    TextField("E · Events leading up to this", text: p.events, axis: .vertical)
                } header: {
                    Text("SAMPLE history")
                }
            case .exam:
                Section {
                    TextField("Findings: look, ask and feel head to toe. Note pain, tenderness, deformity, swelling, bleeding, and circulation, sensation and movement in the hands and feet.",
                              text: p.examFindings, axis: .vertical)
                        .lineLimit(6...20)
                } header: {
                    Text("Head-to-toe exam")
                } footer: {
                    Text("Order: head, neck, chest, abdomen, pelvis, legs, arms, back. Compare left with right. Keep them covered and warm.")
                }
            case .vitals:
                VitalsSection(patient: p)
            case .plan:
                Section {
                    TextField("Problem list (e.g. 1. Possible fractured left ankle, 2. Mild hypothermia)",
                              text: p.problems, axis: .vertical).lineLimit(3...10)
                } header: { Text("Assessment") }
                Section {
                    TextField("Plan for each problem (splint, rewarm, monitor every 15 min…)",
                              text: p.plan, axis: .vertical).lineLimit(3...10)
                    Picker("Evacuation", selection: p.evac) {
                        ForEach(EvacUrgency.allCases) { Text($0.rawValue).tag($0) }
                    }
                    NavigationLink("Help me decide") { EvacGuideView() }
                } header: { Text("Plan") }
                if !p.wrappedValue.redFlags.isEmpty {
                    Section("Red flags so far") {
                        ForEach(p.wrappedValue.redFlags, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .navigationTitle(step.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func checkRow(_ title: String, _ value: Binding<Check>) -> some View {
        Picker(title, selection: value) {
            ForEach(Check.allCases) { Text($0.rawValue).tag($0) }
        }
    }
}

struct VitalsSection: View {
    @Binding var patient: Patient
    @State private var draft = VitalSet()

    var body: some View {
        Section {
            Picker("Responsiveness", selection: $draft.avpu) {
                ForEach(AVPU.allCases) { Text("\($0.rawValue) · \($0.label)").tag($0) }
            }
            if draft.avpu == .alert {
                Stepper("Oriented to \(draft.oriented) of 4", value: $draft.oriented, in: 0...4)
            }
            TextField("Heart rate (beats per minute)", text: $draft.heartRate).keyboardType(.numberPad)
            TextField("Breathing rate (per minute)", text: $draft.respRate).keyboardType(.numberPad)
            TextField("Skin: color, temperature, moisture", text: $draft.skin)
            TextField("Blood pressure or radial pulse", text: $draft.bloodPressure)
            TextField("Pupils", text: $draft.pupils)
            TextField("Temperature", text: $draft.temperature)
            Button {
                withAnimation(.bouncy) { draft.time = .now }
                patient.vitals.append(draft)
                let keep = draft
                draft = VitalSet()
                draft.avpu = keep.avpu
                draft.oriented = keep.oriented
            } label: {
                Label("Save vitals now", systemImage: "plus.circle.fill").fontWeight(.semibold)
            }
            .sensoryFeedback(.success, trigger: patient.vitals.count)
        } header: {
            Text("New set")
        } footer: {
            Text("Oriented: knows who they are, where, when, and what happened. Count the pulse and breaths for "
                 + "30 seconds and double. Repeat every 15 minutes if serious; the trend matters most.")
        }
        if !patient.vitals.isEmpty {
            Section("Log (newest first)") {
                ForEach(patient.vitals.reversed()) { v in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.time.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.semibold))
                        Text(v.compact).font(.callout.monospacedDigit())
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { patient.vitals.reversed()[$0].id }
                    patient.vitals.removeAll { ids.contains($0.id) }
                }
            }
        }
    }
}

// MARK: - SOAP

/// The note writes itself from the assessment. Share it, send the 160-character SOS version, or hand it to Scout.
struct SOAPView: View {
    @Environment(FieldStore.self) private var field
    @Environment(Router.self) private var router
    @State private var copied = false

    var body: some View {
        let patient = field.patient ?? Patient()
        let note = SOAP.note(patient)
        let sat = SOAP.satellite(patient)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Satellite / SOS message", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Theme.danger)
                    Text(sat).font(.callout.monospaced()).foregroundStyle(Theme.ink)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.danger.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                    HStack {
                        Text("\(sat.count)/160").font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(sat.count > 150 ? Theme.danger : Theme.inkSoft)
                        Text("Your messenger adds your location.").font(.caption).foregroundStyle(Theme.inkSoft)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = sat
                            withAnimation(.bouncy) { copied = true }
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .sensoryFeedback(.success, trigger: copied)
                        ShareLink(item: sat) { Label("Send…", systemImage: "paperplane.fill") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("SOAP note", systemImage: "doc.text.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accentDeep)
                        Spacer()
                        Text("Updates as you assess").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Text(note).font(.footnote.monospaced()).foregroundStyle(Theme.ink).textSelection(.enabled)
                }
                .card()

                ShareLink(item: note) { Label("Share SOAP note", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { router.ask(Self.question(for: patient)) } label: {
                    Label("Ask Scout about this patient", systemImage: "bubble.left.and.text.bubble.right.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("Scout reads this note and searches the library for what to do next. Uses some battery.")
                    .font(.caption).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                FieldDisclaimer()
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("SOAP note")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func question(for p: Patient) -> String {
        let focus = [p.chiefComplaint, p.problems].filter { !$0.isEmpty }.joined(separator: ". ")
        return "I'm treating a patient in the backcountry. \(focus.isEmpty ? "" : focus + ".") "
            + "What should I do next, what should I watch for, and how urgently should we evacuate?\n\n"
            + SOAP.forAI(p)
    }
}

// MARK: - Evacuation guide

struct EvacGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                tier("Evacuate urgently", "light.beacon.max.fill", Theme.danger, [
                    "Airway, breathing or circulation problems, or signs of shock",
                    "Level of responsiveness dropping, or confused",
                    "Severe bleeding, or a tourniquet in place",
                    "Possible spine injury with numbness, tingling or weakness",
                    "Anaphylaxis treated with epinephrine",
                    "Heat stroke, severe hypothermia, HACE or HAPE",
                    "Chest pain that could be the heart",
                    "Open fracture, femur or pelvis fracture, or a limb with poor circulation",
                ])
                tier("Evacuate, non-urgent", "figure.walk", Theme.sun, [
                    "Stable fracture or a sprain they can't walk on",
                    "Wound that needs closing or is dirty and deep",
                    "Infection that's spreading, or a fever",
                    "Frostbite beyond frostnip",
                    "Brief knockout with full recovery",
                    "Anything you can't manage, or that's getting worse",
                ])
                tier("Treat in the field", "tent.fill", Theme.moss, [
                    "Minor wounds, blisters, mild sprains they can walk on",
                    "Mild hypothermia that fully rewarms",
                    "Mild altitude sickness that improves with rest (don't go higher)",
                ])
                Text("Also weigh: weather, daylight, distance, your group's strength, and whether you can call for "
                     + "help. When unsure, choose the more cautious option early. It's easier to cancel an "
                     + "evacuation than to start one in the dark.")
                    .font(.callout).foregroundStyle(Theme.ink)
                FieldDisclaimer()
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Should we evacuate?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tier(_ title: String, _ icon: String, _ color: Color, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(color).frame(width: 6, height: 6).offset(y: -2)
                    Text(item).font(.callout).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22).fill(color).frame(width: 5)
        }
    }
}

// MARK: - Library search from a card

struct LibrarySearchSheet: View {
    let query: String
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var open: Passage?
    @State private var results: [Passage]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if store.library == nil {
                        Text("Download the library to read the source manuals.").foregroundStyle(Theme.inkSoft)
                    } else if let results {
                        if results.isEmpty { Text("No matches in the library.").foregroundStyle(Theme.inkSoft) }
                        ForEach(results) { p in
                            Button { open = p } label: { SearchResultRow(passage: p) }
                                .buttonStyle(SquishyButtonStyle(scale: 0.98))
                        }
                    } else {
                        ProgressView().padding(.top, 30)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle(query.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold) }
            .sheet(item: $open) { p in ArticleView(passage: p) }
            .task {
                guard let lib = store.library else { return }
                let q = query
                results = await Task.detached(priority: .userInitiated) { lib.search(q, limit: 15, maxChars: 220) }.value
            }
        }
        .tint(Theme.accent)
    }
}
