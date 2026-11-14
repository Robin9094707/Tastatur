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
}

struct Suggestion: Identifiable, Equatable {
    enum Kind { case word, typed, correction, macro, ai, phrase, token }
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
    private let client = OpenAIClient(store: SharedStore.shared)

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
            pairs.count == 1 ? "\(pairs[0].wrong) → \(pairs[0].right)" : "\(pairs.count) Tippfehler korrigiert"
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
    @Published var composeMode = false
    @Published var composeTarget: ComposeTarget = .ai
    @Published var settingsPage: SettingsPage = .main
    private var pendingMacroShortcut = ""
    var composeIsRefine: Bool { composeTarget == .refine }

    /// Wohin die Eingabe im Eingabe-Modus geht (KI-Auftrag oder eine Einstellung).
    enum ComposeTarget: Equatable {
        case ai, refine, translate, calc, apiKey, baseURL, chatModel, personalContext, writingStyle
        case macroShortcut, macroText, profileName, profileContext(UUID), actionTitle, actionPrompt

        var placeholder: String {
            switch self {
            case .ai: return "Was soll die KI schreiben?"
            case .refine: return "Wie soll das Ergebnis geändert werden?"
            case .translate: return "Tippe in deiner Sprache …"
            case .calc: return "Rechnung, z. B. 12,5*4+3"
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
            }
        }

        var symbol: String {
            switch self {
            case .ai: return "sparkles"
            case .refine: return "slider.horizontal.3"
            case .translate: return "character.bubble"
            case .calc: return "plus.forwardslash.minus"
            case .apiKey: return "key.fill"
            case .baseURL: return "server.rack"
            case .chatModel: return "cpu"
            case .personalContext, .writingStyle, .profileContext: return "person.text.rectangle"
            case .macroShortcut, .macroText: return "text.badge.star"
            case .profileName: return "person.2"
            case .actionTitle, .actionPrompt: return "wand.and.stars"
            }
        }

        var isSetting: Bool { self != .ai && self != .refine && self != .translate && self != .calc }
    }

    enum SettingsPage: Equatable { case main, ai, context, design, typing, macros, actions, toolbar }
    @Published var composeText = "" { didSet { if composeText != oldValue { composeDidChange() } } }
    private var lastRun: (() -> Void)?
    private var aiTask: Task<Void, Never>?
    private(set) var replaceTarget: ReplaceTarget = .none

    // Zwischenablage
    @Published var clips: [ClipItem] = []
    private var lastChangeCount = -1
    private var clipTimer: Timer?

    // Tippen
    private var lastSpaceTime = Date.distantPast
    private var lastShiftTap = Date.distantPast
    private var undoCorrection: (original: String, corrected: String, trailing: String)?
    private var aiSuggestionTask: Task<Void, Never>?
    private var refreshWork: DispatchWorkItem?
    private var deleteTimer: Timer?
    private var deleteCount = 0
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()

    var onHeightChange: ((CGFloat) -> Void)?

