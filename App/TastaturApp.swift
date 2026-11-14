import SwiftUI
import UIKit

@main
struct TastaturApp: App {
    @StateObject private var store = SharedStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack { HomeView() }
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.tint(store.keyboardTint))
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reload() }
                }
        }
    }
}
