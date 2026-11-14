import SwiftUI
import Observation

enum AppTab: Hashable { case scout, guide, saved }

/// Lets any screen hand a question to Scout: switches to the chat tab and starts it there.
@MainActor @Observable final class Router {
    var tab: AppTab = .scout
    /// The Scout tab's stack: your chats underneath, the open chat pushed on top. The app opens on a chat.
    var chatPath: [ChatRoute] = [.chat]
    /// A question waiting for the chat tab to send it.
    var pending: String?
    /// Set to open Field mode in the Guide tab (from the SOS sheet).
    var openField = false
    /// What the app menu has open (see AppSheets).
    var sheet: AppSheet?
    var showHowItWorks = false

    func ask(_ question: String) {
        pending = question
        showChat()
    }

    /// Switches to Scout with the current chat on screen.
    func showChat() {
        withAnimation(.bouncy) {
            tab = .scout
            chatPath = [.chat]
        }
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

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Scout", systemImage: "bubble.left.and.text.bubble.right.fill", value: AppTab.scout) {
                NavigationStack(path: $router.chatPath) {
                    ChatListView()
                        .navigationDestination(for: ChatRoute.self) { _ in ChatView() }
                }
            }
            Tab("Guide", systemImage: "book.pages.fill", value: AppTab.guide) {
                GuideView()
            }
            Tab("Saved", systemImage: "bookmark.fill", value: AppTab.saved) {
                NavigationStack {
                    SavedListView()
                        .navigationDestination(for: Route.self) { route in
                            if case let .savedChat(id) = route { SavedChatView(chatID: id) }
                        }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in  // a file opened in the app from Files or a share sheet
            guard url.isFileURL else { return }
            store.importDocuments([url])
            router.sheet = .library
        }
        .modifier(AppSheets())
        .environment(router)
        .tint(Theme.accent)
    }
}

enum ChatRoute: Hashable { case chat }

/// The sheets the app menu opens.
enum AppSheet: String, Identifiable {
    case library, readiness
    var id: String { rawValue }
}

enum Route: Hashable {
    case savedChat(UUID)
}
