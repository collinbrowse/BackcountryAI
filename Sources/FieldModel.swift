import Foundation
import Observation

// MARK: - Patient record (one at a time, saved on the phone)
//
// The record follows a Wilderness First Responder patient assessment in its four parts: scene size-up, primary
// assessment (ABCDE and glucose, then stable or critical), secondary assessment (vital signs, history, physical
// exam) and reassessment. The note it writes is a SOAP note with the anticipated worst case added.

enum AVPU: String, Codable, CaseIterable, Identifiable {
    case alert = "A", verbal = "V", pain = "P", unresponsive = "U"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .alert: "Alert"
        case .verbal: "Responds to voice"
        case .pain: "Responds to pain"
        case .unresponsive: "Unresponsive"
        }
    }
}

enum Check: String, Codable, CaseIterable, Identifiable {
    case unknown = "Not checked", ok = "OK", problem = "Problem"
    var id: String { rawValue }
}

/// Injury or illness: with stable or critical, the first thing a rescue team is told.
enum ProblemKind: String, Codable, CaseIterable, Identifiable {
    case unknown = "Not sure", trauma = "Trauma", medical = "Medical"
    var id: String { rawValue }
}

/// Decided at the end of the primary assessment: critical is a life threat that hasn't been fixed.
enum Condition: String, Codable, CaseIterable, Identifiable {
    case unknown = "Not decided", stable = "Stable", critical = "Critical"
    var id: String { rawValue }
}

enum EvacUrgency: String, Codable, CaseIterable, Identifiable {
    case undecided = "Not decided"
    case stay = "Treat in the field"
    case slow = "Evacuate, non-urgent"
    case fast = "Evacuate urgently"
    var id: String { rawValue }
    var short: String {
        switch self {
        case .undecided: "evac TBD"
        case .stay: "no evac needed now"
        case .slow: "non-urgent evac"
        case .fast: "URGENT evac"
        }
    }
}

/// One set of the seven vital signs, in the order they are taken and written down.
struct VitalSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var time = Date.now
    var heartRate = ""             // per minute
    var respRate = ""              // per minute
    var bloodPressure = ""         // a cuff reading, or the pulse at the wrist: strong, weak or none
    var avpu: AVPU = .alert
    var oriented: Int = 4          // A&O x1-4: person, place, time, event
    var skin = ""                  // color, temperature, moisture, e.g. "pink, warm, dry"
    var csm = ""                   // circulation, sensation and movement in the hands and feet
    var pupils = ""                // e.g. "PERRL"
    var temperature = ""           // not one of the seven: only when there is a thermometer

    var loc: String { avpu == .alert ? "A&Ox\(oriented)" : avpu.label }

    var compact: String {
        var parts: [String] = []
        if !heartRate.isEmpty { parts.append("HR\(heartRate)") }
        if !respRate.isEmpty { parts.append("RR\(respRate)") }
        if !bloodPressure.isEmpty { parts.append("BP \(bloodPressure)") }
        parts.append(loc)
        if !skin.isEmpty { parts.append("skin \(skin)") }
        if !csm.isEmpty { parts.append("CSM \(csm)") }
        if !pupils.isEmpty { parts.append("pupils \(pupils)") }
        if !temperature.isEmpty { parts.append("T \(temperature)") }
        return parts.joined(separator: ", ")
    }

    init() {}

    /// A set saved by another version of the app still opens: what it lacks keeps its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: id)
        time = c.value(.time, or: time)
        heartRate = c.value(.heartRate, or: heartRate)
        respRate = c.value(.respRate, or: respRate)
        bloodPressure = c.value(.bloodPressure, or: bloodPressure)
        avpu = c.value(.avpu, or: avpu)
        oriented = c.value(.oriented, or: oriented)
        skin = c.value(.skin, or: skin)
        csm = c.value(.csm, or: csm)
        pupils = c.value(.pupils, or: pupils)
        temperature = c.value(.temperature, or: temperature)
    }
}

