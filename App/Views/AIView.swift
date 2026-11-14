import SwiftUI

struct AIView: View {
    @EnvironmentObject var store: SharedStore

    var body: some View {
        List {
            Section {
                NavigationLink { APIKeyView() } label: {
                    row("API-Schlüssel", "key.fill", store.hasAPIKey ? "Hinterlegt ✓" : "Fehlt")
                }
                NavigationLink { ModelsView() } label: {
                    row("Modelle", "cpu", store.chatModel)
                }
            } header: { Text("Verbindung") }
            .glassRow()

            Section {
                NavigationLink { ContextView() } label: {
                    row("Persönlicher Kontext", "person.text.rectangle", store.personalContext.isEmpty ? "Leer" : "Aktiv")
                }
                NavigationLink { ProfilesView() } label: {
                    row("Profile", "person.2", store.activeProfile.map { "\($0.emoji) \($0.name)" } ?? "Keins")
                }
                Picker(selection: $store.aiScope) {
                    ForEach(AIScope.allCases) { Text($0.label).tag($0) }
                } label: {
                    Label("Bereich für KI-Aktionen", systemImage: "selection.pin.in.out")
                }
                Toggle(isOn: $store.useAppContext) {
                    Label("Umgebenden Text als Kontext senden", systemImage: "text.viewfinder")
                }
            } header: { Text("Kontext") } footer: {
                Text("Der Kontext wird jeder KI-Anfrage mitgegeben, damit Antworten nach dir klingen. Auch sehr lange Texte im Feld werden vollständig eingelesen.")
            }
            .glassRow()

            Section {
                NavigationLink { ActionsView() } label: {
                    row("KI-Aktionen", "wand.and.stars", "\(store.actions.filter(\.enabled).count) aktiv")
                }
                Toggle(isOn: $store.streamResponses) {
                    Label("Antworten live anzeigen", systemImage: "text.cursor")
                }
                Picker(selection: $store.outputLanguage) {
                    Text("Wie Originaltext").tag("auto")
                    Text("Deutsch").tag("Deutsch")
                    Text("Englisch").tag("Englisch")
                } label: {
                    Label("Antwortsprache", systemImage: "character.bubble")
                }
                Toggle(isOn: $store.aiSuggestions) {
                    Label("KI-Wortvorschläge", systemImage: "text.word.spacing")
                }
            } header: { Text("Funktionen") } footer: {
                Text("„Live anzeigen“ streamt die Antwort Wort für Wort – fühlt sich viel schneller an. KI-Wortvorschläge kosten pro Tipp-Pause eine kleine Anfrage.")
            }
            .glassRow()

        }
        .glassBackground()
        .navigationTitle("KI")
    }

