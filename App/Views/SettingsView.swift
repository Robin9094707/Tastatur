import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: SharedStore
    @State private var confirmReset = false
    @State private var learnedCount = 0

    var body: some View {
        List {
            Section {
                Toggle(isOn: $store.aiSuggestions) { Label("KI-Vorschläge & Satzfortsetzung", systemImage: "sparkles") }
                Toggle(isOn: $store.autocorrect) { Label("Autokorrektur", systemImage: "textformat.abc.dottedunderline") }
                Toggle(isOn: $store.smartTouch) { Label("Intelligente Trefferzonen", systemImage: "hand.point.up.braille") }
                Toggle(isOn: $store.liveAICorrection) { Label("KI-Live-Korrektur", systemImage: "checkmark.seal") }
                Toggle(isOn: $store.autocapitalize) { Label("Automatische Großschreibung", systemImage: "textformat.size.larger") }
                Toggle(isOn: $store.doubleSpacePeriod) { Label("Punkt durch doppeltes Leerzeichen", systemImage: "circle.fill") }
                Toggle(isOn: $store.learnWords) { Label("Neue Wörter lernen", systemImage: "brain") }
                Toggle(isOn: $store.showNumberRow) { Label("Zahlenreihe anzeigen", systemImage: "number") }
            } header: { Text("Tippen & Tippkontrolle") } footer: {
                Text("Trefferzonen: Triffst du zwischen zwei Tasten, gewinnt der Buchstabe, der ein echtes Wort ergibt. KI-Live-Korrektur: Nach ein paar Wörtern und einer kurzen Pause werden nur eindeutige Tippfehler korrigiert – mit Rückgängig-Knopf in der Leiste.")
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
                NavigationLink { DictionaryView() } label: {
                    HStack {
                        Label("Mein Wörterbuch", systemImage: "character.book.closed")
                        Spacer()
                        Text("\(learnedCount) Wörter").foregroundStyle(.secondary)
                    }
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

/// Alles, was die Tastatur über dich gelernt hat.
struct DictionaryView: View {
    @EnvironmentObject var store: SharedStore
    @State private var words: [(String, Int)] = []
    @State private var tokens: [(String, Int)] = []
    @State private var search = ""

    private static var tokensURL: URL { SharedStore.containerURL.appendingPathComponent("tokens.json") }

    var body: some View {
        List {
            Section {
                ForEach(Array(tokens.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }.enumerated()), id: \.offset) { _, t in
                    HStack {
                        Text(t.0).lineLimit(1)
                        Spacer()
                        Text("\(t.1)×").foregroundStyle(.secondary).font(.caption)
                    }
                    .swipeActions { Button("Löschen", role: .destructive) { removeToken(t.0) } }
                }
                if tokens.isEmpty {
                    Text("E-Mail-Adressen, Links, Nummern und @Namen, die du öfter tippst, landen hier und werden dir vorgeschlagen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Persönliche Einträge") }
            .glassRow()

            Section {
                ForEach(Array(words.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }.prefix(300).enumerated()), id: \.offset) { _, w in
                    HStack {
                        Text(w.0)
                        Spacer()
                        Text("\(w.1)×").foregroundStyle(.secondary).font(.caption)
                    }
                    .swipeActions { Button("Löschen", role: .destructive) { removeWord(w.0) } }
                }
            } header: { Text("Gelernte Wörter (häufigste zuerst)") }
            .glassRow()
        }
        .glassBackground()
        .searchable(text: $search, prompt: "Suchen")
        .navigationTitle("Mein Wörterbuch")
        .onAppear(perform: load)
    }

    private func load() {
        words = store.loadLearnedWords().sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        if let data = try? Data(contentsOf: Self.tokensURL),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            tokens = dict.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        }
    }

    private func removeWord(_ w: String) {
        var dict = store.loadLearnedWords()
        dict[w] = nil
        store.saveLearnedWords(dict)
        load()
    }

    private func removeToken(_ t: String) {
        var dict = Dictionary(uniqueKeysWithValues: tokens.map { ($0.0, $0.1) })
        dict[t] = nil
        if let data = try? JSONEncoder().encode(dict) { try? data.write(to: Self.tokensURL, options: .atomic) }
        load()
    }
}
