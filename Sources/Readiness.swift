import Foundation
import Network
import Observation
import SwiftUI

/// Whether the phone has any network path right now. Used to show "Offline" honestly and to notice
/// when someone has tested the app in Airplane Mode.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkMonitor.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }
}

/// "Trail ready": the four things that make the app work when you need it. Kept deliberately small;
/// it's the only game-like part of the app and every item is something you really should do before a trip.
enum Readiness {
    static let askedKey = "readiness.asked"
    static let offlineKey = "readiness.askedOffline"
    static let celebratedKey = "readiness.celebrated"

    struct Item: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let done: Bool
    }

    @MainActor
    static func items(libraryReady: Bool, aiReady: Bool, asked: Bool, offline: Bool) -> [Item] {
        [
            Item(id: "library", title: "Download the library", detail: "Answers come from it. Needs Wi-Fi.",
                 symbol: "books.vertical.fill", done: libraryReady),
            Item(id: "ai", title: "Turn on Apple Intelligence", detail: "The model downloads once, then works offline.",
                 symbol: "sparkles", done: aiReady),
            Item(id: "asked", title: "Ask a practice question", detail: "Try one of the topics below.",
                 symbol: "bubble.left.and.text.bubble.right.fill", done: asked),
            Item(id: "offline", title: "Test it in Airplane Mode", detail: "Prove it works with no signal.",
                 symbol: "airplane", done: offline),
        ]
    }

    /// The checklist as it stands, from what's saved on this phone.
    @MainActor
    static func current(libraryReady: Bool, aiReady: Bool) -> [Item] {
        let d = UserDefaults.standard
        return items(libraryReady: libraryReady, aiReady: aiReady,
                     asked: d.bool(forKey: askedKey), offline: d.bool(forKey: offlineKey))
    }

    /// Called when an answer finishes without error.
    @MainActor
    static func recordAnswer() {
        let d = UserDefaults.standard
        d.set(true, forKey: askedKey)
        if !NetworkMonitor.shared.isOnline { d.set(true, forKey: offlineKey) }
    }
}
