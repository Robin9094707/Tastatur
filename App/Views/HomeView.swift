import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var store: SharedStore
    @State private var showSetup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                if !store.hasAPIKey { apiKeyHint }
                NavigationLink { WorkshopView() } label: {
                    GlassCard(tint: Theme.tint(store.keyboardTint).opacity(0.35)) {
                        CardHeader(title: "KI-Werkstatt", symbol: "wand.and.stars.inverse",
                                   subtitle: "Lange Texte einfügen und zusammenfassen, korrigieren, übersetzen – ohne Längenlimit.")
                    }
                }
                .buttonStyle(.plain)
                tipsCard
                setupCard
                statsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .glassBackground()
        .navigationTitle("Tastatur KI")
        .sheet(isPresented: $showSetup) { SetupGuideView() }
    }

    private var hero: some View {
        GlassCard(padding: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deine KI-Tastatur")
                        .font(.title2.bold())
                    Text("Autokorrektur, Vorschläge, Makros, Zwischenablage und ChatGPT – direkt beim Tippen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            HStack {
                StatusPill(ok: store.hasAPIKey, text: store.hasAPIKey ? "API verbunden" : "Kein API-Schlüssel")
                StatusPill(ok: store.usesAppGroup, text: store.usesAppGroup ? "Sync aktiv" : "Sync eingeschränkt")
            }
            Text("Modell: \(store.chatModel)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var apiKeyHint: some View {
        NavigationLink {
            APIKeyView()
        } label: {
            GlassCard(tint: .orange) {
                CardHeader(title: "API-Schlüssel hinterlegen", symbol: "key.fill", subtitle: "Für alle KI-Funktionen brauchst du einen OpenAI-Schlüssel.")
            }
        }
        .buttonStyle(.plain)
    }

    private var tipsCard: some View {
        GlassCard {
            CardHeader(title: "So holst du alles raus", symbol: "lightbulb")
            tip("sparkles", "Tippe in der Tastatur auf ✨ für KI, Ablage, Makros und Emojis.")
            tip("wand.and.stars", "Der Zauberstab rechts öffnet direkt die KI-Aktionen.")
            tip("character.cursor.ibeam", "Markiere Text, damit die KI nur diesen bearbeitet – sonst wird der ganze Text im Feld genutzt.")
            tip("doc.on.clipboard", "Riesige Texte (z. B. Artikel, Mails): kopieren und in der Tastatur „Quelle: Zwischenablage“ wählen.")
            tip("arrow.left.and.right", "Wische über die Leertaste, um den Cursor zu bewegen.")
            tip("hand.point.up.left", "Halte Buchstaben gedrückt für Umlaute und Akzente (s → ß).")
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(text).font(.subheadline)
        }
    }

    private var setupCard: some View {
        GlassCard {
            CardHeader(title: "Einrichtung", symbol: "checklist", subtitle: "In 30 Sekunden startklar.")
            GlassButton(title: "Anleitung öffnen", symbol: "book") { showSetup = true }
            GlassButton(title: "iOS-Einstellungen öffnen", symbol: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }

    private var statsCard: some View {
        GlassCard {
            CardHeader(title: "Statistik", symbol: "chart.bar.xaxis")
            HStack {
                stat("\(store.stat("aiActions"))", "KI-Aktionen")
                stat("\(store.stat("macros"))", "Makros")
                stat("\(store.stat("corrections"))", "Korrekturen")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// In der App: beliebig lange Texte mit KI bearbeiten.
struct WorkshopView: View {
    @EnvironmentObject var store: SharedStore
    @State private var input = ""
    @State private var output = ""
    @State private var original = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showDiff = false
    @State private var task: Task<Void, Never>?
    @State private var customPrompt = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    HStack {
                        CardHeader(title: "Dein Text", symbol: "doc.plaintext", subtitle: "\(input.wordCount) Wörter · \(input.count) Zeichen")
                    }
                    TextField("Text hier einfügen oder tippen …", text: $input, axis: .vertical)
                        .lineLimit(6...16)
                        .padding(12)
                        .glass(cornerRadius: 14)
                    HStack {
                        GlassButton(title: "Einfügen", symbol: "doc.on.clipboard") {
                            if let s = UIPasteboard.general.string { input = s }
                        }
                        GlassButton(title: "Leeren", symbol: "trash") { input = ""; output = "" }
                    }
                }

                ForEach([ActionCategory.summary, .edit, .tone, .translate, .custom]) { cat in
                    let items = store.actions.filter { $0.enabled && $0.category == cat }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cat.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(items) { action in
                                        Button { run(action.prompt, diff: action.showDiff) } label: {
                                            Label(action.title, systemImage: action.symbol)
                                                .font(.subheadline.weight(.semibold))
                                                .padding(.horizontal, 14)
                                                .frame(height: 40)
                                                .glassCapsule(interactive: true)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(busy)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                    }
                }

                GlassCard {
                    CardHeader(title: "Eigene Anweisung", symbol: "text.bubble")
                    HStack {
                        TextField("z. B. Schreib daraus eine LinkedIn-Post", text: $customPrompt)
                            .padding(10)
                            .glass(cornerRadius: 12)
                        Button { run(customPrompt, diff: false) } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title)
                        }
                        .disabled(customPrompt.isEmpty || busy)
                    }
                }

                if busy || !output.isEmpty || error != nil {
                    GlassCard(tint: Theme.tint(store.keyboardTint).opacity(0.2)) {
                        HStack {
                            CardHeader(title: "Ergebnis", symbol: "sparkles", subtitle: output.isEmpty ? nil : "\(output.wordCount) Wörter")
                            if busy {
                                Button("Stopp") { task?.cancel(); busy = false }.buttonStyle(.bordered)
                            }
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.subheadline)
                        }
                        if showDiff, !busy, let segs = TextDiff.segments(original: original, revised: output) {
                            diffText(segs).textSelection(.enabled)
                        } else {
                            Text(output.isEmpty ? "…" : output).textSelection(.enabled)
                        }
                        if !busy && !output.isEmpty {
                            HStack {
                                GlassButton(title: "Kopieren", symbol: "doc.on.doc", prominent: true) {
                                    UIPasteboard.general.string = output
                                    store.addClip(output)
                                }
                                GlassButton(title: "Übernehmen", symbol: "arrow.up.doc") {
                                    input = output
                                    output = ""
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .glassBackground()
        .navigationTitle("KI-Werkstatt")
        .scrollDismissesKeyboard(.interactively)
    }

    private func diffText(_ segs: [TextDiff.Segment]) -> Text {
        var attr = AttributedString()
        for s in segs {
            var part = AttributedString(s.text)
            if s.changed {
                part.swiftUI.foregroundColor = .green
                part.swiftUI.font = .body.bold()
            }
            attr += part
        }
        return Text(attr)
    }

    private func run(_ instruction: String, diff: Bool) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { error = "Füge zuerst einen Text ein."; return }
        busy = true
        error = nil
        output = ""
        original = text
        showDiff = diff
        store.incrementStat("aiActions")
        task = Task {
            do {
                let result = try await OpenAIClient().transform(text: text, instruction: instruction) { partial in
                    Task { @MainActor in output = partial }
                }
                await MainActor.run { output = result; busy = false }
            } catch {
                await MainActor.run {
                    if !(error is CancellationError) { self.error = error.localizedDescription }
                    busy = false
                }
            }
        }
    }
}

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String)] = [
        ("1", "gear", "Öffne die iOS-Einstellungen → Allgemein → Tastatur → Tastaturen."),
        ("2", "plus.circle", "Tippe auf „Tastatur hinzufügen…“ und wähle „Tastatur KI“."),
        ("3", "lock.open", "Tippe auf „Tastatur KI“ und aktiviere „Vollen Zugriff erlauben“. Nötig für KI und Zwischenablage. Dein Text geht nur an OpenAI – mit deinem eigenen Schlüssel."),
        ("4", "key", "Trage in dieser App unter „KI“ deinen OpenAI-API-Schlüssel ein."),
        ("5", "globe", "Halte in einer beliebigen App die 🌐-Taste gedrückt und wähle „Tastatur KI“."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(steps, id: \.0) { step in
                        GlassCard {
                            HStack(alignment: .top, spacing: 14) {
                                Text(step.0)
                                    .font(.headline)
                                    .frame(width: 34, height: 34)
                                    .glass(cornerRadius: 17, tint: .accentColor)
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: step.1).foregroundStyle(.tint)
                                    Text(step.2).font(.subheadline)
                                }
                            }
                        }
                    }
                    GlassButton(title: "Einstellungen öffnen", symbol: "gear", prominent: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                .padding(16)
            }
            .glassBackground()
            .navigationTitle("Einrichtung")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
