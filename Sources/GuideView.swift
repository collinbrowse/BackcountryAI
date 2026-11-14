import SwiftUI

/// Which sources the Guide shows: everything, official sources only, or one source.
enum GuideFilter {
    static let key = "guide.filter"
    static let official = "official"

    static func keys(_ filter: String) -> Set<String>? {
        switch filter {
        case "": nil
        case official: Library.officialLabel
        default: [filter]
        }
    }
}

/// Browse the library without asking: topic shelves (first aid up front), live search and source filters.
struct GuideView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(FieldStore.self) private var field
    @AppStorage(GuideFilter.key) private var filter = ""
    @State private var query = ""
    @State private var results: [Passage] = []
    @State private var searching = false
    @State private var sources: [Library.SourceInfo] = []
    @State private var openArticle: Passage?
    @State private var showLibrary = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if store.library == nil {
                        noLibrary
                    } else if trimmed.count >= 2 {
                        FilterBar(sources: sources, filter: $filter)
                        searchResults
                    } else {
                        fieldCard.riseIn(0)
                        ForEach(Array(GuideCollection.all.enumerated()), id: \.element.id) { i, c in
                            shelf(c).riseIn(i + 1)
                        }
                        bySource.riseIn(6)
                    }
                }
                .padding(.vertical, 12)
                .animation(.bouncy, value: trimmed.count >= 2)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Guide")
            .toolbar { ToolbarItem(placement: .topBarLeading) { SOSToolbarButton() } }
            .searchable(text: $query, prompt: "Search \(store.articleCount.formatted()) articles")
            .navigationDestination(for: Topic.self) { TopicView(topic: $0) }
            .navigationDestination(for: Library.SourceInfo.self) { SourceView(info: $0) }
            .navigationDestination(for: GuideCollection.self) { CollectionView(collection: $0) }
            .navigationDestination(isPresented: Binding(get: { router.openField }, set: { router.openField = $0 })) {
                FieldView()
            }
        }
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
        .sheet(isPresented: $showLibrary) { LibraryView() }
        .task(id: store.articleCount) { loadSources() }
        .task(id: "\(trimmed)|\(filter)") { await search() }
    }

    // MARK: Shelves

    /// Field mode up front: start or continue a patient assessment, plus the quick cards.
    private var fieldCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { router.openField = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: field.patient == nil ? "cross.case.fill" : "stethoscope")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.18), in: .rect(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.patient?.title ?? "Field mode")
                            .font(.system(.title3, design: .rounded).weight(.bold)).lineLimit(2)
                        Text(field.patient == nil ? "Patient assessment, vitals, SOAP note. No AI needed."
                             : "Continue assessment · \(field.patient!.vitals.count) vital sets")
                            .font(.footnote).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).opacity(0.7)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(FieldCard.all.prefix(6)) { c in
                    NavigationLink(value: c) { MiniTile(title: c.title, symbol: c.icon) }
                        .buttonStyle(SquishyButtonStyle(scale: 0.94))
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Theme.pine, Color(hex: 0x13786A)], startPoint: .topLeading,
                                   endPoint: .bottomTrailing), in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16)
        .navigationDestination(for: FieldCard.self) { card in
            FieldCardView(card: card) { q in query = q }
        }
    }

    private func shelf(_ c: GuideCollection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: c) {
                HStack(spacing: 10) {
                    Image(systemName: c.symbol).font(.subheadline.weight(.bold)).foregroundStyle(c.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.headline).foregroundStyle(Theme.ink)
                        Text(c.subtitle).font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Text("See all").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(c.topics) { t in
                        NavigationLink(value: t) { TopicChip(topic: t) }
                            .buttonStyle(SquishyButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var bySource: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By source").sectionLabel().padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { i, s in
                    NavigationLink(value: s) {
                        HStack(spacing: 12) {
                            Image(systemName: s.official ? "checkmark.seal.fill" : "books.vertical.fill")
                                .foregroundStyle(s.official ? Theme.moss : Theme.inkSoft)
                                .frame(width: 26)
                            Text(s.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(s.docs.formatted()).font(.footnote.monospacedDigit()).foregroundStyle(Theme.inkSoft)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.vertical, 13).padding(.horizontal, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if i < sources.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .background(Theme.card, in: .rect(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
            .padding(.horizontal, 16)
        }
    }

    // MARK: Search

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { router.ask(trimmed) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title3).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(Theme.accentGradient, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask Scout instead").font(.headline).foregroundStyle(Theme.ink)
                        Text("Get step-by-step help written from these articles")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
                }
                .card(padding: 12)
            }
            .buttonStyle(SquishyButtonStyle(scale: 0.97))
            HStack {
                Text("\(results.count) matches").sectionLabel()
                if searching { ProgressView().controlSize(.mini) }
            }
            if results.isEmpty && !searching {
                Text(filter.isEmpty ? "No matches. Try other words, like what you see or feel."
                     : "No matches in this filter. Try All sources.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { i, p in
                Button { openArticle = p } label: { SearchResultRow(passage: p) }
                    .buttonStyle(SquishyButtonStyle(scale: 0.98))
                    .riseIn(i)
            }
        }
        .padding(.horizontal, 16)
    }

    private var noLibrary: some View {
        VStack(spacing: 14) {
            Scout(mood: .sleepy, size: 110)
            Text("The Guide needs the offline library").font(.headline).foregroundStyle(Theme.ink)
            Text("Download it once on Wi-Fi. After that, everything here works with no signal.")
                .font(.subheadline).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            Button { showLibrary = true } label: { Label("Get the library", systemImage: "arrow.down.circle.fill") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .padding(.top, 40)
    }

    private func loadSources() {
        guard let lib = store.library else { sources = []; return }
        sources = lib.sources()
    }

    private func search() async {
        let q = trimmed
        guard q.count >= 2, let lib = store.library else { results = []; return }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        searching = true
        let keys = GuideFilter.keys(filter)
        let hits = await Task.detached(priority: .userInitiated) { lib.search(q, limit: 25, maxChars: 220, only: keys) }.value
        guard !Task.isCancelled else { return }
        searching = false
        withAnimation(.bouncy) { results = hits }
    }
}

/// All, Official, then each source by size.
struct FilterBar: View {
    let sources: [Library.SourceInfo]
    @Binding var filter: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All sources", nil, "")
                if sources.contains(where: \.official) { chip("Official only", "checkmark.seal.fill", GuideFilter.official) }
                ForEach(sources) { s in chip(s.label, nil, s.key) }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func chip(_ title: String, _ symbol: String?, _ value: String) -> some View {
        Button { filter = value } label: { FilterChip(title: title, symbol: symbol, selected: filter == value) }
            .buttonStyle(SquishyButtonStyle(scale: 0.92))
    }
}

struct MiniTile: View {
    let title: String
    let symbol: String
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12).padding(.horizontal, 4)
        .background(.white.opacity(0.13), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

/// Every topic in one collection.
struct CollectionView: View {
    let collection: GuideCollection
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(collection.subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft).padding(.bottom, 6)
                ForEach(Array(collection.topics.enumerated()), id: \.element.id) { i, t in
                    NavigationLink(value: t) { TopicTile(topic: t) }
                        .buttonStyle(SquishyButtonStyle(scale: 0.97))
                        .riseIn(i)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(collection.title)
    }
}

/// One topic: ask Scout about it, or read what the library has, filtered by source.
struct TopicView: View {
    let topic: Topic
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage(GuideFilter.key) private var filter = ""
    @State private var results: [Passage]?
    @State private var sources: [Library.SourceInfo] = []
    @State private var openArticle: Passage?

    private var collection: GuideCollection? { GuideCollection.all.first { $0.topics.contains(topic) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header.padding(.horizontal, 16)
                Button { router.ask(topic.question) } label: {
                    Label("Ask Scout about this", systemImage: "bubble.left.and.text.bubble.right.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16)

                if let card = FieldCard.forTopic(topic.id) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Quick card").sectionLabel()
                            Spacer()
                            Text("No AI · instant").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                        FieldCardBody(card: card)
                    }
                    .padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("In the library").sectionLabel().padding(.horizontal, 16)
                    FilterBar(sources: sources, filter: $filter)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let results {
                        if results.isEmpty {
                            Text(filter.isEmpty ? "Nothing in the library on this yet. Scout can still help."
                                 : "Nothing from this source. Try All sources.")
                                .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, p in
                            Button { openArticle = p } label: { SearchResultRow(passage: p) }
                                .buttonStyle(SquishyButtonStyle(scale: 0.98))
                                .riseIn(i)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 16)
                if let siblings = collection?.topics.filter({ $0 != topic }), !siblings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Related").sectionLabel()
                        FlowLayout {
                            ForEach(siblings) { t in
                                NavigationLink(value: t) { SuggestionChip(title: t.title, symbol: t.symbol, tint: t.tint) }
                                    .buttonStyle(SquishyButtonStyle(scale: 0.92))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
        .task { sources = store.library?.sources() ?? [] }
        .task(id: filter) { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: topic.symbol)
                .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(topic.tint.gradient, in: .rect(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                if let collection {
                    Text(collection.title).font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(collection.tint)
                }
                Text(topic.title).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Theme.ink)
            }
        }
    }

    private func load() async {
        guard let lib = store.library else { results = []; return }
        let terms = topic.searchTerms, keys = GuideFilter.keys(filter)
        let hits = await Task.detached(priority: .userInitiated) { lib.search(terms, limit: 20, maxChars: 220, only: keys) }.value
        withAnimation(.bouncy) { results = hits }
    }
}

/// Every article from one source, A to Z, or searched within the source.
struct SourceView: View {
    let info: Library.SourceInfo
    @Environment(LibraryStore.self) private var store
    @State private var items: [Passage] = []
    @State private var done = false
    @State private var query = ""
    @State private var hits: [Passage] = []
    @State private var openArticle: Passage?

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static let page = 60

    var body: some View {
        List {
            if trimmed.count >= 2 {
                ForEach(hits) { p in row(p) }
            } else {
                ForEach(items) { p in
                    row(p).onAppear { if p.id == items.last?.id { loadMore() } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(info.label)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search \(info.docs.formatted()) articles")
        .sheet(item: $openArticle) { ArticleView(passage: $0) }
        .onAppear { if items.isEmpty { loadMore() } }
        .task(id: trimmed) {
            guard trimmed.count >= 2, let lib = store.library else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let q = trimmed, key = info.key
            hits = await Task.detached(priority: .userInitiated) { lib.search(q, limit: 40, maxChars: 160, only: [key]) }.value
        }
    }

    private func row(_ p: Passage) -> some View {
        Button { openArticle = p } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if !p.text.isEmpty { Text(p.text).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(2) }
            }
        }
        .listRowBackground(Color.clear)
    }

    private func loadMore() {
        guard !done, let lib = store.library else { return }
        let next = lib.titles(sourceKey: info.key, offset: items.count, limit: Self.page)
        if next.count < Self.page { done = true }
        items += next
    }
}
