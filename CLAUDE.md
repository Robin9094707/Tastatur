# Tastatur KI – Projektwissen für Claude

iOS-KI-Tastatur (komplett auf Deutsch) mit eigenem OpenAI-API-Schlüssel. Ziel des Nutzers: „die beste Tastatur der Welt“ –
schnell wie die iOS-Tastatur, Liquid-Glass-Design, alles direkt in der Tastatur einstellbar.
Der Nutzer spricht Deutsch und möchte nach jeder Änderung eine **fertige IPA** (über GitHub Actions gebaut) als Datei.

## Build & Auslieferung
- Kein Mac lokal: Gebaut wird **nur über GitHub Actions** (`.github/workflows/build.yml`, Runner `macos-26`, Xcode 26).
- Projekt wird per **XcodeGen** aus `project.yml` erzeugt (`*.xcodeproj` ist in `.gitignore`).
- Ergebnis: unsignierte IPA als Artefakt `Tastatur-KI-ipa` (App + Keyboard-Extension werden ad-hoc mit Entitlements signiert, damit Sideloadly/AltStore die App Group übernehmen).
- Ablauf in einer Sitzung: Code ändern → committen/pushen → Workflow abwarten (≈1,5 Min.) → bei Fehlern Logs lesen (`mcp__github__get_job_logs`) und fixen, bis grün → Artefakt herunterladen (`download_workflow_run_artifact`), `Tastatur-KI.ipa` ins Repo-Verzeichnis kopieren (ist in `.gitignore`) und dem Nutzer schicken.
- `SWIFT_VERSION` 5.0 (keine strikte Concurrency), Deployment Target iOS 17.0, Liquid Glass nur hinter `#available(iOS 26, *)`.

## Struktur
- `project.yml` – Targets `Tastatur` (App, `de.tastatur.app`) und `TastaturKeyboard` (Extension, `de.tastatur.app.keyboard`), App Group `group.de.tastatur.app`.
- `Shared/` (in beiden Targets):
  - `SharedStore.swift` – alle Einstellungen (App Group, Fallback auf `UserDefaults.standard`). `reload()` setzt Werte nur bei Änderung (`upd`). **Migrationen** über `settingsVersion` in `migrateIfNeeded()` (aktuell 8) – bei neuen Standard-Aktionen/Werkzeugen Version erhöhen.
  - `OpenAIClient.swift` – Chat Completions mit Streaming, Modell-Fallback (`SharedStore.fallbackModels`, Standard **gpt-6-luna**), automatisches Weglassen nicht unterstützter Parameter (`reasoning_effort`, `stream`), Chunking sehr langer Texte, `predict` (KI-Vorschläge), `typoCheck` (Live-Korrektur), `translate`, `minecraftCommand`.
  - `Models.swift` – Makros, Ablage, Profile, KI-Aktionen (Kategorien inkl. Formatieren), `TextDiff`, `SavedCommand` (Minecraft-Befehle).
  - `Glass.swift` – `glass()`/`glassCapsule()`-Helfer. **In der Tastatur ist `GlassConfig.lightweight = true`** (Speicher!): echtes Liquid Glass nur mit `force: true` (Toolbar). Hintergründe, Verläufe, `KeyboardBackgroundView`, Bild-Downsampling.
  - `KeyStyle.swift` – 7 Tastenstile, `KeyStyleKit.colors`, 21 `ThemePreset`s + `random()`, `ThemeThumbnail`.
  - `ChatGPTAuth.swift` – „Sign in with ChatGPT“ (Tokens, Erneuerung, Kopplungscode App→Tastatur ohne App Group); Anfragen über `/v1/responses` in `OpenAIClient`.
  - `AppProfiles.swift` – Ziel-Apps (Discord, WhatsApp …) mit Formatierungsregeln; Host-Erkennung ab iOS 26.4 gesperrt → manuelle Auswahl.
  - `Tools.swift` – Werkzeuge der Schnellleiste (`ToolItem`, auch `tr:<Sprache>` = Ein-Klick-Übersetzen), Sprachen, `StickerStore`, sicherer `Calculator` (kein NSExpression – stürzt bei Fehleingaben ab).
