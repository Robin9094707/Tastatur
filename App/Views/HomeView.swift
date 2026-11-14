import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var store: SharedStore
    @EnvironmentObject var dictation: DictationService
    @State private var testText = ""
    @State private var showSetup = false
    @FocusState private var testFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                if !store.hasAPIKey { apiKeyHint }
                sessionCard
                inAppDictation
                playground
                setupCard
                statsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .glassBackground()
        .navigationTitle("Tastatur KI")
        .sheet(isPresented: $showSetup) { SetupGuideView() }
        .scrollDismissesKeyboard(.interactively)
    }

    private var hero: some View {
        GlassCard(padding: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deine KI-Tastatur")
                        .font(.title2.bold())
                    Text("Autokorrektur, Vorschläge, Makros, Zwischenablage, Diktat und ChatGPT – direkt beim Tippen.")
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
        }
    }

    private var apiKeyHint: some View {
        NavigationLink {
            APIKeyView()
        } label: {
            GlassCard(tint: .orange) {
                CardHeader(title: "API-Schlüssel hinterlegen", symbol: "key.fill", subtitle: "Für KI-Funktionen und Diktat brauchst du einen OpenAI-Schlüssel.")
            }
        }
        .buttonStyle(.plain)
    }

    private var sessionCard: some View {
        GlassCard {
            CardHeader(title: "Diktat-Sitzung", symbol: dictation.sessionActive ? "waveform.circle.fill" : "waveform.circle",
                       subtitle: dictation.sessionActive ? "Aktiv – du kannst in der Tastatur auf 🎙 tippen." : "Startet die Hintergrund-Aufnahme für die Tastatur.")
            if dictation.sessionActive, let end = dictation.sessionEndsAt {
                HStack {
                    Image(systemName: "timer")
                    Text("Endet automatisch ") + Text(end, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            stateView
            if dictation.sessionActive {
                GlassButton(title: "Sitzung beenden", symbol: "stop.fill") { dictation.endSession() }
            } else {
                GlassButton(title: "Sitzung starten", symbol: "mic.fill", prominent: true) {
                    Task { await dictation.startKeyboardSession(recordImmediately: false) }
                }
            }
            Text("Tipp: Wenn du in der Tastatur auf das Mikrofon tippst, öffnet sich diese App kurz. Wische danach über „◀︎ Zurück“ oben links in deine App zurück – die Aufnahme läuft dann im Hintergrund.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch dictation.state {
        case .recording:
            HStack {
                LevelMeter(level: dictation.level)
                Text("Aufnahme läuft…").font(.subheadline.weight(.medium))
            }
        case .processing:
            HStack { ProgressView(); Text("Wird transkribiert…").font(.subheadline) }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private var inAppDictation: some View {
        GlassCard {
            CardHeader(title: "Schnell-Diktat", symbol: "mic.badge.plus", subtitle: "Direkt hier sprechen – Text landet in der Zwischenablage.")
            HStack(spacing: 16) {
                Button {
                    Task { await dictation.toggleInAppRecording() }
                } label: {
                    Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .glass(cornerRadius: 36, tint: dictation.isRecording ? .red : .accentColor, interactive: true)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading) {
                    if dictation.isRecording {
                        LevelMeter(level: dictation.level)
                        Text("Tippe zum Beenden").font(.caption).foregroundStyle(.secondary)
                    } else if case .processing = dictation.state {
                        ProgressView()
                    } else {
                        Text(dictation.lastTranscript.isEmpty ? "Noch kein Diktat" : dictation.lastTranscript)
                            .font(.subheadline)
                            .lineLimit(4)
                    }
                }
                Spacer(minLength: 0)
            }
            if !dictation.lastTranscript.isEmpty, !dictation.isRecording {
                HStack {
                    GlassButton(title: "Kopieren", symbol: "doc.on.doc") {
                        UIPasteboard.general.string = dictation.lastTranscript
                        store.addClip(dictation.lastTranscript)
                    }
                    GlassButton(title: "Ins Testfeld", symbol: "arrow.down.doc") {
                        testText += (testText.isEmpty ? "" : " ") + dictation.lastTranscript
                    }
                }
            }
        }
        .onChange(of: dictation.state) { _, newValue in
            if case .done(let text) = newValue, !dictation.sessionActive {
                UIPasteboard.general.string = text
                store.addClip(text)
            }
        }
    }

    private var playground: some View {
        GlassCard {
            CardHeader(title: "Testfeld", symbol: "character.cursor.ibeam", subtitle: "Wechsle mit 🌐 zur Tastatur KI und probiere alles aus.")
            TextField("Hier tippen…", text: $testText, axis: .vertical)
                .lineLimit(4...10)
                .focused($testFocused)
                .padding(12)
                .glass(cornerRadius: 14)
            if !testText.isEmpty {
                Button("Leeren", role: .destructive) { testText = "" }.font(.caption)
            }
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
                stat("\(store.stat("dictations"))", "Diktate")
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

struct LevelMeter: View {
    var level: Float
    var bars = 14

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let falloff = 1 - abs(Double(i) - Double(bars) / 2) / Double(bars)
                Capsule()
                    .fill(.tint)
                    .frame(width: 4, height: max(4, CGFloat(Double(level) * 40 * falloff)))
            }
        }
        .frame(height: 40)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String)] = [
        ("1", "gear", "Öffne die iOS-Einstellungen → Allgemein → Tastatur → Tastaturen."),
        ("2", "plus.circle", "Tippe auf „Tastatur hinzufügen…“ und wähle „Tastatur KI“."),
        ("3", "lock.open", "Tippe auf „Tastatur KI“ und aktiviere „Vollen Zugriff erlauben“. Nötig für KI, Zwischenablage und Diktat. Dein Text geht nur an OpenAI – mit deinem eigenen Schlüssel."),
        ("4", "key", "Trage in dieser App unter „KI“ deinen OpenAI-API-Schlüssel ein."),
        ("5", "globe", "Halte in einer beliebigen App die 🌐-Taste gedrückt und wähle „Tastatur KI“."),
        ("6", "mic", "Für Diktat: Tippe in der Tastatur auf das Mikrofon. Die App öffnet sich einmalig für die Diktat-Sitzung – danach oben links zurück wischen und lossprechen."),
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
