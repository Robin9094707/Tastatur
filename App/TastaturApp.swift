import SwiftUI
import UIKit

@main
struct TastaturApp: App {
    @StateObject private var store = SharedStore.shared
    @StateObject private var login = ChatGPTLogin()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack { HomeView() }
                .environmentObject(store)
                .environmentObject(login)
                .onOpenURL { url in
                    // Aus der Tastatur: tastatur://chatgpt-login startet direkt die Anmeldung
                    if url.host == "chatgpt-login" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { login.start() }
                    }
                }
                .preferredColorScheme(.dark)
                .tint(Theme.tint(store.keyboardTint))
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reload() }
                }
        }
    }
}
