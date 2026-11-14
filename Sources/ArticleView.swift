import SwiftUI

/// A library article, opened from a source card or search result. Long articles open at the section the hit
/// came from (see `ArticleFocus`), with the matched passage marked and the whole article a tap away.
struct ArticleView: View {
    let passage: Passage
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Loaded?
    @State private var article: Article?
    @State private var showWhole = false

    private struct Loaded {
        struct Part { let blocks: [AnswerBlock]; let matched: Bool }
        let section: [Part], whole: [Part], heading: String?, found: Bool
    }

    nonisolated private static func parts(_ f: ArticleFocus) -> [Loaded.Part] {
        [(f.before, false), (f.match, true), (f.after, false)].map { .init(blocks: AnswerBlock.parse($0.0), matched: $0.1) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        header
                        if let loaded {
                            if !loaded.found && !passage.text.isEmpty { matched }
                            ForEach(Array((showWhole ? loaded.whole : loaded.section).enumerated()), id: \.offset) { i, part in
                                if part.matched && !part.blocks.isEmpty {
                                    VStack(alignment: .leading, spacing: 14) {
                                        ForEach(Array(part.blocks.enumerated()), id: \.offset) { _, b in block(b) }
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.accent.opacity(0.09), in: .rect(cornerRadius: 16, style: .continuous))
                                    .overlay(alignment: .leading) {
                                        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                                            .fill(Theme.accent).frame(width: 4)
                                    }
                                    .id("match")
                                } else {
                                    ForEach(Array(part.blocks.enumerated()), id: \.offset) { _, b in block(b) }
                                }
                            }
                            if let heading = loaded.heading { wholeToggle(heading, proxy: proxy) }
                            footer
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                        }
                    }
                    .padding(20)
                }
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task {
                guard let lib = store.library else { loaded = Loaded(section: [], whole: [], heading: nil, found: false); return }
                let (docID, passageID) = (passage.docID, passage.id)
                let result = await Task.detached(priority: .userInitiated) { () -> (Article?, Loaded) in
                    let a = lib.article(docID: docID)
                    let raw = lib.passageText(id: passageID)
                    let body = a?.body ?? ""
                    let section = ArticleFocus.make(body: body, passage: raw)
                    let whole = ArticleFocus.make(body: body, passage: raw, narrow: false)
                    return (a, Loaded(section: Self.parts(section), whole: Self.parts(whole), heading: section.heading,
                                      found: !whole.match.isEmpty))
                }.value
                article = result.0
                withAnimation(.easeOut) { loaded = result.1 }
            }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(passage.source).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                if passage.official { OfficialBadge() } else if passage.isMine { MineBadge() }
            }
            Text(passage.title)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
        }
    }

    /// Below a narrowed section: the rest of the article, or back to the section.
    private func wholeToggle(_ heading: String, proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut) { showWhole.toggle() }
            Task { @MainActor in withAnimation { proxy.scrollTo("match", anchor: .top) } }
        } label: {
            Label(showWhole ? "Show only “\(heading)”" : "Show the whole article",
                  systemImage: showWhole ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.accent.opacity(0.12), in: .capsule)
        }
        .padding(.top, 8)
    }

    private var matched: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Why this matched", systemImage: "text.magnifyingglass")
                .font(.caption.weight(.bold)).foregroundStyle(Theme.accentDeep)
            Text(passage.text).font(.callout).foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.09), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16).fill(Theme.accent).frame(width: 4)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder private func block(_ b: AnswerBlock) -> some View {
        switch b {
        case let .heading(t):
            Text(Inline.render(t, citations: false)).font(.system(.title3, design: .rounded).weight(.bold)).padding(.top, 8)
        case let .paragraph(t):
            Text(Inline.render(t, citations: false)).fixedSize(horizontal: false, vertical: true)
        case let .bullet(t):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(y: -2)
                Text(Inline.render(t, citations: false)).fixedSize(horizontal: false, vertical: true)
            }
        case let .step(n, t):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(n).").font(.body.weight(.bold)).foregroundStyle(Theme.accentDeep)
                Text(Inline.render(t, citations: false)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if let article, !article.url.isEmpty || !article.license.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !article.url.isEmpty { Text("Original: \(article.url)") }
                if !article.license.isEmpty { Text("License: \(article.license)") }
            }
            .font(.caption).foregroundStyle(Theme.inkSoft)
            .textSelection(.enabled)
            .padding(.top, 16)
        }
    }
}