    private func row(_ title: String, _ symbol: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct APIKeyView: View {
    @EnvironmentObject var store: SharedStore
    @State private var draft = ""
    @State private var reveal = false
    @State private var testing = false
    @State private var result: String?
    @State private var success = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    CardHeader(title: "OpenAI-API-Schlüssel", symbol: "key.fill", subtitle: "Wird nur lokal auf deinem Gerät gespeichert.")
                    HStack {
                        Group {
                            if reveal {
                                TextField("sk-…", text: $draft)
                            } else {
                                SecureField("sk-…", text: $draft)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    }
                    .padding(12)
                    .glass(cornerRadius: 14)
                    HStack {
                        GlassButton(title: "Einfügen", symbol: "doc.on.clipboard") {
                            if let s = UIPasteboard.general.string { draft = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        GlassButton(title: "Speichern & testen", symbol: "checkmark", prominent: true) { save() }
                    }
                    if testing { ProgressView("Teste Verbindung…") }
                    if let result {
                        Label(result, systemImage: success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.subheadline)
                            .foregroundStyle(success ? .green : .orange)
                    }
                }
                GlassCard {
                    CardHeader(title: "Eigener Endpunkt", symbol: "server.rack", subtitle: "Optional – z. B. für Azure/Proxy. Standard: api.openai.com")
                    TextField("https://api.openai.com/v1", text: $store.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(12)
                        .glass(cornerRadius: 14)
                }
                GlassCard {
                    CardHeader(title: "So bekommst du einen Schlüssel", symbol: "questionmark.circle")
                    Text("1. Melde dich auf platform.openai.com an.\n2. Gehe zu „API keys“ → „Create new secret key“.\n3. Lade unter „Billing“ ein kleines Guthaben auf (5 $ reichen sehr lange).\n4. Kopiere den Schlüssel und füge ihn hier ein.")
                        .font(.subheadline)
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Label("platform.openai.com öffnen", systemImage: "safari")
                    }
                }
                if store.hasAPIKey {
                    Button("Schlüssel entfernen", role: .destructive) {
                        store.apiKey = ""
                        draft = ""
                        result = nil
                    }
                }
            }
            .padding(16)
        }
        .glassBackground()
        .navigationTitle("API-Schlüssel")
        .onAppear { draft = store.apiKey }
    }

    private func save() {
        store.apiKey = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        testing = true
        result = nil
        Task {
            do {
                let models = try await OpenAIClient().listModels()
                await MainActor.run {
                    store.knownModels = models
                    success = true
                    result = "Verbunden! \(models.count) Modelle verfügbar."
                    autoPickModels(models)
                    testing = false
                }
            } catch {
                await MainActor.run {
                    success = false
                    result = error.localizedDescription
                    testing = false
                }
            }
        }
    }

    /// Wählt sinnvolle Modelle, falls die gespeicherten nicht verfügbar sind.
    private func autoPickModels(_ models: [String]) {
        let set = Set(models)
        if !set.contains(store.chatModel), let m = ModelsView.preferredChat.first(where: set.contains) {
            store.chatModel = m
        }
        if !set.contains(store.fastModel), let m = ModelsView.preferredFast.first(where: set.contains) {
            store.fastModel = m
        }
    }
}

struct ModelsView: View {
    @EnvironmentObject var store: SharedStore
    @State private var loading = false
    @State private var error: String?

    static let preferredChat = SharedStore.fallbackModels
    static let preferredFast = ["gpt-6-luna", "gpt-5.6-luna", "gpt-5-nano", "gpt-4.1-nano", "gpt-4o-mini"]

    private var chatModels: [String] {
        let all = store.knownModels.filter { m in
            (m.hasPrefix("gpt-") || m.hasPrefix("o")) && !m.contains("transcribe") && !m.contains("tts") && !m.contains("audio") && !m.contains("realtime") && !m.contains("image") && !m.contains("search")
        }
        return all.isEmpty ? Array(Set(Self.preferredChat + Self.preferredFast)).sorted() : all
    }

    var body: some View {
        List {
            Section {
                modelField("Hauptmodell", "Für KI-Aktionen und Texte", $store.chatModel, chatModels)
                modelField("Schnelles Modell", "Für KI-Wortvorschläge", $store.fastModel, chatModels)
                Picker("Denkaufwand", selection: $store.reasoningEffort) {
                    Text("Standard").tag("standard")
                    Text("Keiner").tag("none")
                    Text("Minimal").tag("minimal")
                    Text("Niedrig (empfohlen)").tag("low")
                    Text("Mittel").tag("medium")
                }
            } header: { Text("Text-Modelle") } footer: {
                Text("„Niedrig“ ist ideal für eine Tastatur: schnelle Antworten, gute Qualität. Nicht unterstützte Werte werden automatisch ignoriert.")
            }
            .glassRow()

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    priceRow("gpt-6-luna", "0,10 $ / 0,50 $", "Empfohlen · neu · 1 Mio. Kontext")
                    priceRow("gpt-5.6-luna", "0,20 $ / 1,20 $", "Vorgänger")
                    priceRow("gpt-5-mini", "0,25 $ / 2,00 $", "Älter")
                }
                Button("GPT-6 Luna verwenden") {
                    store.chatModel = "gpt-6-luna"
                    store.fastModel = "gpt-6-luna"
                }
            } header: { Text("Preise pro 1 Mio. Tokens (Ein/Aus)") } footer: {
                Text("Eine typische Korrektur kostet mit GPT-6 Luna weniger als 0,001 $. Ist ein Modell für deinen Schlüssel nicht verfügbar, wird automatisch auf das nächste ausgewichen.")
            }
            .glassRow()

            Section {
                Button {
                    refresh()
                } label: {
                    HStack {
                        Label("Modelle von OpenAI laden", systemImage: "arrow.clockwise")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                if !store.knownModels.isEmpty {
                    Text("\(store.knownModels.count) Modelle bekannt").font(.caption).foregroundStyle(.secondary)
                }
            }
            .glassRow()
        }
        .glassBackground()
        .navigationTitle("Modelle")
    }

    private func modelField(_ title: String, _ subtitle: String, _ binding: Binding<String>, _ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Modellname", text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Menu {
                    ForEach(options, id: \.self) { m in
                        Button(m) { binding.wrappedValue = m }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down.circle.fill").font(.title3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func priceRow(_ model: String, _ price: String, _ note: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model).font(.subheadline.monospaced().weight(.semibold))
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(price).font(.caption.monospacedDigit())
        }
    }

    private func refresh() {
        loading = true
        error = nil
        Task {
            do {
                let models = try await OpenAIClient().listModels()
                await MainActor.run { store.knownModels = models; loading = false }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; loading = false }
            }
        }
    }
}

struct ContextView: View {
    @EnvironmentObject var store: SharedStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    CardHeader(title: "Über mich", symbol: "person.crop.circle", subtitle: "Name, Beruf, Wohnort, wichtige Personen, Fakten …")
                    editor($store.personalContext, placeholder: "z. B. Ich heiße Alex, bin Student in Berlin und arbeite nebenbei als Barista. Meine Freundin heißt Sam.")
                }
                GlassCard {
                    CardHeader(title: "Mein Schreibstil", symbol: "pencil.and.scribble", subtitle: "Wie sollen Texte klingen?")
                    editor($store.writingStyle, placeholder: "z. B. Kurz und direkt, gerne mit Emojis, keine Floskeln, ich schreibe „Hey“ statt „Hallo“.")
                }
                GlassCard {
                    CardHeader(title: "Vorschau des System-Prompts", symbol: "eye")
                    Text(OpenAIClient(store: store).systemPrompt())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .glassBackground()
        .navigationTitle("Kontext")
        .scrollDismissesKeyboard(.interactively)
    }

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(4...12)
            .padding(12)
            .glass(cornerRadius: 14)
    }
}

