import Foundation

/// Ziel-App, für die die KI schreibt und formatiert (automatisch erkannt oder manuell gewählt).
struct AppProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let bundleIDs: [String]
    /// true = die App versteht Markdown-Zeichen, die KI darf sie benutzen.
    let markdown: Bool
    /// Formatierungs- und Stilregeln für die KI.
    let rules: String
}

enum AppProfiles {
    /// Aktuelle Discord-Formatierung (Stand Ende 2026).
    static let discordRules = """
    Du schreibst für Discord. Nutze Discord-Markdown, wo es dem Text hilft (nicht übertreiben):
    - **fett**, *kursiv*, __unterstrichen__, ~~durchgestrichen~~, ||Spoiler||, Kombinationen wie ***fett kursiv*** oder __**fett unterstrichen**__.
    - Überschriften am Zeilenanfang: „# “ groß, „## “ mittel, „### “ klein. Kleiner grauer Untertext: „-# “ am Zeilenanfang.
    - Listen: „- “ oder „* “, nummeriert „1. “; Unterpunkte mit zwei Leerzeichen einrücken.
    - Zitate: „> “ für eine Zeile, „>>> “ für den ganzen Rest der Nachricht.
    - `Inline-Code` und Codeblöcke mit ```sprache … ```.
    - Maskierte Links: [Text](https://…) – ohne Leerzeichen zwischen ] und (. Mit <https://…> wird die Vorschau unterdrückt.
    - Zeitstempel: <t:UNIX:R> relativ, <t:UNIX:f> Datum+Uhrzeit, <t:UNIX:F> lang, <t:UNIX:d>/<t:UNIX:D> Datum, <t:UNIX:t>/<t:UNIX:T> Uhrzeit, <t:UNIX:s>/<t:UNIX:S> kurz.
    - Erwähnungen @everyone und @here nur, wenn ausdrücklich gewünscht. Emojis wie 🎉📢✅ passen gut.
    - Maximal 2000 Zeichen pro Nachricht.
    """

    static let all: [AppProfile] = [
        AppProfile(id: "discord", name: "Discord", emoji: "🎮", bundleIDs: ["com.hammerandchisel.discord"], markdown: true, rules: discordRules),
        AppProfile(id: "whatsapp", name: "WhatsApp", emoji: "💬", bundleIDs: ["net.whatsapp.WhatsApp", "net.whatsapp.WhatsAppSMB"], markdown: true, rules: """
        Du schreibst für WhatsApp. Formatierung: *fett* (EIN Sternchen), _kursiv_, ~durchgestrichen~, ```Monospace```, `Inline-Code`, „> “ Zitat, „- “ Liste, „1. “ nummerierte Liste. Keine **doppelten Sternchen**, keine Überschriften mit #. Locker, kurz, natürliche Emojis.
        """),
        AppProfile(id: "telegram", name: "Telegram", emoji: "✈️", bundleIDs: ["ph.telegra.Telegraph"], markdown: true, rules: """
        Du schreibst für Telegram. Formatierung: **fett**, __kursiv__, ~~durchgestrichen~~, ||Spoiler||, `Code`, ```Codeblock```, „> “ Zitat. Keine Überschriften mit #.
        """),
        AppProfile(id: "slack", name: "Slack", emoji: "🧵", bundleIDs: ["com.tinyspeck.chatlyio"], markdown: true, rules: """
        Du schreibst für Slack. Formatierung: *fett* (ein Sternchen), _kursiv_, ~durchgestrichen~, `Code`, ```Codeblock```, „> “ Zitat, „• “ Listen. Sachlich, gut strukturiert.
        """),
        AppProfile(id: "reddit", name: "Reddit", emoji: "👽", bundleIDs: ["com.reddit.Reddit"], markdown: true, rules: """
        Du schreibst für Reddit (Markdown): **fett**, *kursiv*, ~~durch~~, # Überschriften, Listen mit „- “, > Zitate, [Text](Link). Stil der Community, ehrlich und direkt.
        """),
        AppProfile(id: "mail", name: "E-Mail", emoji: "✉️", bundleIDs: ["com.apple.mobilemail", "com.google.Gmail", "com.microsoft.Office.Outlook", "com.readdle.smartemail", "de.web.mobile.android.mail", "de.gmx.mobile.ios.mail"], markdown: false, rules: """
        Du schreibst eine E-Mail: passende Anrede, klare Absätze, höflicher Ton, Grußformel. Kein Markdown.
        """),
        AppProfile(id: "imessage", name: "iMessage/SMS", emoji: "💭", bundleIDs: ["com.apple.MobileSMS"], markdown: false, rules: """
        Du schreibst eine kurze, natürliche Chat-Nachricht. Kein Markdown, keine steifen Floskeln.
        """),
        AppProfile(id: "instagram", name: "Instagram", emoji: "📸", bundleIDs: ["com.burbn.instagram"], markdown: false, rules: """
        Du schreibst für Instagram: lockere, ansprechende Sprache, passende Emojis, Absätze mit Leerzeilen, bei Beiträgen 3–8 passende Hashtags am Ende. Kein Markdown.
        """),
        AppProfile(id: "x", name: "X / Twitter", emoji: "𝕏", bundleIDs: ["com.atebits.Tweetie2"], markdown: false, rules: """
        Du schreibst für X (Twitter): prägnant, maximal 280 Zeichen pro Beitrag, kein Markdown, höchstens 1–2 Hashtags.
        """),
        AppProfile(id: "linkedin", name: "LinkedIn", emoji: "💼", bundleIDs: ["com.linkedin.LinkedIn"], markdown: false, rules: """
        Du schreibst für LinkedIn: professionell, aber persönlich, kurze Absätze, starke erste Zeile, wenige passende Emojis, 3–5 Hashtags am Ende. Kein Markdown.
        """),
        AppProfile(id: "notes", name: "Notizen", emoji: "🗒️", bundleIDs: ["com.apple.mobilenotes", "com.apple.reminders"], markdown: false, rules: """
        Du schreibst Notizen: übersichtlich, Stichpunkte mit „• “, keine Floskeln. Kein Markdown.
        """),
    ]

    static func profile(_ id: String) -> AppProfile? { all.first { $0.id == id } }

    static func detect(bundleID: String) -> AppProfile? {
        let b = bundleID.lowercased()
        return all.first { p in p.bundleIDs.contains { b.hasPrefix($0.lowercased()) } }
    }
}
