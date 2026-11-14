import Foundation

/// Ein Textbaustein / Makro. Wird beim Tippen des Kürzels + Leertaste automatisch ersetzt
/// oder kann direkt über das Makro-Panel eingefügt werden.
struct Macro: Codable, Identifiable, Hashable {
    var id = UUID()
    var shortcut: String
    var title: String
    var text: String
    /// Wenn gesetzt, wird `text` als KI-Anweisung verstanden.
    var isAI: Bool = false
}

/// Ein Eintrag im Zwischenablage-Verlauf.
struct ClipItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var date = Date()
    var pinned = false
}

/// Ein Kontext-Profil (z. B. „Arbeit“, „Privat“), das jeder KI-Anfrage mitgegeben wird.
struct ContextProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String
    var context: String
}

enum ActionCategory: String, Codable, CaseIterable, Identifiable {
    case summary, edit, tone, translate, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .summary: return "Zusammenfassen"
        case .edit: return "Bearbeiten"
        case .tone: return "Ton"
        case .translate: return "Übersetzen"
        case .custom: return "Eigene"
        }
    }
}

/// Eine KI-Aktion, die in der Tastatur angezeigt wird.
struct AIAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String
    var prompt: String
    var enabled = true
    var builtIn = false
    var category: ActionCategory = .custom
    /// Zeigt nach der Antwort markierte Änderungen (für Korrekturen).
    var showDiff = false

    enum CodingKeys: String, CodingKey { case id, title, symbol, prompt, enabled, builtIn, category, showDiff }

    init(id: UUID = UUID(), title: String, symbol: String, prompt: String, enabled: Bool = true, builtIn: Bool = false, category: ActionCategory = .custom, showDiff: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.prompt = prompt
        self.enabled = enabled
        self.builtIn = builtIn
        self.category = category
        self.showDiff = showDiff
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "wand.and.stars"
        prompt = try c.decode(String.self, forKey: .prompt)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        builtIn = try c.decodeIfPresent(Bool.self, forKey: .builtIn) ?? false
        category = try c.decodeIfPresent(ActionCategory.self, forKey: .category) ?? .custom
        showDiff = try c.decodeIfPresent(Bool.self, forKey: .showDiff) ?? false
    }
}

enum AIScope: String, Codable, CaseIterable, Identifiable {
    case auto, paragraph, clipboard
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Markierung, sonst ganzer Text"
        case .paragraph: return "Markierung, sonst aktueller Absatz"
        case .clipboard: return "Zwischenablage"
        }
    }
}

