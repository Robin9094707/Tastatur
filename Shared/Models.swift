import Foundation

/// Ein Textbaustein / Makro. Wird beim Tippen des Kürzels + Leertaste automatisch ersetzt
/// oder kann direkt über das Makro-Panel eingefügt werden.
struct Macro: Codable, Identifiable, Hashable {
    var id = UUID()
    var shortcut: String
    var title: String
    var text: String
    /// Wenn gesetzt, wird `text` als KI-Anweisung verstanden und auf den aktuellen Text angewendet.
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

/// Eine KI-Aktion, die in der Tastatur-Leiste angezeigt wird.
struct AIAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String
    var prompt: String
    var enabled = true
    var builtIn = false
}

enum AIScope: String, Codable, CaseIterable, Identifiable {
    case auto, selection, sentence, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Automatisch"
        case .selection: return "Nur Auswahl"
        case .sentence: return "Aktueller Satz/Absatz"
        case .all: return "Gesamter Text"
        }
    }
}

extension AIAction {
    static let defaults: [AIAction] = [
        AIAction(title: "Korrigieren", symbol: "checkmark.seal", prompt: "Korrigiere Rechtschreibung, Grammatik und Zeichensetzung. Ändere Stil und Inhalt nicht. Gib nur den korrigierten Text zurück.", builtIn: true),
        AIAction(title: "Zusammenfassen", symbol: "text.append", prompt: "Fasse den Text knapp und klar zusammen. Behalte die Sprache des Originals bei.", builtIn: true),
        AIAction(title: "Umformulieren", symbol: "arrow.triangle.2.circlepath", prompt: "Formuliere den Text flüssiger und natürlicher um, ohne die Bedeutung zu ändern.", builtIn: true),
        AIAction(title: "Formell", symbol: "briefcase", prompt: "Schreibe den Text in einem höflichen, professionellen und formellen Ton um.", builtIn: true),
        AIAction(title: "Locker", symbol: "face.smiling", prompt: "Schreibe den Text in einem lockeren, freundlichen Ton um, gerne mit passenden Emojis.", builtIn: true),
        AIAction(title: "Kürzen", symbol: "scissors", prompt: "Kürze den Text deutlich, behalte aber alle wichtigen Informationen.", builtIn: true),
        AIAction(title: "Ausführlicher", symbol: "text.badge.plus", prompt: "Erweitere den Text sinnvoll und ausführlicher, ohne Fakten zu erfinden.", builtIn: true),
        AIAction(title: "→ Englisch", symbol: "globe", prompt: "Übersetze den Text ins Englische. Gib nur die Übersetzung zurück.", builtIn: true),
        AIAction(title: "→ Deutsch", symbol: "globe.europe.africa", prompt: "Übersetze den Text ins Deutsche. Gib nur die Übersetzung zurück.", builtIn: true),
        AIAction(title: "Antworten", symbol: "arrowshape.turn.up.left", prompt: "Der Text ist eine Nachricht, die ich erhalten habe. Schreibe eine passende, natürliche Antwort in meinem Stil. Gib nur die Antwort zurück.", builtIn: true),
        AIAction(title: "Emojis", symbol: "sparkles", prompt: "Ergänze den Text um passende Emojis, ohne den Wortlaut zu ändern.", builtIn: true),
        AIAction(title: "Stichpunkte", symbol: "list.bullet", prompt: "Wandle den Text in übersichtliche Stichpunkte um.", builtIn: true),
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
