import ActivityKit
import Foundation
import Observation
import UIKit

/// Keeps the downloads' Live Activity in step with the field guides and the larger model: starts it when a download
/// starts, updates it as progress comes in, and ends it when everything is done, stopped or cancelled.
///
/// While iOS has the app suspended the download carries on but the app can't run, so each update also carries an
/// estimated finish time and the activity's bar and countdown move toward it on their own. When the app runs again
/// (or relaunches and rejoins the download) the real figures replace the estimate.
@MainActor
final class DownloadActivity {
    static let shared = DownloadActivity()

    private typealias State = DownloadActivityAttributes.ContentState
    private typealias Content = ActivityContent<State>
    /// The activity on screen, by ID: ActivityKit's calls are made off the main actor, which looks it up again.
    private var activityID: String?
    /// What this activity covers ("library", "model"), to tell finished from cancelled when it ends.
    private var tracking: Set<String> = []
    /// The first progress reading of this download: the speed so far is measured from it.
    private var firstReading: (date: Date, bytes: Double)?
    private var lastSent: (date: Date, state: State)?
    private var latest: Snapshot?
    private var observing: Task<Void, Never>?

    /// Updates sent at most this often while progress trickles in; changes of stage always go at once.
    static let minimumInterval: TimeInterval = 3

    private init() {}

    func observe(store: LibraryStore, better: BetterModel) {
        guard observing == nil, !ScreenshotMode.isOn else { return }
        #if DEBUG
        // The simulator can't run the real downloads: `-DemoDownloadActivity` shows a sample one to check the design.
        if ProcessInfo.processInfo.arguments.contains("-DemoDownloadActivity") {
            let now = Date()
            let state = State(stage: .downloading, title: "Offline field guides", kinds: ["library"], fraction: 0.38,
                              detail: "Downloading 0.95 GB", estimatedEnd: now.addingTimeInterval(240), updatedAt: now)
            _ = try? Activity.request(attributes: DownloadActivityAttributes(), content: Content(state: state, staleDate: nil))
            return
        }
        #endif
        // An activity from before the app was last stopped: carry on with it if its download resumes.
        let leftover = Activity<DownloadActivityAttributes>.activities.first
        activityID = leftover?.id
        tracking = Set(leftover?.content.state.kinds ?? [])
        observing = Task { [weak self] in
            for await snapshot in Observations({ Snapshot(store: store, better: better) }) {
                await self?.apply(snapshot)
            }
        }
        // Leaving the app: send the freshest figures and estimate, since there may be no more until it's back.
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated {
                let shared = DownloadActivity.shared
                guard let latest = shared.latest else { return }
                Task { await shared.apply(latest, force: true) }
            }
        }
    }

    private func apply(_ snapshot: Snapshot, force: Bool = false) async {
        latest = snapshot
        if snapshot.parts.isEmpty {
            await finish(snapshot)
            return
        }
        tracking.formUnion(snapshot.parts.map(\.kind))
        let state = makeState(snapshot)
        let content = Content(state: state, staleDate: Self.staleDate(state))
        if let activityID {
            if !force, let last = lastSent, last.state.stage == state.stage,
               Date().timeIntervalSince(last.date) < Self.minimumInterval { return }
            lastSent = (Date(), state)
            await Self.update(activityID, content)
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            activityID = (try? Activity.request(attributes: DownloadActivityAttributes(), content: content))?.id
            lastSent = (Date(), state)
        }
    }

    private nonisolated static func update(_ id: String, _ content: Content) async {
        await Activity<DownloadActivityAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private nonisolated static func end(_ id: String, _ content: Content?,
                                        dismissalPolicy: ActivityUIDismissalPolicy) async {
        await Activity<DownloadActivityAttributes>.activities.first { $0.id == id }?
            .end(content, dismissalPolicy: dismissalPolicy)
    }

    /// Nothing downloading any more: show how it ended, or take it away if it was cancelled.
    private func finish(_ snapshot: Snapshot) async {
        guard let current = activityID.flatMap({ id in
            Activity<DownloadActivityAttributes>.activities.first { $0.id == id }
        }) ?? Activity<DownloadActivityAttributes>.activities.first else { return }
        let id = current.id
        let title = lastSent?.state.title ?? current.content.state.title
        let tracking = tracking
        let kinds = Array(tracking)
        let fraction = lastSent?.state.fraction ?? 0
        // Reset before ending, so a download started meanwhile gets an activity of its own.
        activityID = nil
        self.tracking = []
        firstReading = nil
        lastSent = nil
        if let failure = tracking.lazy.compactMap({ snapshot.failures[$0] }).first {
            let state = State(stage: .failed, title: title, kinds: kinds, fraction: fraction,
                              detail: failure, estimatedEnd: nil, updatedAt: Date())
            await Self.end(id, Content(state: state, staleDate: nil), dismissalPolicy: .default)
        } else if !tracking.isEmpty, tracking.allSatisfy({ snapshot.ready.contains($0) }) {
            let state = State(stage: .finished, title: title, kinds: kinds, fraction: 1, detail: "Downloaded",
                              estimatedEnd: nil, updatedAt: Date())
            await Self.end(id, Content(state: state, staleDate: nil),
                           dismissalPolicy: .after(Date().addingTimeInterval(10 * 60)))
        } else {
            // Cancelled, or left over from a run whose download didn't resume.
            await Self.end(id, nil, dismissalPolicy: .immediate)
        }
    }

    private func makeState(_ snapshot: Snapshot) -> State {
        let now = Date()
        let total = snapshot.parts.reduce(0) { $0 + $1.bytes }
        guard snapshot.parts.allSatisfy({ $0.fraction != nil }) else {
            return State(stage: .starting, title: snapshot.title, kinds: Array(tracking), fraction: 0,
                         detail: "Starting the download…",
                         estimatedEnd: nil, updatedAt: now)
        }
        let done = snapshot.parts.reduce(0) { $0 + ($1.fraction ?? 0) * $1.bytes }
        let fraction = total > 0 ? min(done / total, 1) : 0
        let first = firstReading ?? (now, done)
        firstReading = first
        var end: Date?
        let elapsed = now.timeIntervalSince(first.date)
        if elapsed > 5, done > first.bytes {
            let rate = (done - first.bytes) / elapsed
            end = now.addingTimeInterval((total - done) / rate)
        }
        // The total, not how much is done: that figure would sit still while the app is suspended and the bar moves.
        let detail = String(format: "Downloading %.2f GB", total / 1e9)
        return State(stage: .downloading, title: snapshot.title, kinds: Array(tracking), fraction: fraction,
                     detail: detail,
                     estimatedEnd: end, updatedAt: now)
    }

    /// After this the activity says it should be about done and to open the app, rather than keep a full bar
    /// waiting for an app that can't run to say so.
    private static func staleDate(_ state: State) -> Date? {
        state.estimatedEnd.map { $0.addingTimeInterval(5 * 60) }
    }
}

