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

    @Published var apiKey: String = "" { didSet { set(apiKey, "apiKey") } }
    @Published var baseURL: String = "https://api.openai.com/v1" { didSet { set(baseURL, "baseURL") } }
    @Published var chatModel: String = "gpt-5-mini" { didSet { set(chatModel, "chatModel") } }
    @Published var fastModel: String = "gpt-5-nano" { didSet { set(fastModel, "fastModel") } }
    @Published var transcribeModel: String = "gpt-transcribe" { didSet { set(transcribeModel, "transcribeModel") } }
    @Published var reasoningEffort: String = "minimal" { didSet { set(reasoningEffort, "reasoningEffort") } }
    @Published var knownModels: [String] = [] { didSet { setCodable(knownModels, "knownModels") } }

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
    @Published var autocorrect: Bool = true { didSet { set(autocorrect, "autocorrect") } }
    @Published var autocapitalize: Bool = true { didSet { set(autocapitalize, "autocapitalize") } }
    @Published var doubleSpacePeriod: Bool = true { didSet { set(doubleSpacePeriod, "doubleSpacePeriod") } }
    @Published var aiSuggestions: Bool = false { didSet { set(aiSuggestions, "aiSuggestions") } }
    @Published var learnWords: Bool = true { didSet { set(learnWords, "learnWords") } }
    @Published var showNumberRow: Bool = false { didSet { set(showNumberRow, "showNumberRow") } }
    @Published var keyboardTint: Int = 0 { didSet { set(keyboardTint, "keyboardTint") } }

    @Published var dictationLanguage: String = "de" { didSet { set(dictationLanguage, "dictationLanguage") } }
    @Published var dictationCleanup: Bool = true { didSet { set(dictationCleanup, "dictationCleanup") } }
    @Published var dictationVocabulary: String = "" { didSet { set(dictationVocabulary, "dictationVocabulary") } }
    @Published var dictationSessionMinutes: Int = 5 { didSet { set(dictationSessionMinutes, "dictationSessionMinutes") } }

    private var loading = false

    func reload() {
        loading = true
        defer { loading = false }
        let d = defaults
        apiKey = d.string(forKey: "apiKey") ?? ""
        baseURL = d.string(forKey: "baseURL") ?? "https://api.openai.com/v1"
        chatModel = d.string(forKey: "chatModel") ?? "gpt-5-mini"
        fastModel = d.string(forKey: "fastModel") ?? "gpt-5-nano"
        transcribeModel = d.string(forKey: "transcribeModel") ?? "gpt-transcribe"
        reasoningEffort = d.string(forKey: "reasoningEffort") ?? "minimal"
        knownModels = getCodable("knownModels") ?? []
        personalContext = d.string(forKey: "personalContext") ?? ""
        writingStyle = d.string(forKey: "writingStyle") ?? ""
        profiles = getCodable("profiles") ?? ContextProfile.defaults
        activeProfileID = d.string(forKey: "activeProfileID") ?? ""
        aiScope = AIScope(rawValue: d.string(forKey: "aiScope") ?? "") ?? .auto
        useAppContext = bool("useAppContext", true)
        actions = getCodable("actions") ?? AIAction.defaults
        macros = getCodable("macros") ?? Macro.defaults
        macroAutoExpand = bool("macroAutoExpand", true)
        clipboardEnabled = bool("clipboardEnabled", true)
        clipboardLimit = d.object(forKey: "clipboardLimit") as? Int ?? 50
        haptics = bool("haptics", true)
        keySound = bool("keySound", true)
        autocorrect = bool("autocorrect", true)
        autocapitalize = bool("autocapitalize", true)
        doubleSpacePeriod = bool("doubleSpacePeriod", true)
        aiSuggestions = bool("aiSuggestions", false)
        learnWords = bool("learnWords", true)
        showNumberRow = bool("showNumberRow", false)
        keyboardTint = d.object(forKey: "keyboardTint") as? Int ?? 0
        dictationLanguage = d.string(forKey: "dictationLanguage") ?? "de"
        dictationCleanup = bool("dictationCleanup", true)
        dictationVocabulary = d.string(forKey: "dictationVocabulary") ?? ""
        dictationSessionMinutes = d.object(forKey: "dictationSessionMinutes") as? Int ?? 5
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
