import UIKit

/// What one answer cost in battery. iOS only reports the battery level in whole-percent steps,
/// so a single answer often reads as "under 1%"; the running average over many answers is more accurate.
struct BatteryReport: Hashable, Sendable {
    var startLevel: Int?      // percent, nil when unknown (simulator)
    var endLevel: Int?
    var seconds: Double
    var wasCharging: Bool
    var lowPowerMode: Bool

    var usedPercent: Int? {
        guard let s = startLevel, let e = endLevel, !wasCharging else { return nil }
        return max(0, s - e)
    }

    /// Compact label for the answer footer, e.g. "<1% · 9s".
    var short: String {
        let time = String(format: "%.0fs", seconds)
        if wasCharging { return "Charging · \(time)" }
        guard let used = usedPercent else { return time }
        return (used == 0 ? "<1%" : "\(used)%") + " · " + time
    }

    var summary: String {
        let time = String(format: "%.0f s", seconds)
        if wasCharging { return "Charging, so battery use can't be measured · \(time)" }
        guard let s = startLevel, let e = endLevel, let used = usedPercent else {
            return "Battery level unavailable on this device · \(time)"
        }
        let amount = used == 0 ? "under 1%" : "about \(used)%"
        return "Used \(amount) of battery (\(s)% → \(e)%) · \(time)"
    }
}

@MainActor
final class BatteryMeter {
    static let shared = BatteryMeter()

    /// Session totals, for an average that is more accurate than any single 1%-step reading.
    private(set) var answers = 0
    private(set) var totalPercent = 0
    private(set) var totalSeconds: Double = 0

    private init() { UIDevice.current.isBatteryMonitoringEnabled = true }

    var level: Int? {
        let l = UIDevice.current.batteryLevel
        return l < 0 ? nil : Int((l * 100).rounded())
    }

    var isCharging: Bool {
        let s = UIDevice.current.batteryState
        return s == .charging || s == .full
    }

    struct Start { let level: Int?; let date: Date; let charging: Bool }

    func begin() -> Start { Start(level: level, date: .now, charging: isCharging) }

    func end(_ start: Start) -> BatteryReport {
        let r = BatteryReport(startLevel: start.level, endLevel: level,
                              seconds: Date.now.timeIntervalSince(start.date),
                              wasCharging: start.charging || isCharging,
                              lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if let used = r.usedPercent {
            answers += 1
            totalPercent += used
            totalSeconds += r.seconds
        }
        return r
    }

    /// e.g. "This session: 3% over 7 answers (about 0.4% each)."
    var sessionSummary: String? {
        guard answers >= 2 else { return nil }
        let each = Double(totalPercent) / Double(answers)
        var s = "This session: \(totalPercent)% over \(answers) answers"
        if totalPercent > 0 {
            s += String(format: " (about %.1f%% each, roughly %d answers per full charge)", each, Int(100 / each))
        }
        return s + "."
    }
}
