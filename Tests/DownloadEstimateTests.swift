import Foundation
import Testing
@testable import BackcountryAI

/// The time-left estimate shown in the library and the Live Activity.
struct DownloadEstimateTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let total = 1_000_000_000.0

    /// 4 MB/s, reported in bursts: one reading every 4 s, with 3 s-later repeats that carry no new bytes.
    @Test func burstyProgressNeverPushesTheFinishBack() {
        var estimate = DownloadEstimate()
        var ends: [Date] = []
        for second in stride(from: 0, through: 200, by: 1) {
            let reported = Double(second / 4 * 4) * 4_000_000  // only moves on every 4th second
            if let end = estimate.record(bytes: reported, total: total, at: start.addingTimeInterval(Double(second))) {
                ends.append(end)
            }
        }
        #expect(!ends.isEmpty)
        // Settles near the true finish (250 s) and never jumps later than the first estimate it showed.
        #expect(abs(ends.last!.timeIntervalSince(start) - 250) < 20)
        #expect(ends.allSatisfy { $0 <= ends.first! })
    }

    @Test func noEstimateDuringWarmUp() {
        var estimate = DownloadEstimate()
        for second in 0..<Int(DownloadEstimate.warmUp) {
            #expect(estimate.record(bytes: Double(second) * 4_000_000, total: total,
                                    at: start.addingTimeInterval(Double(second))) == nil)
        }
    }

    @Test func smallChangesDontMoveTheFinish() {
        var estimate = DownloadEstimate()
        estimate.record(bytes: 0, total: total, at: start)
        let first = estimate.record(bytes: 80_000_000, total: total, at: start.addingTimeInterval(20))
        // A little slower (3.9 MB/s instead of 4): about 6 s later at the end, under the threshold.
        let second = estimate.record(bytes: 82_000_000, total: total, at: start.addingTimeInterval(21))
        #expect(first != nil)
        #expect(second == first)
    }

    @Test func aRealSlowdownMovesTheFinish() {
        var estimate = DownloadEstimate()
        estimate.record(bytes: 0, total: total, at: start)
        let first = estimate.record(bytes: 80_000_000, total: total, at: start.addingTimeInterval(20))!
        // Half the speed from here on.
        let later = estimate.record(bytes: 120_000_000, total: total, at: start.addingTimeInterval(40))!
        #expect(later > first.addingTimeInterval(DownloadEstimate.minimumShift))
    }

    /// A resumed download starts partway: the bytes from before don't count as speed.
    @Test func resumedDownloadMeasuresOnlyNewBytes() {
        var estimate = DownloadEstimate()
        estimate.record(bytes: 500_000_000, total: total, at: start)
        let end = estimate.record(bytes: 580_000_000, total: total, at: start.addingTimeInterval(20))!
        // 4 MB/s with 420 MB left: about 105 s more.
        #expect(abs(end.timeIntervalSince(start) - 125) < 1)
    }
}