- `Keyboard/`:
  - `KeyboardViewController.swift` – Höhe, Rotation/Querformat (`updateLayoutMetrics`), Hell/Dunkel des Textfelds, `delaysTouchesBegan=false` (Rand-Verzögerung), `openURL`.
  - `KeyboardState.swift` – Herzstück: Tippen, Autokorrektur, Vorschläge, KI (startAI/runAI/perform), Volltext-Einlesen (`readFullText` – bewegt den Cursor schrittweise), Ersetzen, Übersetzen (Feld/Live/Ablage), Live-Korrektur, Befehlsmodus (Zeile beginnt mit „/“ → keine Korrekturen), Sticker, Cursor, Rechner, Einstellungs-Eingaben (`ComposeTarget`).
    - **Performance:** `BarModel` (Vorschlagsleiste) und `KeyModel` (Tasten) sind getrennte ObservableObjects – Tippen darf nicht die ganze SwiftUI-Oberfläche neu zeichnen.
  - `KeysView.swift` – Tastenfeld in **UIKit** (Multitouch, Rollover, Popups, Akzente, intelligente Trefferzonen, Leertasten-Cursor). Abonniert `KeyModel` direkt per Combine.
  - `KeyboardView.swift` – SwiftUI-Root, Toolbar (Vorschläge, ✨-Knopf „KI denk mit“, Eingabe-/Übersetzungsleiste), Schnellleiste.
  - `Panels/Panels.swift` – alle Panels: KI, Ergebnis, Ablage, Makros, Emoji, Einstellungen (mehrseitig), Sticker, Cursor, Übersetzen, Befehle.
  - `TextEngine.swift` – lokale Vorschläge, tastaturgewichtete Autokorrektur (QWERTZ-Nachbarn), Lernen (Wörter, Bi-/Trigramme, persönliche Einträge wie E-Mails), Speichern im Hintergrund.
  - `SwipeDecoder.swift` + `Resources/swipe-words.txt` – Gesten-Tippen (Bahnform + Häufigkeit + Kontext), KI-Nachkorrektur in `KeyboardState.commitSwipe`.
  - `CommonWords.swift`, `EmojiCatalog.swift` (generiert aus Unicode emoji-test.txt, ≤ E16.0), `KeyLayouts.swift`.
- `App/` – bewusst **schlank**: eine Seite (`HomeView`) mit Status, ChatGPT-Anmeldung (`ChatGPTLogin.swift`, Loopback 127.0.0.1:1455), API-Schlüssel, Stickern (Freistellen per Vision in `StickerMaker.swift`), Hintergrundbild, Wörterbuch (`DictionaryView`). Alles andere wird in der Tastatur eingestellt.

## Wichtige Grenzen von iOS-Tastaturen
- Kein Mikrofon (Diktat wurde deshalb entfernt), kein Fotozugriff (Bilder/Sticker über die Zwischenablage), keine Bilder direkt einfügen (Sticker werden kopiert).
- Die Tastatur kann nicht über ihre Höhe hinauswachsen (große Ablage-Ansicht wurde deshalb entfernt).
- Strenges Speicherlimit (~50–70 MB): keine schweren Effekte/Bilder voll dekodieren, alles Schwere verzögert/im Hintergrund.
- Passwort-/Einmalcode-Felder nutzen immer die System-Tastatur.
- Netzwerk/Zwischenablage nur mit „Vollem Zugriff“.

## Konventionen
- Alle Texte auf Deutsch, Code-Kommentare deutsch.
- Keine Modell-IDs von Claude in Commits/Code.
- Commits auf dem Arbeits-Branch, danach pushen und den Build bis grün begleiten.
