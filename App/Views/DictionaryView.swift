import SwiftUI

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
