import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: SharedStore
    @State private var confirmReset = false
    @State private var learnedCount = 0

    var body: some View {
        List {
            Section("Tippen") {
                Toggle(isOn: $store.aiSuggestions) { Label("KI-Vorschläge & Satzfortsetzung", systemImage: "sparkles") }
                Toggle(isOn: $store.autocorrect) { Label("Autokorrektur", systemImage: "textformat.abc.dottedunderline") }
                Toggle(isOn: $store.autocapitalize) { Label("Automatische Großschreibung", systemImage: "textformat.size.larger") }
                Toggle(isOn: $store.doubleSpacePeriod) { Label("Punkt durch doppeltes Leerzeichen", systemImage: "circle.fill") }
                Toggle(isOn: $store.learnWords) { Label("Neue Wörter lernen", systemImage: "brain") }
                Toggle(isOn: $store.showNumberRow) { Label("Zahlenreihe anzeigen", systemImage: "number") }
            }
            .glassRow()

            Section("Gefühl") {
                Toggle(isOn: $store.haptics) { Label("Haptisches Feedback", systemImage: "hand.tap") }
                Toggle(isOn: $store.keySound) { Label("Tastenklick", systemImage: "speaker.wave.2") }
                Toggle(isOn: $store.keyPopups) { Label("Tasten-Vorschau beim Tippen", systemImage: "rectangle.on.rectangle") }
            }
            .glassRow()

            Section("Design") {
                NavigationLink { AppearanceView() } label: {
                    HStack {
                        Label("Hintergrund, Farben & Tasten", systemImage: "paintbrush.pointed")
                        Spacer()
                        Circle().fill(Theme.tint(store.keyboardTint).gradient).frame(width: 18, height: 18)
                    }
                }
            }
            .glassRow()

            Section {
                HStack {
                    Label("Favoriten", systemImage: "star")
                    Spacer()
                    Text(store.emojiFavorites.prefix(8).joined())
                }
                Button("Emoji-Verlauf löschen", role: .destructive) { store.emojiRecents = [] }
            } header: { Text("Emojis") } footer: {
                Text("In der Tastatur ein Emoji gedrückt halten, um es zu den Favoriten hinzuzufügen oder zu entfernen.")
            }
            .glassRow()

            Section {
                HStack {
                    Label("Gelernte Wörter", systemImage: "character.book.closed")
                    Spacer()
                    Text("\(learnedCount)").foregroundStyle(.secondary)
                }
                Button("Gelernte Wörter löschen", role: .destructive) {
                    store.saveLearnedWords([:])
                    learnedCount = 0
                }
            } header: { Text("Wörterbuch") }
            .glassRow()

            Section {
                HStack {
                    Label("Datenaustausch", systemImage: "arrow.left.arrow.right")
                    Spacer()
                    Text(store.usesAppGroup ? "App Group aktiv" : "Eingeschränkt").foregroundStyle(store.usesAppGroup ? .green : .orange)
                }
                if !store.usesAppGroup {
                    Text("Die App Group ist nicht verfügbar (z. B. durch die Signierung beim Sideloaden). Trage den API-Schlüssel dann zusätzlich direkt in der Tastatur ein: Tastatur → ⚙︎.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "https://platform.openai.com/usage")!) {
                    Label("OpenAI-Verbrauch ansehen", systemImage: "chart.line.uptrend.xyaxis")
                }
            } header: { Text("System") }
            .glassRow()

            Section {
                Button("Alles zurücksetzen", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Tastatur KI · Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")\nDeine Texte werden nur an OpenAI gesendet, wenn du eine KI-Funktion nutzt.")
            }
            .glassRow()
        }
        .glassBackground()
        .navigationTitle("Einstellungen")
        .onAppear { learnedCount = store.loadLearnedWords().count }
        .confirmationDialog("Wirklich alle Einstellungen, Makros und den API-Schlüssel löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                store.resetAll()
                store.saveClips([])
                store.saveLearnedWords([:])
            }
        }
    }
}
