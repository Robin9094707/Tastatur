import Foundation
import Combine

/// Zentrale Einstellungen, die zwischen App und Tastatur über die App Group geteilt werden.
final class SharedStore: ObservableObject {
    static let appGroup = "group.de.tastatur.app"
    static let shared = SharedStore()

    let defaults: UserDefaults
    /// true, wenn die App Group verfügbar ist (bei manchen Sideload-Varianten nicht der Fall).
    let usesAppGroup: Bool

    private init() {
        if let d = UserDefaults(suiteName: SharedStore.appGroup),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup) != nil {
            defaults = d
            usesAppGroup = true
        } else {
            defaults = .standard
            usesAppGroup = false
        }
        reload()
    }

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Werte

    static let defaultChatModel = "gpt-6-luna"
    static let fallbackModels = ["gpt-6-luna", "gpt-5.6-luna", "gpt-5-mini", "gpt-4.1-mini", "gpt-4o-mini"]
    static let settingsVersion = 7

    @Published var apiKey: String = "" { didSet { set(apiKey, "apiKey") } }
    @Published var baseURL: String = "https://api.openai.com/v1" { didSet { set(baseURL, "baseURL") } }
    @Published var chatModel: String = SharedStore.defaultChatModel { didSet { set(chatModel, "chatModel") } }
    @Published var fastModel: String = SharedStore.defaultChatModel { didSet { set(fastModel, "fastModel") } }
    @Published var reasoningEffort: String = "low" { didSet { set(reasoningEffort, "reasoningEffort") } }
    @Published var knownModels: [String] = [] { didSet { setCodable(knownModels, "knownModels") } }
    @Published var streamResponses: Bool = true { didSet { set(streamResponses, "streamResponses") } }
    @Published var outputLanguage: String = "auto" { didSet { set(outputLanguage, "outputLanguage") } }

    @Published var personalContext: String = "" { didSet { set(personalContext, "personalContext") } }
    @Published var writingStyle: String = "" { didSet { set(writingStyle, "writingStyle") } }
    @Published var profiles: [ContextProfile] = ContextProfile.defaults { didSet { setCodable(profiles, "profiles") } }
    @Published var activeProfileID: String = "" { didSet { set(activeProfileID, "activeProfileID") } }
    @Published var aiScope: AIScope = .auto { didSet { set(aiScope.rawValue, "aiScope") } }
    @Published var useAppContext: Bool = true { didSet { set(useAppContext, "useAppContext") } }

    @Published var actions: [AIAction] = AIAction.defaults { didSet { setCodable(actions, "actions") } }
    @Published var macros: [Macro] = Macro.defaults { didSet { setCodable(macros, "macros") } }
    @Published var macroAutoExpand: Bool = true { didSet { set(macroAutoExpand, "macroAutoExpand") } }

    @Published var clipboardEnabled: Bool = true { didSet { set(clipboardEnabled, "clipboardEnabled") } }
    @Published var clipboardLimit: Int = 50 { didSet { set(clipboardLimit, "clipboardLimit") } }

    @Published var haptics: Bool = true { didSet { set(haptics, "haptics") } }
    @Published var keySound: Bool = true { didSet { set(keySound, "keySound") } }
    @Published var keyPopups: Bool = true { didSet { set(keyPopups, "keyPopups") } }
    @Published var autocorrect: Bool = true { didSet { set(autocorrect, "autocorrect") } }
    @Published var autocapitalize: Bool = true { didSet { set(autocapitalize, "autocapitalize") } }
    @Published var doubleSpacePeriod: Bool = true { didSet { set(doubleSpacePeriod, "doubleSpacePeriod") } }
    @Published var aiSuggestions: Bool = true { didSet { set(aiSuggestions, "aiSuggestions") } }
    @Published var learnWords: Bool = true { didSet { set(learnWords, "learnWords") } }
    @Published var showNumberRow: Bool = false { didSet { set(showNumberRow, "showNumberRow") } }
    @Published var keyboardTint: Int = 0 { didSet { set(keyboardTint, "keyboardTint") } }

    // Aussehen
    @Published var backgroundStyle: String = "system" { didSet { set(backgroundStyle, "backgroundStyle") } }
    @Published var backgroundPreset: Int = 0 { didSet { set(backgroundPreset, "backgroundPreset") } }
    @Published var backgroundColorHex: String = "#3A2E8C" { didSet { set(backgroundColorHex, "backgroundColorHex") } }
    @Published var backgroundDim: Double = 0.25 { didSet { set(backgroundDim, "backgroundDim") } }
    @Published var keyOpacity: Double = 1.0 { didSet { set(keyOpacity, "keyOpacity") } }
    @Published var keyCornerRadius: Double = 8.5 { didSet { set(keyCornerRadius, "keyCornerRadius") } }
    @Published var keyFontScale: Double = 1.0 { didSet { set(keyFontScale, "keyFontScale") } }
    @Published var backgroundVersion: Int = 0 { didSet { set(backgroundVersion, "backgroundVersion") } }
    @Published var keyStyle: String = "glass" { didSet { set(keyStyle, "keyStyle") } }
    @Published var keyColorHex: String = "#FFFFFF" { didSet { set(keyColorHex, "keyColorHex") } }
    @Published var keyTextColorHex: String = "" { didSet { set(keyTextColorHex, "keyTextColorHex") } }
    @Published var keyFontDesign: String = "default" { didSet { set(keyFontDesign, "keyFontDesign") } }
    @Published var themeID: String = "" { didSet { set(themeID, "themeID") } }

    // KI-Vorschläge: "manual" (Knopf), "occasional" (gelegentlich), "off"
    @Published var aiSuggestMode: String = "manual" { didSet { set(aiSuggestMode, "aiSuggestMode") } }
    @Published var translateTarget: String = "Englisch" { didSet { set(translateTarget, "translateTarget") } }
    /// Übersetzen-Panel: Sprache antippen ersetzt sofort (ohne Ergebnis-Vorschau).
    @Published var translateDirect: Bool = true { didSet { set(translateDirect, "translateDirect") } }
    @Published var commands: [SavedCommand] = SavedCommand.defaults { didSet { setCodable(commands, "commands") } }
    @Published var commandEdition: String = "Bedrock" { didSet { set(commandEdition, "commandEdition") } }
    @Published var toolbarItems: [String] = ToolItem.defaultOrder { didSet { setCodable(toolbarItems, "toolbarItems") } }

    // Tippkontrolle
    @Published var smartTouch: Bool = true { didSet { set(smartTouch, "smartTouch") } }
    @Published var liveAICorrection: Bool = true { didSet { set(liveAICorrection, "liveAICorrection") } }

    // Emojis
    @Published var emojiRecents: [String] = [] { didSet { setCodable(emojiRecents, "emojiRecents") } }
    @Published var emojiFavorites: [String] = ["❤️", "😂", "👍", "🙏", "🔥", "✨"] { didSet { setCodable(emojiFavorites, "emojiFavorites") } }

    private var loading = false

    func reload() {
        loading = true
        defer { loading = false }
        let d = defaults
        migrateIfNeeded()
        upd(\.apiKey, d.string(forKey: "apiKey") ?? "")
        upd(\.baseURL, d.string(forKey: "baseURL") ?? "https://api.openai.com/v1")
        upd(\.chatModel, d.string(forKey: "chatModel") ?? SharedStore.defaultChatModel)
        upd(\.fastModel, d.string(forKey: "fastModel") ?? SharedStore.defaultChatModel)
        upd(\.reasoningEffort, d.string(forKey: "reasoningEffort") ?? "low")
        upd(\.knownModels, getCodable("knownModels") ?? [])
        upd(\.streamResponses, bool("streamResponses", true))
        upd(\.outputLanguage, d.string(forKey: "outputLanguage") ?? "auto")
        upd(\.personalContext, d.string(forKey: "personalContext") ?? "")
        upd(\.writingStyle, d.string(forKey: "writingStyle") ?? "")
        upd(\.profiles, getCodable("profiles") ?? ContextProfile.defaults)
        upd(\.activeProfileID, d.string(forKey: "activeProfileID") ?? "")
        upd(\.aiScope, AIScope(rawValue: d.string(forKey: "aiScope") ?? "") ?? .auto)
        upd(\.useAppContext, bool("useAppContext", true))
        upd(\.actions, getCodable("actions") ?? AIAction.defaults)
        upd(\.macros, getCodable("macros") ?? Macro.defaults)
        upd(\.macroAutoExpand, bool("macroAutoExpand", true))
        upd(\.clipboardEnabled, bool("clipboardEnabled", true))
        upd(\.clipboardLimit, d.object(forKey: "clipboardLimit") as? Int ?? 50)
        upd(\.haptics, bool("haptics", true))
        upd(\.keySound, bool("keySound", true))
        upd(\.keyPopups, bool("keyPopups", true))
        upd(\.autocorrect, bool("autocorrect", true))
        upd(\.autocapitalize, bool("autocapitalize", true))
        upd(\.doubleSpacePeriod, bool("doubleSpacePeriod", true))
        upd(\.aiSuggestions, bool("aiSuggestions", true))
        upd(\.learnWords, bool("learnWords", true))
        upd(\.showNumberRow, bool("showNumberRow", false))
        upd(\.keyboardTint, d.object(forKey: "keyboardTint") as? Int ?? 0)
        upd(\.backgroundStyle, d.string(forKey: "backgroundStyle") ?? "system")
        upd(\.backgroundPreset, d.object(forKey: "backgroundPreset") as? Int ?? 0)
        upd(\.backgroundColorHex, d.string(forKey: "backgroundColorHex") ?? "#3A2E8C")
        upd(\.backgroundDim, d.object(forKey: "backgroundDim") as? Double ?? 0.25)
        upd(\.keyOpacity, d.object(forKey: "keyOpacity") as? Double ?? 1.0)
        upd(\.keyCornerRadius, d.object(forKey: "keyCornerRadius") as? Double ?? 8.5)
        upd(\.keyFontScale, d.object(forKey: "keyFontScale") as? Double ?? 1.0)
        upd(\.backgroundVersion, d.object(forKey: "backgroundVersion") as? Int ?? 0)
        upd(\.emojiRecents, getCodable("emojiRecents") ?? [])
        upd(\.emojiFavorites, getCodable("emojiFavorites") ?? ["❤️", "😂", "👍", "🙏", "🔥", "✨"])
        upd(\.keyStyle, d.string(forKey: "keyStyle") ?? "glass")
        upd(\.keyColorHex, d.string(forKey: "keyColorHex") ?? "#FFFFFF")
        upd(\.keyTextColorHex, d.string(forKey: "keyTextColorHex") ?? "")
        upd(\.keyFontDesign, d.string(forKey: "keyFontDesign") ?? "default")
        upd(\.themeID, d.string(forKey: "themeID") ?? "")
        upd(\.smartTouch, bool("smartTouch", true))
        upd(\.aiSuggestMode, d.string(forKey: "aiSuggestMode") ?? "manual")
        upd(\.translateTarget, d.string(forKey: "translateTarget") ?? "Englisch")
        upd(\.translateDirect, d.object(forKey: "translateDirect") as? Bool ?? true)
        upd(\.commands, getCodable("commands") ?? SavedCommand.defaults)
        upd(\.commandEdition, d.string(forKey: "commandEdition") ?? "Bedrock")
        upd(\.toolbarItems, getCodable("toolbarItems") ?? ToolItem.defaultOrder)
        upd(\.liveAICorrection, bool("liveAICorrection", true))
    }

    /// Setzt einen Wert nur, wenn er sich geändert hat (vermeidet unnötiges Neuzeichnen).
    private func upd<T: Equatable>(_ kp: ReferenceWritableKeyPath<SharedStore, T>, _ value: T) {
        if self[keyPath: kp] != value { self[keyPath: kp] = value }
    }

    // MARK: - Hintergrundbild

    static var backgroundImageURL: URL { containerURL.appendingPathComponent("keyboard-background.jpg") }

    func saveBackgroundImage(_ data: Data) {
        try? data.write(to: Self.backgroundImageURL, options: .atomic)
        backgroundVersion += 1
        backgroundStyle = "image"
    }

    // MARK: - Status der Tastatur (für die App)

    func reportKeyboardStatus(fullAccess: Bool) {
        defaults.set(fullAccess, forKey: "kb.fullAccess")
        defaults.set(Date().timeIntervalSince1970, forKey: "kb.lastSeen")
    }

    var keyboardLastSeen: Date? {
        let t = defaults.double(forKey: "kb.lastSeen")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    var keyboardHasFullAccess: Bool { defaults.bool(forKey: "kb.fullAccess") }

    // MARK: - Emojis

    func useEmoji(_ e: String) {
        var r = emojiRecents
        r.removeAll { $0 == e }
        r.insert(e, at: 0)
        emojiRecents = Array(r.prefix(40))
    }

    @discardableResult
    func toggleFavorite(_ e: String) -> Bool {
        if emojiFavorites.contains(e) {
            emojiFavorites.removeAll { $0 == e }
            return false
        }
        emojiFavorites.insert(e, at: 0)
        return true
    }

    /// Aktualisiert alte Einstellungen (neue Standardmodelle, neue KI-Aktionen).
    private func migrateIfNeeded() {
        let d = defaults
        let version = d.integer(forKey: "settingsVersion")
        guard version < SharedStore.settingsVersion else { return }
        let oldDefaults: Set<String> = ["gpt-5-mini", "gpt-5-nano", ""]
        if oldDefaults.contains(d.string(forKey: "chatModel") ?? "") { d.set(SharedStore.defaultChatModel, forKey: "chatModel") }
        if oldDefaults.contains(d.string(forKey: "fastModel") ?? "") { d.set(SharedStore.defaultChatModel, forKey: "fastModel") }
        if d.string(forKey: "reasoningEffort") == "minimal" { d.set("low", forKey: "reasoningEffort") }
        if let data = d.data(forKey: "actions"), let old = try? JSONDecoder().decode([AIAction].self, from: data) {
            let custom = old.filter { !$0.builtIn }
            if let newData = try? JSONEncoder().encode(AIAction.defaults + custom) { d.set(newData, forKey: "actions") }
        }
        if let scope = d.string(forKey: "aiScope"), AIScope(rawValue: scope) == nil { d.removeObject(forKey: "aiScope") }
        if version < 3 { d.set(true, forKey: "aiSuggestions") }
        if version < 5 { d.set("manual", forKey: "aiSuggestMode") }
        if version < 6, let data = d.data(forKey: "toolbarItems"), var items = try? JSONDecoder().decode([String].self, from: data) {
            if !items.contains("commands") { items.insert("commands", at: min(2, items.count)) }
            if let newData = try? JSONEncoder().encode(items) { d.set(newData, forKey: "toolbarItems") }
        }
        // v7: Ein-Klick-Übersetzen ins Englische direkt hinter „Übersetzen“
        if version < 7, let data = d.data(forKey: "toolbarItems"), var items = try? JSONDecoder().decode([String].self, from: data) {
            if !items.contains(where: { $0.hasPrefix(ToolItem.translatePrefix) }) {
                let pos = items.firstIndex(of: "translate").map { $0 + 1 } ?? min(1, items.count)
                items.insert(ToolItem.translateID("Englisch"), at: pos)
            }
            if let newData = try? JSONEncoder().encode(items) { d.set(newData, forKey: "toolbarItems") }
        }
        for key in ["transcribeModel", "dictationLanguage", "dictationCleanup", "dictationVocabulary", "dictationSessionMinutes"] {
            d.removeObject(forKey: key)
        }
        d.set(SharedStore.settingsVersion, forKey: "settingsVersion")
    }

    var activeProfile: ContextProfile? {
        profiles.first { $0.id.uuidString == activeProfileID }
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Zwischenablage-Verlauf (Datei, damit beide Prozesse sauber lesen/schreiben)

    private static var clipURL: URL { containerURL.appendingPathComponent("clipboard.json") }

    func loadClips() -> [ClipItem] {
        guard let data = try? Data(contentsOf: Self.clipURL),
              let items = try? JSONDecoder().decode([ClipItem].self, from: data) else { return [] }
        return items
    }

    func saveClips(_ items: [ClipItem]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.clipURL, options: .atomic)
        }
    }

    /// Fügt einen Text zum Verlauf hinzu (Duplikate wandern nach oben).
    @discardableResult
    func addClip(_ text: String) -> [ClipItem] {
        var items = loadClips()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        if let idx = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: idx)
            existing.date = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(text: text), at: 0)
        }
        let pinned = items.filter { $0.pinned }
        let unpinned = items.filter { !$0.pinned }.prefix(max(5, clipboardLimit))
        items = (pinned + unpinned).sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
        saveClips(items)
        return items
    }

    // MARK: - Gelernte Wörter

    private static var wordsURL: URL { containerURL.appendingPathComponent("learned-words.json") }

    func loadLearnedWords() -> [String: Int] {
        guard let data = try? Data(contentsOf: Self.wordsURL),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return dict
    }

    func saveLearnedWords(_ words: [String: Int]) {
        if let data = try? JSONEncoder().encode(words) {
            try? data.write(to: Self.wordsURL, options: .atomic)
        }
    }

    // MARK: - Statistik

    func incrementStat(_ key: String, by value: Int = 1) {
        defaults.set(defaults.integer(forKey: "stat." + key) + value, forKey: "stat." + key)
    }

    func stat(_ key: String) -> Int { defaults.integer(forKey: "stat." + key) }

    // MARK: - Helfer

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func set(_ value: Any, _ key: String) {
        guard !loading else { return }
        defaults.set(value, forKey: key)
    }

    private func setCodable<T: Encodable>(_ value: T, _ key: String) {
        guard !loading else { return }
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func getCodable<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: key) }
        reload()
    }
}
