import Foundation

/// When a download should finish, from its progress readings, steady enough to show as a countdown.
///
/// iOS reports progress in bursts. Measuring speed on a timer would count the pauses between bursts as the download
/// slowing down, and push the finish time back a little every few seconds. So the speed comes only from readings that
/// brought new bytes, and the finish time moves only when the new figure differs enough to matter.
struct DownloadEstimate {
    /// No estimate before this much downloading: early speeds swing too much to be worth showing.
    static let warmUp: TimeInterval = 15
    /// The finish time moves only by more than this, or `relativeShift` of the time left, whichever is larger.
    static let minimumShift: TimeInterval = 15
    static let relativeShift = 0.1

    private var first: (date: Date, bytes: Double)?
    private var newest: (date: Date, bytes: Double)?
    /// The estimated finish, once there is one.
    private(set) var end: Date?
    /// Bytes per second over the readings so far, once past the warm-up.
    private(set) var rate: Double?

    /// Records a reading and returns the finish estimate (nil while still warming up).
    /// - Parameters:
    ///   - bytes: downloaded so far, including anything downloaded before this measurement began (a resumed download
    ///     counts from its first reading here, so earlier bytes don't inflate the speed).
    ///   - total: the full size.
    @discardableResult
    mutating func record(bytes: Double, total: Double, at now: Date = Date()) -> Date? {
        guard let first else {
            first = (now, bytes)
            newest = (now, bytes)
            return nil
        }
        // No new bytes since the last reading: a pause between reports, not a slowdown.
        guard bytes > newest?.bytes ?? bytes else { return end }
        newest = (now, bytes)
        let elapsed = now.timeIntervalSince(first.date)
        guard elapsed >= Self.warmUp else { return end }
        let rate = (bytes - first.bytes) / elapsed
        guard rate > 0 else { return end }
        self.rate = rate
        let candidate = now.addingTimeInterval(max(total - bytes, 0) / rate)
        if let end {
            let left = max(end.timeIntervalSince(now), 0)
            guard abs(candidate.timeIntervalSince(end)) > max(Self.minimumShift, left * Self.relativeShift) else {
                return end
            }
        }
        end = candidate
        return end
    }
}
