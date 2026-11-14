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
  - `SharedStore.swift` – alle Einstellungen (App Group, Fallback auf `UserDefaults.standard`). `reload()` setzt Werte nur bei Änderung (`upd`). **Migrationen** über `settingsVersion` in `migrateIfNeeded()` (aktuell 11) – bei neuen Standard-Aktionen/Werkzeugen Version erhöhen.
  - `OpenAIClient.swift` – Chat Completions mit Streaming, Modell-Fallback (`SharedStore.fallbackModels`, Standard **gpt-6-luna**), automatisches Weglassen nicht unterstützter Parameter (`reasoning_effort`, `stream`), Chunking sehr langer Texte, `predict` (KI-Vorschläge), `finalCheck` (Schlusskorrektur des ganzen Textes), `contextCheck`, `swipeWord`, `discordAnnouncement`, `learnProfile`, `translate`, `minecraftCommand`.
  - `Models.swift` – Makros, Ablage, Profile, KI-Aktionen (Kategorien inkl. Formatieren), `TextDiff`, `SavedCommand` (Minecraft-Befehle).
  - `Glass.swift` – `glass()`/`glassCapsule()`-Helfer. **In der Tastatur ist `GlassConfig.lightweight = true`** (Speicher!): echtes Liquid Glass nur mit `force: true` (Toolbar). Hintergründe, Verläufe, `KeyboardBackgroundView`, Bild-Downsampling.
  - `KeyStyle.swift` – 7 Tastenstile, `KeyStyleKit.colors`, 21 `ThemePreset`s + `random()`, `ThemeThumbnail`.
  - `ChatGPTAuth.swift` – „Sign in with ChatGPT“ (Tokens, Erneuerung, Kopplungscode App→Tastatur ohne App Group); Anfragen über `/v1/responses` in `OpenAIClient`.
  - `AppProfiles.swift` – Ziel-Apps (Discord, WhatsApp …) mit Formatierungsregeln; Host-Erkennung ab iOS 26.4 gesperrt → manuelle Auswahl.
  - `PersonalData.swift` – `ContactEntry`/`ContactsCache` (contacts.json) und `SavedLocation` (last-location.json): von der App geschrieben, von der Tastatur gelesen.
  - `Tools.swift` – Werkzeuge der Schnellleiste (`ToolItem`, auch `tr:<Sprache>` = Ein-Klick-Übersetzen), Sprachen, `StickerStore`, sicherer `Calculator` (kein NSExpression – stürzt bei Fehleingaben ab).
- `Keyboard/`:
  - `KeyboardViewController.swift` – Höhe, Rotation/Querformat (`updateLayoutMetrics`), Hell/Dunkel des Textfelds, `delaysTouchesBegan=false` (Rand-Verzögerung), `openURL`.
  - `KeyboardState.swift` – Herzstück: Tippen, Autokorrektur, Vorschläge, KI (startAI/runAI/perform), Volltext-Einlesen (`readFullText` – bewegt den Cursor schrittweise), Ersetzen, Übersetzen (Feld/Live/Ablage), Live-Korrektur, Befehlsmodus (Zeile beginnt mit „/“ → keine Korrekturen), Sticker, Cursor, Rechner, Einstellungs-Eingaben (`ComposeTarget`).
    - **Performance:** `BarModel` (Vorschlagsleiste) und `KeyModel` (Tasten) sind getrennte ObservableObjects – Tippen darf nicht die ganze SwiftUI-Oberfläche neu zeichnen.
    - **Keine schwere Arbeit pro Tastendruck!** KI-Korrektur nur „Wenn ich fertig bin“ (Pause ≈2,5 s → `runEndCheck`, Korrekturen werden in der Leiste angeboten, nie ungefragt eingesetzt) oder manuell (Werkzeug „Korrigieren“). „Wort für Wort“/KI-Turbo wurden wegen Hängern entfernt.
    - Power-Tippen: lernende Trefferzonen (`touchModel`), Tipp-Korrektur über Fingerpositionen (`smartCorrection`, nur beim Leerzeichen), Leertasten-Rettung.
  - `KeysView.swift` – Tastenfeld in **UIKit** (Multitouch, Rollover, Popups, Akzente, intelligente Trefferzonen, Leertasten-Cursor). Abonniert `KeyModel` direkt per Combine.
  - `KeyboardView.swift` – SwiftUI-Root, Toolbar (Vorschläge, ✨-Knopf „KI denk mit“, Eingabe-/Übersetzungsleiste), Schnellleiste.
  - `Panels/Panels.swift` – alle Panels: KI, Ergebnis, Ablage, Makros, Emoji, Einstellungen (mehrseitig), Sticker, Cursor, Übersetzen, Befehle.
  - `TextEngine.swift` – lokale Vorschläge, tastaturgewichtete Autokorrektur (QWERTZ-Nachbarn), Lernen (Wörter, Bi-/Trigramme, persönliche Einträge wie E-Mails), Speichern im Hintergrund.
  - `SwipeDecoder.swift` + `Resources/swipe-words.txt` – Gesten-Tippen (Bahnform + Häufigkeit + Kontext), KI-Nachkorrektur in `KeyboardState.commitSwipe`. Außerdem alphabetisch sortierte Wortliste für Präfix-Prüfung/Vervollständigung per Binärsuche (`hasWord(withPrefix:)`, `completions`).
  - `Extras.swift` – Verlauf & Rückgängig (`HistoryStore`, writing-history.json, max. 7 Tage; Lösch-Vorgänge → „Wiederherstellen“-Angebot; KI-Ersetzung rückgängig), Angebote in der Leiste (`BarOffer` in `BarModel.offer`), Kontakt-Vorschläge, Standort einfügen, Termin-Erkennung (`EventParser`, Deutsch, lokal) + Speichern (EventKit oder `tastatur://event?...` in der App), Antwortvorschläge auf kopierte Nachrichten, „Merken“ (KI-Gedächtnis), `HistoryPanel`. Zusatz-Zustand in `ExtrasState` (`state.extras`).
  - `ClipPeek.swift` – **Kopiertes oben in der Leiste** (`BarModel.clip`, Text/Link/Bild mit Miniatur per ImageIO-Thumbnail/Datei/Passwort; 5 Min. frisch, Zustand in Defaults `peek.*`; beim Tippen `clipHidden`), `CurrentClipCard` oben in der Ablage. Passwort-Kopien (`org.nspasteboard.ConcealedType` u. a.) nie im Verlauf. **Passwort-Hilfe**: Anmeldefelder (`textContentType` username/password/…) → `BarModel.login` → „Passwörter“ wechselt per `advanceToNextInputMode` zur iOS-Tastatur (dort Autofill der Passwort-App), optional Auto-Wechsel und Öffnen der Passwort-App (`PasswordApps`, URL-Schemata). Bilder/Dateien kann eine Tastatur nicht einfügen → Hinweis „Textfeld gedrückt halten → Einfügen“ bzw. als Sticker sichern. `PressableStyle` für Knöpfe.
  - `CommonWords.swift`, `EmojiCatalog.swift` (generiert aus Unicode emoji-test.txt, ≤ E16.0), `KeyLayouts.swift`.