/// What's downloading right now, read from the stores. Values only, so it can leave the main actor.
private struct Snapshot: Sendable, Equatable {
    struct Part: Sendable, Equatable {
        let kind: String
        let fraction: Double?
        let bytes: Double
    }

    var parts: [Part] = []
    /// What's on the phone now ("library", "model").
    var ready: Set<String> = []
    /// Why a download stopped, by kind.
    var failures: [String: String] = [:]

    @MainActor
    init(store: LibraryStore, better: BetterModel) {
        if !store.hasPack && store.isWorking {
            parts.append(Part(kind: "library", fraction: store.downloadFraction,
                              bytes: Double(store.packs.first?.downloadBytes ?? 1)))
        }
        if case let .downloading(f) = better.state {
            parts.append(Part(kind: "model", fraction: f > 0 ? f : nil, bytes: Double(better.downloadBytes)))
        }
        if store.hasPack { ready.insert("library") }
        if better.isDownloaded { ready.insert("model") }
        if case let .failed(message) = store.phase { failures["library"] = message }
        if case let .failed(message) = better.state, !better.isDownloaded { failures["model"] = message }
    }

    var title: String {
        switch Set(parts.map(\.kind)) {
        case ["library"]: "Offline field guides"
        case ["model"]: "Larger AI model"
        default: "Field guides and AI model"
        }
    }
}