extension KeyedDecodingContainer {
    /// The stored value, or `fallback` when the record lacks it or holds something this version can't read.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

struct Patient: Codable, Identifiable {
    var id = UUID()
    var started = Date.now

    // 1. Scene size-up
    var sceneSafe: Check = .unknown
    var mechanism = ""            // what happened: how they were hurt, or how the illness came on
    var patientCount = "1"
    var sceneNotes = ""           // hazards, location, the help and gear needed

    // 2. Primary assessment: find life threats, stop and fix
    var airway: Check = .unknown
    var breathing: Check = .unknown
    var circulation: Check = .unknown      // pulse present, severe bleeding controlled
    var severeBleeding = false
    var spineConcern = false               // D: disability
    var avpu: AVPU = .alert
    var exposed = false                    // E: looked under clothing, then covered and insulated
    var sugarGiven = false                 // G: glucose
    var primaryNotes = ""
    var kind: ProblemKind = .unknown
    var condition: Condition = .unknown

    // 3. Secondary assessment: vital signs, history, physical exam
    var vitals: [VitalSet] = []
    var name = ""
    var age = ""
    var sex = ""
    var pronouns = ""
    var chiefComplaint = ""
    var symptoms = ""             // S (and OPQRST for pain)
    var allergies = ""            // A
    var medications = ""          // M
    var history = ""              // P: pre-existing conditions
    var lastInOut = ""            // L
    var events = ""               // E
    var examFindings = ""         // head to toe, or focused on the chief complaint

    // Assessment and plan
    var problems = ""
    var worstCase = ""            // what this could turn into, so the plan is ready for it
    var plan = ""
    var evac: EvacUrgency = .undecided

    // 4. Reassessment
    var changes = ""

    var title: String {
        let who = [name.isEmpty ? nil : name, age.isEmpty ? nil : "\(age)y", sex.isEmpty ? nil : sex]
            .compactMap { $0 }.joined(separator: " ")
        let what = chiefComplaint.isEmpty ? "Patient" : chiefComplaint
        return who.isEmpty ? what : "\(who) · \(what)"
    }

    /// "Critical trauma", "Stable", "Medical", or nothing while neither is decided.
    var status: String {
        let words = [condition == .unknown ? nil : condition.rawValue, kind == .unknown ? nil : kind.rawValue]
            .compactMap { $0 }.joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst().lowercased()
    }

    /// Red flags found so far, for the evacuation prompt.
    var redFlags: [String] {
        var f: [String] = []
        if avpu != .alert { f.append("Not fully alert (\(avpu.label.lowercased()))") }
        if airway == .problem { f.append("Airway problem") }
        if breathing == .problem { f.append("Breathing problem") }
        if circulation == .problem || severeBleeding { f.append("Circulation problem or severe bleeding") }
        if spineConcern { f.append("Possible spine injury") }
        if let last = vitals.last, last.avpu == .alert, last.oriented < 4 { f.append("Not fully oriented (A&Ox\(last.oriented))") }
        if vitals.count >= 2, let a = vitals.first, let b = vitals.last,
           Self.rank(b.avpu) > Self.rank(a.avpu) || (a.avpu == .alert && b.avpu == .alert && b.oriented < a.oriented) {
            f.append("Level of responsiveness getting worse")
        }
        return f
    }

    private static func rank(_ a: AVPU) -> Int { AVPU.allCases.firstIndex(of: a) ?? 0 }

    init() {}

