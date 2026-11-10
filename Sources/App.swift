import SwiftUI

@main
struct BackcountryApp: App {
    @State private var store = LibraryStore()
    @State private var assistant = Assistant()
    @AppStorage("seenBatteryNotice") private var seenBatteryNotice = false

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(store)
                .environment(assistant)
                .tint(.orange)
                .fullScreenCover(isPresented: .constant(!seenBatteryNotice)) {
                    BatteryNoticeView { seenBatteryNotice = true }
                }
        }
    }
}

/// Shown once, before the first question.
struct BatteryNoticeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "battery.25percent")
                .font(.system(size: 56)).foregroundStyle(.orange)
            Text("This app uses a lot of battery")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("The AI runs entirely on this iPhone, with no internet. The chip works hard the "
                      + "whole time it's writing an answer.", systemImage: "cpu")
                Label("After every answer you'll see how much battery it used, plus a running average.",
                      systemImage: "gauge.with.dots.needle.33percent")
                Label("In the backcountry, carry a battery pack, and use the library search when you don't "
                      + "need a full answer. Reading an article costs almost nothing.",
                      systemImage: "battery.100percent.bolt")
                Label("Download the library before you lose signal.", systemImage: "arrow.down.circle")
            }
            .font(.body)
            Spacer()
            Button(action: onContinue) {
                Text("Got it").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .tint(.orange)
        .interactiveDismissDisabled()
    }
}
