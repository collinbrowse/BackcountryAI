import Foundation

/// The emergency number for the phone's region, so the app doesn't tell someone in Europe or Australia to call 911.
///
/// The app's fixed text, field cards and prompts are written with "911"; `localized(_:)` swaps in the local number
/// where they're shown or sent to the model. The region comes from Settings › General › Language & Region, not
/// from where the phone is. A traveler keeps their home region, which is usually still fine: phones route 112 and
/// 911 to the local service in most countries.
enum Emergency {
    /// The number for the phone's region.
    static var number: String { number(for: Locale.current.region?.identifier) }

    /// Calls `number`. iOS asks for confirmation before it dials.
    static var callURL: URL { URL(string: "tel://\(number)")! }

    /// The general emergency number for an ISO region code. 112 where a region isn't listed: it's the number for
    /// the EU and much of the world, and GSM phones route it to the local service in most other places.
    static func number(for region: String?) -> String {
        guard let region = region?.uppercased() else { return "112" }
        return numbers[region] ?? "112"
    }

    /// `text` with every "911" replaced by the number for the phone's region.
    static func localized(_ text: String) -> String { localized(text, number: number) }

    static func localized(_ text: String, number: String) -> String {
        number == "911" ? text : text.replacing(standalone911, with: number)
    }

    /// 911 on its own, not part of a longer number.
    nonisolated(unsafe) private static let standalone911 = /\b911\b/

    /// Regions whose number isn't 112. Kept to numbers that are certain: everywhere else gets 112, which every GSM
    /// network has to route to its local emergency service. Where police, fire and ambulance differ, this is the
    /// ambulance number, since that's what the app's emergencies need most.
    private static let numbers: [String: String] = [
        // North America (NANP) and Mexico.
        "US": "911", "CA": "911", "PR": "911", "VI": "911", "GU": "911", "AS": "911", "MP": "911", "MX": "911",
        // The UK and Crown dependencies (112 works too).
        "GB": "999", "IM": "999", "JE": "999", "GG": "999",
        // Oceania.
        "AU": "000", "NZ": "111",
        // Asia and the Middle East.
        "JP": "119", "KR": "119", "TW": "119", "CN": "120", "HK": "999", "SG": "995", "MY": "999",
        "TH": "1669", "PH": "911", "IL": "101", "AE": "998", "SA": "997",
    ]
}