    /// A record saved by another version of the app still opens: what it lacks keeps its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: id)
        started = c.value(.started, or: started)
        sceneSafe = c.value(.sceneSafe, or: sceneSafe)
        mechanism = c.value(.mechanism, or: mechanism)
        patientCount = c.value(.patientCount, or: patientCount)
        sceneNotes = c.value(.sceneNotes, or: sceneNotes)
        airway = c.value(.airway, or: airway)
        breathing = c.value(.breathing, or: breathing)
        circulation = c.value(.circulation, or: circulation)
        severeBleeding = c.value(.severeBleeding, or: severeBleeding)
        spineConcern = c.value(.spineConcern, or: spineConcern)
        avpu = c.value(.avpu, or: avpu)
        exposed = c.value(.exposed, or: exposed)
        sugarGiven = c.value(.sugarGiven, or: sugarGiven)
        primaryNotes = c.value(.primaryNotes, or: primaryNotes)
        kind = c.value(.kind, or: kind)
        condition = c.value(.condition, or: condition)
        vitals = c.value(.vitals, or: vitals)
        name = c.value(.name, or: name)
        age = c.value(.age, or: age)
        sex = c.value(.sex, or: sex)
        pronouns = c.value(.pronouns, or: pronouns)
        chiefComplaint = c.value(.chiefComplaint, or: chiefComplaint)
        symptoms = c.value(.symptoms, or: symptoms)
        allergies = c.value(.allergies, or: allergies)
        medications = c.value(.medications, or: medications)
        history = c.value(.history, or: history)
        lastInOut = c.value(.lastInOut, or: lastInOut)
        events = c.value(.events, or: events)
        examFindings = c.value(.examFindings, or: examFindings)
        problems = c.value(.problems, or: problems)
        worstCase = c.value(.worstCase, or: worstCase)
        plan = c.value(.plan, or: plan)
        evac = c.value(.evac, or: evac)
        changes = c.value(.changes, or: changes)
    }
}

// MARK: - SOAP note

/// The written record: subjective, objective, assessment, the anticipated worst case, and plan.
enum SOAP {
    static func note(_ p: Patient) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short

        func line(_ label: String, _ value: String) -> String? {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "\(label): \(value)"
        }
        var s: [String] = ["SOAP NOTE · started \(df.string(from: p.started))", ""]

        s.append("S — SUBJECTIVE")
        s += [line("Patient", who(p)),
              line("Chief complaint", p.chiefComplaint),
              line("What happened", p.mechanism),
              line("Signs and symptoms", p.symptoms),
              line("Allergies", p.allergies),
              line("Medications", p.medications),
              line("Pre-existing conditions", p.history),
              line("Last ins and outs", p.lastInOut),
              line("Events prior", p.events)].compactMap { $0 }
        s.append("")

        s.append("O — OBJECTIVE")
        s.append("Scene safe: \(p.sceneSafe.rawValue). Patients: \(p.patientCount).")
        if let n = line("Scene", p.sceneNotes) { s.append(n) }
        s.append("Primary: airway \(p.airway.rawValue); breathing \(p.breathing.rawValue); "
                 + "circulation \(p.circulation.rawValue)"
                 + (p.severeBleeding ? "; severe bleeding" : "")
                 + (p.spineConcern ? "; possible spine injury" : "")
                 + "; \(p.avpu.label.lowercased())"
                 + (p.exposed ? "; exposed and covered" : "")
                 + (p.sugarGiven ? "; sugar given" : "") + ".")
        if let n = line("Primary notes", p.primaryNotes) { s.append(n) }
        if !p.status.isEmpty { s.append("After the primary assessment: \(p.status.lowercased()).") }
        if p.vitals.isEmpty {
            s.append("Vitals: none recorded")
        } else {
            s.append("Vitals:")
            for v in p.vitals { s.append("  \(time(v.time)) — \(v.compact)") }
        }
        if let n = line("Exam", p.examFindings) { s.append(n) }
        s.append("")

        s.append("A — ASSESSMENT")
        s.append(p.problems.isEmpty ? "(not yet written)" : p.problems)
        if let n = line("Anticipated worst case", p.worstCase) { s.append(n) }
        let flags = p.redFlags
        if !flags.isEmpty { s.append("Red flags: " + flags.joined(separator: "; ")) }
        s.append("")

