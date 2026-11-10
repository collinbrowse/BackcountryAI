import SwiftUI

struct ChatView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Assistant.self) private var assistant
    @State private var draft = ""
    @State private var showLibrary = false
    @State private var showGuide = false
    @State private var openArticle: Passage?
    @State private var searchOnly = false
    @FocusState private var focused: Bool

    static let examples = [
        "How do I treat early frostbite on my toes?",
        "My truck won't start and just clicks. What do I check?",
        "How do I start a fire with wet wood?",
        "Signs of hypothermia and what to do",
        "How do I purify water from a stream?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if assistant.messages.isEmpty { emptyState }
                        ForEach(assistant.messages) { m in
                            MessageView(message: m, open: { openArticle = $0 }).id(m.id)
                        }
                        if searchOnly, !draft.isEmpty, let lib = store.library {
                            SearchResultsView(query: draft, library: lib, open: { openArticle = $0 })
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.messages.last?.text) {
                    if let id = assistant.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Backcountry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLibrary = true } label: {
                        Label("Library", systemImage: store.library == nil ? "books.vertical.circle" : "books.vertical")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showGuide = true } label: { Label("How to use Backcountry", systemImage: "questionmark.circle") }
                        Button { showLibrary = true } label: { Label("Offline library", systemImage: "books.vertical") }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { assistant.clear() } label: { Label("New chat", systemImage: "square.and.pencil") }
                        .disabled(assistant.messages.isEmpty || assistant.isBusy)
                }
            }
            .sheet(isPresented: $showLibrary) { LibraryView() }
            .fullScreenCover(isPresented: $showGuide) {
                OnboardingView(isReplay: true) { showGuide = false }
            }
            .sheet(item: $openArticle) { p in ArticleView(passage: p) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.library == nil {
                Button { showLibrary = true } label: {
                    Label("Download the offline library first (while you have Wi-Fi)", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.orange.opacity(0.15), in: .rect(cornerRadius: 12))
                }
            } else {
                Text("\(store.articleCount.formatted()) articles on this phone. No signal needed.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            BatteryNote()
            if let problem = assistant.availabilityProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .padding(12)
                    .background(.yellow.opacity(0.15), in: .rect(cornerRadius: 12))
            }
            Text("Try asking").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(Self.examples, id: \.self) { e in
                Button { send(e) } label: {
                    Text(e).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(store.library == nil)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            Picker("Mode", selection: $searchOnly) {
                Text("Ask AI").tag(false)
                Text("Search only (saves battery)").tag(true)
            }
            .pickerStyle(.segmented)
            HStack(alignment: .bottom, spacing: 8) {
                TextField(searchOnly ? "Search the library" : "Ask about first aid, gear, engines…",
                          text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.background.secondary, in: .rect(cornerRadius: 18))
                    .submitLabel(.send)
                    .onSubmit { if !searchOnly { send(draft) } }
                if assistant.isBusy {
                    Button { assistant.stop() } label: { Image(systemName: "stop.circle.fill").font(.title) }
                } else if !searchOnly {
                    Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || store.library == nil)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ text: String) {
        assistant.ask(text, library: store.library)
        draft = ""
        focused = false
    }
}

struct BatteryNote: View {
    var body: some View {
        Label {
            Text("**Heavy on battery.** The AI runs on this iPhone and works the chip hard while it answers. You'll see how much battery each answer used. Use **Search only** to save power.")
        } icon: {
            Image(systemName: "battery.25percent").foregroundStyle(.orange)
        }
        .font(.callout)
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
    }
}

struct MessageView: View {
    let message: ChatMessage
    var open: (Passage) -> Void

    var body: some View {
        if message.role == .user {
            Text(message.text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.orange.opacity(0.18), in: .rect(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let status = message.status, message.text.isEmpty {
                    HStack(spacing: 8) { ProgressView(); Text(status).foregroundStyle(.secondary) }
                }
                if !message.text.isEmpty {
                    Text(Self.markdown(message.text))
                        .foregroundStyle(message.failed ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                if !message.sources.isEmpty && message.status == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sources: tap to read and check").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(message.sources.enumerated()), id: \.element.id) { i, s in
                            Button { open(s) } label: { SourceRow(index: i + 1, passage: s) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if let b = message.battery {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.summary)
                        if let session = message.batterySession { Text(session) }
                        if b.lowPowerMode { Text("Low Power Mode is on, so answers may be slower.") }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

struct SourceRow: View {
    let index: Int?
    let passage: Passage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let index {
                Text("\(index)").font(.caption.bold()).frame(width: 20, height: 20)
                    .background(.orange.opacity(0.2), in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(passage.title).font(.subheadline.weight(.medium)).lineLimit(2)
                HStack(spacing: 4) {
                    if passage.official {
                        Text("Official").font(.caption2.bold()).padding(.horizontal, 5)
                            .background(.green.opacity(0.2), in: .capsule)
                    }
                    Text(passage.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }
}

/// Plain library search: no AI, almost no battery.
struct SearchResultsView: View {
    let query: String
    let library: Library
    var open: (Passage) -> Void
    @State private var results: [Passage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(results) { p in
                Button { open(p) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        SourceRow(index: nil, passage: p)
                        Text(p.text).font(.caption).foregroundStyle(.secondary).lineLimit(3).padding(.horizontal, 10)
                    }
                }
                .buttonStyle(.plain)
            }
            if results.isEmpty { Text("No matches yet").foregroundStyle(.secondary) }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))  // wait for typing to pause
            guard !Task.isCancelled else { return }
            let q = query, lib = library
            results = await Task.detached { lib.search(q, limit: 15, maxChars: 300) }.value
        }
    }
}

struct ArticleView: View {
    let passage: Passage
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var article: Article?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(passage.title).font(.title2.bold())
                    Text(passage.source).font(.subheadline).foregroundStyle(.secondary)
                    Text("Matching passage").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text(passage.text)
                        .padding(10)
                        .background(.yellow.opacity(0.18), in: .rect(cornerRadius: 8))
                    Divider()
                    if let article {
                        Text(article.body).textSelection(.enabled)
                        Divider()
                        Group {
                            if !article.url.isEmpty { Text("Original: \(article.url)") }
                            if !article.license.isEmpty { Text("License: \(article.license)") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .padding()
            }
            .toolbar { Button("Done") { dismiss() } }
            .task {
                guard let lib = store.library else { return }
                let id = passage.docID
                article = await Task.detached { lib.article(docID: id) }.value
            }
        }
    }
}