extension AIAction {
    static let defaults: [AIAction] = [
        // Zusammenfassen
        AIAction(title: "Kurz", symbol: "text.append",
                 prompt: "Fasse den Text in 2–4 klaren Sätzen zusammen. Konzentriere dich auf die wichtigsten Aussagen, Entscheidungen und Zahlen.",
                 builtIn: true, category: .summary),
        AIAction(title: "Ausführlich", symbol: "doc.text.magnifyingglass",
                 prompt: "Erstelle eine gründliche, gut strukturierte Zusammenfassung. Gliedere nach Themen mit kurzen Zwischenüberschriften (eine Zeile, ohne Markdown-Zeichen), behalte alle wichtigen Fakten, Zahlen, Namen, Termine und offenen Punkte.",
                 builtIn: true, category: .summary),
        AIAction(title: "Stichpunkte", symbol: "list.bullet",
                 prompt: "Fasse den Text als übersichtliche Stichpunktliste zusammen (Zeilen beginnen mit „• “). Maximal 8 Punkte, jeder Punkt eine Kernaussage.",
                 builtIn: true, category: .summary),
        AIAction(title: "TL;DR", symbol: "bolt",
                 prompt: "Fasse den Text in genau einem prägnanten Satz zusammen.",
                 builtIn: true, category: .summary),
        AIAction(title: "To-dos", symbol: "checklist",
                 prompt: "Extrahiere alle Aufgaben, Fristen, Termine und Verantwortlichkeiten als Liste (Zeilen beginnen mit „☐ “). Wenn es keine gibt, schreibe „Keine Aufgaben gefunden.“",
                 builtIn: true, category: .summary),
        // Bearbeiten
        AIAction(title: "Korrigieren", symbol: "checkmark.seal",
                 prompt: "Korrigiere ausschließlich Rechtschreibung, Grammatik, Zeichensetzung und Groß-/Kleinschreibung. Ändere weder Wortwahl, Stil, Inhalt noch Formatierung (Zeilenumbrüche, Emojis, Listen bleiben exakt erhalten). Ist der Text fehlerfrei, gib ihn unverändert zurück.",
                 builtIn: true, category: .edit, showDiff: true),
        AIAction(title: "Verbessern", symbol: "wand.and.stars",
                 prompt: "Verbessere den Text: korrigiere Fehler, mache ihn klarer, flüssiger und besser lesbar. Behalte Bedeutung, Tonfall und ungefähre Länge bei.",
                 builtIn: true, category: .edit, showDiff: true),
        AIAction(title: "Umformulieren", symbol: "arrow.triangle.2.circlepath",
                 prompt: "Formuliere den Text mit anderen Worten neu, ohne die Bedeutung zu ändern. Er soll natürlich und menschlich klingen.",
                 builtIn: true, category: .edit),
        AIAction(title: "Kürzen", symbol: "scissors",
                 prompt: "Kürze den Text auf etwa die Hälfte. Streiche Füllwörter und Wiederholungen, behalte alle wichtigen Informationen.",
                 builtIn: true, category: .edit),
        AIAction(title: "Ausbauen", symbol: "text.badge.plus",
                 prompt: "Baue den Text ausführlicher und überzeugender aus, ohne Fakten zu erfinden.",
                 builtIn: true, category: .edit),
        AIAction(title: "Gliedern", symbol: "text.alignleft",
                 prompt: "Strukturiere den Text übersichtlich mit sinnvollen Absätzen. Inhalt und Wortlaut bleiben so weit wie möglich erhalten.",
                 builtIn: true, category: .edit),
        AIAction(title: "Antworten", symbol: "arrowshape.turn.up.left",
                 prompt: "Der Text ist eine Nachricht, die ich erhalten habe. Schreibe eine passende, natürliche Antwort darauf in meinem Stil. Gib nur die Antwort zurück.",
                 builtIn: true, category: .edit),
        AIAction(title: "Erklären", symbol: "lightbulb",
                 prompt: "Erkläre den Inhalt des Textes einfach und verständlich in wenigen Sätzen, als würdest du es einem Freund erklären.",
                 builtIn: true, category: .edit),
        // Ton
        AIAction(title: "Formell", symbol: "briefcase",
                 prompt: "Schreibe den Text in einem höflichen, professionellen und formellen Ton um (Sie-Form, sofern nicht anders erkennbar).",
                 builtIn: true, category: .tone),
        AIAction(title: "Locker", symbol: "face.smiling",
                 prompt: "Schreibe den Text in einem lockeren, freundlichen Ton um (Du-Form), gerne mit 1–2 passenden Emojis.",
                 builtIn: true, category: .tone),
        AIAction(title: "Freundlicher", symbol: "heart",
                 prompt: "Formuliere den Text wärmer, freundlicher und wertschätzender, ohne den Inhalt zu ändern.",
                 builtIn: true, category: .tone),
        AIAction(title: "Selbstbewusst", symbol: "flame",
                 prompt: "Formuliere den Text selbstbewusster und klarer. Entferne unnötige Abschwächungen und Entschuldigungen.",
                 builtIn: true, category: .tone),
        AIAction(title: "Emojis", symbol: "sparkles",
                 prompt: "Ergänze den Text um passende Emojis, ohne den Wortlaut zu ändern.",
                 builtIn: true, category: .tone),
        // Übersetzen
        AIAction(title: "Englisch", symbol: "globe",
                 prompt: "Übersetze den Text natürlich und idiomatisch ins Englische.",
                 builtIn: true, category: .translate),
        AIAction(title: "Deutsch", symbol: "globe.europe.africa",
                 prompt: "Übersetze den Text natürlich und idiomatisch ins Deutsche.",
                 builtIn: true, category: .translate),
        AIAction(title: "Spanisch", symbol: "globe.americas",
                 prompt: "Übersetze den Text natürlich und idiomatisch ins Spanische.",
                 builtIn: true, category: .translate),
        AIAction(title: "Französisch", symbol: "globe.europe.africa.fill",
                 prompt: "Übersetze den Text natürlich und idiomatisch ins Französische.",
                 builtIn: true, category: .translate),
    ]

