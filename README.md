# Tastatur KI ⌨️✨

KI-Tastatur für iOS mit eigenem OpenAI-API-Schlüssel – komplett auf Deutsch, im Liquid-Glass-Design.

## Funktionen
- **QWERTZ-Tastatur** mit Umlauten, Long-Press-Akzenten (z. B. s → ß), Zahlen/Symbolen, Emoji-Panel, Cursor-Steuerung per Wischen über die Leertaste, Haptik und Klick-Ton
- **Autokorrektur** (lässt sich mit ⌫ rückgängig machen), **Autovervollständigung** und **Wortvorhersage**, lernt deine Wörter, optional **KI-Wortvorschläge**
- **KI-Aktionen**: Korrigieren, Zusammenfassen, Umformulieren, Formell/Locker, Kürzen, Erweitern, Übersetzen, Antworten, Emojis, Stichpunkte + **eigene Aktionen**
- **KI schreiben lassen**: Aufgabe direkt in der Tastatur eintippen
- **Eigener Kontext**: „Über mich“, Schreibstil, Profile (Arbeit/Privat …) – direkt in der Tastatur umschaltbar
- **Makros/Textbausteine** mit Auto-Ersetzen (`mfg` + Leertaste), Platzhaltern (`{datum}`, `{uhrzeit}`, `{zwischenablage}`) und KI-Makros
- **Zwischenablage-Verlauf** mit Anheften
- **Diktat** über OpenAI `gpt-transcribe` (Fallback: `gpt-4o-mini-transcribe`, `whisper-1`) mit KI-Aufbereitung (Füllwörter weg, Satzzeichen, „neue Zeile“ …)

## Installation
1. Unter **Actions → IPA bauen** das Artefakt `Tastatur-KI-ipa` herunterladen.
2. Die IPA mit Sideloadly/AltStore (o. Ä.) installieren. Die App-Group `group.de.tastatur.app` ist in den Entitlements enthalten.
3. Einstellungen → Allgemein → Tastatur → Tastaturen → „Tastatur KI“ hinzufügen → **Vollen Zugriff erlauben**.
4. In der App unter **KI** den OpenAI-Schlüssel eintragen und testen.

## Diktat – so funktioniert's
Tastatur-Erweiterungen dürfen unter iOS das Mikrofon nicht nutzen. Deshalb nimmt die App im Hintergrund auf: Beim ersten Tippen auf 🎙 öffnet sich kurz die App und startet eine Diktat-Sitzung. Danach oben links mit „◀︎ Zurück“ zurückwechseln. Solange die Sitzung läuft (einstellbar, Standard 5 Min.), funktioniert 🎙 direkt in der Tastatur.

## Build
`xcodegen generate` → `xcodebuild` (siehe `.github/workflows/build.yml`). Läuft auf `macos-26` mit Xcode 26.
