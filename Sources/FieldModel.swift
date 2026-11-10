import Foundation
import Observation

// MARK: - Patient record (one at a time, saved on the phone)

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

struct VitalSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var time = Date.now
    var avpu: AVPU = .alert
    var oriented: Int = 4          // A&O x0-4 (person, place, time, event)
    var heartRate = ""             // per minute
    var respRate = ""              // per minute
    var skin = ""                  // color, temperature, moisture, e.g. "pink, warm, dry"
    var bloodPressure = ""         // e.g. "120/80" or "radial pulse present"
    var pupils = ""                // e.g. "PERRL"
    var temperature = ""           // body temperature if measured

    var loc: String { avpu == .alert ? "A&Ox\(oriented)" : avpu.label }

    var compact: String {
        var parts = [loc]
        if !heartRate.isEmpty { parts.append("HR\(heartRate)") }
        if !respRate.isEmpty { parts.append("RR\(respRate)") }
        if !bloodPressure.isEmpty { parts.append("BP \(bloodPressure)") }
        if !skin.isEmpty { parts.append("skin \(skin)") }
        if !pupils.isEmpty { parts.append("pupils \(pupils)") }
        if !temperature.isEmpty { parts.append("T \(temperature)") }
        return parts.joined(separator: ", ")
    }
}

struct Patient: Codable, Identifiable {
    var id = UUID()
    var started = Date.now

    // Scene
    var sceneSafe: Check = .unknown
    var mechanism = ""            // what happened
    var patientCount = "1"
    var sceneNotes = ""           // hazards, resources, location

    // Patient
    var age = ""
    var sex = ""
    var chiefComplaint = ""

    // Primary survey
    var avpu: AVPU = .alert
    var airway: Check = .unknown
    var breathing: Check = .unknown
    var circulation: Check = .unknown      // pulse present, severe bleeding controlled
    var severeBleeding = false
    var spineConcern = false
    var primaryNotes = ""

    // Secondary survey
    var examFindings = ""         // head-to-toe
    var symptoms = ""             // S (and OPQRST for pain)
    var allergies = ""            // A
    var medications = ""          // M
    var history = ""              // P
    var lastInOut = ""            // L
    var events = ""               // E

    var vitals: [VitalSet] = []

    // Assessment and plan
    var problems = ""
    var plan = ""
    var evac: EvacUrgency = .undecided

    var title: String {
        let who = [age.isEmpty ? nil : "\(age)y", sex.isEmpty ? nil : sex].compactMap { $0 }.joined(separator: " ")
        let what = chiefComplaint.isEmpty ? "Patient" : chiefComplaint
        return who.isEmpty ? what : "\(who) · \(what)"
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
}

// MARK: - SOAP note

enum SOAP {
    static func note(_ p: Patient) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        let tf = DateFormatter()
        tf.timeStyle = .short

        func line(_ label: String, _ value: String) -> String? {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "\(label): \(value)"
        }
        var s: [String] = ["SOAP NOTE · started \(df.string(from: p.started))", ""]

        s.append("S — SUBJECTIVE")
        s += [line("Patient", [p.age.isEmpty ? "" : "\(p.age) y/o", p.sex].filter { !$0.isEmpty }.joined(separator: " ")),
              line("Chief complaint", p.chiefComplaint),
              line("What happened", p.mechanism),
              line("Symptoms", p.symptoms),
              line("Allergies", p.allergies),
              line("Medications", p.medications),
              line("Pertinent history", p.history),
              line("Last in/out", p.lastInOut),
              line("Events leading up", p.events)].compactMap { $0 }
        s.append("")

        s.append("O — OBJECTIVE")
        s.append("Scene safe: \(p.sceneSafe.rawValue). Patients: \(p.patientCount).")
        if let n = line("Scene", p.sceneNotes) { s.append(n) }
        s.append("Primary: \(p.avpu.label); airway \(p.airway.rawValue); breathing \(p.breathing.rawValue); "
                 + "circulation \(p.circulation.rawValue)"
                 + (p.severeBleeding ? "; severe bleeding" : "")
                 + (p.spineConcern ? "; possible spine injury" : "") + ".")
        if let n = line("Primary notes", p.primaryNotes) { s.append(n) }
        if let n = line("Exam", p.examFindings) { s.append(n) }
        if p.vitals.isEmpty {
            s.append("Vitals: none recorded")
        } else {
            s.append("Vitals:")
            for v in p.vitals { s.append("  \(tf.string(from: v.time)) — \(v.compact)") }
        }
        s.append("")

        s.append("A — ASSESSMENT")
        s.append(p.problems.isEmpty ? "(not yet written)" : p.problems)
        let flags = p.redFlags
        if !flags.isEmpty { s.append("Red flags: " + flags.joined(separator: "; ")) }
        s.append("")

        s.append("P — PLAN")
        s.append(p.plan.isEmpty ? "(not yet written)" : p.plan)
        s.append("Evacuation: \(p.evac.rawValue)")
        return s.joined(separator: "\n")
    }

    /// Fits a satellite messenger's 160-character limit.
    static func satellite(_ p: Patient, limit: Int = 160) -> String {
        var parts: [String] = []
        if p.evac != .undecided { parts.append(p.evac.short) }
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

    /// A compact summary for the AI (its context window is small).
    static func forAI(_ p: Patient) -> String {
        let full = note(p)
        return full.count <= 1400 ? full : String(full.prefix(1400)) + "…"
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
