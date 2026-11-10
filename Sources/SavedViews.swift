import SwiftUI

struct SavedRow: View {
    let item: SavedAnswer
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Theme.sun)
                .frame(width: 36, height: 36)
                .background(Theme.sun.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.question).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                Text(item.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(Theme.inkSoft)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
        }
        .card(padding: 12, radius: 18)
    }
}

struct SavedListView: View {
    @Environment(SavedStore.self) private var saved

    var body: some View {
        List {
            ForEach(saved.items) { item in
                NavigationLink(value: Route.saved(item)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.question).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(item.date, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .onDelete { idx in idx.map { saved.items[$0] }.forEach(saved.remove) }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if saved.items.isEmpty {
                ContentUnavailableView("Nothing saved yet", systemImage: "bookmark",
                                       description: Text("Tap Save under an answer to keep it. Saved answers open instantly and use no battery."))
            }
        }
        .navigationTitle("Saved answers")
    }
}

struct SavedAnswerView: View {
    let item: SavedAnswer
    @Environment(SavedStore.self) private var saved
    @Environment(\.dismiss) private var dismiss
    @State private var openArticle: Passage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                UserBubble(text: item.question)
                if Urgency.isUrgent(item.question) { SOSBanner() }
                AnswerBody(text: item.answer) { n in
                    if item.sources.indices.contains(n - 1) { openArticle = item.sources[n - 1] }
                }
                if !item.sources.isEmpty { SourceCarousel(sources: item.sources) { openArticle = $0 } }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    saved.remove(item)
                    dismiss()
                } label: { Label("Remove", systemImage: "bookmark.slash") }
            }
        }
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
    }
}

/// Emergency help, one tap from the home screen.
struct SOSSheet: View {
    var ask: (Topic) -> Void
    var openField: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Scout(mood: .alert, size: 70)
                        Text("Stay calm. Get help first, then I'll walk you through it.")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    SOSBanner()
                    VStack(alignment: .leading, spacing: 10) {
                        tip("location.fill", "Share where you are",
                            "Tell the dispatcher your trail, landmarks and GPS coordinates (Compass app shows them).")
                        tip("battery.25percent", "Save battery",
                            "Turn on Low Power Mode. Text instead of calling if your signal keeps dropping.")
                        tip("figure.stand", "Stay put if you're lost",
                            "Rescuers find people faster when they stop moving.")
                    }
                    .card()
                    FieldStartCard(title: "Treating someone?", button: "Open Field mode", action: openField)
                    Text("Walk me through it").sectionLabel()
                    ForEach(Topic.urgent) { t in
                        Button { ask(t) } label: { TopicTile(topic: t) }
                            .buttonStyle(SquishyButtonStyle(scale: 0.97))
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Emergency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { dismiss() } }
        }
        .tint(Theme.accent)
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(text).font(.footnote).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}
