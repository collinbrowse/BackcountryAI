import SwiftUI
import Observation

enum AppTab: Hashable { case scout, guide, saved }

/// Lets any screen hand a question to Scout: switches to the chat tab and starts it there.
@MainActor @Observable final class Router {
    var tab: AppTab = .scout
    /// A question waiting for the chat tab to send it.
    var pending: String?
    /// Set to open Field mode in the Guide tab (from the SOS sheet).
    var openField = false

    func ask(_ question: String) {
        pending = question
        withAnimation(.bouncy) { tab = .scout }
    }

    func showField() {
        tab = .guide
        openField = true
    }
}

/// Chat first: the app opens on Scout. The Guide tab is for browsing the library by topic or source.
struct RootView: View {
    @State private var router = Router()
    @Environment(LibraryStore.self) private var store
    @State private var showImport = false

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Scout", systemImage: "bubble.left.and.text.bubble.right.fill", value: AppTab.scout) {
                ChatView()
            }
            Tab("Guide", systemImage: "book.pages.fill", value: AppTab.guide) {
                GuideView()
            }
            Tab("Saved", systemImage: "bookmark.fill", value: AppTab.saved) {
                NavigationStack {
                    SavedListView()
                        .navigationDestination(for: Route.self) { route in
                            if case let .saved(item) = route { SavedAnswerView(item: item) }
                        }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in  // a file opened in the app from Files or a share sheet
            guard url.isFileURL else { return }
            store.importDocuments([url])
            showImport = true
        }
        .sheet(isPresented: $showImport) { LibraryView() }
        .environment(router)
        .tint(Theme.accent)
    }
}

enum Route: Hashable {
    case saved(SavedAnswer)
}
