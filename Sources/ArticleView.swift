import SwiftUI

/// A library article, opened from a source card or search result. Starts with the passage that
/// matched, so you can check the answer without hunting through the article.
struct ArticleView: View {
    let passage: Passage
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var blocks: [AnswerBlock]?
    @State private var article: Article?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    matched
                    if let blocks {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in block(b) }
                        footer
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task {
                guard let lib = store.library else { blocks = []; return }
                let id = passage.docID
                let loaded = await Task.detached(priority: .userInitiated) { () -> (Article?, [AnswerBlock]) in
                    let a = lib.article(docID: id)
                    return (a, AnswerBlock.parse(a?.body ?? ""))
                }.value
                article = loaded.0
                withAnimation(.easeOut) { blocks = loaded.1 }
            }
        }
        .tint(Theme.ember)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(passage.source).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                if passage.official { OfficialBadge() }
            }
            Text(passage.title)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
        }
    }

    private var matched: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Why this matched", systemImage: "text.magnifyingglass")
                .font(.caption.weight(.bold)).foregroundStyle(Theme.emberDeep)
            Text(passage.text).font(.callout).foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ember.opacity(0.09), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16).fill(Theme.ember).frame(width: 4)
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
                Circle().fill(Theme.ember).frame(width: 5, height: 5).offset(y: -2)
                Text(Inline.render(t, citations: false)).fixedSize(horizontal: false, vertical: true)
            }
        case let .step(n, t):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(n).").font(.body.weight(.bold)).foregroundStyle(Theme.emberDeep)
                Text(Inline.render(t, citations: false)).fixedSize(horizontal: false, vertical: true)
            }
        case .notFromLibrary:
            EmptyView()
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