    /// Schnelle Verfeinerungen für ein KI-Ergebnis.
    static let refinements: [(title: String, prompt: String)] = [
        ("Kürzer", "Mach den Text deutlich kürzer."),
        ("Länger", "Mach den Text etwas ausführlicher."),
        ("Formeller", "Mach den Ton formeller und professioneller."),
        ("Lockerer", "Mach den Ton lockerer und persönlicher."),
        ("Einfacher", "Formuliere einfacher und verständlicher."),
        ("Stichpunkte", "Wandle den Text in Stichpunkte um (Zeilen beginnen mit „• “)."),
        ("Englisch", "Übersetze den Text ins Englische."),
    ]
}

extension Macro {
    static let defaults: [Macro] = [
        Macro(shortcut: "mfg", title: "Grußformel", text: "Mit freundlichen Grüßen\n"),
        Macro(shortcut: "lg", title: "Liebe Grüße", text: "Liebe Grüße"),
        Macro(shortcut: "datum", title: "Heutiges Datum", text: "{datum}"),
        Macro(shortcut: "zeit", title: "Uhrzeit", text: "{uhrzeit}"),
        Macro(shortcut: "unterwegs", title: "Bin unterwegs", text: "Bin gerade unterwegs, melde mich gleich bei dir! 🚗"),
        Macro(shortcut: "danke", title: "Danke-Antwort (KI)", text: "Schreibe eine kurze, herzliche Dankesnachricht passend zum bisherigen Text.", isAI: true),
    ]

    /// Ersetzt Platzhalter wie {datum}, {uhrzeit}, {wochentag}, {zwischenablage}.
    func expanded(clipboard: String?) -> String {
        var result = text
        let now = Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "dd.MM.yyyy"
        result = result.replacingOccurrences(of: "{datum}", with: df.string(from: now))
        df.dateFormat = "HH:mm"
        result = result.replacingOccurrences(of: "{uhrzeit}", with: df.string(from: now))
        df.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: "{wochentag}", with: df.string(from: now))
        result = result.replacingOccurrences(of: "{zwischenablage}", with: clipboard ?? "")
        return result
    }
}

extension ContextProfile {
    static let defaults: [ContextProfile] = [
        ContextProfile(name: "Privat", emoji: "🏠", context: "Ich schreibe locker und duze meine Gesprächspartner."),
        ContextProfile(name: "Arbeit", emoji: "💼", context: "Ich schreibe professionell, freundlich und präzise. Ich sieze, außer der Kontext zeigt etwas anderes."),
    ]
}

/// Wortweiser Vergleich zweier Texte (für markierte Korrekturen).
enum TextDiff {
    struct Segment { let text: String; let changed: Bool }

    static func segments(original: String, revised: String) -> [Segment]? {
        let a = tokenize(original), b = tokenize(revised)
        guard a.count * b.count < 2_500_000, !b.isEmpty else { return nil }
        let n = a.count, m = b.count
        var dp = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var result: [Segment] = []
        var i = 0, j = 0
        while j < m {
            if i < n && a[i] == b[j] {
                result.append(Segment(text: b[j], changed: false)); i += 1; j += 1
            } else if i < n && dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                result.append(Segment(text: b[j], changed: !b[j].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)); j += 1
            }
        }
        return result
    }

    static func changeCount(original: String, revised: String) -> Int {
        segments(original: original, revised: revised)?.filter(\.changed).count ?? 0
    }

    /// Zerlegt in Wörter inkl. nachfolgender Leerzeichen.
    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSpace = false
        for ch in s {
            let space = ch.isWhitespace
            if space != inSpace && !current.isEmpty && !space {
                tokens.append(current); current = ""
            }
            current.append(ch)
            inSpace = space
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

extension String {
    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }
}