        s.append("P — PLAN")
        s.append(p.plan.isEmpty ? "(not yet written)" : p.plan)
        s.append("Evacuation: \(p.evac.rawValue)")
        if let n = line("Changes on reassessment", p.changes) { s.append(n) }
        return s.joined(separator: "\n")
    }

    /// Fits a satellite messenger's 160-character limit. Leads with what a rescue team asks first: stable or
    /// critical, injury or illness, and what is wanted.
    static func satellite(_ p: Patient, limit: Int = 160) -> String {
        var parts: [String] = []
        let lead = [p.status, p.evac == .undecided ? "" : p.evac.short].filter { !$0.isEmpty }.joined(separator: ", ")
        if !lead.isEmpty { parts.append(lead) }
        let who = [p.age, p.sex.prefix(1).uppercased()].filter { !$0.isEmpty }.joined()
        if !who.isEmpty { parts.append(who) }
        if !p.chiefComplaint.isEmpty { parts.append(p.chiefComplaint) }
        if !p.mechanism.isEmpty { parts.append(p.mechanism) }
        if let v = p.vitals.last { parts.append(v.compact) }
        if !p.problems.isEmpty { parts.append(p.problems.replacingOccurrences(of: "\n", with: "; ")) }
        if !p.plan.isEmpty { parts.append(p.plan.replacingOccurrences(of: "\n", with: "; ")) }
        let joined = parts.joined(separator: ". ")
        return joined.count <= limit ? joined : String(joined.prefix(limit - 1)) + "…"
    }

    /// What to say on a radio or phone, in the order a rescue team needs it. The first four lines are the
    /// call itself; the rest is the patient report that follows.
    static func rescueCall(_ p: Patient) -> [String] {
        let status = p.status.isEmpty ? "Stable or critical? Injury or illness?" : p.status + "."
        let complaint = p.chiefComplaint.isEmpty ? "Their chief complaint." : "Chief complaint: \(p.chiefComplaint)."
        var report = ["Your phone number."]
        let age = p.age.isEmpty ? "" : "\(p.age)-year-old"
        let person = [age, p.sex].filter { !$0.isEmpty }.joined(separator: " ")
        let what = p.mechanism.isEmpty ? "what happened" : p.mechanism
        report.append(person.isEmpty ? "Their age and sex, and \(what)." : "\(person): \(what).")
        report.append(complaint)
        if let v = p.vitals.last {
            report.append("Latest vitals (\(time(v.time))): \(v.compact).")
        } else {
            report.append("Their latest vital signs.")
        }
        report.append("What you are asking for: a helicopter or a ground team, at your location.")
        return ["Who you are: your name and your group.",
                "Where you are: coordinates, a river mile, or a place on the map.",
                "\(status) \(complaint)",
                "\"We need a rescue. Do you copy?\""] + report
    }

    /// A compact summary for the AI (its context window is small).
    static func forAI(_ p: Patient) -> String {
        let full = note(p)
        return full.count <= 1400 ? full : String(full.prefix(1400)) + "…"
    }

    private static func who(_ p: Patient) -> String {
        let ageAndSex = [p.age.isEmpty ? "" : "\(p.age) y/o", p.sex].filter { !$0.isEmpty }.joined(separator: " ")
        let basics = [p.name, ageAndSex].filter { !$0.isEmpty }.joined(separator: ", ")
        return p.pronouns.isEmpty ? basics : basics + (basics.isEmpty ? "" : " ") + "(\(p.pronouns))"
    }

    private static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Storage

@MainActor
@Observable
final class FieldStore {
    var patient: Patient? { didSet { save() } }

    private static var file: URL { URL.documentsDirectory.appending(path: "field-patient.json") }

    init() {
        if let data = try? Data(contentsOf: Self.file) {
            patient = try? JSONDecoder().decode(Patient.self, from: data)
        }
    }

    func startNew() { patient = Patient() }

    func discard() { patient = nil }

    private func save() {
        guard let patient else { try? FileManager.default.removeItem(at: Self.file); return }
        if let data = try? JSONEncoder().encode(patient) {
            try? data.write(to: Self.file, options: [.atomic, .completeFileProtection])
        }
    }
}
