# Tastatur KI ⌨️✨

KI-Tastatur für iOS mit eigenem OpenAI-API-Schlüssel – komplett auf Deutsch, im Liquid-Glass-Design.

## Funktionen
- **Schnelle UIKit-Tastatur** (QWERTZ) mit Multitouch, Tasten-Vorschau, Akzent-Auswahl per Wischen (s → ß), Zahlen/Symbolen, Emojis, Cursor-Steuerung über die Leertaste, Haptik und Klick-Ton
- **Autokorrektur** (mit ⌫ rückgängig), **Autovervollständigung** und **Wortvorhersage**, lernt deine Wörter, optional **KI-Wortvorschläge**
- **KI-Aktionen** direkt in der Tastatur, in Kategorien: Formatieren (E-Mail, Nachricht, Liste, Absätze, Überschriften + Sofort-Formatierung ohne KI), Zusammenfassen (Kurz, Ausführlich, Stichpunkte, TL;DR, To-dos), Bearbeiten (Korrigieren mit markierten Änderungen, Verbessern, Umformulieren, Kürzen, Ausbauen, Gliedern, Antworten, Erklären), Ton, Übersetzen + **eigene Aktionen**
- **Große Texte**: Die Tastatur liest den kompletten Text im Feld ein (nicht nur den sichtbaren Ausschnitt). Sehr lange Texte werden in Abschnitten verarbeitet. Quelle wählbar: Feld, Absatz oder Zwischenablage
- **Live-Antworten** (Streaming), **Verfeinern** (Kürzer, Formeller, eigene Anweisung …), Ersetzen/Einfügen/Kopieren
- **Eigener Kontext**: „Über mich“, Schreibstil, Profile (Arbeit/Privat …)
- **Makros/Textbausteine** mit Auto-Ersetzen (`mfg` + Leertaste), Platzhaltern und KI-Makros
- **Zwischenablage-Verlauf** mit Anheften und Ein-Tipp-Zusammenfassung
- Standardmodell **GPT-6 Luna** (günstigstes und neuestes Modell, ~0,10 $ / 0,50 $ pro 1 Mio. Tokens) mit automatischem Fallback

## Installation
1. Unter **Actions → IPA bauen** das Artefakt `Tastatur-KI-ipa` herunterladen.
2. Die IPA mit Sideloadly/AltStore (o. Ä.) installieren. Die App-Group `group.de.tastatur.app` ist in den Entitlements enthalten.
3. Einstellungen → Allgemein → Tastatur → Tastaturen → „Tastatur KI“ hinzufügen → **Vollen Zugriff erlauben**.
4. In der App unter **KI** den OpenAI-Schlüssel eintragen und testen.

## Build
`xcodegen generate` → `xcodebuild` (siehe `.github/workflows/build.yml`). Läuft auf `macos-26` mit Xcode 26.
