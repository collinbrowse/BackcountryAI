import Foundation
import Testing
@testable import BackcountryAI

/// Field mode's record and what it writes: the assessment order, the vital signs, the SOAP note and the rescue call.
struct FieldModeTests {
    private func patient() -> Patient {
        var p = Patient()
        p.name = "Sam"; p.age = "34"; p.sex = "M"; p.pronouns = "he/him"
        p.chiefComplaint = "left leg pain"; p.mechanism = "fell 5 m"
        p.kind = .trauma; p.condition = .critical; p.evac = .fast
        var v = VitalSet()
        v.heartRate = "110"; v.respRate = "24"; v.bloodPressure = "weak wrist pulse"; v.skin = "pale, cool, clammy"
        v.csm = "x4"; v.pupils = "PERRL"
        p.vitals = [v]
        p.problems = "Open tib-fib fracture"; p.worstCase = "Shock"; p.plan = "Splint"
        return p
    }

    @Test func theAssessmentRunsInTheCoursesOrder() {
        #expect(AssessmentStep.allCases == [.scene, .primary, .vitals, .history, .exam, .plan, .reassess])
        var p = Patient()
        #expect(AssessmentStep.allCases.allSatisfy { !$0.isDone(p) })
        p.vitals = [VitalSet()]
        #expect(AssessmentStep.vitals.isDone(p) && !AssessmentStep.reassess.isDone(p))
        p.vitals.append(VitalSet())
        #expect(AssessmentStep.reassess.isDone(p))
    }

    @Test func aVitalSetReadsInTheOrderItIsTaken() {
        let v = patient().vitals[0]
        #expect(v.compact == "HR110, RR24, BP weak wrist pulse, A&Ox4, skin pale, cool, clammy, CSM x4, pupils PERRL")
        #expect(VitalSet().compact == "A&Ox4")
    }

    @Test func theNoteCarriesTheAnticipatedWorstCase() {
        let note = SOAP.note(patient())
        #expect(note.contains("S — SUBJECTIVE\nPatient: Sam, 34 y/o M (he/him)\nChief complaint: left leg pain\nWhat happened: fell 5 m"))
        #expect(note.contains("After the primary assessment: critical trauma."))
        #expect(note.contains("A — ASSESSMENT\nOpen tib-fib fracture\nAnticipated worst case: Shock"))
        #expect(note.contains("P — PLAN\nSplint\nEvacuation: Evacuate urgently"))
        // An empty record still writes a note.
        let blank = SOAP.note(Patient())
        #expect(blank.contains("S — SUBJECTIVE\n\nO — OBJECTIVE") && blank.contains("Vitals: none recorded"))
    }

    @Test func theRescueMessageLeadsWithStableOrCritical() {
        let p = patient()
        let message = SOAP.satellite(p)
        #expect(message.hasPrefix("Critical trauma, URGENT evac. 34M. left leg pain. fell 5 m. HR110"))
        #expect(message.count <= 160)
        let call = SOAP.rescueCall(p)
        #expect(call.count == 9)
        #expect(call[2] == "Critical trauma. Chief complaint: left leg pain.")
        #expect(call[3] == "\"We need a rescue. Do you copy?\"")
        #expect(call[5] == "34-year-old M: fell 5 m.")
        // With nothing recorded it is still the script to follow.
        let blank = SOAP.rescueCall(Patient())
        #expect(blank[2] == "Stable or critical? Injury or illness? Their chief complaint.")
        #expect(blank[5] == "Their age and sex, and what happened.")
        #expect(blank[7] == "Their latest vital signs.")
        #expect(SOAP.satellite(Patient()).isEmpty)
    }

    @Test func aRecordSavedByAnOlderVersionStillOpens() throws {
        // What the app wrote before: no name, pronouns, CSM, worst case or transport decision.
        let old = """
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","started":800000000,"sceneSafe":"OK","mechanism":"fell",
             "patientCount":"1","sceneNotes":"","age":"40","sex":"F","chiefComplaint":"ankle","avpu":"A","airway":"OK",
             "breathing":"OK","circulation":"OK","severeBleeding":false,"spineConcern":false,"primaryNotes":"",
             "examFindings":"","symptoms":"","allergies":"","medications":"","history":"","lastInOut":"","events":"",
             "vitals":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","time":800000100,"avpu":"A","oriented":4,
                        "heartRate":"88","respRate":"16","skin":"pink","bloodPressure":"","pupils":"","temperature":""}],
             "problems":"sprain","plan":"wrap","evac":"Treat in the field"}
            """
        let p = try JSONDecoder().decode(Patient.self, from: Data(old.utf8))
        #expect(p.chiefComplaint == "ankle" && p.evac == .stay && p.vitals.first?.heartRate == "88")
        #expect(p.id.uuidString == "6F9619FF-8B86-D011-B42D-00C04FC964FF")
        #expect(p.name.isEmpty && p.worstCase.isEmpty && p.kind == .unknown && p.condition == .unknown)
        #expect(p.vitals.first?.csm == "")
        // And what this version writes reads back whole.
        let again = try JSONDecoder().decode(Patient.self, from: JSONEncoder().encode(patient()))
        #expect(again.name == "Sam" && again.kind == .trauma && again.condition == .critical)
        #expect(again.vitals.first?.csm == "x4" && again.worstCase == "Shock")
    }
}
