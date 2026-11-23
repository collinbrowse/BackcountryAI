import Testing
@testable import BackcountryAI

/// The emergency number follows the phone's region, so nobody outside North America is told to call 911.
struct EmergencyTests {
    @Test(arguments: [("US", "911"), ("CA", "911"), ("MX", "911"), ("GB", "999"), ("AU", "000"), ("NZ", "111"),
                      ("JP", "119"), ("DE", "112"), ("FR", "112"), ("IN", "112"), ("gb", "999")])
    func numberForRegion(_ region: String, _ number: String) {
        #expect(Emergency.number(for: region) == number)
    }

    @Test func unknownRegionGets112() {
        #expect(Emergency.number(for: nil) == "112")
        #expect(Emergency.number(for: "ZZ") == "112")
    }

    @Test func replacesOnly911() {
        let text = "Call or text 911 now. Poison Control (1-800-222-1222 in the U.S.) or 911. Room 9115, unit 1911."
        #expect(Emergency.localized(text, number: "112")
                == "Call or text 112 now. Poison Control (1-800-222-1222 in the U.S.) or 112. Room 9115, unit 1911.")
    }

    @Test func leaves911Alone() {
        #expect(Emergency.localized("Call 911.", number: "911") == "Call 911.")
    }

    @Test func promptsTellTheModelTheLocalNumber() {
        #expect(Emergency.localized(Retrieval.emergencyShape, number: "999").contains("texting 999"))
        #expect(!Emergency.localized(Retrieval.emergencyShape, number: "999").contains("911"))
    }
}
