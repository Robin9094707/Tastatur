import UIKit
import SwiftUI
import AudioToolbox

enum KeyboardLayer: Equatable { case letters, numbers, symbols }
enum ShiftState: Equatable { case off, on, caps }

enum Panel: Equatable {
    case none
    case tools
    case ai
    case result
    case clipboard
    case macros
    case emoji
    case settings
    case stickers
    case cursor
    case translate
    case commands
    case discord
    case check
    case history
}

struct Suggestion: Identifiable, Equatable {
    enum Kind { case word, typed, correction, macro, ai, phrase, token, command, swipe, contact, reply }
    let id = UUID()
    var text: String
    var kind: Kind
    var display: String? = nil
    var rest: String = ""
}

/// Nur die Vorschlagsleiste beobachtet dieses Modell – Tippen zeichnet so nicht die ganze Tastatur neu.
final class BarModel: ObservableObject {
    @Published var suggestions: [Suggestion] = []
    @Published var phrases: [Suggestion] = []
    @Published var thinking = false
    @Published var liveFix: KeyboardState.LiveFix?
    /// Hinweise der Kontextprüfung (orange Markierung in der Leiste).
    @Published var issues: [OpenAIClient.CheckIssue] = []
    @Published var checking = false
    /// Korrekturen nach der Schlussprüfung groß anbieten (bis zum nächsten Tastendruck).
    @Published var offerFixes = false
    /// Angebot in der Leiste: Gelöschtes wiederherstellen, Termin speichern, Antworten …
    @Published var offer: BarOffer?
}

/// Zustand, den nur das UIKit-Tastenfeld braucht.
final class KeyModel: ObservableObject {
    @Published var layer: KeyboardLayer = .letters
    @Published var shift: ShiftState = .on
    @Published var returnTitle = "⏎"
    @Published var needsGlobe = true
}

final class KeyboardState: ObservableObject {
    weak var controller: KeyboardViewController?
    let store = SharedStore.shared
    let engine = TextEngine()
    let client = OpenAIClient(store: SharedStore.shared)
    /// Verlauf, Kontakte, Standort, Termine (siehe Extras.swift)
    let extras = ExtrasState()

    let bar = BarModel()
    let keyModel = KeyModel()

    // Layout (Weiterleitungen in die schlanken Teil-Modelle)
    var layer: KeyboardLayer {
        get { keyModel.layer }
        set { if keyModel.layer != newValue { keyModel.layer = newValue } }
    }
    var shift: ShiftState {
        get { keyModel.shift }
        set { if keyModel.shift != newValue { keyModel.shift = newValue } }
    }
    var returnTitle: String {
        get { keyModel.returnTitle }
        set { if keyModel.returnTitle != newValue { keyModel.returnTitle = newValue } }
    }
    var needsGlobe: Bool {
        get { keyModel.needsGlobe }
        set { if keyModel.needsGlobe != newValue { keyModel.needsGlobe = newValue } }
    }
    var suggestions: [Suggestion] {
        get { bar.suggestions }
        set { bar.suggestions = newValue }
    }
    var aiPhrase: Suggestion? {
        get { bar.phrases.first }
        set { let v = newValue.map { [$0] } ?? []; if v.map(\.text) != bar.phrases.map(\.text) { bar.phrases = v } }
    }
    var aiThinking: Bool {
        get { bar.thinking }
        set { if bar.thinking != newValue { bar.thinking = newValue } }
    }
    var liveFix: LiveFix? {
        get { bar.liveFix }
        set { bar.liveFix = newValue }
    }
    @Published var panel: Panel = .none
    private var liveCheckWork: DispatchWorkItem?
    private var liveCheckPending = false
    private var wordsSinceCheck = 0
    private var liveEditing = false
    private var neverFix = Set<String>()
    private var liveFixHideWork: DispatchWorkItem?

    struct LiveFix: Equatable {
        var pairs: [Pair]
        struct Pair: Equatable { var wrong: String; var right: String }
        var label: String {
            pairs.count == 1 ? "\(pairs[0].wrong) → \(pairs[0].right)" : "KI: \(pairs.count) Stellen korrigiert"
        }
    }
    private var predictionCache: [String: OpenAIClient.Prediction] = [:]
    private var predictionOrder: [String] = []
    @Published var hasFullAccess = false
    @Published var toast: String?

    // KI
    @Published var sourceMode: AIScope = .auto
    @Published var aiBusy = false
    @Published var aiStatus = ""
    @Published var aiResult = ""
    @Published var aiOriginal = ""
    @Published var aiShowDiff = false
    @Published var aiDiff: [TextDiff.Segment]?
    @Published var aiChangeCount = 0
    @Published var aiError: String?
    @Published var aiTitle = ""
    /// Ergebnis enthält App-Formatierung (z. B. Discord-Markdown) – nicht bereinigen.
    var aiKeepMarkdown = false
    /// Ergebnis nach Fertigstellung automatisch kopieren.
    var aiAutoCopy = false
    @Published var composeMode = false
    @Published var composeTarget: ComposeTarget = .ai
    @Published var settingsPage: SettingsPage = .main
    private var pendingMacroShortcut = ""
    var composeIsRefine: Bool { composeTarget == .refine }

    /// Wohin die Eingabe im Eingabe-Modus geht (KI-Auftrag oder eine Einstellung).
    enum ComposeTarget: Equatable {
        case ai, refine, translate, calc, mcCommand, apiKey, baseURL, chatModel, personalContext, writingStyle
        case macroShortcut, macroText, profileName, profileContext(UUID), actionTitle, actionPrompt
        case aiBehavior, learnedProfile, actionEdit(UUID), discordAnnounce, memoryNote
        case clipEdit(UUID), clipNew, clipRename(UUID), clipFolderNew, clipFolderRename(String), clipSearch

        var placeholder: String {
            switch self {
            case .ai: return "Was soll die KI schreiben?"
            case .refine: return "Wie soll das Ergebnis geändert werden?"
            case .translate: return "Tippe in deiner Sprache …"
            case .calc: return "Rechnung, z. B. 12,5*4+3"
            case .mcCommand: return "Was soll passieren? z. B. „64 Diamanten“"
            case .apiKey: return "OpenAI-API-Schlüssel (sk-…)"
            case .baseURL: return "API-Adresse (https://…/v1)"
            case .chatModel: return "Modellname, z. B. gpt-6-luna"
            case .personalContext: return "Über mich: Name, Beruf, Fakten …"
            case .writingStyle: return "Mein Schreibstil …"
            case .macroShortcut: return "Kürzel für das Makro (z. B. adr)"
            case .macroText: return "Text des Makros"
            case .profileName: return "Name des neuen Profils"
            case .profileContext: return "Kontext für dieses Profil"
            case .actionTitle: return "Name der KI-Aktion"
            case .actionPrompt: return "Anweisung an die KI"
            case .aiBehavior: return "Wie soll sich die KI verhalten? z. B. „Duze immer, kurz & locker“"
            case .learnedProfile: return "Was die KI über dich weiß …"
            case .memoryNote: return "Was soll sich die KI merken?"
            case .actionEdit: return "Neue Anweisung für die Aktion"
            case .discordAnnounce: return "Worum geht die Ankündigung?"
            case .clipEdit: return "Eintrag bearbeiten …"
            case .clipNew: return "Neuer Eintrag – tippe den Text …"
            case .clipRename: return "Name für den Eintrag"
            case .clipFolderNew: return "Name des neuen Ordners"
            case .clipFolderRename: return "Neuer Ordnername"
            case .clipSearch: return "In der Ablage suchen …"
            }
        }

        var symbol: String {
            switch self {
            case .ai: return "sparkles"
            case .refine: return "slider.horizontal.3"
            case .translate: return "character.bubble"
            case .calc: return "plus.forwardslash.minus"
            case .mcCommand: return "terminal"
            case .apiKey: return "key.fill"
            case .baseURL: return "server.rack"
            case .chatModel: return "cpu"
            case .personalContext, .writingStyle, .profileContext: return "person.text.rectangle"
            case .macroShortcut, .macroText: return "text.badge.star"
            case .profileName: return "person.2"
            case .actionTitle, .actionPrompt, .actionEdit: return "wand.and.stars"
            case .aiBehavior: return "slider.horizontal.below.square.and.square.filled"
            case .learnedProfile, .memoryNote: return "brain.head.profile"
            case .discordAnnounce: return "megaphone"
            case .clipEdit, .clipNew, .clipRename: return "doc.on.clipboard"
            case .clipFolderNew, .clipFolderRename: return "folder"
            case .clipSearch: return "magnifyingglass"
            }
        }

        var isSetting: Bool { self != .ai && self != .refine && self != .translate && self != .calc && self != .mcCommand && self != .discordAnnounce && !isClip }

        /// Eingaben, die zur Zwischenablage gehören.
        var isClip: Bool {
            switch self {
            case .clipEdit, .clipNew, .clipRename, .clipFolderNew, .clipFolderRename, .clipSearch: return true
            default: return false
            }
        }

        /// Lange Texte: großer Editor, Return = neue Zeile, Speichern über ✓.
        var isLongText: Bool {
            switch self {
            case .clipEdit, .clipNew, .aiBehavior, .learnedProfile, .actionPrompt, .actionEdit, .personalContext, .writingStyle, .profileContext, .macroText: return true
            default: return false
            }
        }
    }

    enum SettingsPage: Equatable { case main, ai, context, design, typing, macros, actions, toolbar }
    @Published var composeText = "" { didSet { if composeText != oldValue { composeDidChange() } } }
    private var lastRun: (() -> Void)?
    private var aiTask: Task<Void, Never>?
    private(set) var replaceTarget: ReplaceTarget = .none

    // Zwischenablage
    @Published var clips: [ClipItem] = []
    var lastChangeCount = -1
    private var clipTimer: Timer?

    // Tippen
    private var lastSpaceTime = Date.distantPast
    private var lastShiftTap = Date.distantPast
    var undoCorrection: (original: String, corrected: String, trailing: String)?
    private var aiSuggestionTask: Task<Void, Never>?
    private var refreshWork: DispatchWorkItem?
    private var deleteTimer: Timer?
    private var deleteCount = 0
    private var impact = UIImpactFeedbackGenerator(style: .light)
    private var impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private var hapticStyleInUse = "light"
    private let selection = UISelectionFeedbackGenerator()

    var onHeightChange: ((CGFloat) -> Void)?

    var isLandscape: Bool {
        let size = controller?.view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        return size.width > size.height
    }
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var toolbarHeight: CGFloat {
        let compact = isLandscape && !isPad
        if composeMode && composeTarget == .translate { return compact ? 82 : 96 }
        if composeMode && composeTarget.isLongText { return compact ? 88 : 120 }
        return compact ? 42 : 48
    }
    var contentHeight: CGFloat { keysHeight }
    var keyRowHeight: CGFloat {
        if isPad { return isLandscape ? 60 : 64 }
        return isLandscape ? 39 : 55
    }
    /// Seitlicher Abstand im Querformat (Notch / Dynamic Island / runde Ecken)
    @Published var sideInset: CGFloat = 0
    var rowCount: Int { store.showNumberRow && layer == .letters ? 5 : 4 }
    var keysHeight: CGFloat { CGFloat(rowCount) * keyRowHeight + 8 }
    var totalHeight: CGFloat { toolbarHeight + keysHeight }

    enum ReplaceTarget { case none, selection, all(length: Int), range(before: Int, after: Int) }