- **Systemwörterbuch nur im Hintergrund:** Alle `UITextChecker`-Aufrufe laufen in `TextEngine` auf der seriellen `checkQueue` (ein Checker, `bg*`-Funktionen nur dort). Beim Tippen wird jedes Wort sofort vorgeladen (`schedulePrefetch` → `engine.prefetch`, Tipp-Korrektur über `TapFixBox`), die Leiste nutzt nur `cachedCorrection` und frischt sich über `engine.onAsyncResult` auf. Blockierend (`checkQueue.sync`) nur noch beim Leerzeichen, falls nichts vorberechnet ist. Klick-Ton auf eigener Warteschlange.
- **Tipp-Pfad (Power-User):** In `touchesBegan`/Trefferzonen nie `UITextChecker` – nur `isPlausiblePrefixFast` (Speicher/Binärsuche); Unbekanntes wird in Tipp-Pausen nachgeschlagen. Vorschläge laufen mit adaptivem Abstand (`refreshDelay` nach Tipp-Rhythmus), Tipp-/Autokorrektur wird in der Pause vorberechnet (`tapFix`, `correctionCache`).
- `App/` – bewusst **schlank**: eine Seite (`HomeView`) mit Status, ChatGPT-Anmeldung (`ChatGPTLogin.swift`, Loopback 127.0.0.1:1455), API-Schlüssel, Stickern (Freistellen per Vision in `StickerMaker.swift`), Hintergrundbild, Wörterbuch (`DictionaryView`). Dazu `PrivacyView.swift`: Kontakte/Standort/Kalender freigeben (`PersonalDataManager`, auch `tastatur://event` speichern), Sicherung exportieren/importieren (`BackupManager`, .tastatur-Datei, tägliche Auto-Sicherung in Documents/Sicherungen). Echte iCloud-Sync geht ohne bezahlten Entwickler-Account nicht. Alles andere wird in der Tastatur eingestellt.

## Wichtige Grenzen von iOS-Tastaturen
- Kein Mikrofon (Diktat wurde deshalb entfernt), kein Fotozugriff (Bilder/Sticker über die Zwischenablage), keine Bilder direkt einfügen (Sticker werden kopiert).
- Die Tastatur kann nicht über ihre Höhe hinauswachsen (große Ablage-Ansicht wurde deshalb entfernt).
- Strenges Speicherlimit (~50–70 MB): keine schweren Effekte/Bilder voll dekodieren, alles Schwere verzögert/im Hintergrund.
- Passwort-/Einmalcode-Felder nutzen immer die System-Tastatur.
- Die Tastatur sieht nur das aktuelle Textfeld – keinen Bildschirm, keine anderen Apps/Nachrichten (auch nicht bei Sideload). Antwortvorschläge daher über die Zwischenablage.
- Kontakte/Standort/Kalender-Rechte fragt die App ab; die Tastatur nutzt Caches im App-Group-Container (Standort/Kalender versucht sie auch direkt).
- Netzwerk/Zwischenablage nur mit „Vollem Zugriff“.

## Konventionen
- Alle Texte auf Deutsch, Code-Kommentare deutsch.
- Keine Modell-IDs von Claude in Commits/Code.
- Commits auf dem Arbeits-Branch, danach pushen und den Build bis grün begleiten.
