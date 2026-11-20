import ActivityKit
import Foundation

/// The Live Activity for downloads (the field guides and the larger model), on the Lock Screen and in the
/// Dynamic Island. Shared by the app, which starts and updates it, and the widget extension, which draws it.
struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Stage: String, Codable, Hashable { case starting, downloading, finished, failed }

        var stage: Stage
        /// What's downloading: "Field guides", "Larger AI model", or both.
        var title: String
        /// What it covers ("library", "model"), so a relaunched app can tell whether they finished meanwhile.
        var kinds: [String]
        /// 0...1 when the app last heard from iOS.
        var fraction: Double
        /// "Downloading 0.95 GB", or why it stopped.
        var detail: String
        /// When it should finish at the speed so far. iOS keeps downloading while the app is suspended but the app
        /// can't update the activity then, so the bar and countdown run on their own toward this.
        var estimatedEnd: Date?
        /// When `fraction` was measured.
        var updatedAt: Date

        /// The span the bar fills across, chosen so it shows `fraction` at `updatedAt` and is full at
        /// `estimatedEnd`. Nil when there's no estimate yet: the bar then shows `fraction` as it stands.
        var progressSpan: ClosedRange<Date>? {
            guard stage == .downloading, let end = estimatedEnd, end > updatedAt, fraction < 1 else { return nil }
            let total = end.timeIntervalSince(updatedAt) / (1 - fraction)
            return updatedAt.addingTimeInterval(-fraction * total)...end
        }
    }
}
