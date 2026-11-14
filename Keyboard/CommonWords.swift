import Foundation

/// Häufige deutsche Wörter, grob nach Häufigkeit sortiert (für Ranking & Autokorrektur).
enum CommonWords {
    static let german: [String] = [
        "ich", "und", "die", "der", "nicht", "das", "ist", "du", "zu", "es",
        "sie", "in", "ein", "mit", "auf", "den", "was", "so", "wir", "hast",
        "ja", "habe", "dass", "auch", "mal", "noch", "aber", "wie", "bin", "für",
        "eine", "er", "sind", "von", "dann", "sich", "hat", "schon", "wenn", "kann",
        "nur", "im", "dem", "jetzt", "war", "bei", "gut", "oder", "einen", "da",
        "doch", "heute", "mir", "mich", "dir", "dich", "uns", "euch", "ihr", "hier",
        "mehr", "gerne", "nach", "wo", "wird", "morgen", "kommen", "kommst", "komme", "gehen",
        "gehe", "gehst", "machen", "mache", "machst", "sehen", "geht", "gibt", "gib", "alles",
        "viel", "immer", "keine", "kein", "danke", "bitte", "hallo", "hey", "tschüss", "liebe",
        "lieber", "Grüße", "viele", "genau", "okay", "ok", "vielleicht", "wieder", "einfach", "sehr",
        "richtig", "bisschen", "später", "gleich", "Zeit", "Tag", "Abend", "Woche", "Wochenende", "Freitag",
        "Samstag", "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Uhr", "gestern", "weiß", "wissen",
        "glaube", "denke", "finde", "sagen", "sagt", "gesagt", "gemacht", "gesehen", "gehabt", "gewesen",
        "worden", "werden", "würde", "würden", "könnte", "könnten", "sollte", "sollten", "möchte", "möchten",
        "muss", "musst", "müssen", "will", "willst", "wollen", "darf", "dürfen", "soll", "sollen",
        "ganz", "etwas", "nichts", "jemand", "niemand", "warum", "weil", "wann", "wer", "wen",
        "wem", "welche", "welcher", "welches", "denn", "also", "ob", "als", "bis", "seit",
        "ohne", "gegen", "durch", "über", "unter", "vor", "hinter", "neben", "zwischen", "zusammen",
        "allein", "selbst", "wirklich", "natürlich", "eigentlich", "trotzdem", "deshalb", "deswegen", "außerdem", "übrigens",
        "ungefähr", "schnell", "langsam", "lange", "kurz", "groß", "klein", "neu", "alt", "schön",
        "toll", "super", "cool", "geil", "krass", "schade", "leider", "hoffentlich", "sicher", "bestimmt",
        "wahrscheinlich", "vielen", "Dank", "Entschuldigung", "sorry", "Termin", "treffen", "Arbeit", "Hause", "Zuhause",
        "Schule", "Uni", "Essen", "Trinken", "Kaffee", "Wasser", "Bier", "Geld", "Handy", "Nachricht",
        "Anruf", "rufe", "ruf", "melde", "meld", "schreib", "schreibe", "schreiben", "Antwort", "Frage",
        "fragen", "Problem", "Idee", "Plan", "erstmal", "schonmal", "nochmal", "irgendwie", "irgendwann", "irgendwo",
        "überall", "nirgendwo", "dort", "dahin", "hierher", "weg", "zurück", "weniger", "meisten", "erste",
        "ersten", "zweite", "letzte", "nächste", "nächsten", "nächstes", "anderen", "andere", "anderes", "beide",
        "jeden", "jeder", "jedes", "alle", "allen", "diese", "dieser", "dieses", "diesen", "meine",
        "meiner", "meinen", "meinem", "mein", "deine", "deiner", "deinen", "deinem", "dein", "seine",
        "seiner", "seinen", "seinem", "sein", "ihre", "ihrer", "ihren", "ihrem", "unser", "unsere",
        "euer", "eure", "man", "Mann", "Frau", "Kind", "Kinder", "Eltern", "Mama", "Papa",
        "Freund", "Freundin", "Freunde", "Familie", "Leute", "Menschen", "Stadt", "Land", "Straße", "Auto",
        "Bahn", "Zug", "Bus", "Fahrrad", "Minuten", "Stunden", "Stunde", "Minute", "Jahr", "Jahre",
        "Monat", "Monate", "Geburtstag", "Glückwunsch", "herzlichen", "gute", "feiern", "Party", "Urlaub", "Reise",
        "Wetter", "Regen", "Sonne", "kalt", "warm", "gefällt", "gefallen", "vermisse", "freue", "freust",
        "freuen", "hoffe", "hoffen", "brauche", "brauchst", "brauchen", "haben", "hatte", "hatten", "bist",
        "seid", "waren", "wäre", "wären", "gehört", "höre", "hören", "spielen", "Spiel", "Film",
        "Musik", "Buch", "Bild", "Bilder", "Foto", "Fotos", "Video", "Email", "Mail", "Link",
        "Adresse", "Nummer", "Telefon"
    ]

    static let set: Set<String> = Set(german.map { $0.lowercased() })

    static let rank: [String: Int] = {
        var dict: [String: Int] = [:]
        for (i, w) in german.enumerated() where dict[w.lowercased()] == nil { dict[w.lowercased()] = i }
        return dict
    }()
}