    init(controller: KeyboardViewController) {
        self.controller = controller
    }

    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }
    var tint: Color { Theme.tint(store.keyboardTint) }

    // MARK: - Lebenszyklus

    func appear() {
        store.reload()
        if store.swipeTyping || store.tapCorrection { SwipeDecoder.shared.loadIfNeeded() }
        sourceMode = store.aiScope
        hasFullAccess = controller?.hasFullAccess ?? false
        needsGlobe = controller?.needsInputModeSwitchKey ?? true
        store.reportKeyboardStatus(fullAccess: hasFullAccess)
        onHeightChange?(totalHeight)
        updateReturnKey()
        updateAutoShift()
        // Alles Schwere erst nach dem ersten Frame – die Tastatur erscheint sofort.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.impact.prepare()
            if !self.lexiconRequested {
                self.lexiconRequested = true
                self.controller?.requestSupplementaryLexicon { [weak self] lex in
                    DispatchQueue.main.async { self?.engine.setLexicon(lex) }
                }
            }
            self.engine.warmUp()
            self.loadContactsIfNeeded()
            self.refreshSuggestionsNow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.startClipboardWatch()
        }
    }

    private var lexiconRequested = false

    func handleMemoryWarning() {
        predictionCache.removeAll()
        predictionOrder.removeAll()
        aiDiff = nil
        if panel == .emoji { panel = .none }
    }

    func disappear() {
        finishDeletionBurst()
        snapshotHistory()
        engine.save()
        if touchModelUpdates > 0 { saveTouchModel() }
        clipTimer?.invalidate()
        clipTimer = nil
        stopDelete()
    }

    func textDidChange() {
        if !wordTaps.isEmpty, wordTaps.count != currentWord.count { wordTaps = [] }
        updateReturnKey()
        if !composeMode {
            updateAutoShift()
            scheduleRefresh()
        }
    }

    private func updateReturnKey() {
        let title: String
        switch proxy?.returnKeyType ?? .default {
        case .go: title = "Los"
        case .google, .yahoo, .search: title = "Suchen"
        case .join: title = "Beitreten"
        case .next, .continue: title = "Weiter"
        case .send: title = "Senden"
        case .done: title = "Fertig"
        case .route: title = "Route"
        case .emergencyCall: title = "Notruf"
        default: title = "⏎"
        }
        if composeMode {
            let t = composeTarget.isLongText ? "⏎" : "Senden"
            if returnTitle != t { returnTitle = t }
            return
        }
        if title != returnTitle { returnTitle = title }
    }

    // MARK: - Feedback

    /// Sofortiges Feedback beim Herunterdrücken einer Taste.
    func keyDownFeedback(special: Bool) {
        if store.keySound { AudioServicesPlaySystemSound(special ? 1156 : 1104) }
        if store.haptics, hasFullAccess, store.hapticStrength > 0.01 {
            ensureHapticStyle()
            let base = store.hapticStrength
            impact.impactOccurred(intensity: CGFloat(min(1, special ? base + 0.15 : base)))
            impact.prepare()
        }
    }

    func feedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        if store.keySound { AudioServicesPlaySystemSound(1104) }
        if store.haptics, hasFullAccess, store.hapticStrength > 0.01 {
            ensureHapticStyle()
            let base = store.hapticStrength
            if style == .medium || style == .heavy {
                impactMedium.impactOccurred(intensity: CGFloat(min(1, base + 0.3)))
            } else {
                impact.impactOccurred(intensity: CGFloat(base))
            }
        }
    }

    /// Haptik-Art geändert → Generator neu anlegen (nur dann, kostet sonst nichts).
    private func ensureHapticStyle() {
        let st = store.hapticStyle
        guard st != hapticStyleInUse else { return }
        hapticStyleInUse = st
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch st {
        case "soft": style = .soft
        case "medium": style = .medium
        case "rigid": style = .rigid
        case "heavy": style = .heavy
        default: style = .light
        }
        impact = UIImpactFeedbackGenerator(style: style)
        impactMedium = UIImpactFeedbackGenerator(style: style == .light || style == .soft ? .medium : .heavy)
        impact.prepare()
    }

    /// Kurzer Test beim Einstellen der Haptik.
    func hapticPreview() {
        guard hasFullAccess else { showToast("Haptik braucht „Vollen Zugriff“."); return }
        ensureHapticStyle()
        impact.impactOccurred(intensity: CGFloat(max(0.05, store.hapticStrength)))
        impact.prepare()
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    // MARK: - Text-Kontext

    var before: String { proxy?.documentContextBeforeInput ?? "" }
    var after: String { proxy?.documentContextAfterInput ?? "" }
    var selected: String { proxy?.selectedText ?? "" }

    var currentWord: String {
        var word = ""
        for ch in before.reversed() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "'" { word.insert(ch, at: word.startIndex) } else { break }
        }
        return word
    }

    /// Alles seit dem letzten Leerzeichen (für E-Mails, Links usw.).
    var currentToken: String {
        var t = ""
        for ch in before.reversed() {
            if ch.isWhitespace { break }
            t.insert(ch, at: t.startIndex)
        }
        return t
    }

    /// Aktuelle Zeile bis zum Cursor.
    var currentLine: String {
        let b = before
        if let i = b.lastIndex(of: "\n") { return String(b[b.index(after: i)...]) }
        return b
    }

    /// Befehlsmodus: Zeile beginnt mit „/“ (z. B. Minecraft-Chat) – keine Korrekturen, keine Großschreibung.
    var isCommandLine: Bool {
        currentLine.drop(while: { $0 == " " }).first == "/"
    }

    /// Das vorletzte Wort (für Dreier-Folgen).
    var secondPreviousWord: String? {
        let text = String(before.dropLast(currentWord.count))
        let words = text.split { !($0.isLetter || $0.isNumber) }
        return words.count >= 2 ? String(words[words.count - 2]) : nil
    }

    /// Enthält das aktuelle „Wort“ Zeichen wie @ . / : ? Dann ist es eine Adresse o. Ä. – nicht korrigieren.
    private var tokenIsSpecial: Bool {
        let t = currentToken
        return t.contains("@") || t.contains("/") || t.contains(":") || t.contains("_")
            || (t.contains(".") && t.last != ".") || t.rangeOfCharacter(from: .decimalDigits) != nil
    }

    var previousWord: String? {
        let text = String(before.dropLast(currentWord.count))
        let words = text.split { !($0.isLetter || $0.isNumber) }
        return words.last.map(String.init)
    }

    // MARK: - Eingabe (schneller Pfad)

    func insert(_ text: String) {
        finishDeletionBurst()
        if composeMode {
            composeText += text
            return
        }
        undoCorrection = nil
        proxy?.insertText(text)
        if shift == .on { shift = .off }
        scheduleRefresh()
    }

    func insertAlternate(_ s: String) {
        insert(s)
    }

    func tapKey(_ key: String) {
        finishDeletionBurst()
        var output = (shift != .off && layer == .letters) ? key.uppercased() : key
        // Intelligente Interpunktion wie bei iOS: „…“ und ’
        if store.smartPunctuation, !composeMode, (key == "\"" || key == "'"), !isCommandLine, !tokenIsSpecial {
            let prev = before.last
            let opening = prev == nil || prev!.isWhitespace || "([{„‚".contains(prev!)
            if key == "\"" { output = opening ? "„" : "“" } else if !opening { output = "’" }
        }
        if let sw = lastSwipe {
            lastSwipe = nil
            swipeAITask?.cancel()
            // Nach einem gewischten Wort beginnt ein Buchstabe ein neues Wort (wie bei iOS)
            if !composeMode, let ch = output.first, ch.isLetter || ch.isNumber, before.hasSuffix(sw.word) {
                proxy?.insertText(" ")
                protectedSwipeWord = nil
            }
        }
        if composeMode {
            composeText += output
            if shift == .on { shift = .off }
            return
        }
        let isPunct = output.count == 1 && ".,!?;:".contains(output)
        if isPunct && isCommandLine {
            proxy?.insertText(output)
            if shift == .on { shift = .off }
            scheduleRefresh()
            return
        }
        if isPunct {
            let b = before
            if b.hasSuffix(" "), undoCorrection == nil, let prev = b.dropLast().last, prev.isLetter || prev.isNumber {
                // „Wort .“ → „Wort. “
                proxy?.deleteBackward()
                proxy?.insertText(output + " ")
                afterCommit()
                return
            }
            commitWord(trailing: output)
            return
        }
        undoCorrection = nil
        let startsWord = currentWord.isEmpty
        proxy?.insertText(output)
        if output.count == 1, output.first?.isLetter == true, layer == .letters {
            if startsWord { wordTaps = [] }
            wordTaps.append(pendingTapPoint ?? CGPoint(x: -9999, y: -9999))
        } else {
            wordTaps = []
        }
        pendingTapPoint = nil
        if shift == .on { shift = .off }
        if layer != .letters, key == "'" { layer = .letters }
        scheduleRefresh()
    }

    func tapSpace() {
        finishDeletionBurst()
        lastSwipe = nil
        if composeMode { composeText += " "; return }
        let now = Date()
        let b = before
        if store.doubleSpacePeriod, !isCommandLine, now.timeIntervalSince(lastSpaceTime) < 0.45, b.hasSuffix(" "),
           let c = b.dropLast().last, c.isLetter || c.isNumber {
            proxy?.deleteBackward()
            proxy?.insertText(". ")
            lastSpaceTime = .distantPast
            undoCorrection = nil
            afterCommit()
            return
        }
        lastSpaceTime = now
        commitWord(trailing: " ")
    }

    func tapReturn() {
        finishDeletionBurst()
        lastSwipe = nil
        // Vor dem Senden: Text im Verlauf sichern (danach ist das Feld meist leer)
        if !composeMode, returnTitle != "⏎" { snapshotHistory() }
        if !composeMode { detectEvent(in: currentLine) }
        if composeMode {
            if composeTarget.isLongText { composeText += "\n"; return }
            sendCompose(); return
        }
        commitWord(trailing: "\n")
    }

    /// Schließt das aktuelle Wort ab: Makros, Textersetzung, Autokorrektur, Lernen.
    private func commitWord(trailing: String) {
        if isCommandLine {
            // Befehle exakt so lassen, wie getippt
            proxy?.insertText(trailing)
            undoCorrection = nil
            afterCommit()
            return
        }
        let word = currentWord
        let prev = previousWord
        let token = currentToken
        if !token.isEmpty, tokenIsSpecial {
            // Persönliche Einträge lernen, nie autokorrigieren
            engine.learnToken(token.trimmingCharacters(in: CharacterSet(charactersIn: ",;!?")))
            proxy?.insertText(trailing)
            undoCorrection = nil
            afterCommit()
            return
        }

        if !word.isEmpty, let protected = protectedSwipeWord, protected == word {
            protectedSwipeWord = nil
            engine.learn(word: word, previous: prev)
            proxy?.insertText(trailing)
            undoCorrection = nil
            afterCommit()
            return
        }
        if !word.isEmpty {
            if store.macroAutoExpand, let macro = store.macros.first(where: { !$0.shortcut.isEmpty && $0.shortcut.lowercased() == word.lowercased() }) {
                deleteChars(word.count)
                runMacro(macro, trailing: trailing)
                return
            }
            if let replacement = engine.textReplacement(for: word) {
                deleteChars(word.count)
                proxy?.insertText(replacement + trailing)
                undoCorrection = (word, replacement, trailing)
                afterCommit()
                return
            }
            if store.autocorrect, shouldAutocorrect, !looksLikeName(word), let corr = smartCorrection(for: word), corr != word {
                deleteChars(word.count)
                proxy?.insertText(corr + trailing)
                undoCorrection = (word, corr, trailing)
                store.incrementStat("corrections")
                engine.learn(word: corr, previous: prev)
                afterCommit()
                return
            }
            learnTouches(for: word)
            engine.learn(word: word, previous: prev)
        }
        proxy?.insertText(trailing)
        undoCorrection = nil
        afterCommit()
    }

    /// Großgeschriebenes Wort mitten im Satz → vermutlich Name/Marke, nicht korrigieren.
    private func looksLikeName(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        let head = before.dropLast(word.count).trimmingCharacters(in: .whitespaces)
        guard let last = head.last else { return false }
        return !".!?\n:".contains(last)
    }

    var shouldAutocorrect: Bool {
        guard let proxy else { return true }
        if proxy.autocorrectionType == .no { return false }
        switch proxy.keyboardType ?? .default {
        case .URL, .emailAddress, .webSearch, .twitter, .numberPad, .phonePad, .asciiCapableNumberPad: return false
        default: break
        }
        let contentType: UITextContentType? = proxy.textContentType ?? nil
        if let ct = contentType, [UITextContentType.URL, .emailAddress, .username, .password, .newPassword, .oneTimeCode].contains(ct) {
            return false
        }
        return true
    }

    func afterCommit() {
        wordTaps = []
        wordsSincePrediction += 1
        if !liveEditing {
            let end = before.last.map { ".!?\n".contains($0) } ?? false
            scheduleContextCheck(sentenceEnd: end)
            if end { collectSample(); detectEvent(in: lastSentence) }
        }
        if !liveEditing {
            wordsSinceCheck += 1
            let last = before.last
            if wordsSinceCheck >= (store.aiTypoTurbo ? 4 : 8) || (last != nil && ".!?\n".contains(last!)) && wordsSinceCheck >= 1 {
                liveCheckPending = true
            }
        }
        if layer != .letters { layer = .letters }
        if shift == .on { shift = .off }
        updateAutoShift()
        scheduleRefresh()
    }

    func deleteChars(_ n: Int) {
        for _ in 0..<max(0, n) { proxy?.deleteBackward() }
    }

    func tapDelete() {
        if composeMode {
            if !composeText.isEmpty { composeText.removeLast() }
            return
        }
        if let sw = lastSwipe, before.hasSuffix(sw.word) {
            // Wie bei iOS: ein gewischtes Wort verschwindet mit einem Tipp
            lastSwipe = nil
            swipeAITask?.cancel()
            protectedSwipeWord = nil
            captureDeleted(String(before.suffix(sw.word.count + (sw.addedSpace && before.dropLast(sw.word.count).hasSuffix(" ") ? 1 : 0))))
            deleteChars(sw.word.count + (sw.addedSpace && before.dropLast(sw.word.count).hasSuffix(" ") ? 1 : 0))
            feedback()
            updateAutoShift()
            scheduleRefresh()
            return
        }
        if let undo = undoCorrection, before.hasSuffix(undo.corrected + undo.trailing) {
            deleteChars(undo.corrected.count + undo.trailing.count)
            proxy?.insertText(undo.original)
            engine.learn(word: undo.original, previous: nil, weight: 3)
            undoCorrection = nil
            scheduleRefresh()
            return
        }
        undoCorrection = nil
        let sel = selected
        if !sel.isEmpty { captureDeleted(sel) } else if let ch = before.last { captureDeleted(String(ch)) }
        proxy?.deleteBackward()
        if !wordTaps.isEmpty { wordTaps.removeLast() }
        updateAutoShift()
        scheduleRefresh()
    }

    func startDelete() {
        tapDelete()
        deleteCount = 0
        deleteTimer?.invalidate()
        let started = Date()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self, self.deleteTimer != nil else { return }
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                // Sicherheitsnetz gegen „hängende“ Löschtaste
                if Date().timeIntervalSince(started) > 12 { self.stopDelete(); return }
                self.deleteCount += 1
                if self.deleteCount > 15, !self.composeMode {
                    self.deleteWord()
                } else {
                    self.tapDelete()
                }
                if self.store.haptics, self.hasFullAccess { self.selection.selectionChanged() }
            }
        }
    }

    func stopDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        updateRestoreOffer()
    }

    private func deleteWord() {
        let text = before
        guard !text.isEmpty else { return }
        var count = 0
        var seenLetter = false
        for ch in text.reversed() {
            if ch.isWhitespace || ch.isPunctuation {
                if seenLetter { break }
            } else {
                seenLetter = true
            }
            count += 1
        }
        captureDeleted(String(text.suffix(max(1, count))))
        deleteChars(max(1, count))
        scheduleRefresh()
    }

    func tapShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3, store.capsLockEnabled {
            shift = .caps
        } else {
            shift = shift == .off ? .on : .off
        }
        lastShiftTap = now
    }

    func moveCursor(_ offset: Int) {
        guard offset != 0 else { return }
        proxy?.adjustTextPosition(byCharacterOffset: offset)
        if store.haptics, hasFullAccess { selection.selectionChanged() }
    }

    func cursorMoveEnded() {
        updateAutoShift()
        scheduleRefresh()
    }

    func updateAutoShift() {
        guard layer == .letters, shift != .caps, !composeMode else { return }
        if isCommandLine { if shift != .off { shift = .off }; return }
        var newShift: ShiftState = .off
        if store.autocapitalize, let proxy {
            let type = proxy.autocapitalizationType ?? .sentences
            if type == .allCharacters {
                newShift = .on
            } else if type != UITextAutocapitalizationType.none {
                let text = before
                if text.isEmpty || text.last == "\n" {
                    newShift = .on
                } else if type == .words, text.last?.isWhitespace == true {
                    newShift = .on
                } else if text.last == " " {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if let last = trimmed.last, ".!?".contains(last) { newShift = .on }
                }
            }
        }
        if newShift != shift { shift = newShift }
    }

    // MARK: - Vorschläge (entkoppelt vom Tippen)

    // MARK: - Tipp-Rhythmus (Power-Tippen)

    private var lastKeystroke: CFTimeInterval = 0
    /// Geglätteter Abstand zwischen zwei Tasten (Sekunden).
    private var keyInterval: CFTimeInterval = 0.3

    /// Wird bei jedem Tastendruck aufgerufen (nur Zeitstempel – kostet nichts).
    func noteKeystroke() {
        let now = CACurrentMediaTime()
        let dt = now - lastKeystroke
        lastKeystroke = now
        if dt < 1.0 { keyInterval = keyInterval * 0.7 + dt * 0.3 }
    }

    /// Vorschläge erst in der Tipp-Pause berechnen: Wer schnell tippt, bekommt zwischen zwei Tasten
    /// keine Arbeit auf den Haupt-Thread – jeder Tipp wird sofort verarbeitet.
    private var refreshDelay: TimeInterval {
        let sinceKey = CACurrentMediaTime() - lastKeystroke
        guard sinceKey < 0.6 else { return 0.05 }
        return min(0.28, max(0.07, keyInterval * 1.35))
    }

    func scheduleRefresh() {
        if !liveEditing, !bar.issues.isEmpty { pruneIssues() }
        if !liveEditing {
            if bar.offerFixes { bar.offerFixes = false }
            scheduleEndCheck()
        }
        if !liveEditing {
            liveCheckWork?.cancel()
            if liveCheckPending { scheduleLiveCheck() }
        }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshSuggestionsNow() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay, execute: work)
    }

    func refreshSuggestionsNow() {
        aiSuggestionTask?.cancel()
        aiThinking = false
        if composeMode || (panel != .none && panel != .tools) { return }
        if let sw = lastSwipe, currentWord == sw.word {
            let alts = sw.alternatives.filter { $0 != sw.word }.prefix(3).map { Suggestion(text: $0, kind: .swipe) }
            let newList = Array(alts)
            if newList.map(\.text) != suggestions.map(\.text) { suggestions = newList }
            aiPhrase = nil
            return
        }
        if isCommandLine {
            let line = currentLine.trimmingCharacters(in: .whitespaces).lowercased()
            let matches = store.commands.filter { line.count <= 1 || $0.command.lowercased().hasPrefix(line) || $0.title.lowercased().contains(line.dropFirst()) }
                .sorted { a, b in a.favorite != b.favorite ? a.favorite : false }
                .prefix(8)
                .map { Suggestion(text: $0.command, kind: .command, display: $0.command) }
            let newList = Array(matches)
            if newList.map(\.text) != suggestions.map(\.text) { suggestions = newList }
            aiPhrase = nil
            return
        }
        let word = currentWord
        // Tipp-Pause nutzen: offene Präfix-Fragen klären und die Tipp-Korrektur vorberechnen,
        // damit das Leerzeichen später sofort fertig ist.
        engine.warmPendingPrefixes()
        precomputeTapFix(for: word)
        var list: [Suggestion] = []
        let token = currentToken
        for t in engine.tokenCompletions(prefix: token) {
            list.append(Suggestion(text: t, kind: .token))
        }
        if tokenIsSpecial && !token.isEmpty {
            // In Adressen keine Wortvorschläge/Korrekturen
            let newList = Array(list.prefix(3))
            if newList.map(\.text) != suggestions.map(\.text) { suggestions = newList }
            aiPhrase = nil
            return
        }

        if !word.isEmpty {
            if let macro = store.macros.first(where: { !$0.shortcut.isEmpty && $0.shortcut.lowercased() == word.lowercased() }) {
                list.append(Suggestion(text: macro.shortcut, kind: .macro, display: "⚡︎ " + macro.title))
            }
            var correction: String?
            if store.autocorrect, shouldAutocorrect, !looksLikeName(word) { correction = engine.correction(for: word) }
            list.append(Suggestion(text: word, kind: .typed, display: "„\(word)“"))
            if let correction { list.append(Suggestion(text: correction, kind: .correction)) }
            for c in engine.completions(prefix: word, previousWord: previousWord, limit: 3) where !list.contains(where: { $0.text == c }) {
                list.append(Suggestion(text: c, kind: .word))
            }
        } else {
            for p in engine.predictions(after: previousWord, prev2: secondPreviousWord, limit: 3) {
                list.append(Suggestion(text: p, kind: .word))
            }
        }
        list = addContactSuggestions(word: word, to: list)
        if !store.showPredictions {
            // Wie iOS „Vorschläge aus“: nur noch Korrekturen, Makros und Kontakte
            list = list.filter { $0.kind == .correction || $0.kind == .macro || $0.kind == .contact }
        }
        let newList = Array(list.prefix(3))
        if newList.map(\.text) != suggestions.map(\.text) || newList.map(\.kind) != suggestions.map(\.kind) {
            suggestions = newList
        }

        requestPrediction()
    }

    /// KI-Vorhersage für die Vorschlagsleiste (entprellt, mit Cache).
    private var wordsSincePrediction = 0
    private var lastPredictionContext = ""
    /// Aktuellen Text als „schon vorhergesagt“ markieren (z. B. nach Antwortvorschlägen).
    func markPredictionContext() { lastPredictionContext = before }

    /// KI denkt jetzt sofort mit (Knopf in der Leiste).
    func predictNow() {
        guard hasFullAccess, store.hasAPIKey else {
            showToast(hasFullAccess ? "Kein API-Schlüssel – ✨ → Einstellungen → KI & API" : "Bitte „Vollen Zugriff“ erlauben.")
            return
        }
        feedback(.medium)
        refreshWork?.cancel()
        requestPrediction(force: true)
    }

    private func requestPrediction(force: Bool = false) {
        // Veraltete KI-Vorschläge entfernen, sobald weitergetippt wurde
        if !force, before != lastPredictionContext, aiPhrase != nil { aiPhrase = nil }
        guard store.aiSuggestMode != "off", hasFullAccess, store.hasAPIKey, !composeMode else {
            if aiPhrase != nil { aiPhrase = nil }
            aiThinking = false
            return
        }
        if !force {
            // Nur „gelegentlich“: an Wortgrenzen, nach einigen Wörtern oder am Satzende
            guard store.aiSuggestMode == "occasional" else { aiThinking = false; return }
            let last = before.last
            let atBoundary = last == " " || last == "\n"
            let sentenceEnd = before.trimmingCharacters(in: .whitespaces).last.map { ".!?".contains($0) } ?? false
            guard atBoundary, wordsSincePrediction >= 6 || (sentenceEnd && wordsSincePrediction >= 2) else {
                aiThinking = false
                return
            }
        }
        wordsSincePrediction = 0
        let context = before
        lastPredictionContext = context
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            if aiPhrase != nil { aiPhrase = nil }
            aiThinking = false
            return
        }
        let key = String(context.suffix(300))
        if let cached = predictionCache[key] {
            applyPrediction(cached, context: context)
            return
        }
        if aiPhrase != nil { aiPhrase = nil }
        aiThinking = true
        let delay: UInt64 = force ? 0 : 1_200_000_000
        aiSuggestionTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled, let self else { return }
            let prediction = try? await self.client.predict(context: context)
            await MainActor.run {
                self.aiThinking = false
                guard !Task.isCancelled, let prediction else { return }
                self.predictionCache[key] = prediction
                self.predictionOrder.append(key)
                if self.predictionOrder.count > 60 {
                    self.predictionCache[self.predictionOrder.removeFirst()] = nil
                }
                guard self.before == context else { return }
                self.applyPrediction(prediction, context: context)
            }
        }
    }

    private func applyPrediction(_ p: OpenAIClient.Prediction, context: String) {
        let word = currentWord
        var merged = suggestions.filter { $0.kind == .typed || $0.kind == .correction || $0.kind == .macro }
        // Vervollständigung des aktuellen Wortes aus "rest"
        if !word.isEmpty, !p.rest.isEmpty, p.rest.count < 25 {
            let full = word + p.rest
            if !merged.contains(where: { $0.text == full }) {
                merged.insert(Suggestion(text: full, kind: .ai), at: min(1, merged.count))
            }
        }
        for w in p.words where !merged.contains(where: { $0.text.lowercased() == w.lowercased() }) {
            merged.append(Suggestion(text: w, kind: .ai))
        }
        // Lokale Vorschläge auffüllen
        for s in suggestions where !merged.contains(where: { $0.text == s.text }) { merged.append(s) }
        let phraseTexts = p.phrases.isEmpty ? (p.phrase.isEmpty ? [] : [p.phrase]) : p.phrases
        // Mit Satzfortsetzungen wird die Leiste scrollbar – dann mehr Wörter zeigen
        suggestions = Array(merged.prefix(phraseTexts.isEmpty ? 3 : 6))
        let rest = word.isEmpty ? "" : p.rest
        let newPhrases = phraseTexts.map { text in
            Suggestion(text: text, kind: .phrase, display: rest.isEmpty ? text : "…" + rest + " " + text, rest: rest)
        }
        if newPhrases.map(\.text) != bar.phrases.map(\.text) { bar.phrases = newPhrases }
    }

    func pickSuggestion(_ s: Suggestion) {
        feedback()
        switch s.kind {
        case .swipe:
            guard var sw = lastSwipe, currentWord == sw.word else { break }
            deleteChars(sw.word.count)
            proxy?.insertText(s.text)
            engine.learn(word: s.text, previous: nil, weight: 2)
            sw.word = s.text
            lastSwipe = sw
            protectedSwipeWord = s.text
            swipeAITask?.cancel()
            scheduleRefresh()
        case .macro:
            if let macro = store.macros.first(where: { $0.shortcut == s.text }) {
                deleteChars(currentWord.count)
                runMacro(macro, trailing: " ")
            }
        case .typed:
            engine.learn(word: s.text, previous: previousWord, weight: 2)
            proxy?.insertText(" ")
            undoCorrection = nil
            afterCommit()
        case .command:
            insertCommand(s.text)
        case .token:
            deleteChars(currentToken.count)
            proxy?.insertText(s.text + " ")
            engine.learnToken(s.text)
            undoCorrection = nil
            afterCommit()
        case .phrase:
            // Rest des Wortes + Phrase anhängen
            let word = currentWord
            var insertText = s.text
            if !s.rest.isEmpty {
                insertText = s.rest + " " + s.text
            } else if !word.isEmpty {
                insertText = " " + s.text
            } else if let last = before.last, !last.isWhitespace {
                insertText = " " + s.text
            }
            proxy?.insertText(insertText + " ")
            aiPhrase = nil
            store.incrementStat("aiPhrases")
            afterCommit()
        case .ai:
            let word = currentWord
            if !word.isEmpty, s.text.lowercased().hasPrefix(word.lowercased()) {
                deleteChars(word.count)
            } else if let last = before.last, !last.isWhitespace {
                proxy?.insertText(" ")
            }
            proxy?.insertText(s.text + " ")
            afterCommit()
        case .contact:
            if s.rest == "append" {
                // Nummer/E-Mail hinter den Namen setzen
                if let last = before.last, !last.isWhitespace { proxy?.insertText(" ") }
                proxy?.insertText(s.text + " ")
            } else {
                deleteChars(currentWord.count)
                proxy?.insertText(s.text + " ")
            }
            undoCorrection = nil
            afterCommit()
        case .reply:
            if let last = before.last, !last.isWhitespace { proxy?.insertText(" ") }
            proxy?.insertText(s.text)
            bar.phrases = []
            store.incrementStat("aiPhrases")
            afterCommit()
        default:
            let word = currentWord
            let prev = previousWord
            deleteChars(word.count)
            proxy?.insertText(s.text + " ")
            engine.learn(word: s.text, previous: prev)
            undoCorrection = nil
            afterCommit()
        }
    }

    // MARK: - Makros

    func runMacro(_ macro: Macro, trailing: String = "") {
        store.incrementStat("macros")
        if macro.isAI {
            let context = before + after
            runAI(title: macro.title, original: "", target: .none, showDiff: false) { [client = self.client] partial in
                try await client.compose(prompt: macro.text, context: context, onPartial: partial)
            }
            return
        }
        let clip = hasFullAccess ? UIPasteboard.general.string : nil
        let text = macro.expanded(clipboard: clip)
        proxy?.insertText(text + (text.hasSuffix("\n") ? "" : trailing))
        if panel == .macros { panel = .none }
        afterCommit()
    }

    // MARK: - KI

    func requireAI() -> Bool {
        if !hasFullAccess {
            showToast("Bitte „Vollen Zugriff“ für Tastatur KI erlauben.")
            return false
        }
        if !store.hasAPIKey {
            showToast("Kein KI-Zugang – ⚙︎ → KI & API: mit ChatGPT anmelden oder API-Schlüssel")
            return false
        }
        return true
    }

    /// Wartet kurz, bis das Textfeld den neuen Kontext gemeldet hat.
    @MainActor
    func waitForContextChange(from old: String?) async {
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 12_000_000)
            if proxy?.documentContextBeforeInput != old { return }
        }
    }

    @MainActor
    private func moveToEnd() async {
        for _ in 0..<1000 {
            let a = after
            if a.isEmpty { return }
            let old = proxy?.documentContextBeforeInput
            proxy?.adjustTextPosition(byCharacterOffset: a.utf16.count)
            await waitForContextChange(from: old)
        }
    }

    /// Liest den kompletten Text des Feldes ein – auch wenn iOS nur Ausschnitte liefert.
    @MainActor
    func readFullText() async -> String {
        await moveToEnd()
        var collected = ""
        var movedBack = 0
        for _ in 0..<4000 {
            let b = before
            if b.isEmpty { break }
            collected = b + collected
            let n = b.utf16.count
            proxy?.adjustTextPosition(byCharacterOffset: -n)
            movedBack += n
            await waitForContextChange(from: b)
            if before == b { break } // Feld bewegt sich nicht weiter
            if collected.count > 3_000_000 { break }
        }
        if movedBack > 0 {
            proxy?.adjustTextPosition(byCharacterOffset: movedBack)
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        await moveToEnd()
        return collected
    }

    @MainActor
    private func gatherSource(mode: AIScope? = nil) async -> (text: String, target: ReplaceTarget, context: String?)? {
        let sourceMode = mode ?? self.sourceMode
        if sourceMode == .clipboard {
            guard let s = UIPasteboard.general.string, !s.isEmpty else {
                showToast("Die Zwischenablage ist leer.")
                return nil
            }
            return (s, .none, nil)
        }
        let sel = selected
        if !sel.isEmpty {
            let ctx = store.useAppContext ? String((before + "[…]" + after).suffix(4000)) : nil
            return (sel, .selection, ctx)
        }
        if sourceMode == .paragraph {
            let b = before, a = after
            let startIdx = b.lastIndex(of: "\n").map { b.index(after: $0) } ?? b.startIndex
            let head = String(b[startIdx...])
            let endIdx = a.firstIndex(of: "\n") ?? a.endIndex
            let tail = String(a[..<endIdx])
            if !(head + tail).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (head + tail, .range(before: head.count, after: tail.count), store.useAppContext ? b + a : nil)
            }
        }
        aiStatus = "Lese Text ein …"
        let full = await readFullText()
        return (full, .all(length: full.count), nil)
    }

    func runAction(_ action: AIAction) {
        guard requireAI() else { return }
        startAI(title: action.title, showDiff: action.showDiff) { [weak self] in
            guard let self else { return nil }
            guard let source = await self.gatherSource() else { return nil }
            return source
        } work: { [client = self.client] text, context, partial in
            try await client.transform(text: text, instruction: action.prompt, appContext: context, onPartial: partial)
        }
    }

    /// Führt eine KI-Aktion mit vorheriger Quell-Ermittlung aus.
    private func startAI(title: String, showDiff: Bool, autoApply: Bool = false,
                         source: @escaping () async -> (text: String, target: ReplaceTarget, context: String?)?,
                         work: @escaping (String, String?, @escaping (String) -> Void) async throws -> String) {
        aiTask?.cancel()
        aiTitle = title
        aiResult = ""
        aiOriginal = ""
        aiError = nil
        aiKeepMarkdown = store.activeApp?.markdown == true
        aiAutoCopy = false
        aiBusy = true
        aiStatus = "Bereite vor …"
        aiShowDiff = showDiff
        aiDiff = nil
        lastResultIsCommand = false
        composeMode = false
        panel = .result
        store.incrementStat("aiActions")
        lastRun = { [weak self] in self?.startAI(title: title, showDiff: showDiff, autoApply: autoApply, source: source, work: work) }
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let src = await source() else {
                self.aiBusy = false
                self.panel = .ai
                return
            }
            guard !src.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.aiBusy = false
                self.panel = .ai
                self.showToast("Kein Text vorhanden – tippe, markiere oder kopiere zuerst etwas.")
                return
            }
            self.replaceTarget = src.target
            self.aiOriginal = src.text
            let words = src.text.wordCount
            self.aiStatus = words > 400 ? "KI liest \(words) Wörter …" : "KI schreibt …"
            await self.perform { partial in try await work(src.text, src.context, partial) }
            // Ein-Klick-Aktionen: Ergebnis direkt einsetzen (bei Fehler bleibt das Ergebnis-Panel offen)
            if autoApply, !Task.isCancelled, self.aiError == nil, !self.aiResult.isEmpty {
                self.applyResult(replace: true)
                self.showToast("Übersetzt ✓")
            }
        }
    }

    /// Einfache KI-Ausführung ohne Quelltext (Schreiben, Makros, Verfeinern).
    func runAI(title: String, original: String, target: ReplaceTarget, showDiff: Bool,
               _ work: @escaping (@escaping (String) -> Void) async throws -> String) {
        guard requireAI() else { return }
        aiTask?.cancel()
        aiTitle = title
        aiResult = ""
        aiOriginal = original
        aiKeepMarkdown = store.activeApp?.markdown == true
        aiAutoCopy = false
        aiError = nil
        aiBusy = true
        aiStatus = "KI schreibt …"
        aiShowDiff = showDiff
        aiDiff = nil
        lastResultIsCommand = false
        replaceTarget = target
        composeMode = false
        panel = .result
        store.incrementStat("aiActions")
        lastRun = { [weak self] in self?.runAI(title: title, original: original, target: target, showDiff: showDiff, work) }
        aiTask = Task { @MainActor [weak self] in
            await self?.perform(work)
        }
    }

    @MainActor
    private func perform(_ work: @escaping (@escaping (String) -> Void) async throws -> String) async {
        do {
            let result = try await work { [weak self] partial in
                DispatchQueue.main.async {
                    guard let self, self.aiBusy else { return }
                    self.aiResult = OpenAIClient.cleanup(partial, keepMarkdown: self.aiKeepMarkdown)
                }
            }
            guard !Task.isCancelled else { return }
            aiResult = result
            aiBusy = false
            feedback(.medium)
            computeDiff()
            if aiAutoCopy, hasFullAccess, !result.isEmpty {
                UIPasteboard.general.string = result
                lastChangeCount = UIPasteboard.general.changeCount
                showToast("Fertig & kopiert ✓")
            }
        } catch {
            guard !Task.isCancelled else { return }
            aiError = error.localizedDescription
            aiBusy = false
        }
    }

    /// Berechnet die markierten Änderungen einmalig im Hintergrund.
    private func computeDiff() {
        aiDiff = nil
        aiChangeCount = 0
        guard aiShowDiff, !aiOriginal.isEmpty, !aiResult.isEmpty else { return }
        let original = aiOriginal, revised = aiResult
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let segs = TextDiff.segments(original: original, revised: revised)
            DispatchQueue.main.async {
                guard let self, self.aiResult == revised else { return }
                self.aiDiff = segs
                self.aiChangeCount = segs?.filter(\.changed).count ?? 0
            }
        }
    }

    func cancelAI() {
        aiTask?.cancel()
        aiBusy = false
    }

    func retryAI() { lastRun?() }

    /// Verfeinert das aktuelle Ergebnis.
    func refine(_ instruction: String) {
        let base = aiResult
        guard !base.isEmpty else { return }
        let target = replaceTarget
        let original = aiOriginal
        runAI(title: "Verfeinert", original: original, target: target, showDiff: false) { [client = self.client] partial in
            try await client.transform(text: base, instruction: instruction, onPartial: partial)
        }
    }

    func startCompose(refine: Bool = false) {
        guard requireAI() else { return }
        beginInput(refine ? .refine : .ai)
    }

    /// Startet den Eingabe-Modus: Die Tasten schreiben in die Leiste statt ins Textfeld.
    func beginInput(_ target: ComposeTarget, prefill: String = "") {
        composeTarget = target
        composeText = prefill
        composeMode = true
        panel = .none
        layer = .letters
        let lowerStart: Bool
        switch target {
        case .apiKey, .baseURL, .chatModel, .macroShortcut: lowerStart = true
        default: lowerStart = !prefill.isEmpty
        }
        shift = lowerStart ? .off : .on
        if target == .calc { layer = .numbers; shift = .off }
        translatePreview = ""
        calcResult = ""
        updateReturnKey()
        onHeightChange?(totalHeight)
    }

    func cancelCompose() {
        let target = composeTarget
        composeMode = false
        composeText = ""
        composeTarget = .ai
        updateReturnKey()
        if target == .refine, !aiResult.isEmpty { panel = .result }
        if target.isSetting { panel = .settings }
        if target.isClip { panel = .clipboard; reloadClips() }
        translateTask?.cancel()
        translatePreview = ""
        showLanguagePicker = false
        onHeightChange?(totalHeight)
        updateAutoShift()
        scheduleRefresh()
    }

    func sendCompose() {
        if composeTarget == .translate { insertTranslation(); return }
        if composeTarget == .calc { insertCalcResult(); return }
        let raw = composeText
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = composeTarget
        composeMode = false
        composeTarget = .ai
        composeText = ""
        updateReturnKey()
        if target.isClip {
            saveClipInput(target, target.isLongText ? raw : text)
            return
        }
        if target.isSetting {
            saveSettingInput(target, target.isLongText ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : text)
            return
        }
        guard !text.isEmpty else { cancelCompose(); return }
        if target == .refine {
            refine(text)
            return
        }
        if target == .discordAnnounce {
            discordAnnouncement(description: text)
            return
        }
        if target == .mcCommand {
            let edition = store.commandEdition
            runAI(title: "Minecraft-Befehl (\(edition))", original: "", target: .none, showDiff: false) { [client = self.client] partial in
                try await client.minecraftCommand(text, edition: edition, onPartial: partial)
            }
            lastResultIsCommand = true
            return
        }
        let context = store.useAppContext ? String((before + after).suffix(8000)) : nil
        runAI(title: "„\(text.prefix(30))“", original: "", target: .none, showDiff: false) { [client = self.client] partial in
            try await client.compose(prompt: text, context: context, onPartial: partial)
        }
    }

    /// Speichert eine in der Tastatur getippte Einstellung.
    private func saveSettingInput(_ target: ComposeTarget, _ text: String) {
        panel = .settings
        switch target {
        case .apiKey:
            let key = text.replacingOccurrences(of: " ", with: "")
            if key.isEmpty { store.deleteAPIKey() } else {
                store.apiKey = key
                store.apiKeyEnabled = true
                store.aiProvider = "apikey"
            }
            showToast(key.isEmpty ? "API-Schlüssel entfernt" : "API-Schlüssel gespeichert ✓")
        case .baseURL:
            store.baseURL = text.isEmpty ? "https://api.openai.com/v1" : text.replacingOccurrences(of: " ", with: "")
            showToast("API-Adresse gespeichert ✓")
        case .chatModel:
            guard !text.isEmpty else { return }
            let m = text.lowercased().replacingOccurrences(of: " ", with: "")
            if store.usesChatGPT {
                store.chatgptModel = m
            } else {
                store.chatModel = m
                store.fastModel = m
            }
            showToast("Modell: \(m)")
        case .personalContext:
            store.personalContext = text
            showToast("„Über mich“ gespeichert ✓")
        case .writingStyle:
            store.writingStyle = text
            showToast("Schreibstil gespeichert ✓")
        case .macroShortcut:
            guard !text.isEmpty else { return }
            pendingMacroShortcut = text.replacingOccurrences(of: " ", with: "")
            beginInput(.macroText)
        case .macroText:
            guard !text.isEmpty else { return }
            let sc = pendingMacroShortcut
            store.macros.append(Macro(shortcut: sc, title: sc.isEmpty ? String(text.prefix(20)) : sc, text: text))
            pendingMacroShortcut = ""
            showToast("Makro „\(sc)“ angelegt ✓")
        case .profileName:
            guard !text.isEmpty else { return }
            let p = ContextProfile(name: text, emoji: "✨", context: "")
            store.profiles.append(p)
            store.activeProfileID = p.id.uuidString
            beginInput(.profileContext(p.id))
        case .profileContext(let id):
            if let i = store.profiles.firstIndex(where: { $0.id == id }) {
                store.profiles[i].context = text
                showToast("Profil gespeichert ✓")
            }
        case .actionTitle:
            guard !text.isEmpty else { return }
            pendingMacroShortcut = text
            beginInput(.actionPrompt)
        case .actionPrompt:
            guard !text.isEmpty else { return }
            store.actions.append(AIAction(title: pendingMacroShortcut, symbol: "wand.and.stars", prompt: text))
            showToast("KI-Aktion „\(pendingMacroShortcut)“ angelegt ✓")
            pendingMacroShortcut = ""
        case .aiBehavior:
            store.aiBehavior = text
            showToast(text.isEmpty ? "Eigene KI-Regeln entfernt" : "KI-Regeln gespeichert ✓")
        case .memoryNote:
            guard !text.isEmpty else { return }
            store.memoryNotes.insert(String(text.prefix(300)), at: 0)
            showToast("Gemerkt 🧠")
        case .learnedProfile:
            store.learnedProfile = text
            showToast(text.isEmpty ? "Gelerntes Profil gelöscht" : "Profil gespeichert ✓")
        case .actionEdit(let id):
            guard !text.isEmpty, let i = store.actions.firstIndex(where: { $0.id == id }) else { return }
            store.actions[i].prompt = text
            showToast("Aktion „\(store.actions[i].title)“ geändert ✓")
        case .ai, .refine, .translate, .calc, .mcCommand, .discordAnnounce,
             .clipEdit, .clipNew, .clipRename, .clipFolderNew, .clipFolderRename, .clipSearch:
            break
        }
    }

    /// Fügt Text aus der Zwischenablage in die aktuelle Eingabe ein.
    func pasteIntoCompose() {
        guard hasFullAccess, let s = UIPasteboard.general.string else {
            showToast("Zwischenablage leer oder kein voller Zugriff.")
            return
        }
        composeText += s.trimmingCharacters(in: composeTarget == .apiKey ? .whitespacesAndNewlines : CharacterSet())
    }

    /// Ergebnis anwenden.
    func applyResult(replace: Bool) {
        let result = aiResult
        guard !result.isEmpty, !aiBusy else { return }
        feedback(.medium)
        let target = replaceTarget
        panel = .none
        Task { @MainActor [weak self] in
            guard let self, let proxy = self.proxy else { return }
            if replace {
                switch target {
                case .selection, .none:
                    proxy.insertText(result)
                case .all(let length):
                    self.rememberBeforeAIReplace(self.aiOriginal, newText: result)
                    await self.replaceAll(with: result, expectedLength: length)
                case .range(let b, let a):
                    if a > 0 {
                        let old = proxy.documentContextBeforeInput
                        let tail = String(self.after.prefix(a))
                        proxy.adjustTextPosition(byCharacterOffset: tail.utf16.count)
                        await self.waitForContextChange(from: old)
                    }
                    self.deleteChars(b + a)
                    proxy.insertText(result)
                }
            } else {
                var text = result
                if let last = self.before.last, !last.isWhitespace { text = (result.contains("\n") ? "\n\n" : " ") + text }
                proxy.insertText(text)
            }
            self.aiResult = ""
            self.afterCommit()
        }
    }

    /// Löscht den kompletten Text im Feld und setzt den neuen ein.
    /// Klappt das Löschen in Blöcken nicht, wird so lange „Löschen“ gedrückt, bis alles weg ist.
    @MainActor
    func replaceAll(with text: String, expectedLength: Int) async {
        await moveToEnd()
        let limit = max(expectedLength * 2 + 500, 20_000)
        var deleted = 0
        var stalls = 0
        var rounds = 0
        while deleted < limit, rounds < 6000 {
            rounds += 1
            let b = before
            if b.isEmpty {
                // iOS liefert manchmal kurz einen leeren Ausschnitt – nachprüfen
                try? await Task.sleep(nanoseconds: 40_000_000)
                if !before.isEmpty { continue }
                if !after.isEmpty { await moveToEnd(); continue }
                // Letzte Sicherheit: ein paar einzelne Löschschläge, falls doch noch Text da ist
                proxy?.deleteBackward()
                try? await Task.sleep(nanoseconds: 30_000_000)
                if before.isEmpty && after.isEmpty { break }
                continue
            }
            let n = b.count
            for _ in 0..<n { proxy?.deleteBackward() }
            deleted += n
            await waitForContextChange(from: b)
            if before == b {
                // Feld reagiert nicht auf Blocklöschen → Taste für Taste
                stalls += 1
                proxy?.deleteBackward()
                deleted += 1
                try? await Task.sleep(nanoseconds: 15_000_000)
                if stalls > 400 { break }
            } else {
                stalls = 0
            }
        }
        proxy?.insertText(text)
    }

    func copyResult() {
        guard hasFullAccess, !aiResult.isEmpty else { return }
        UIPasteboard.general.string = aiResult
        clips = store.addClip(aiResult)
        lastChangeCount = UIPasteboard.general.changeCount
        showToast("Kopiert ✓")
    }

    // MARK: - Zwischenablage

    private func startClipboardWatch() {
        guard hasFullAccess, store.clipboardEnabled else {
            clips = store.loadClips()
            return
        }
        checkClipboard()
        clipTimer?.invalidate()
        clipTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func checkClipboard() {
        let pb = UIPasteboard.general
        if pb.changeCount != lastChangeCount {
            lastChangeCount = pb.changeCount
            if pb.hasStrings, let s = pb.string {
                // Kopplungscode aus der App: automatisch übernehmen, nie im Verlauf speichern
                if ChatGPTAuth.isTransferCode(s) {
                    importChatGPTCode(s)
                    return
                }
                clips = store.addClip(s)
                clipboardDidChange(s)
                return
            }
        }
        if clips.isEmpty { clips = store.loadClips() }
    }

    func reloadClips() { clips = store.loadClips() }

    func pasteClip(_ item: ClipItem) {
        feedback()
        var text = item.text
        if let last = before.last, last.isLetter || last.isNumber { text = " " + text }
        proxy?.insertText(text)
        afterCommit()
    }

    func togglePin(_ item: ClipItem) {
        clips = store.updateClips { items in
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].pinned.toggle() }
        }
        feedback()
    }

    func deleteClip(_ item: ClipItem) {
        clips = store.updateClips { $0.removeAll { $0.id == item.id } }
        feedback(.medium)
        showToast("Eintrag gelöscht")
    }

    // MARK: - Ablage: Ordner, Bearbeiten, Suche

    /// "" = Alle, "★" = Angeheftet, "⏱" = nur Verlauf, sonst Ordnername
    @Published var clipFilter = ""
    @Published var clipQuery = ""

    var visibleClips: [ClipItem] {
        var list = clips
        switch clipFilter {
        case "": break
        case "★": list = list.filter(\.pinned)
        case "⏱": list = list.filter { $0.folder == nil }
        default: list = list.filter { $0.folder == clipFilter }
        }
        let q = clipQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.text.lowercased().contains(q) || ($0.title?.lowercased().contains(q) ?? false) }
        }
        return list
    }

    func copyClip(_ item: ClipItem) {
        guard hasFullAccess else { return }
        UIPasteboard.general.string = item.text
        lastChangeCount = UIPasteboard.general.changeCount
        clips = store.updateClips { items in
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].date = Date() }
        }
        feedback()
        showToast("Kopiert ✓")
    }

    func moveClip(_ item: ClipItem, to folder: String?) {
        clips = store.updateClips { items in
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].folder = folder }
        }
        feedback()
        showToast(folder.map { "In „\($0)“ verschoben ✓" } ?? "Aus dem Ordner genommen")
    }

    func setClipFilter(_ f: String) {
        clipFilter = f
        feedback()
    }

    func deleteFolder(_ name: String, keepItems: Bool) {
        store.clipFolders.removeAll { $0 == name }
        clips = store.updateClips { items in
            if keepItems {
                for i in items.indices where items[i].folder == name { items[i].folder = nil; items[i].pinned = true }
            } else {
                items.removeAll { $0.folder == name }
            }
        }
        if clipFilter == name { clipFilter = "" }
        feedback(.medium)
        showToast(keepItems ? "Ordner gelöscht – Einträge angeheftet" : "Ordner samt Inhalt gelöscht")
    }

    /// Löscht den Verlauf (Angeheftetes und Ordner bleiben).
    func clearHistory() {
        clips = store.updateClips { $0.removeAll { !$0.pinned && $0.folder == nil } }
        feedback(.medium)
        showToast("Verlauf geleert")
    }

    /// Text im Feld (oder Markierung) als neuen Eintrag speichern.
    func saveFieldAsClip() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let t = self.selected.isEmpty ? await self.readFullText() : self.selected
            guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self.showToast("Kein Text im Feld."); return }
            self.addClipEntry(t)
            self.showToast("Als Eintrag gespeichert ✓")
        }
    }

    private func addClipEntry(_ text: String) {
        let folder = (clipFilter.isEmpty || clipFilter == "★" || clipFilter == "⏱") ? nil : clipFilter
        let pinned = clipFilter == "★"
        clips = store.updateClips { items in
            items.insert(ClipItem(text: text, pinned: pinned, folder: folder), at: 0)
        }
    }

    private func saveClipInput(_ target: ComposeTarget, _ text: String) {
        panel = .clipboard
        onHeightChange?(totalHeight)
        switch target {
        case .clipEdit(let id):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showToast("Leerer Text – nichts geändert."); return }
            clips = store.updateClips { items in
                if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = text }
            }
            showToast("Eintrag gespeichert ✓")
        case .clipNew:
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            addClipEntry(text)
            showToast("Eintrag angelegt ✓")
        case .clipRename(let id):
            clips = store.updateClips { items in
                if let i = items.firstIndex(where: { $0.id == id }) { items[i].title = text.isEmpty ? nil : text }
            }
            showToast(text.isEmpty ? "Name entfernt" : "Umbenannt ✓")
        case .clipFolderNew:
            guard !text.isEmpty, !["★", "⏱"].contains(text) else { return }
            if !store.clipFolders.contains(text) { store.clipFolders.append(text) }
            clipFilter = text
            showToast("Ordner „\(text)“ angelegt ✓")
        case .clipFolderRename(let old):
            guard !text.isEmpty, text != old, !store.clipFolders.contains(text) else { return }
            if let i = store.clipFolders.firstIndex(of: old) { store.clipFolders[i] = text }
            clips = store.updateClips { items in
                for i in items.indices where items[i].folder == old { items[i].folder = text }
            }
            if clipFilter == old { clipFilter = text }
            showToast("Ordner umbenannt ✓")
        case .clipSearch:
            clipQuery = text
        default: break
        }
        reloadClips()
    }

    /// KI-Aktion direkt auf einen Ablage-Eintrag.
    func summarizeClip(_ item: ClipItem) {
        guard requireAI() else { return }
        let text = item.text
        let prompt = AIAction.defaults.first(where: { $0.category == .summary })?.prompt ?? "Fasse den Text zusammen."
        runAI(title: "Ablage zusammenfassen", original: text, target: .none, showDiff: false) { [client = self.client] partial in
            try await client.transform(text: text, instruction: prompt, onPartial: partial)
        }
    }

    func translateClipItem(_ item: ClipItem) {
        guard requireAI() else { return }
        let text = item.text, target = store.translateTarget
        runAI(title: "Übersetzung → \(Languages.flag(target)) \(target)", original: text, target: .none, showDiff: false) { [client = self.client] partial in
            let r = try await client.translate(text, to: target)
            partial(r)
            return r
        }
    }

    func pasteCurrent() {
        guard hasFullAccess, let s = UIPasteboard.general.string else {
            showToast("Zwischenablage leer oder kein voller Zugriff.")
            return
        }
        proxy?.insertText(s)
        afterCommit()
    }

    func copyAll() {
        guard hasFullAccess else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let t = self.selected.isEmpty ? await self.readFullText() : self.selected
            guard !t.isEmpty else { return }
            UIPasteboard.general.string = t
            self.clips = self.store.addClip(t)
            self.lastChangeCount = UIPasteboard.general.changeCount
            self.showToast("\(t.wordCount) Wörter kopiert ✓")
        }
    }

    func openApp(_ path: String = "") {
        if let url = URL(string: "tastatur://\(path)") { controller?.openURL(url) }
    }

    // MARK: - KI-Live-Korrektur

    private func scheduleLiveCheck() {
        liveCheckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runLiveCheck() }
        liveCheckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (store.aiTypoTurbo ? 0.8 : 1.4), execute: work)
    }

    private func runLiveCheck() {
        guard store.liveAICorrection, store.aiCorrectMode == "word", hasFullAccess, store.hasAPIKey, panel == .none, !composeMode, shouldAutocorrect else { return }
        let snapshot = before
        guard let last = snapshot.last, !(last.isLetter || last.isNumber) else { return }
        let region = String(snapshot.suffix(320))
        guard region.wordCount >= 2 else { return }
        liveCheckPending = false
        wordsSinceCheck = 0
        Task { [weak self] in
            guard let self else { return }
            guard let fixes = try? await self.client.typoCheck(text: region) else { return }
            await self.applyLiveFixes(fixes, snapshot: snapshot, region: region)
        }
    }

    @MainActor
    private func applyLiveFixes(_ fixes: [OpenAIClient.TypoFix], snapshot: String, region: String) async {
        guard before == snapshot, panel == .none, !composeMode else { return }
        let words = Set(region.split { !($0.isLetter || $0.isNumber || $0 == "-") }.map(String.init))
        let safe = fixes.filter { f in
            f.confidence >= (store.aiTypoTurbo ? 0.85 : 0.9) && !f.wrong.isEmpty && !f.right.isEmpty && f.wrong != f.right
                && !f.wrong.contains(" ") && !f.right.contains(" ")
                && words.contains(f.wrong)
                && !neverFix.contains(f.wrong.lowercased())
                && !engine.isLearned(f.wrong)
                && TextEngine.keyboardDistance(f.wrong.lowercased(), f.right.lowercased()) <= max(2, Double(f.wrong.count) / 3)
        }
        guard !safe.isEmpty else { return }
        var applied: [LiveFix.Pair] = []
        liveEditing = true
        defer { liveEditing = false }
        for f in safe.prefix(4) {
            guard let ok = await replaceWordBeforeCursor(f.wrong, with: f.right), ok else { break }
            applied.append(.init(wrong: f.wrong, right: f.right))
            engine.learn(word: f.right, previous: nil)
        }
        guard !applied.isEmpty else { return }
        store.incrementStat("corrections", by: applied.count)
        showLiveFix(LiveFix(pairs: applied))
    }

    /// Ersetzt das letzte Vorkommen eines ganzen Wortes vor dem Cursor. nil = abgebrochen.
    @MainActor
    private func replaceWordBeforeCursor(_ wrong: String, with right: String) async -> Bool? {
        let text = before
        guard let range = lastWholeWordRange(of: wrong, in: text) else { return false }
        let tail = String(text[range.upperBound...])
        let tailUTF16 = tail.utf16.count
        if tailUTF16 > 0 {
            proxy?.adjustTextPosition(byCharacterOffset: -tailUTF16)
            await waitForContextChange(from: text)
            guard before.hasSuffix(wrong) else {
                // zurück an die alte Stelle
                proxy?.adjustTextPosition(byCharacterOffset: tailUTF16)
                return nil
            }
        }
        deleteChars(wrong.count)
        proxy?.insertText(right)
        if tailUTF16 > 0 {
            proxy?.adjustTextPosition(byCharacterOffset: tailUTF16)
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return true
    }

    private func lastWholeWordRange(of word: String, in text: String) -> Range<String.Index>? {
        var searchEnd = text.endIndex
        while let r = text.range(of: word, options: .backwards, range: text.startIndex..<searchEnd) {
            let beforeOK = r.lowerBound == text.startIndex || !(text[text.index(before: r.lowerBound)].isLetter || text[text.index(before: r.lowerBound)].isNumber)
            let afterOK = r.upperBound == text.endIndex || !(text[r.upperBound].isLetter || text[r.upperBound].isNumber)
            if beforeOK && afterOK { return r }
            searchEnd = r.lowerBound
        }
        return nil
    }

    private func showLiveFix(_ fix: LiveFix) {
        liveFix = fix
        feedback(.light)
        liveFixHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.liveFix = nil }
        liveFixHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Macht die letzte Live-Korrektur rückgängig und merkt sich die Wörter.
    func undoLiveFix() {
        guard let fix = liveFix else { return }
        liveFix = nil
        feedback(.medium)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.liveEditing = true
            defer { self.liveEditing = false }
            for p in fix.pairs.reversed() {
                _ = await self.replaceWordBeforeCursor(p.right, with: p.wrong)
                self.neverFix.insert(p.wrong.lowercased())
                self.engine.learn(word: p.wrong, previous: nil, weight: 3)
            }
        }
    }

    // MARK: - Intelligente Trefferzonen

    /// Bewertet, ob ein Buchstabe das aktuelle Wort sinnvoll fortsetzt.
    /// Läuft direkt im Tipp-Moment: nur Speicher-Abfragen (Wortliste per Binärsuche, Cache) – nie das langsame
    /// Systemwörterbuch. Unbekanntes zählt als „passt“ (die Taste wird dann nie umgebogen) und wird in der
    /// nächsten Tipp-Pause nachgeschlagen.
    func isPlausibleContinuation(_ letter: String, word: String? = nil) -> Bool {
        let word = word ?? currentWord
        guard !word.isEmpty else { return true }
        return engine.isPlausiblePrefixFast(word + letter) ?? true
    }

    /// Strenge Variante für Nachbartasten: nur nachweislich passende Fortsetzungen.
    func isSurelyPlausibleContinuation(_ letter: String, word: String) -> Bool {
        guard !word.isEmpty else { return true }
        return engine.isPlausiblePrefixFast(word + letter) == true
    }

    var currentWordIsEmpty: Bool { currentWord.isEmpty }

    // MARK: - Lokales Formatieren (ohne KI, sofort)

    enum LocalFormat { case upper, lower, title, sentence, cleanSpaces }

    func localFormat(_ f: LocalFormat) {
        feedback(.medium)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.sourceMode == .clipboard {
                guard self.hasFullAccess, let s = UIPasteboard.general.string, !s.isEmpty else {
                    self.showToast("Die Zwischenablage ist leer.")
                    return
                }
                UIPasteboard.general.string = Self.format(s, f)
                self.lastChangeCount = UIPasteboard.general.changeCount
                self.showToast("Zwischenablage formatiert ✓")
                return
            }
            let sel = self.selected
            let text: String
            if !sel.isEmpty {
                text = sel
                self.replaceTarget = .selection
            } else {
                text = await self.readFullText()
                self.replaceTarget = .all(length: text.count)
            }
            guard !text.isEmpty else { self.showToast("Kein Text vorhanden."); return }
            let out = Self.format(text, f)
            guard out != text else { self.showToast("Schon passend formatiert ✓"); return }
            self.aiResult = out
            self.aiBusy = false
            self.applyResult(replace: true)
        }
    }

    static func format(_ text: String, _ f: LocalFormat) -> String {
        let de = Locale(identifier: "de_DE")
        switch f {
        case .upper: return text.uppercased(with: de)
        case .lower: return text.lowercased(with: de)
        case .title: return text.capitalized(with: de)
        case .sentence:
            var result = ""
            var capNext = true
            for ch in text.lowercased(with: de) {
                if capNext, ch.isLetter {
                    result += String(ch).uppercased(with: de)
                    capNext = false
                } else {
                    result.append(ch)
                }
                if ".!?\n".contains(ch) { capNext = true }
            }
            return result
        case .cleanSpaces:
            var t = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            t = t.replacingOccurrences(of: " +([.,!?;:])", with: "$1", options: .regularExpression)
            t = t.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            t = t.replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Übersetzungsmodus

    @Published var translatePreview = ""
    @Published var translating = false
    @Published var showLanguagePicker = false
    @Published var calcResult = ""
    private var translateTask: Task<Void, Never>?

    func startTranslateMode() {
        guard requireAI() else { return }
        beginInput(.translate)
    }

    private func composeDidChange() {
        switch composeTarget {
        case .translate: scheduleTranslation()
        case .calc:
            calcResult = Calculator.evaluate(composeText).map(Calculator.format) ?? ""
        default: break
        }
    }

    private func scheduleTranslation(immediate: Bool = false) {
        translateTask?.cancel()
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { translatePreview = ""; translating = false; return }
        translating = true
        let target = store.translateTarget
        translateTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: 550_000_000) }
            guard !Task.isCancelled, let self else { return }
            let result = try? await self.client.translate(text, to: target)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.translating = false
                if let result, self.composeText.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                    self.translatePreview = result
                }
            }
        }
    }

    func setTranslateTarget(_ lang: String) {
        store.translateTarget = lang
        showLanguagePicker = false
        feedback()
        if composeMode, composeTarget == .translate { scheduleTranslation(immediate: true) }
    }

    /// Fügt die Übersetzung ein und bleibt im Übersetzungsmodus (für Chats).
    private func insertTranslation() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { cancelCompose(); return }
        let target = store.translateTarget
        let ready = !translating && !translatePreview.isEmpty
        let insertNow: (String) -> Void = { [weak self] result in
            guard let self else { return }
            var t = result
            if let last = self.before.last, !last.isWhitespace { t = " " + t }
            self.proxy?.insertText(t)
            self.composeText = ""
            self.translatePreview = ""
            self.feedback(.medium)
            self.store.incrementStat("translations")
        }
        if ready { insertNow(translatePreview); return }
        translating = true
        translateTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            let result = try? await self.client.translate(text, to: target)
            await MainActor.run {
                self.translating = false
                if let result { insertNow(result) } else { self.showToast("Übersetzung fehlgeschlagen") }
            }
        }
    }

    /// Übersetzt den Text, der schon im Feld steht (oder die Markierung) – mit „Ersetzen“.
    /// `direct`: Ein-Klick – übersetzt und ersetzt den Text sofort, ohne Nachfrage.
    func translateField(to lang: String, direct: Bool = false) {
        guard requireAI() else { return }
        store.translateTarget = lang
        if direct { store.incrementStat("translations") }
        let fallback = lang == "Deutsch" ? "Englische" : "Deutsche"
        let instruction = "Übersetze den Text natürlich und idiomatisch ins \(lang) – so, wie ein Muttersprachler schreiben würde. Behalte Ton, Emojis, Zeilenumbrüche, Namen, Zahlen und Links bei. Ist der Text bereits auf \(lang), übersetze ihn stattdessen ins \(fallback). Gib nur die Übersetzung zurück."
        startAI(title: "Übersetzung → \(Languages.flag(lang)) \(lang)", showDiff: false, autoApply: direct) { [weak self] in
            guard let self else { return nil }
            return await self.gatherSource(mode: .auto)
        } work: { [client = self.client] text, _, partial in
            try await client.transform(text: text, instruction: instruction, appContext: nil, onPartial: partial)
        }
    }

    /// Kopierten Text übersetzen und als Ergebnis anzeigen.
    func translateClipboard() {
        guard requireAI() else { return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            showToast("Die Zwischenablage ist leer.")
            return
        }
        let target = store.translateTarget
        runAI(title: "Übersetzung → \(Languages.flag(target)) \(target)", original: text, target: .none, showDiff: false) { [client = self.client] partial in
            let r = try await client.translate(text, to: target)
            partial(r)
            return r
        }
    }

    // MARK: - Befehle (Minecraft & Co.)

    @Published var lastResultIsCommand = false

    /// Fügt einen Befehl ein – ersetzt eine angefangene Befehlszeile.
    func insertCommand(_ cmd: String) {
        feedback(.medium)
        if composeMode { composeText += cmd; return }
        if isCommandLine { deleteChars(currentLine.count) }
        else if let last = before.last, !last.isWhitespace { proxy?.insertText(" ") }
        proxy?.insertText(cmd)
        undoCorrection = nil
        if panel == .commands { panel = .none }
        scheduleRefresh()
    }

    func runCommandItem(_ c: SavedCommand) {
        // Mehrzeilige KI-Ergebnisse: nur die erste Zeile einfügen
        insertCommand(c.command)
    }

    func saveCommand(_ text: String, title: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { showToast("Kein Text zum Speichern."); return }
        let name = title ?? String(t.replacingOccurrences(of: "/", with: "").prefix(28))
        store.commands.insert(SavedCommand(title: name, command: t, group: store.commands.first?.group ?? "Minecraft"), at: 0)
        feedback(.medium)
        showToast("Befehl gespeichert ✓")
    }

    func saveFieldAsCommand() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sel = self.selected
            let text = sel.isEmpty ? self.currentLine : sel
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                let full = await self.readFullText()
                self.saveCommand(full)
            } else {
                self.saveCommand(text)
            }
        }
    }

    func saveClipboardAsCommand() {
        guard hasFullAccess, let s = UIPasteboard.general.string else {
            showToast("Zwischenablage leer oder kein voller Zugriff.")
            return
        }
        saveCommand(s)
    }

    func deleteCommand(_ c: SavedCommand) {
        store.commands.removeAll { $0.id == c.id }
        showToast("Befehl gelöscht")
    }

    func toggleCommandFavorite(_ c: SavedCommand) {
        if let i = store.commands.firstIndex(where: { $0.id == c.id }) { store.commands[i].favorite.toggle() }
        feedback()
    }

    func startCommandAI() {
        guard requireAI() else { return }
        beginInput(.mcCommand)
    }

    /// Speichert das aktuelle KI-Ergebnis (jede Zeile ein Befehl).
    func saveResultAsCommands() {
        let lines = aiResult.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for l in lines.reversed() { store.commands.insert(SavedCommand(title: String(l.replacingOccurrences(of: "/", with: "").prefix(28)), command: l), at: 0) }
        feedback(.medium)
        showToast(lines.count == 1 ? "Befehl gespeichert ✓" : "\(lines.count) Befehle gespeichert ✓")
    }

    // MARK: - Rechner

    func startCalculator() { beginInput(.calc) }

    private func insertCalcResult() {
        let result = calcResult
        composeMode = false
        composeTarget = .ai
        composeText = ""
        updateReturnKey()
        onHeightChange?(totalHeight)
        layer = .letters
        guard !result.isEmpty else { return }
        var t = result
        if let last = before.last, !last.isWhitespace { t = " " + t }
        proxy?.insertText(t)
        feedback(.medium)
        afterCommit()
    }

    // MARK: - KI-Schlusskorrektur („Am Ende“)

    private var endCheckWork: DispatchWorkItem?
    private var endCheckTask: Task<Void, Never>?
    fileprivate(set) var lastEndChecked = ""

    /// Nach jeder Eingabe neu starten: Erst wenn du kurz pausierst, liest die KI den ganzen Text.
    private func scheduleEndCheck() {
        endCheckWork?.cancel()
        endCheckTask?.cancel()
        guard store.aiCorrectMode == "end", hasFullAccess, store.hasAPIKey, panel == .none, !composeMode else { return }
        let work = DispatchWorkItem { [weak self] in self?.runEndCheck(manual: false) }
        endCheckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// Korrigiert den ganzen Text direkt im Feld (Paare ersetzen, Cursor bleibt, mit Rückgängig).
    func runEndCheck(manual: Bool) {
        if manual {
            guard requireAI() else { return }
            if panel == .tools { panel = .none; onHeightChange?(totalHeight) }
        } else {
            guard store.aiCorrectMode == "end", hasFullAccess, store.hasAPIKey, panel == .none, !composeMode,
                  shouldAutocorrect, !isCommandLine, !liveEditing else { return }
        }
        let snapshotBefore = before, snapshotAfter = after
        // Cursor mitten in einem Wort (Text links und rechts direkt dran) → nicht stören
        if !manual, let l = snapshotBefore.last, let r = snapshotAfter.first, l.isLetter, r.isLetter { return }
        let text = String(snapshotBefore.suffix(2500)) + (manual ? String(snapshotAfter.prefix(1500)) : "")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).wordCount >= (manual ? 1 : 2) else {
            if manual { showToast("Kein Text zum Korrigieren.") }
            return
        }
        if !manual, text == lastEndChecked { return }
        lastEndChecked = text
        let afterContext = manual ? nil : String(snapshotAfter.prefix(300))
        bar.checking = true
        if manual { showToast("KI liest deinen Text …") }
        endCheckTask = Task { [weak self] in
            guard let self else { return }
            let fixes = (try? await self.client.finalCheck(text: text, after: afterContext)) ?? []
            await MainActor.run {
                self.bar.checking = false
                guard !Task.isCancelled else { return }
                self.offerEndFixes(fixes, snapshot: snapshotBefore, text: text, manual: manual)
            }
        }
    }

    /// Ergebnis der Schlussprüfung als Vorschlag anbieten – ein Tipp übernimmt alles.
    @MainActor
    private func offerEndFixes(_ fixes: [OpenAIClient.TypoFix], snapshot: String, text: String, manual: Bool) {
        guard before == snapshot, !composeMode else { return }
        let current = before + after
        let list = fixes.filter { f in
            !neverFix.contains(f.wrong.lowercased()) && f.wrong.count <= 80 && f.right.count <= 120 && current.contains(f.wrong)
        }.map { OpenAIClient.CheckIssue(original: $0.wrong, suggestion: $0.right, kind: "Korrektur", reason: "") }
        checkedText = text
        bar.issues = list
        bar.offerFixes = !list.isEmpty
        if list.isEmpty {
            if manual { showToast("Alles sauber ✓") }
        } else if store.haptics, hasFullAccess {
            selection.selectionChanged()
        }
    }

    // MARK: - Ziel-App

    /// Setzt die erkannte App (falls iOS sie verrät).
    func setHostApp(bundleID: String?) {
        let id = bundleID.flatMap { AppProfiles.detect(bundleID: $0)?.id } ?? ""
        if store.detectedApp != id { store.detectedApp = id }
    }

    func setAppProfile(_ id: String) {
        store.appProfile = id
        feedback()
        let name = store.activeApp.map { "\($0.emoji) \($0.name)" } ?? (id == "auto" ? "Automatisch" : "Keine App")
        showToast("Schreibe für: \(name)")
    }

    // MARK: - Kontextprüfung

    private var contextCheckWork: DispatchWorkItem?
    private var contextCheckTask: Task<Void, Never>?
    private var wordsSinceContextCheck = 0
    private var lastContextChecked = ""
    private var dismissedIssues = Set<String>()
    /// Text, der zuletzt geprüft wurde (für die Markierungen im Prüf-Panel).
    @Published var checkedText = ""

    private var contextCheckReady: Bool {
        store.contextCheck != "off" && store.aiCorrectMode == "word" && hasFullAccess && store.hasAPIKey && panel == .none && !composeMode && shouldAutocorrect && !isCommandLine
    }

    /// Nach jedem Wort: kurz warten und dann im Hintergrund prüfen.
    private func scheduleContextCheck(sentenceEnd: Bool) {
        guard contextCheckReady else { return }
        wordsSinceContextCheck += 1
        let intense = store.contextCheck == "intense"
        let needed = intense ? 3 : 6
        guard sentenceEnd || wordsSinceContextCheck >= needed else { return }
        contextCheckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runContextCheck(manual: false) }
        contextCheckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (intense ? 1.5 : 2.6), execute: work)
    }

    /// Prüft den aktuellen Abschnitt. `manual`: über den Knopf „Prüfen“ (gründlich, öffnet das Panel).
    func runContextCheck(manual: Bool) {
        if manual {
            guard requireAI() else { return }
        } else {
            guard contextCheckReady else { return }
        }
        let b = before, a = after
        let text = String(b.suffix(manual ? 2500 : 700)) + String(a.prefix(manual ? 800 : 200))
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).wordCount >= (manual ? 1 : 3) else {
            if manual { showToast("Noch kein Text zum Prüfen.") }
            return
        }
        if !manual, text == lastContextChecked { return }
        lastContextChecked = text
        wordsSinceContextCheck = 0
        let surrounding = String(b.dropLast(min(b.count, 700)).suffix(2500))
        let intense = manual || store.contextCheck == "intense"
        contextCheckTask?.cancel()
        bar.checking = true
        if manual {
            checkedText = text
            bar.issues = []
            panel = .check
        }
        contextCheckTask = Task { [weak self] in
            guard let self else { return }
            let result: [OpenAIClient.CheckIssue]
            do {
                result = try await self.client.contextCheck(text: text, surrounding: surrounding.isEmpty ? nil : surrounding, intense: intense)
            } catch {
                await MainActor.run {
                    self.bar.checking = false
                    if manual { self.showToast(error.localizedDescription) }
                }
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.bar.checking = false
                let current = self.before + self.after
                let fresh = result.filter { !self.dismissedIssues.contains($0.original + "→" + $0.suggestion) && current.contains($0.original) }
                self.checkedText = text
                let hadIssues = !self.bar.issues.isEmpty
                self.bar.issues = fresh
                if !fresh.isEmpty, !hadIssues, !manual, self.store.haptics, self.hasFullAccess { self.selection.selectionChanged() }
                if manual && fresh.isEmpty { self.showToast("Alles gut – nichts gefunden ✓") }
            }
        }
    }

    /// Entfernt Hinweise, deren Textstelle nicht mehr existiert.
    private func pruneIssues() {
        guard !bar.issues.isEmpty else { return }
        let current = before + after
        let kept = bar.issues.filter { current.contains($0.original) }
        if kept.count != bar.issues.count { bar.issues = kept }
    }

    func applyIssue(_ issue: OpenAIClient.CheckIssue) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.liveEditing = true
            let ok = await self.replacePhrase(issue.original, with: issue.suggestion)
            self.liveEditing = false
            self.bar.issues.removeAll { $0.id == issue.id }
            if ok {
                self.feedback(.medium)
                self.store.incrementStat("corrections")
                for w in issue.suggestion.split(separator: " ") where w.count > 2 { self.engine.learn(word: String(w), previous: nil) }
            } else {
                self.showToast("Stelle nicht mehr gefunden.")
            }
            if self.bar.issues.isEmpty, self.panel == .check { self.panel = .none }
        }
    }

    func applyAllIssues() {
        let list = bar.issues
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.liveEditing = true
            var count = 0
            for issue in list {
                if await self.replacePhrase(issue.original, with: issue.suggestion) { count += 1 }
            }
            self.liveEditing = false
            self.bar.issues = []
            self.bar.offerFixes = false
            self.lastEndChecked = String(self.before.suffix(2500))
            self.feedback(.medium)
            self.showToast("\(count) Stelle\(count == 1 ? "" : "n") korrigiert ✓")
            if self.panel == .check { self.panel = .none }
        }
    }

    func dismissIssue(_ issue: OpenAIClient.CheckIssue) {
        dismissedIssues.insert(issue.original + "→" + issue.suggestion)
        bar.issues.removeAll { $0.id == issue.id }
        feedback()
        if bar.issues.isEmpty, panel == .check { panel = .none }
    }

    /// Ersetzt eine Textstelle vor oder hinter dem Cursor, ohne die Cursorposition zu verlieren.
    @MainActor
    private func replacePhrase(_ wrong: String, with right: String) async -> Bool {
        let b = before
        if let r = b.range(of: wrong, options: .backwards) {
            let tailUTF16 = b[r.upperBound...].utf16.count
            if tailUTF16 > 0 {
                proxy?.adjustTextPosition(byCharacterOffset: -tailUTF16)
                await waitForContextChange(from: b)
                guard before.hasSuffix(wrong) else {
                    proxy?.adjustTextPosition(byCharacterOffset: tailUTF16)
                    return false
                }
            }
            deleteChars(wrong.count)
            proxy?.insertText(right)
            if tailUTF16 > 0 {
                proxy?.adjustTextPosition(byCharacterOffset: tailUTF16)
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return true
        }
        let a = after
        if let r = a.range(of: wrong) {
            let headUTF16 = a[..<r.upperBound].utf16.count
            let old = proxy?.documentContextBeforeInput
            proxy?.adjustTextPosition(byCharacterOffset: headUTF16)
            await waitForContextChange(from: old)
            guard before.hasSuffix(wrong) else {
                proxy?.adjustTextPosition(byCharacterOffset: -headUTF16)
                return false
            }
            deleteChars(wrong.count)
            proxy?.insertText(right)
            let back = headUTF16 - wrong.utf16.count + right.utf16.count
            proxy?.adjustTextPosition(byCharacterOffset: -back)
            try? await Task.sleep(nanoseconds: 25_000_000)
            return true
        }
        return false
    }

    // MARK: - Kennenlernen (gelerntes Profil)

    private static var samplesURL: URL { SharedStore.containerURL.appendingPathComponent("writing-samples.json") }
    private var learning = false

    /// Merkt sich fertige Sätze (lokal) und lässt die KI daraus ab und zu ein Profil lernen.
    private func collectSample() {
        guard store.learnProfile, shouldAutocorrect, !isCommandLine, !composeMode else { return }
        var b = before
        while let l = b.last, l == " " || l == "\n" { b.removeLast() }
        guard let last = b.last, ".!?".contains(last) || before.last == "\n" else { return }
        let body = b.dropLast()
        let start = body.lastIndex(where: { ".!?\n".contains($0) }).map { body.index(after: $0) } ?? body.startIndex
        let sentence = String(b[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentence.wordCount >= 4, sentence.count < 600 else { return }
        let url = Self.samplesURL
        let defaults = store.defaults
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var list = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            if list.last == sentence { return }
            list.append(sentence)
            if list.count > 150 { list.removeFirst(list.count - 150) }
            if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
            let newCount = defaults.integer(forKey: "learn.newSamples") + 1
            defaults.set(newCount, forKey: "learn.newSamples")
            let lastRun = defaults.double(forKey: "learn.lastRun")
            let interval: Double = SharedStore.shared.usesChatGPT ? 3600 : 6 * 3600
            if newCount >= 20, Date().timeIntervalSince1970 - lastRun > interval {
                DispatchQueue.main.async { self?.learnNow(silent: true) }
            }
        }
    }

    /// Lässt die KI jetzt aus den gesammelten Texten lernen.
    func learnNow(silent: Bool = false) {
        guard !learning else { return }
        if silent {
            guard store.learnProfile, hasFullAccess, store.hasAPIKey else { return }
        } else {
            guard requireAI() else { return }
        }
        let list = (try? Data(contentsOf: Self.samplesURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        guard list.count >= (silent ? 10 : 3) else {
            if !silent { showToast("Schreib noch ein bisschen – dann lernt die KI dich kennen.") }
            return
        }
        learning = true
        if !silent { showToast("KI lernt dich kennen …") }
        let existing = store.learnedProfile
        Task { [weak self] in
            guard let self else { return }
            let result = try? await self.client.learnProfile(samples: list, existing: existing)
            await MainActor.run {
                self.learning = false
                self.store.defaults.set(Date().timeIntervalSince1970, forKey: "learn.lastRun")
                self.store.defaults.set(0, forKey: "learn.newSamples")
                if let result, !result.isEmpty {
                    self.store.learnedProfile = String(result.prefix(2500))
                    self.learnMemories(from: list)
                    if !silent { self.showToast("Profil aktualisiert ✓") }
                } else if !silent {
                    self.showToast("Lernen fehlgeschlagen – später nochmal.")
                }
            }
        }
    }

    /// Generalüberblick: Die KI merkt sich wichtige, wiederkehrende Dinge (Projekte, Pläne, Vorlieben).
    func learnMemories(from samples: [String]) {
        guard store.memoryEnabled, hasFullAccess, store.hasAPIKey else { return }
        let existing = store.memoryNotes
        Task { [weak self] in
            guard let self else { return }
            let notes = (try? await self.client.extractMemories(samples: samples, existing: existing)) ?? []
            await MainActor.run {
                guard !notes.isEmpty else { return }
                var merged = self.store.memoryNotes
                for n in notes where !merged.contains(where: { $0.lowercased() == n.lowercased() }) { merged.append(n) }
                self.store.memoryNotes = Array(merged.suffix(60))
            }
        }
    }

    func forgetProfile() {
        store.learnedProfile = ""
        try? FileManager.default.removeItem(at: Self.samplesURL)
        store.defaults.set(0, forKey: "learn.newSamples")
        showToast("Gelerntes vergessen ✓")
    }

    // MARK: - Discord

    /// Umschließt die Markierung (oder setzt die Zeichen und den Cursor dazwischen).
    func discordWrap(_ left: String, _ right: String) {
        feedback()
        let sel = selected
        if !sel.isEmpty {
            proxy?.insertText(left + sel + right)
        } else {
            proxy?.insertText(left + right)
            proxy?.adjustTextPosition(byCharacterOffset: -right.utf16.count)
            panel = .none
        }
        scheduleRefresh()
    }

    /// Setzt ein Zeilen-Präfix (z. B. „# “) an den Anfang einer neuen Zeile.
    func discordLine(_ prefix: String) {
        feedback()
        if let last = before.last, last != "\n" { proxy?.insertText("\n") }
        let sel = selected
        proxy?.insertText(prefix + sel)
        if sel.isEmpty { panel = .none }
        scheduleRefresh()
    }

    func discordInsert(_ text: String, copy: Bool = false) {
        feedback()
        if copy, hasFullAccess {
            UIPasteboard.general.string = text
            lastChangeCount = UIPasteboard.general.changeCount
            showToast("Kopiert ✓")
            return
        }
        if let last = before.last, !last.isWhitespace, !text.hasPrefix("\n") { proxy?.insertText(" ") }
        proxy?.insertText(text)
        scheduleRefresh()
    }

    var discordLanguageLabel: String {
        switch store.discordLanguages {
        case "en": return "🇬🇧"
        case "both": return "🇩🇪+🇬🇧"
        default: return "🇩🇪"
        }
    }

    /// Ankündigung aus einer Beschreibung (Eingabeleiste).
    func discordAnnouncement(description: String) {
        let langs = store.discordLanguages, mention = store.discordMention
        runAI(title: "Discord-Ankündigung \(discordLanguageLabel)", original: "", target: .none, showDiff: false) { [client = self.client] partial in
            try await client.discordAnnouncement(source: description, isDescription: true, languages: langs, mention: mention, onPartial: partial)
        }
        aiKeepMarkdown = true
        aiAutoCopy = store.discordAutoCopy
    }

    /// Ankündigung aus dem Text im Feld (oder der Markierung) – Ergebnis zum Ersetzen/Kopieren.
    func discordAnnouncementFromField() {
        guard requireAI() else { return }
        let langs = store.discordLanguages, mention = store.discordMention
        startAI(title: "Discord-Ankündigung \(discordLanguageLabel)", showDiff: false) { [weak self] in
            guard let self else { return nil }
            return await self.gatherSource(mode: .auto)
        } work: { [client = self.client] text, _, partial in
            try await client.discordAnnouncement(source: text, isDescription: false, languages: langs, mention: mention, onPartial: partial)
        }
        aiKeepMarkdown = true
        aiAutoCopy = store.discordAutoCopy
    }

    /// Text im Feld mit Discord-Markdown formatieren.
    func discordFormatField() {
        guard requireAI() else { return }
        let instruction = "Formatiere den Text als schön strukturierte Discord-Nachricht mit Discord-Markdown (Überschriften wo sinnvoll, **fett** für Wichtiges, Listen, passende Emojis). Inhalt und Sprache beibehalten, nichts erfinden.\n\n" + AppProfiles.discordRules
        startAI(title: "Discord-Format", showDiff: false) { [weak self] in
            guard let self else { return nil }
            return await self.gatherSource(mode: .auto)
        } work: { [client = self.client] text, _, partial in
            let r = try await client.chat(messages: [
                ChatMessage(role: "system", content: "Du formatierst Texte für Discord. Gib NUR die fertige Nachricht zurück, ohne Codeblock drumherum."),
                ChatMessage(role: "user", content: "Aufgabe: \(instruction)\n\n<text>\n\(text)\n</text>"),
            ], onPartial: partial)
            return OpenAIClient.cleanup(r, keepMarkdown: true)
        }
        aiKeepMarkdown = true
        aiAutoCopy = store.discordAutoCopy
    }

    // MARK: - Power-Tippen

    struct KeyGeometry {
        var centers: [Character: CGPoint]
        var keyWidth: CGFloat
        var rowHeight: CGFloat
    }
    var keyGeometry: KeyGeometry?
    /// Punkt der zuletzt getippten Taste (vom Tastenfeld gesetzt).
    var pendingTapPoint: CGPoint?
    /// Fingerpositionen der Buchstaben im aktuellen Wort.
    private var wordTaps: [CGPoint] = []
    /// Gelernte persönliche Abweichung je Taste (wo du eine Taste wirklich triffst).
    private(set) lazy var touchModel: [Character: CGPoint] = loadTouchModel()
    private var touchModelUpdates = 0

    private var wordTapsValid: Bool { wordTaps.allSatisfy { $0.x > -1000 } }

    var currentWordIsComplete: Bool {
        let w = currentWord
        guard w.count >= 2 else { return false }
        return engine.isKnown(w) || SwipeDecoder.shared.rank(of: w) != nil
    }

    private struct TapInputs {
        var lower: String
        var taps: [CGPoint]
        var geo: KeyGeometry
        var learned: [String: Int]
        var context: [String: Int]
    }
    /// Im Hintergrund berechnete Tipp-Korrektur für das aktuelle Wort.
    private var tapFix: (word: String, result: String?)?

    /// Schnelle Vorprüfung (ohne Wörterbuch-Abfragen): Kommt eine Tipp-Korrektur überhaupt infrage?
    private func tapInputs(for word: String) -> TapInputs? {
        guard store.tapCorrection, let geo = keyGeometry, wordTaps.count == word.count, word.count >= 2, wordTapsValid,
              word.allSatisfy({ $0.isLetter }), !(word.count > 1 && word == word.uppercased()),
              SwipeDecoder.shared.ready else { return nil }
        let lower = word.lowercased()
        guard SwipeDecoder.shared.rank(of: lower) == nil, !engine.isKnown(word) else { return nil }
        return TapInputs(lower: lower, taps: wordTaps, geo: geo, learned: engine.swipeLearned(),
                         context: previousWord.map { engine.bigramNext($0) } ?? [:])
    }

    private static func computeTap(_ i: TapInputs) -> String? {
        guard let r = SwipeDecoder.shared.tapCorrect(typed: i.lower, taps: i.taps, centers: i.geo.centers, kw: i.geo.keyWidth,
                                                      learned: i.learned, context: i.context),
              r.word != i.lower, r.spatial <= 2.2 + Double(i.lower.count) * 0.15 else { return nil }
        return r.word
    }

    private func casedTapResult(_ typed: String, _ result: String) -> String {
        typed.first?.isUppercase == true ? engine.casedLike(typed, result) : engine.swipeCased(result)
    }

    /// Berechnet die Tipp-Korrektur für das aktuelle Wort schon in der Pause vor (Ergebnis in `tapFix`).
    private func precomputeTapFix(for word: String) {
        guard !word.isEmpty, store.autocorrect, tapFix?.word != word || tapFixTaps != wordTaps else { return }
        guard let inputs = tapInputs(for: word), !engine.spelledCorrectly(word) else { tapFix = nil; return }
        tapFix = (word, Self.computeTap(inputs))
        tapFixTaps = wordTaps
    }
    private var tapFixTaps: [CGPoint] = []

    /// Korrektur beim Abschließen eines Wortes: zuerst über die Fingerpositionen, sonst klassisch.
    func smartCorrection(for word: String) -> String? {
        if let inputs = tapInputs(for: word), !engine.spelledCorrectly(word) {
            let result: String?
            if let f = tapFix, f.word == word, tapFixTaps == wordTaps { result = f.result } else { result = Self.computeTap(inputs) }
            if let result { return casedTapResult(word, result) }
        }
        return engine.correction(for: word)
    }

    /// Merkt sich, wo du die Tasten eines richtig getippten Wortes getroffen hast.
    private func learnTouches(for word: String) {
        guard store.adaptiveTouch, let geo = keyGeometry, wordTaps.count == word.count, word.count >= 3, wordTapsValid,
              engine.isKnown(word) || SwipeDecoder.shared.rank(of: word.lowercased()) != nil else { return }
        let kw = geo.keyWidth, kh = geo.rowHeight
        for (ch, tap) in zip(word.lowercased(), wordTaps) {
            guard let c = geo.centers[SwipeDecoder.keyChar(ch)] else { continue }
            let dx = tap.x - c.x, dy = tap.y - c.y
            guard abs(dx) < kw * 0.6, abs(dy) < kh * 0.6 else { continue }
            let old = touchModel[ch] ?? .zero
            let nx = old.x * 0.93 + dx * 0.07, ny = old.y * 0.93 + dy * 0.07
            touchModel[ch] = CGPoint(x: max(-kw * 0.3, min(kw * 0.3, nx)), y: max(-kh * 0.3, min(kh * 0.3, ny)))
        }
        touchModelUpdates += 1
        if touchModelUpdates % 15 == 0 { saveTouchModel() }
    }

    private func loadTouchModel() -> [Character: CGPoint] {
        guard let raw = store.defaults.dictionary(forKey: "touchModel") as? [String: [Double]] else { return [:] }
        var out: [Character: CGPoint] = [:]
        for (k, v) in raw where v.count == 2 { if let ch = k.first { out[ch] = CGPoint(x: v[0], y: v[1]) } }
        return out
    }

    private func saveTouchModel() {
        var raw: [String: [Double]] = [:]
        for (k, v) in touchModel { raw[String(k)] = [Double(v.x), Double(v.y)] }
        store.defaults.set(raw, forKey: "touchModel")
    }

    func resetTouchModel() {
        touchModel = [:]
        store.defaults.removeObject(forKey: "touchModel")
        showToast("Trefferzonen zurückgesetzt")
    }

    // MARK: - Gesten-Tippen (Wischen)

    struct SwipeInfo {
        var word: String
        var alternatives: [String]
        var keys: String
        var addedSpace: Bool
    }
    var lastSwipe: SwipeInfo?
    private var protectedSwipeWord: String?
    private var swipeAITask: Task<Void, Never>?

    /// Kontextbonus für Kandidaten: Wörter, die du oft nach dem vorherigen Wort schreibst.
    func swipeContext() -> (String) -> Double {
        let prev = before.split { !($0.isLetter || $0.isNumber) }.last.map { String($0).lowercased() } ?? ""
        let engine = self.engine
        guard !prev.isEmpty else { return { _ in 0 } }
        return { w in Double(min(engine.bigramCount(prev, w), 8)) * 0.07 }
    }

    private func swipeCase(_ word: String, caps: ShiftState) -> String {
        let w = engine.swipeCased(word)
        switch caps {
        case .caps: return w.uppercased()
        case .on: return w.prefix(1).uppercased() + w.dropFirst()
        case .off: return w
        }
    }

    /// Fügt das erkannte Wort ein – mit automatischem Leerzeichen davor.
    func commitSwipe(_ words: [String], keys: String) {
        let caps = layer == .letters ? shift : .off
        if shift == .on { shift = .off }
        guard let first = words.first else {
            if store.swipeAI, hasFullAccess, store.hasAPIKey, keys.count >= 2 {
                swipeAskAI(keys: keys, candidates: [], replacing: nil, caps: caps)
            } else {
                feedback()
                showToast("Wort nicht erkannt – nochmal wischen oder tippen")
            }
            return
        }
        let word = swipeCase(first, caps: caps)
        let alternatives = words.map { swipeCase($0, caps: caps) }
        insertSwipeWord(word, alternatives: alternatives, keys: keys)
        if store.swipeAI, hasFullAccess, store.hasAPIKey, words.count > 1 {
            swipeAskAI(keys: keys, candidates: Array(words.prefix(6)), replacing: word, caps: caps)
        }
    }

    private func insertSwipeWord(_ word: String, alternatives: [String], keys: String) {
        feedback()
        if composeMode {
            if let last = composeText.last, !last.isWhitespace { composeText += " " }
            composeText += word
            return
        }
        var addSpace = false
        if let last = before.last, !last.isWhitespace, !"([{„“\"'/@#-".contains(last) { addSpace = true }
        proxy?.insertText((addSpace ? " " : "") + word)
        undoCorrection = nil
        lastSwipe = SwipeInfo(word: word, alternatives: alternatives, keys: keys, addedSpace: addSpace)
        protectedSwipeWord = word
        store.incrementStat("swipes")
        updateAutoShift()
        scheduleRefresh()
    }

    /// KI prüft das gewischte Wort im Satzzusammenhang und korrigiert es bei Bedarf.
    private func swipeAskAI(keys: String, candidates: [String], replacing old: String?, caps: ShiftState) {
        swipeAITask?.cancel()
        let context = String((old.map { String(before.dropLast($0.count)) } ?? before).suffix(400))
        if old == nil { bar.thinking = true }
        swipeAITask = Task { [weak self] in
            guard let self else { return }
            let answer = try? await self.client.swipeWord(context: context, candidates: candidates, keys: keys)
            await MainActor.run {
                self.bar.thinking = false
                guard !Task.isCancelled, let answer, !answer.isEmpty else {
                    if old == nil { self.showToast("Wort nicht erkannt – nochmal wischen") }
                    return
                }
                let new = self.swipeCase(answer.lowercased(), caps: caps)
                guard let old else {
                    self.insertSwipeWord(new, alternatives: [new], keys: keys)
                    return
                }
                guard new.lowercased() != old.lowercased() else { return }
                Task { @MainActor in
                    if var sw = self.lastSwipe, sw.word == old, self.currentWord == old {
                        self.deleteChars(old.count)
                        self.proxy?.insertText(new)
                        sw.word = new
                        if !sw.alternatives.contains(old) { sw.alternatives.append(old) }
                        sw.alternatives.removeAll { $0 == new }
                        sw.alternatives.insert(old, at: 0)
                        self.lastSwipe = sw
                        self.protectedSwipeWord = new
                        self.scheduleRefresh()
                    } else {
                        self.liveEditing = true
                        let ok = await self.replaceWordBeforeCursor(old, with: new)
                        self.liveEditing = false
                        guard ok == true else { return }
                    }
                    self.showLiveFix(LiveFix(pairs: [.init(wrong: old, right: new)]))
                }
            }
        }
    }

    // MARK: - Werkzeuge der Schnellleiste

    func runTool(_ id: String) {
        switch id {
        case "ai": toggle(.ai)
        case "translate": toggle(.translate)
        case "translateLive": startTranslateMode()
        case "translateClip": translateClipboard()
        case "write": startCompose()
        case "commands": toggle(.commands)
        case "discord": toggle(.discord)
        case "check": runContextCheck(manual: true)
        case "fix": runEndCheck(manual: true)
        case "clipboard": toggle(.clipboard)
        case "stickers": toggle(.stickers)
        case "emoji": toggle(.emoji)
        case "macros": toggle(.macros)
        case "cursor": toggle(.cursor)
        case "calc": startCalculator()
        case "paste": pasteCurrent()
        case "copyAll": copyAll()
        case "theme": randomTheme()
        case "settings": settingsPage = .main; toggle(.settings)
        case "hide": controller?.dismissKeyboard()
        case "undo": undoLast()
        case "reply": suggestReplies(manual: true)
        case "history": toggle(.history)
        case "location": insertLocation()
        case "remember": rememberCurrent()
        case "event": eventFromText()
        default:
            if let lang = ToolItem.translateLanguage(id) { translateField(to: lang, direct: true) }
        }
    }

    // MARK: - Cursor-Steuerung

    enum CursorAction { case left, right, wordLeft, wordRight, start, end, deleteWord, selectHint }

    func cursorAction(_ a: CursorAction) {
        feedback()
        switch a {
        case .left: moveCursor(-1)
        case .right: moveCursor(1)
        case .wordLeft:
            let b = before
            var n = 0
            var seen = false
            for ch in b.reversed() {
                if ch.isLetter || ch.isNumber { seen = true } else if seen { break }
                n += String(ch).utf16.count
            }
            moveCursor(-max(1, n))
        case .wordRight:
            let a = after
            var n = 0
            var seen = false
            for ch in a {
                if ch.isLetter || ch.isNumber { seen = true } else if seen { break }
                n += String(ch).utf16.count
            }
            moveCursor(max(1, n))
        case .start:
            Task { @MainActor [weak self] in
                guard let self else { return }
                for _ in 0..<500 {
                    let b = self.before
                    if b.isEmpty { break }
                    self.proxy?.adjustTextPosition(byCharacterOffset: -b.utf16.count)
                    await self.waitForContextChange(from: b)
                }
            }
        case .end:
            Task { @MainActor [weak self] in await self?.moveToEnd() }
        case .deleteWord:
            deleteWord()
        case .selectHint:
            showToast("Tipp: Wische über die Leertaste, um den Cursor zu bewegen.")
        }
        scheduleRefresh()
    }

    // MARK: - Sticker

    @Published var stickers: [URL] = []

    func reloadStickers() {
        stickers = StickerStore.list()
    }

    /// Kopiert den Sticker – danach im Chat einfach einfügen.
    func copySticker(_ url: URL) {
        guard hasFullAccess else {
            showToast("Dafür „Vollen Zugriff“ erlauben.")
            return
        }
        guard let data = try? Data(contentsOf: url) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: "public.png")
        lastChangeCount = UIPasteboard.general.changeCount
        feedback(.medium)
        showToast("Sticker kopiert – jetzt im Chat einfügen 📋")
    }

    func addStickerFromClipboard() {
        guard hasFullAccess else {
            showToast("Dafür „Vollen Zugriff“ erlauben.")
            return
        }
        let pb = UIPasteboard.general
        var raw: Data?
        for t in ["public.png", "public.heic", "public.jpeg", "public.tiff", "public.image"] {
            if let d = pb.data(forPasteboardType: t) { raw = d; break }
        }
        guard let data = raw else {
            showToast("Kopiere zuerst ein Bild oder einen Sticker.")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = StickerStore.add(imageData: data)
            DispatchQueue.main.async {
                self?.reloadStickers()
                self?.showToast(url == nil ? "Bild konnte nicht gelesen werden." : "Sticker gespeichert ✓")
            }
        }
    }

    func deleteSticker(_ url: URL) {
        StickerStore.delete(url)
        reloadStickers()
        showToast("Sticker gelöscht")
    }

    // MARK: - Design aus der Tastatur

    /// Setzt ein kopiertes Bild als Hintergrund (Tastaturen dürfen die Fotomediathek nicht öffnen).
    func setBackgroundFromClipboard() {
        guard hasFullAccess else {
            showToast("Dafür „Vollen Zugriff“ erlauben.")
            return
        }
        let pb = UIPasteboard.general
        let types = ["public.heic", "public.jpeg", "public.png", "public.tiff", "com.compuserve.gif", "public.image"]
        var raw: Data?
        for t in types {
            if let d = pb.data(forPasteboardType: t) { raw = d; break }
        }
        if raw == nil, pb.hasImages, let img = pb.image { raw = img.jpegData(compressionQuality: 0.9) }
        guard let data = raw else {
            showToast("Kopiere zuerst ein Bild (Fotos → Teilen → Kopieren).")
            return
        }
        showToast("Bild wird gesetzt …")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let jpeg = Theme.downsampledJPEG(from: data, maxPixel: 1100)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let jpeg else { self.showToast("Bild konnte nicht gelesen werden."); return }
                self.store.saveBackgroundImage(jpeg)
                self.store.themeID = ""
                self.showToast("Hintergrund gesetzt ✓")
            }
        }
    }

    func randomTheme() {
        ThemePreset.random().apply(to: store)
        feedback(.medium)
        showToast("🎲 Neuer Look")
    }

    // MARK: - Emojis

    func insertEmoji(_ e: String) {
        feedback()
        if composeMode { composeText += e; return }
        proxy?.insertText(e)
        store.useEmoji(e)
        undoCorrection = nil
    }

    func toggleFavoriteEmoji(_ e: String) {
        let added = store.toggleFavorite(e)
        feedback(.medium)
        showToast(added ? "\(e) zu Favoriten hinzugefügt ⭐️" : "\(e) aus Favoriten entfernt")
    }

    // MARK: - Panels

    func toggle(_ p: Panel) {
        feedback()
        if composeMode { cancelCompose() }
        if panel == .result, p == .result, aiBusy { cancelAI() }
        panel = panel == p ? .none : p
        if panel == .clipboard { reloadClips() }
        if panel == .stickers { reloadStickers() }
        if panel == .history { reloadHistory() }
        onHeightChange?(totalHeight)
        if panel == .none { refreshSuggestionsNow() }
    }

    func setProfile(_ id: String) {
        store.activeProfileID = id
        showToast(store.activeProfile.map { "Profil: \($0.emoji) \($0.name)" } ?? "Kein Profil")
    }

    @Published var loadingModels = false

    /// Lädt die Modelle, die das ChatGPT-Abo freigibt.
    func refreshChatGPTModels(silent: Bool = false) {
        guard hasFullAccess, store.usesChatGPT, !loadingModels else { return }
        loadingModels = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let models = try await ChatGPTAuth.fetchModels()
                self.loadingModels = false
                guard !models.isEmpty else { if !silent { self.showToast("Keine Modelle gefunden.") }; return }
                self.store.chatgptModels = models
                if !models.contains(where: { $0.first == self.store.chatgptModel }) { self.store.chatgptModel = models[0][0] }
                if !silent { self.showToast("\(models.count) Modelle geladen ✓") }
            } catch {
                self.loadingModels = false
                if !silent { self.showToast(error.localizedDescription) }
            }
        }
    }

    /// Übernimmt die ChatGPT-Anmeldung aus dem Kopplungscode der App.
    func importChatGPTCode(_ code: String) {
        if ChatGPTAuth.importTransferCode(code, into: store) {
            if UIPasteboard.general.string == code { UIPasteboard.general.string = "" }
            lastChangeCount = UIPasteboard.general.changeCount
            feedback(.medium)
            showToast("Mit ChatGPT gekoppelt ✓ – \(store.chatgptAccount)")
            refreshChatGPTModels(silent: true)
        } else {
            showToast("Kopplungscode ungültig – in der App neu kopieren.")
        }
    }

    func pasteChatGPTCode() {
        guard hasFullAccess, let s = UIPasteboard.general.string, ChatGPTAuth.isTransferCode(s) else {
            showToast("Kopiere zuerst den Kopplungscode in der App (ChatGPT-Abo → „Code kopieren“).")
            return
        }
        importChatGPTCode(s)
    }

    func pasteAPIKey() {
        if hasFullAccess, let s = UIPasteboard.general.string, ChatGPTAuth.isTransferCode(s) {
            importChatGPTCode(s)
            return
        }
        guard hasFullAccess, let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), s.hasPrefix("sk-") else {
            showToast("Kopiere zuerst einen Schlüssel (sk-…).")
            return
        }
        store.apiKey = s
        store.apiKeyEnabled = true
        store.aiProvider = "apikey"
        showToast("API-Schlüssel gespeichert ✓")
    }

    func setLayer(_ l: KeyboardLayer) {
        layer = l
        onHeightChange?(totalHeight)
    }
}
