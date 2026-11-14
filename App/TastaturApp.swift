import SwiftUI
import UIKit

@main
struct TastaturApp: App {
    @StateObject private var store = SharedStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            RootView(selectedTab: $selectedTab)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.tint(store.keyboardTint))
                .onOpenURL { url in handle(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.reload()
                        captureClipboard()
                    }
                }
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "tastatur" else { return }
        switch url.host ?? "" {
        case "werkstatt", "workshop":
            selectedTab = 0
        case "settings", "ki":
            selectedTab = 1
        case "macros", "makros":
            selectedTab = 2
        case "clipboard", "ablage":
            selectedTab = 3
        default:
            break
        }
    }

    private func captureClipboard() {
        guard store.clipboardEnabled, UIPasteboard.general.hasStrings,
              let text = UIPasteboard.general.string else { return }
        store.addClip(text)
    }
}

struct RootView: View {
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Start", systemImage: "keyboard") }
                .tag(0)
            NavigationStack { AIView() }
                .tabItem { Label("KI", systemImage: "sparkles") }
                .tag(1)
            NavigationStack { MacrosView() }
                .tabItem { Label("Makros", systemImage: "text.badge.star") }
                .tag(2)
            NavigationStack { ClipboardView() }
                .tabItem { Label("Ablage", systemImage: "doc.on.clipboard") }
                .tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("Mehr", systemImage: "slider.horizontal.3") }
                .tag(4)
        }
    }
}
