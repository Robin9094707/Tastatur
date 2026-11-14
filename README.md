# Tastatur KI ⌨️✨

KI-Tastatur für iOS mit eigenem OpenAI-API-Schlüssel – komplett auf Deutsch, im Liquid-Glass-Design.

## Funktionen
- **Alles in der Tastatur:** Designs, KI, Übersetzen, Makros, Schnellleiste und alle Optionen über ⊞ → Einstellungen – funktioniert auch ohne App Group
- **Übersetzungsmodus:** in deiner Sprache tippen, Live-Übersetzung in 20 Sprachen, mit ↑ einfügen; kopierten Text übersetzen
- **Anpassbare Schnellleiste:** Werkzeuge wählen und sortieren (KI, Übersetzen, Ablage, Sticker, Emoji, Cursor-Trackpad, Rechner, Makros …)
- **Sticker:** in der App aus Fotos erstellen (Motiv wird automatisch freigestellt) oder aus der Zwischenablage; in der Tastatur antippen → einfügen
- **KI-Vorschläge auf Knopfdruck** (✨ in der Leiste) oder gelegentlich – keine Anfrage bei jedem Tastendruck
- **Schnelle UIKit-Tastatur** mit Tasten-Vorschau, Akzent-Auswahl, intelligenten Trefferzonen, tastaturgewichteter Autokorrektur und KI-Live-Korrektur
- **Lernt dich kennen:** Wörter, Wortfolgen, E-Mail-Adressen, Links und Nummern
- **KI-Aktionen:** Zusammenfassen, Korrigieren (mit Markierung), Formatieren, Ton, Übersetzen – auch für sehr lange Texte, mit Live-Antworten
- **21 Themes, 7 Tastenstile**, eigene Farben, Schriftarten und Hintergrundbilder
- Standardmodell **GPT-6 Luna** mit automatischem Fallback

## Installation
1. Unter **Actions → IPA bauen** das Artefakt `Tastatur-KI-ipa` herunterladen.
2. Die IPA mit Sideloadly/AltStore (o. Ä.) installieren. Die App-Group `group.de.tastatur.app` ist in den Entitlements enthalten.
3. Einstellungen → Allgemein → Tastatur → Tastaturen → „Tastatur KI“ hinzufügen → **Vollen Zugriff erlauben**.
4. In der App unter **KI** den OpenAI-Schlüssel eintragen und testen.

## Build
`xcodegen generate` → `xcodebuild` (siehe `.github/workflows/build.yml`). Läuft auf `macos-26` mit Xcode 26.