struct ProfilesView: View {
    @EnvironmentObject var store: SharedStore
    @State private var editing: ContextProfile?

    var body: some View {
        List {
            Section {
                Button {
                    store.activeProfileID = ""
                } label: {
                    HStack {
                        Text("Kein Profil")
                        Spacer()
                        if store.activeProfileID.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                ForEach(store.profiles) { p in
                    HStack {
                        Button {
                            store.activeProfileID = p.id.uuidString
                        } label: {
                            HStack {
                                Text(p.emoji)
                                VStack(alignment: .leading) {
                                    Text(p.name)
                                    Text(p.context).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if store.activeProfileID == p.id.uuidString { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .buttonStyle(.plain)
                        Button { editing = p } label: { Image(systemName: "pencil.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                .onDelete { store.profiles.remove(atOffsets: $0) }
            } footer: {
                Text("Das aktive Profil kannst du auch direkt in der Tastatur wechseln.")
            }
            .glassRow()
        }
        .glassBackground()
        .navigationTitle("Profile")
        .toolbar {
            Button {
                editing = ContextProfile(name: "", emoji: "✨", context: "")
            } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { profile in
            ProfileEditor(profile: profile) { updated in
                if let i = store.profiles.firstIndex(where: { $0.id == updated.id }) {
                    store.profiles[i] = updated
                } else {
                    store.profiles.append(updated)
                }
            }
        }
    }
}

struct ProfileEditor: View {
    @State var profile: ContextProfile
    var onSave: (ContextProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Emoji", text: $profile.emoji)
                    TextField("Name", text: $profile.name)
                }
                .glassRow()
                Section("Kontext für die KI") {
                    TextField("z. B. Ich schreibe hier mit Kunden, immer per Sie …", text: $profile.context, axis: .vertical)
                        .lineLimit(5...15)
                }
                .glassRow()
            }
            .glassBackground()
            .navigationTitle("Profil")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(profile); dismiss() }.disabled(profile.name.isEmpty)
                }
            }
        }
    }
}

struct ActionsView: View {
    @EnvironmentObject var store: SharedStore
    @State private var editing: AIAction?

    var body: some View {
        List {
            Section {
                ForEach($store.actions) { $action in
                    HStack {
                        Image(systemName: action.symbol).frame(width: 28).foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(action.title)
                            Text("\(action.category.label) · \(action.prompt)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: $action.enabled).labelsHidden()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = action }
                }
                .onMove { store.actions.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { store.actions.remove(atOffsets: $0) }
            } footer: {
                Text("Die Reihenfolge hier bestimmt die Reihenfolge in der Tastatur. Tippe auf eine Aktion, um den Prompt anzupassen.")
            }
            .glassRow()
            Section {
                Button("Standard-Aktionen wiederherstellen") { store.actions = AIAction.defaults }
            }
            .glassRow()
        }
        .glassBackground()
        .navigationTitle("KI-Aktionen")
        .toolbar {
            EditButton()
            Button {
                editing = AIAction(title: "", symbol: "wand.and.stars", prompt: "")
            } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { action in
            ActionEditor(action: action) { updated in
                if let i = store.actions.firstIndex(where: { $0.id == updated.id }) {
                    store.actions[i] = updated
                } else {
                    store.actions.append(updated)
                }
            }
        }
    }
}

struct ActionEditor: View {
    @State var action: AIAction
    var onSave: (AIAction) -> Void
    @Environment(\.dismiss) private var dismiss

    private let symbols = ["wand.and.stars", "sparkles", "checkmark.seal", "text.append", "briefcase", "face.smiling", "scissors", "globe", "envelope", "heart", "bolt", "lightbulb", "list.bullet", "quote.bubble", "graduationcap", "flame"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") { TextField("z. B. Wie ein Pirat", text: $action.title) }
                    .glassRow()
                Section("Kategorie") {
                    Picker("Kategorie", selection: $action.category) {
                        ForEach(ActionCategory.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Toggle("Änderungen markieren", isOn: $action.showDiff)
                }
                .glassRow()
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8)) {
                        ForEach(symbols, id: \.self) { s in
                            Image(systemName: s)
                                .frame(width: 34, height: 34)
                                .background(action.symbol == s ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { action.symbol = s }
                        }
                    }
                }
                .glassRow()
                Section {
                    TextField("Was soll die KI mit dem Text machen?", text: $action.prompt, axis: .vertical)
                        .lineLimit(4...12)
                } header: { Text("Anweisung") } footer: {
                    Text("Die Anweisung wird auf den markierten bzw. aktuellen Text angewendet.")
                }
                .glassRow()
            }
            .glassBackground()
            .navigationTitle(action.title.isEmpty ? "Neue Aktion" : action.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(action); dismiss() }
                        .disabled(action.title.isEmpty || action.prompt.isEmpty)
                }
            }
        }
    }
}

