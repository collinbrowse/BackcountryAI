import SwiftUI
import UIKit

/// Field mode: a Wilderness First Responder patient assessment, vitals log, SOAP note and quick cards.
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
                        ForEach(Array(FieldCard.firstAid.enumerated()), id: \.element.id) { i, card in
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

struct CardTile: View {
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

/// The assessment in the order it is done: scene size-up, primary assessment, the three parts of the secondary
/// assessment (vital signs, history, physical exam), the written assessment and plan, then reassessment.
enum AssessmentStep: String, CaseIterable, Identifiable {
    case scene, primary, vitals, history, exam, plan, reassess
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scene: "1. Scene size-up"
        case .primary: "2. Primary assessment"
        case .vitals: "3. Vital signs"
        case .history: "4. History"
        case .exam: "5. Physical exam"
        case .plan: "6. Assessment and plan"
        case .reassess: "7. Reassess"
        }
    }
    func isDone(_ p: Patient) -> Bool {
        switch self {
        case .scene: p.sceneSafe != .unknown || !p.mechanism.isEmpty
        case .primary: p.airway != .unknown && p.breathing != .unknown && p.circulation != .unknown
        case .vitals: !p.vitals.isEmpty
        case .history: !p.chiefComplaint.isEmpty
        case .exam: !p.examFindings.isEmpty
        case .plan: !p.problems.isEmpty && p.evac != .undecided
        case .reassess: p.vitals.count >= 2 || !p.changes.isEmpty
        }
    }
    var icon: String {
        switch self {
        case .scene: "exclamationmark.shield"
        case .primary: "lungs"
        case .vitals: "waveform.path.ecg"
        case .history: "person.text.rectangle"
        case .exam: "figure.stand"
        case .plan: "list.clipboard"
        case .reassess: "arrow.triangle.2.circlepath"
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
                    Picker("Safe for you and your group?", selection: p.sceneSafe) {
                        ForEach(Check.allCases) { Text($0 == .ok ? "Yes" : $0 == .problem ? "No" : "Not checked").tag($0) }
                    }
                    if p.wrappedValue.sceneSafe == .problem {
                        Text("Don't become a second patient. Make it safe or move away before you treat.")
                            .font(.callout).foregroundStyle(Theme.danger)
                    }
                    TextField("What happened? An injury: how (fell 5 m, rockfall). An illness: how it came on.",
                              text: p.mechanism, axis: .vertical)
                    TextField("Number of patients", text: p.patientCount).keyboardType(.numberPad)
                    TextField("Hazards, location, and the help and gear you need", text: p.sceneNotes, axis: .vertical)
                } footer: {
                    Text("Protect yourself before you touch them: gloves (plastic bags work), a mask if they are "
                         + "coughing, glasses against splashes. Clean your hands afterwards.")
                }
            case .primary:
                Section {
                    checkRow("A · Airway open and clear", p.airway)
                    checkRow("B · Breathing adequate", p.breathing)
                    checkRow("C · Pulse present, bleeding controlled", p.circulation)
                    Toggle("Severe bleeding", isOn: p.severeBleeding)
                    Toggle("D · Possible spine injury", isOn: p.spineConcern)
                    Picker("D · Responsiveness", selection: p.avpu) {
                        ForEach(AVPU.allCases) { Text("\($0.rawValue) · \($0.label)").tag($0) }
                    }
                    Toggle("E · Looked under clothing, then covered", isOn: p.exposed)
                    Toggle("G · Sugar given", isOn: p.sugarGiven)
                    TextField("Notes", text: p.primaryNotes, axis: .vertical)
                } header: {
                    Text("Find life threats. Stop and fix each one.")
                } footer: {
                    Text("A: tilt the head and lift the chin; if the spine may be hurt, push the jaw forward instead. "
                         + "C: feel for a pulse at the neck and the wrist, stop bleeding, treat for shock. "
                         + "E: remove or cut clothing to find injuries, then insulate them from the ground and the weather. "
                         + "G: unresponsive and you don't know why: sugar between cheek and gum, with them lying on their side. "
                         + "The CPR, Severe bleeding, Shock and Spine injury cards have the steps.")
                }
                Section {
                    Picker("Injury or illness", selection: p.kind) {
                        ForEach(ProblemKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Stable or critical", selection: p.condition) {
                        ForEach(Condition.allCases) { Text($0.rawValue).tag($0) }
                    }
                } header: {
                    Text("Transport decision")
                } footer: {
                    Text("Critical is a life threat you couldn't fix. Decide now whether to send for help: the rest of "
                         + "the assessment can go on while it comes.")
                }
            case .vitals:
                VitalsSection(patient: p)
            case .history:
                Section("Patient") {
                    TextField("Name", text: p.name)
                    TextField("Age", text: p.age).keyboardType(.numberPad)
                    TextField("Sex", text: p.sex)
                    TextField("Pronouns", text: p.pronouns)
                    TextField("Chief complaint (what's wrong, in their words)", text: p.chiefComplaint, axis: .vertical)
                }
                Section {
                    TextField("S · Signs and symptoms", text: p.symptoms, axis: .vertical)
                    TextField("A · Allergies", text: p.allergies)
                    TextField("M · Medications", text: p.medications)
                    TextField("P · Pre-existing conditions", text: p.history, axis: .vertical)
                    TextField("L · Last ins and outs: food, water, urine, stool", text: p.lastInOut, axis: .vertical)
                    TextField("E · Events prior", text: p.events, axis: .vertical)
                } header: {
                    Text("SAMPLE history")
                } footer: {
                    Text("Pain you can't make sense of: ask OPQRST. Onset, what provokes it, its quality, whether it "
                         + "radiates, severity from 0 to 10, and time, with any treatment tried. "
                         + "Not acting normally and you don't know why: run through 1ST STEP. Sugar, temperature, "
                         + "salt, toxins, electricity or elevation, pressure in the skull.")
                }
            case .exam:
                Section {
                    TextField("Findings: pain, tenderness, deformity, swelling, bleeding, and the pulse, feeling and movement in each hand and foot.",
                              text: p.examFindings, axis: .vertical)
                        .lineLimit(6...20)
                } header: {
                    Text("Physical exam")
                } footer: {
                    Text("Head to toe when they fell far, were hit hard or are seriously ill: skull and neck bones, "
                         + "eyes, ears and mouth, neck, chest, each quarter of the abdomen, back, pelvis (one gentle "
                         + "inward squeeze, once), legs and feet, arms and hands. Otherwise examine the chief "
                         + "complaint closely. Keep them covered and warm.")
                }
            case .plan:
                Section {
                    TextField("Problem list (e.g. 1. Possible fractured left ankle, 2. Mild hypothermia)",
                              text: p.problems, axis: .vertical).lineLimit(3...10)
                    TextField("Anticipated worst case: what this could become", text: p.worstCase, axis: .vertical)
                } header: { Text("Assessment") }
                Section {
                    TextField("Plan for each problem (splint, rewarm, new vitals on a schedule…)",
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
            case .reassess:
                Section {
                    Text("Chief complaint: has it changed, and how?")
                    Text("Primary assessment again: anything new?")
                    NavigationLink("Take a new set of vital signs") { AssessmentStepView(step: .vitals) }
                    Text("Treatments: are the splints, bandages and medicines still working?")
                    TextField("What has changed", text: p.changes, axis: .vertical).lineLimit(3...10)
                } header: {
                    Text("Reevaluate")
                } footer: {
                    Text("Look for the trend in the vital signs and what it means. Write things down as they happen: "
                         + "a strip of athletic tape works when there is no paper.")
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
            TextField("Heart rate (beats per minute)", text: $draft.heartRate).keyboardType(.numberPad)
            TextField("Breathing rate (per minute)", text: $draft.respRate).keyboardType(.numberPad)
            TextField("Blood pressure, or wrist pulse: strong, weak, none", text: $draft.bloodPressure)
            Picker("Responsiveness", selection: $draft.avpu) {
                ForEach(AVPU.allCases) { Text("\($0.rawValue) · \($0.label)").tag($0) }
            }
            if draft.avpu == .alert {
                Stepper("Oriented to \(draft.oriented) of 4", value: $draft.oriented, in: 0...4)
            }
            TextField("Skin: color, temperature, moisture", text: $draft.skin)
            TextField("CSM: pulse, feeling, movement in hands and feet", text: $draft.csm)
            TextField("Pupils: equal, round, react to light?", text: $draft.pupils)
            TextField("Temperature, if you can measure it", text: $draft.temperature)
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
            Text("Count the pulse and the breaths for 15 seconds and multiply by 4. Normal at rest: pulse 60–100, "
                 + "breathing 12–20. With no cuff, feel the pulse at the wrist: strong means a pressure near 100, "
                 + "weak near 80, none below 80. Oriented: knows who they are, where, when, and what happened. "
                 + "Skin on a dark-skinned person: look at the gums, the tongue and inside the lower eyelid. "
                 + "CSM: all four hands and feet. Take a new set regularly: the trend matters more than any one set.")
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

/// The note writes itself from the assessment. Share it, send the 160-character SOS version, read out the
/// rescue call, or hand it to Scout.
struct SOAPView: View {
    @Environment(FieldStore.self) private var field
    @Environment(Router.self) private var router
    @State private var copied = false

    var body: some View {
        let patient = field.patient ?? Patient()
        let note = SOAP.note(patient)
        let sat = SOAP.satellite(patient)
        let call = SOAP.rescueCall(patient)
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
                    Label("Calling for a rescue", systemImage: "phone.arrow.up.right.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Theme.danger)
                    Text("By radio or phone, say it in this order.").font(.caption).foregroundStyle(Theme.inkSoft)
                    ForEach(Array(call.enumerated()), id: \.offset) { i, line in
                        if i == 4 {
                            Text("Then the patient report").font(.caption.weight(.bold)).textCase(.uppercase)
                                .foregroundStyle(Theme.inkSoft).padding(.top, 4)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(i < 4 ? "\(i + 1)" : "•").font(.callout.weight(.bold)).foregroundStyle(Theme.danger)
                                .frame(width: 16)
                            Text(line).font(.callout).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    "An airway, breathing or circulation problem you can't fix, or signs of shock",
                    "Getting less responsive or more confused, or any sign of a stroke",
                    "Severe bleeding, a tourniquet in place or a packed wound",
                    "Spine injury with numbness, tingling, weakness or shooting pain",
                    "Head injury with a worsening headache, repeated vomiting, drowsiness or unequal pupils",
                    "Chest pain that rest doesn't settle",
                    "Anaphylaxis, or an asthma attack the inhaler doesn't fix. Anyone given epinephrine",
                    "Heat stroke, hypothermia beyond shivering, or altitude illness with stumbling, confusion or breathlessness at rest",
                    "Any snakebite, even before symptoms",
                    "Open fracture, a broken thigh or pelvis, a dislocation that won't go back, or a limb that is cold, numb or far more painful than it looks",
                    "Burns of the airway, face, hands, feet or genitals, right around a limb, or over 10% of the body",
                    "A diabetic who can't swallow, isn't recovering after sugar, or is sick with high blood sugar",
                    "Bloody diarrhea, or can't keep water down for an hour",
                    "Breathed in water and now coughing hard, wheezing or drowsy",
                ])
                tier("Evacuate, non-urgent", "figure.walk", Theme.sun, [
                    "Knocked out, even briefly, or any sign of concussion",
                    "A first seizure, or one unusual for them",
                    "A stable fracture, or a sprain they can't use or walk on",
                    "A wound that is deep, gaping, dirty or from a bite, or infected and no better in 12–24 hours",
                    "Frostbite that blisters after thawing: reach a hospital within 24 hours",
                    "Something stuck in the eye",
                    "Knocked-out tooth: a dentist as soon as you can. Exposed nerve or lost filling: within 48 hours",
                    "Anything you can't manage, or that's getting worse",
                ])
                tier("Treat in the field", "tent.fill", Theme.moss, [
                    "Minor wounds, blisters, mild sprains they can walk on",
                    "Mild hypothermia that fully rewarms",
                    "Mild altitude sickness that improves with rest (don't go higher)",
                    "Mild dehydration, or a stomach bug that eases within 48 hours",
                    "Breathed in a little water with no symptoms: watch them for 6 hours",
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