    var toolbarHeight: CGFloat { composeMode && composeTarget == .translate ? 96 : 48 }
    var keyRowHeight: CGFloat {
        let size = controller?.view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        let landscape = size.width > size.height
        if UIDevice.current.userInterfaceIdiom == .pad { return landscape ? 60 : 64 }
        return landscape ? 40 : 55
    }
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
        engine.save()
        clipTimer?.invalidate()
        clipTimer = nil
        stopDelete()
    }

    func textDidChange() {
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
        if composeMode { if returnTitle != "Senden" { returnTitle = "Senden" }; return }
        if title != returnTitle { returnTitle = title }
    }

    // MARK: - Feedback

    /// Sofortiges Feedback beim Herunterdrücken einer Taste.
    func keyDownFeedback(special: Bool) {
        if store.keySound { AudioServicesPlaySystemSound(special ? 1156 : 1104) }
        if store.haptics, hasFullAccess {
            impact.impactOccurred(intensity: special ? 0.8 : 0.6)
            impact.prepare()
        }
    }

    func feedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        if store.keySound { AudioServicesPlaySystemSound(1104) }
        if store.haptics, hasFullAccess {
            if style == .medium || style == .heavy { impactMedium.impactOccurred() } else { impact.impactOccurred() }
        }
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
        let output = (shift != .off && layer == .letters) ? key.uppercased() : key
        if composeMode {
            composeText += output
            if shift == .on { shift = .off }
            return
        }
        let isPunct = output.count == 1 && ".,!?;:".contains(output)
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
        proxy?.insertText(output)
        if shift == .on { shift = .off }
        if layer != .letters, output == "'" { layer = .letters }
        scheduleRefresh()
    }

    func tapSpace() {
        if composeMode { composeText += " "; return }
        let now = Date()
        let b = before
        if store.doubleSpacePeriod, now.timeIntervalSince(lastSpaceTime) < 0.45, b.hasSuffix(" "),
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
        if composeMode { sendCompose(); return }
        commitWord(trailing: "\n")
    }

    /// Schließt das aktuelle Wort ab: Makros, Textersetzung, Autokorrektur, Lernen.
    private func commitWord(trailing: String) {
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
            if store.autocorrect, shouldAutocorrect, !looksLikeName(word), let corr = engine.correction(for: word), corr != word {
                deleteChars(word.count)
                proxy?.insertText(corr + trailing)
                undoCorrection = (word, corr, trailing)
                store.incrementStat("corrections")
                engine.learn(word: corr, previous: prev)
                afterCommit()
                return
            }
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

    private var shouldAutocorrect: Bool {
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

    private func afterCommit() {
        wordsSincePrediction += 1
        if !liveEditing {
            wordsSinceCheck += 1
            let last = before.last
            if wordsSinceCheck >= 8 || (last != nil && ".!?\n".contains(last!)) && wordsSinceCheck >= 1 {
                liveCheckPending = true
            }
        }
        if layer != .letters { layer = .letters }
        if shift == .on { shift = .off }
        updateAutoShift()
        scheduleRefresh()
    }

    private func deleteChars(_ n: Int) {
        for _ in 0..<max(0, n) { proxy?.deleteBackward() }
    }

    func tapDelete() {
        if composeMode {
            if !composeText.isEmpty { composeText.removeLast() }
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
        proxy?.deleteBackward()
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
        deleteChars(max(1, count))
        scheduleRefresh()
    }

    func tapShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 {
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

    func scheduleRefresh() {
        if !liveEditing {
            liveCheckWork?.cancel()
            if liveCheckPending { scheduleLiveCheck() }
        }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshSuggestionsNow() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    func refreshSuggestionsNow() {
        aiSuggestionTask?.cancel()
        aiThinking = false
        if composeMode || (panel != .none && panel != .tools) { return }
        let word = currentWord
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
        let newList = Array(list.prefix(3))
        if newList.map(\.text) != suggestions.map(\.text) || newList.map(\.kind) != suggestions.map(\.kind) {
            suggestions = newList
        }

        requestPrediction()
    }

    /// KI-Vorhersage für die Vorschlagsleiste (entprellt, mit Cache).
    private var wordsSincePrediction = 0
    private var lastPredictionContext = ""

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

    private func requireAI() -> Bool {
        if !hasFullAccess {
            showToast("Bitte „Vollen Zugriff“ für Tastatur KI erlauben.")
            return false
        }
        if !store.hasAPIKey {
            showToast("Kein API-Schlüssel – ✨ → Einstellungen → KI & API")
            return false
        }
        return true
    }

    /// Wartet kurz, bis das Textfeld den neuen Kontext gemeldet hat.
    @MainActor
    private func waitForContextChange(from old: String?) async {
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
    private func gatherSource() async -> (text: String, target: ReplaceTarget, context: String?)? {
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
    private func startAI(title: String, showDiff: Bool,
                         source: @escaping () async -> (text: String, target: ReplaceTarget, context: String?)?,
                         work: @escaping (String, String?, @escaping (String) -> Void) async throws -> String) {
        aiTask?.cancel()
        aiTitle = title
        aiResult = ""
        aiOriginal = ""
        aiError = nil
        aiBusy = true
        aiStatus = "Bereite vor …"
        aiShowDiff = showDiff
        aiDiff = nil
        composeMode = false
        panel = .result
        store.incrementStat("aiActions")
        lastRun = { [weak self] in self?.startAI(title: title, showDiff: showDiff, source: source, work: work) }
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
        aiError = nil
        aiBusy = true
        aiStatus = "KI schreibt …"
        aiShowDiff = showDiff
        aiDiff = nil
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
                    self.aiResult = OpenAIClient.cleanup(partial)
                }
            }
            guard !Task.isCancelled else { return }
            aiResult = result
            aiBusy = false
            feedback(.medium)
            computeDiff()
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
        if target.isSetting {
            saveSettingInput(target, text)
            return
        }
        guard !text.isEmpty else { cancelCompose(); return }
        if target == .refine {
            refine(text)
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
            store.apiKey = key
            showToast(key.isEmpty ? "API-Schlüssel entfernt" : "API-Schlüssel gespeichert ✓")
        case .baseURL:
            store.baseURL = text.isEmpty ? "https://api.openai.com/v1" : text.replacingOccurrences(of: " ", with: "")
            showToast("API-Adresse gespeichert ✓")
        case .chatModel:
            guard !text.isEmpty else { return }
            let m = text.lowercased().replacingOccurrences(of: " ", with: "")
            store.chatModel = m
            store.fastModel = m
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
        case .ai, .refine, .translate, .calc:
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

    @MainActor
    private func replaceAll(with text: String, expectedLength: Int) async {
        await moveToEnd()
        var deleted = 0
        let limit = expectedLength + 20
        while deleted < limit {
            let b = before
            if b.isEmpty { break }
            let n = min(b.count, limit - deleted)
            for _ in 0..<n { proxy?.deleteBackward() }
            deleted += n
            await waitForContextChange(from: b)
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
                clips = store.addClip(s)
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
        var items = store.loadClips()
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].pinned.toggle() }
        items.sort { a, b in a.pinned != b.pinned ? a.pinned : a.date > b.date }
        store.saveClips(items)
        clips = items
    }

    func deleteClip(_ item: ClipItem) {
        var items = store.loadClips()
        items.removeAll { $0.id == item.id }
        store.saveClips(items)
        clips = items
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func runLiveCheck() {
        guard store.liveAICorrection, hasFullAccess, store.hasAPIKey, panel == .none, !composeMode, shouldAutocorrect else { return }
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
            f.confidence >= 0.9 && !f.wrong.isEmpty && !f.right.isEmpty && f.wrong != f.right
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
    func isPlausibleContinuation(_ letter: String) -> Bool {
        let word = currentWord
        guard !word.isEmpty else { return true }
        return engine.isPlausiblePrefix(word + letter)
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

    // MARK: - Werkzeuge der Schnellleiste

    func runTool(_ id: String) {
        switch id {
        case "ai": toggle(.ai)
        case "translate": startTranslateMode()
        case "translateClip": translateClipboard()
        case "write": startCompose()
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
        default: break
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
        if panel == .none { refreshSuggestionsNow() }
    }

    func setProfile(_ id: String) {
        store.activeProfileID = id
        showToast(store.activeProfile.map { "Profil: \($0.emoji) \($0.name)" } ?? "Kein Profil")
    }

    func pasteAPIKey() {
        guard hasFullAccess, let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), s.hasPrefix("sk-") else {
            showToast("Kopiere zuerst einen Schlüssel (sk-…).")
            return
        }
        store.apiKey = s
        showToast("API-Schlüssel gespeichert ✓")
    }

    func setLayer(_ l: KeyboardLayer) {
        layer = l
        onHeightChange?(totalHeight)
    }
}
