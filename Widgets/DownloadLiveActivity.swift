import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BackcountryAIWidgets: WidgetBundle {
    var body: some Widget { DownloadLiveActivity() }
}

/// Download progress on the Lock Screen and in the Dynamic Island.
struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StageIcon(stage: state.stage).font(.title2).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLeft(state: state, isStale: context.isStale).font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Bar(state: state)
                        Text(Self.caption(state, isStale: context.isStale)).font(.caption)
                            .foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                StageIcon(stage: state.stage)
            } compactTrailing: {
                Ring(state: state).frame(width: 18, height: 18)
            } minimal: {
                Ring(state: state).frame(width: 18, height: 18)
            }
            .keylineTint(Palette.accent)
        }
    }

    static func caption(_ state: DownloadActivityAttributes.ContentState, isStale: Bool) -> String {
        switch state.stage {
        case .starting: "Starting the download…"
        case .finished: "Ready to use with no signal."
        case .failed: state.detail
        case .downloading:
            isStale ? "Should be about done. Open BackcountryAI to finish." : state.detail
        }
    }
}

private enum Palette {
    static let accent = Color(red: 0x4C / 255, green: 0xC3 / 255, blue: 0xAA / 255)
    static let danger = Color(red: 1, green: 0x5C / 255, blue: 0x61 / 255)
}

private struct LockScreenView: View {
    let state: DownloadActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StageIcon(stage: state.stage).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(DownloadLiveActivity.caption(state, isStale: isStale)).font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
                Spacer(minLength: 8)
                TimeLeft(state: state, isStale: isStale).font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
            if state.stage == .downloading || state.stage == .starting { Bar(state: state) }
        }
    }
}

private struct StageIcon: View {
    let stage: DownloadActivityAttributes.ContentState.Stage
    var body: some View {
        switch stage {
        case .starting, .downloading:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.accent)
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.danger)
        }
    }
}

/// A bar that keeps moving on its own toward the estimated finish while the app is suspended.
private struct Bar: View {
    let state: DownloadActivityAttributes.ContentState
    var body: some View {
        Group {
            if let span = state.progressSpan {
                ProgressView(timerInterval: span, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: state.stage == .finished ? 1 : state.fraction)
            }
        }
        .progressViewStyle(.linear)
        .tint(Palette.accent)
    }
}

private struct Ring: View {
    let state: DownloadActivityAttributes.ContentState
    var body: some View {
        switch state.stage {
        case .finished, .failed:
            StageIcon(stage: state.stage)
        case .starting, .downloading:
            Group {
                if let span = state.progressSpan {
                    ProgressView(timerInterval: span, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: state.fraction)
                }
            }
            .progressViewStyle(.circular)
            .tint(Palette.accent)
        }
    }
}

/// A countdown to the estimated finish, or the percentage when there's no estimate yet.
private struct TimeLeft: View {
    let state: DownloadActivityAttributes.ContentState
    let isStale: Bool
    var body: some View {
        if state.stage == .downloading, !isStale, let end = state.estimatedEnd, end > .now {
            HStack(spacing: 3) {
                Text(timerInterval: Date.now...end, countsDown: true, showsHours: false)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 48, alignment: .trailing)
                Text("left")
            }
        } else if state.stage == .downloading, !isStale {
            Text(state.fraction.formatted(.percent.precision(.fractionLength(0))))
        }
    }
}
