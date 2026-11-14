import SwiftUI
import UIKit
import PhotosUI

/// Die App ist bewusst schlank: Status, Einrichtung, Schlüssel, Sticker.
/// Alles andere wird direkt in der Tastatur eingestellt.
struct HomeView: View {
    @EnvironmentObject var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSetup = false
    @State private var keyDraft = ""
    @State private var revealKey = false
    @State private var testing = false
    @State private var keyResult: String?
    @State private var keyOK = false
    @State private var photoItem: PhotosPickerItem?
    @State private var enabled = false
    @State private var testText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                statusCard
                apiCard
                NavigationLink { StickerManagerView() } label: {
                    GlassCard {
                        HStack {
                            CardHeader(title: "Sticker", symbol: "face.dashed.fill", subtitle: "Fotos auswählen – Motiv wird automatisch freigestellt")
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                backgroundCard
                NavigationLink { DictionaryView() } label: {
                    GlassCard {
                        HStack {
                            CardHeader(title: "Mein Wörterbuch", symbol: "character.book.closed.fill", subtitle: "Was die Tastatur über dich gelernt hat")
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                testCard
                GlassCard {
                    CardHeader(title: "Alles andere in der Tastatur", symbol: "keyboard.badge.ellipsis")
                    Text("Designs, KI, Übersetzen, Makros, Schnellleiste und alle Optionen findest du direkt in der Tastatur: tippe links oben auf ⊞ → Einstellungen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .glassBackground()
        .navigationTitle("Tastatur KI")
        .sheet(isPresented: $showSetup) { SetupGuideView() }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, p in if p == .active { refresh() } }
        .onChange(of: photoItem) { _, item in loadBackground(item) }
        .scrollDismissesKeyboard(.interactively)
    }

    private func refresh() {
        keyDraft = store.apiKey
        enabled = Self.keyboardEnabled()
    }

    /// Prüft, ob die Tastatur in den iOS-Einstellungen hinzugefügt wurde.
    static func keyboardEnabled() -> Bool {
        let id = "de.tastatur.app.keyboard"
        if let list = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String], list.contains(where: { $0.contains(id) }) {
            return true
        }
        let sel = NSSelectorFromString("identifier")
        return UITextInputMode.activeInputModes.contains { mode in
            guard mode.responds(to: sel) else { return false }
            return (mode.value(forKey: "identifier") as? String)?.contains(id) == true
        }
    }

    private var hero: some View {
        GlassCard(padding: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deine KI-Tastatur").font(.title2.bold())
                    Text("Tippen, Übersetzen, Korrigieren, Sticker und KI – alles direkt in der Tastatur.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }

    private var statusCard: some View {
        GlassCard {
            CardHeader(title: "Status", symbol: "checkmark.shield")
            statusRow("Tastatur hinzugefügt", ok: enabled, hint: "Einstellungen → Allgemein → Tastatur → Tastaturen")
            statusRow("Voller Zugriff", ok: store.keyboardHasFullAccess, hint: store.keyboardLastSeen == nil ? "Öffne die Tastatur einmal, dann wird das geprüft" : "In den Tastatur-Einstellungen aktivieren")
            statusRow("API-Schlüssel", ok: store.hasAPIKey, hint: "Unten eintragen oder in der Tastatur")
            statusRow("Einstellungen teilen (App Group)", ok: store.usesAppGroup, hint: "Ohne App Group: alles direkt in der Tastatur einstellen")
            if let seen = store.keyboardLastSeen {
                (Text("Tastatur zuletzt benutzt: ") + Text(seen, style: .relative))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                GlassButton(title: "Anleitung", symbol: "book") { showSetup = true }
                GlassButton(title: "Einstellungen", symbol: "gear", prominent: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
    }

    private func statusRow(_ title: String, ok: Bool, hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if !ok { Text(hint).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }

    private var apiCard: some View {
        GlassCard {
            CardHeader(title: "OpenAI-API-Schlüssel", symbol: "key.fill", subtitle: "Nur lokal gespeichert · Modell: \(store.chatModel)")
            HStack {
                Group {
                    if revealKey { TextField("sk-…", text: $keyDraft) } else { SecureField("sk-…", text: $keyDraft) }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                Button { revealKey.toggle() } label: { Image(systemName: revealKey ? "eye.slash" : "eye") }
            }
            .padding(12)
            .glass(cornerRadius: 14)
            HStack {
                GlassButton(title: "Einfügen", symbol: "doc.on.clipboard") {
                    if let s = UIPasteboard.general.string { keyDraft = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                GlassButton(title: testing ? "Teste …" : "Speichern", symbol: "checkmark", prominent: true) { saveKey() }
            }
            if let keyResult {
                Label(keyResult, systemImage: keyOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(keyOK ? .green : .orange)
            }
            Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                Label("Schlüssel erstellen auf platform.openai.com", systemImage: "safari").font(.caption)
            }
        }
    }

    private func saveKey() {
        store.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.hasAPIKey else { keyResult = "Schlüssel entfernt"; keyOK = true; return }
        testing = true
        keyResult = nil
        Task {
            do {
                let models = try await OpenAIClient().listModels()
                await MainActor.run {
                    store.knownModels = models
                    if !models.contains(store.chatModel), let m = SharedStore.fallbackModels.first(where: models.contains) {
                        store.chatModel = m
                        store.fastModel = m
                    }
                    keyOK = true
                    keyResult = "Verbunden ✓ – Modell: \(store.chatModel)"
                    testing = false
                }
            } catch {
                await MainActor.run {
                    keyOK = false
                    keyResult = error.localizedDescription
                    testing = false
                }
            }
        }
    }

    private var backgroundCard: some View {
        GlassCard {
            CardHeader(title: "Hintergrundbild", symbol: "photo.fill", subtitle: "Foto als Tastatur-Hintergrund")
            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Foto wählen", systemImage: "photo.on.rectangle")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glass(cornerRadius: 14, tint: .accentColor, interactive: true)
                }
                .buttonStyle(.plain)
                if store.backgroundStyle == "image" {
                    GlassButton(title: "Entfernen", symbol: "xmark") { store.backgroundStyle = "system" }
                }
            }
            if !store.usesAppGroup {
                Text("Ohne App Group kommt das Bild nicht in der Tastatur an. Alternative: Bild kopieren → Tastatur → Einstellungen → Design → „Bild aus Zwischenablage“.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func loadBackground(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let jpeg = Theme.downsampledJPEG(from: data, maxPixel: 1200) {
                await MainActor.run { store.saveBackgroundImage(jpeg); store.themeID = "" }
            }
        }
    }

    private var testCard: some View {
        GlassCard {
            CardHeader(title: "Testfeld", symbol: "character.cursor.ibeam", subtitle: "Mit 🌐 zur Tastatur KI wechseln und ausprobieren")
            TextField("Hier tippen …", text: $testText, axis: .vertical)
                .lineLimit(3...8)
                .padding(12)
                .glass(cornerRadius: 14)
        }
    }
}

/// Sticker anlegen – mit automatischem Freistellen (Apple Vision).
struct StickerManagerView: View {
    @State private var items: [PhotosPickerItem] = []
    @State private var stickers: [URL] = []
    @State private var cutout = true
    @State private var working = false
    @State private var thumbs: [URL: UIImage] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    CardHeader(title: "Neue Sticker", symbol: "plus.circle.fill", subtitle: "Bis zu 20 Fotos auf einmal")
                    Toggle("Motiv automatisch freistellen", isOn: $cutout)
                    PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) {
                        Label(working ? "Erstelle Sticker …" : "Fotos auswählen", systemImage: "photo.stack")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .glass(cornerRadius: 14, tint: .accentColor, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                    if working { ProgressView() }
                    Text("In der Tastatur: ⊞ → Sticker → antippen kopiert den Sticker, dann im Chat einfügen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(stickers, id: \.self) { url in
                        Group {
                            if let img = thumbs[url] {
                                Image(uiImage: img).resizable().scaledToFit()
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .glass(cornerRadius: 16)
                        .contextMenu {
                            Button(role: .destructive) {
                                StickerStore.delete(url)
                                reload()
                            } label: { Label("Löschen", systemImage: "trash") }
                        }
                        .onAppear {
                            if thumbs[url] == nil { thumbs[url] = StickerStore.thumbnail(url, maxPixel: 300) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .glassBackground()
        .navigationTitle("Sticker")
        .onAppear(perform: reload)
        .onChange(of: items) { _, newItems in process(newItems) }
    }

    private func reload() { stickers = StickerStore.list() }

    private func process(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }
        working = true
        let doCutout = cutout
        // Freistellen ist rechenintensiv – nicht auf dem Haupt-Thread
        Task.detached(priority: .userInitiated) {
            for item in newItems {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                let prepared = StickerMaker.normalized(image, maxSide: 1024)
                let result = doCutout ? (StickerMaker.liftSubject(prepared) ?? prepared) : prepared
                StickerStore.add(image: result)
            }
            await MainActor.run {
                items = []
                working = false
                reload()
            }
        }
    }
}

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String)] = [
        ("1", "gear", "Öffne die iOS-Einstellungen → Allgemein → Tastatur → Tastaturen."),
        ("2", "plus.circle", "Tippe auf „Tastatur hinzufügen…“ und wähle „Tastatur KI“."),
        ("3", "lock.open", "Tippe auf „Tastatur KI“ und aktiviere „Vollen Zugriff erlauben“. Nötig für KI, Zwischenablage und Sticker. Dein Text geht nur an OpenAI – mit deinem eigenen Schlüssel."),
        ("4", "key", "Trage deinen OpenAI-API-Schlüssel ein – hier in der App oder direkt in der Tastatur."),
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
