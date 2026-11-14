import UIKit
import SwiftUI
import AudioToolbox

enum KeyboardLayer { case letters, numbers, symbols }
enum ShiftState { case off, on, caps }

enum Panel: Equatable {
    case none
    case tools
    case ai
    case result
    case clipboard
    case macros
    case emoji
    case dictation
    case settings
}

enum DictationPhase: Equatable {
    case connecting
    case openingApp
    case recording
    case processing
    case failed(String)
}

struct Suggestion: Identifiable, Equatable {
    enum Kind { case word, typed, correction, macro, ai, accent, replacement }
    let id = UUID()
    var text: String
    var kind: Kind
    var display: String? = nil
}

final class KeyboardState: ObservableObject {
    weak var controller: KeyboardViewController?
    let store = SharedStore.shared
    let engine = TextEngine()
    private lazy var client = OpenAIClient(store: store)

    // Layout
    @Published var layer: KeyboardLayer = .letters
    @Published var shift: ShiftState = .on
    @Published var panel: Panel = .none
    @Published var suggestions: [Suggestion] = []
    @Published var hasFullAccess = false
    @Published var needsGlobe = true
    @Published var returnTitle = "return"
    @Published var isDark = false
    @Published var toast: String?

    // KI
    @Published var aiBusy = false
    @Published var aiResult = ""
    @Published var aiError: String?
    @Published var aiTitle = ""
    @Published var composeMode = false
    @Published var composeText = ""
    private var lastAIAction: (() -> Void)?
    private var replaceTarget: ReplaceTarget = .none

    // Zwischenablage
    @Published var clips: [ClipItem] = []
    private var lastChangeCount = -1
    private var clipTimer: Timer?

    // Diktat
    @Published var dictation: DictationPhase = .connecting
    @Published var dictationLevel: Float = 0
    private var dictationTimer: Timer?
    private var gotPong = false
    private var lastHandledStatus = ""
    private var dictationStartedAt = Date()

    // Tippen
    private var lastSpaceTime = Date.distantPast
    private var lastShiftTap = Date.distantPast
    private var undoCorrection: (original: String, corrected: String, trailing: String)?
    private var aiSuggestionTask: Task<Void, Never>?
    private var deleteTimer: Timer?
    private var deleteCount = 0

    var onHeightChange: ((CGFloat) -> Void)?

    let toolbarHeight: CGFloat = 46
    var keyRowHeight: CGFloat { UIScreen.main.bounds.width > UIScreen.main.bounds.height ? 40 : 52 }
    var rowCount: Int { store.showNumberRow && layer == .letters ? 5 : 4 }
    var keysHeight: CGFloat { CGFloat(rowCount) * keyRowHeight + 10 }
    var totalHeight: CGFloat { toolbarHeight + keysHeight }

    enum ReplaceTarget { case none, selection, all(before: Int, after: Int), range(before: Int, after: Int) }

    init(controller: KeyboardViewController) {
        self.controller = controller
    }

    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }
    var tint: Color { Theme.tint(store.keyboardTint) }

    // MARK: - Lebenszyklus

    func appear() {
        store.reload()
        hasFullAccess = controller?.hasFullAccess ?? false
        needsGlobe = controller?.needsInputModeSwitchKey ?? true
        controller?.requestSupplementaryLexicon { [weak self] lex in self?.engine.setLexicon(lex) }
        onHeightChange?(totalHeight)
        updateReturnKey()
        updateAutoShift()
        refreshSuggestions()
        startClipboardWatch()
        setupDictationObservers()
        if panel == .dictation { resumeDictationCheck() }
    }

    func disappear() {
        engine.save()
        clipTimer?.invalidate()
        clipTimer = nil
        stopDelete()
    }

    func textDidChange() {
        isDark = proxy?.keyboardAppearance == .dark
        updateReturnKey()
        if !composeMode {
            updateAutoShift()
            refreshSuggestions()
        }
    }

    private func updateReturnKey() {
        switch proxy?.returnKeyType ?? .default {
        case .go: returnTitle = "Los"
        case .google, .yahoo, .search: returnTitle = "Suchen"
        case .join: returnTitle = "Beitreten"
        case .next: returnTitle = "Weiter"
        case .send: returnTitle = "Senden"
        case .done: returnTitle = "Fertig"
        case .continue: returnTitle = "Weiter"
        case .route: returnTitle = "Route"
        case .emergencyCall: returnTitle = "Notruf"
        default: returnTitle = "⏎"
        }
    }

    // MARK: - Feedback

    func feedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        if store.keySound { AudioServicesPlaySystemSound(1104) }
        if store.haptics, hasFullAccess { UIImpactFeedbackGenerator(style: style).impactOccurred() }
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

    /// Das gerade getippte (unvollständige) Wort vor dem Cursor.
    var currentWord: String {
        var word = ""
        for ch in before.reversed() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "'" { word.insert(ch, at: word.startIndex) } else { break }
        }
        return word
    }

    var previousWord: String? {
        let text = String(before.dropLast(currentWord.count))
        let words = text.split { !($0.isLetter || $0.isNumber) }
        return words.last.map(String.init)
    }

    // MARK: - Eingabe

    func insert(_ text: String) {
        if composeMode {
            composeText += text
            return
        }
        undoCorrection = nil
        proxy?.insertText(text)
        if layer != .letters, text == " " || text == "'" {
            // nach Leerzeichen zurück zu Buchstaben (wie iOS)
            layer = .letters
        }
        if shift == .on { shift = .off }
        if text == " " || text == "\n" || ".,!?;:".contains(text) { updateAutoShift() }
        refreshSuggestions()
    }

    func tapKey(_ key: String) {
        feedback()
        let output: String
        if shift != .off, layer == .letters { output = key.uppercased() } else { output = key }
        if !composeMode, ".,!?;:".contains(output), let last = before.last, last == " ", undoCorrection == nil, before.count >= 2 {
            // Leerzeichen vor Satzzeichen entfernen
            let beforeLast = before.dropLast().last
            if let b = beforeLast, b.isLetter || b.isNumber {
                proxy?.deleteBackward()
                proxy?.insertText(output + " ")
                updateAutoShift()
                refreshSuggestions()
                return
            }
        }
        if !composeMode, ".,!?;:".contains(output) { commitWord(trailing: output) ; return }
        insert(output)
    }

    func tapSpace() {
        feedback()
        if composeMode { composeText += " "; return }
        let now = Date()
        if store.doubleSpacePeriod, now.timeIntervalSince(lastSpaceTime) < 0.45, before.hasSuffix(" "),
           let c = before.dropLast().last, c.isLetter || c.isNumber {
            proxy?.deleteBackward()
            proxy?.insertText(". ")
            lastSpaceTime = .distantPast
            undoCorrection = nil
            updateAutoShift()
            refreshSuggestions()
            return
        }
        lastSpaceTime = now
        commitWord(trailing: " ")
    }

    func tapReturn() {
        feedback()
        if composeMode { sendCompose(); return }
        commitWord(trailing: "\n")
    }

    /// Schließt das aktuelle Wort ab: Makros, Textersetzung, Autokorrektur, Lernen.
    private func commitWord(trailing: String) {
        let word = currentWord
        let prev = previousWord
        var final = word

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
            if store.autocorrect, shouldAutocorrect, let corr = engine.correction(for: word), corr != word {
                deleteChars(word.count)
                proxy?.insertText(corr + trailing)
                undoCorrection = (word, corr, trailing)
                final = corr
                store.incrementStat("corrections")
                engine.learn(word: final, previous: prev)
                afterCommit()
                return
            }
            engine.learn(word: final, previous: prev)
        }
        proxy?.insertText(trailing)
        undoCorrection = nil
        afterCommit()
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
        if layer != .letters { layer = .letters }
        if shift == .on { shift = .off }
        updateAutoShift()
        refreshSuggestions()
    }

    private func deleteChars(_ n: Int) {
        for _ in 0..<max(0, n) { proxy?.deleteBackward() }
    }

    func tapDelete() {
        feedback(.soft)
        if composeMode {
            if !composeText.isEmpty { composeText.removeLast() }
            return
        }
        // Autokorrektur rückgängig machen
        if let undo = undoCorrection, before.hasSuffix(undo.corrected + undo.trailing) {
            deleteChars(undo.corrected.count + undo.trailing.count)
            proxy?.insertText(undo.original)
            engine.learn(word: undo.original, previous: nil, weight: 3)
            undoCorrection = nil
            refreshSuggestions()
            return
        }
        undoCorrection = nil
        if !selected.isEmpty {
            proxy?.deleteBackward()
        } else {
            proxy?.deleteBackward()
        }
        updateAutoShift()
        refreshSuggestions()
    }

    func startDelete() {
        tapDelete()
        deleteCount = 0
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self] _ in
            self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.deleteCount += 1
                if self.deleteCount > 18, !self.composeMode {
                    self.deleteWord()
                } else {
                    self.tapDelete()
                }
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
        feedback(.soft)
        refreshSuggestions()
    }

    func tapShift() {
        feedback()
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.35 {
            shift = .caps
        } else {
            shift = shift == .off ? .on : .off
        }
        lastShiftTap = now
    }

    func moveCursor(_ offset: Int) {
        guard offset != 0 else { return }
        proxy?.adjustTextPosition(byCharacterOffset: offset)
        if store.haptics, hasFullAccess { UISelectionFeedbackGenerator().selectionChanged() }
    }

    func cursorMoveEnded() {
        updateAutoShift()
        refreshSuggestions()
    }

    func updateAutoShift() {
        guard layer == .letters, shift != .caps else { return }
        guard store.autocapitalize, let proxy else { shift = .off; return }
        if proxy.autocapitalizationType == UITextAutocapitalizationType.none { shift = .off; return }
        if proxy.autocapitalizationType == .allCharacters { shift = .on; return }
        let text = before
        if text.isEmpty { shift = .on; return }
        if proxy.autocapitalizationType == .words, text.last?.isWhitespace == true { shift = .on; return }
        let trimmed = text.replacingOccurrences(of: " ", with: "")
        if text.last == "\n" { shift = .on; return }
        if text.last == " ", let last = trimmed.last, ".!?".contains(last) { shift = .on; return }
        shift = .off
    }

    // MARK: - Vorschläge

    func refreshSuggestions() {
        aiSuggestionTask?.cancel()
        if composeMode || panel != .none && panel != .tools { return }
        let word = currentWord
        var list: [Suggestion] = []

        if !word.isEmpty {
            // Makro-Treffer
            if let macro = store.macros.first(where: { !$0.shortcut.isEmpty && $0.shortcut.lowercased() == word.lowercased() }) {
                list.append(Suggestion(text: macro.shortcut, kind: .macro, display: "⚡︎ " + macro.title))
            }
            var correction: String?
            if store.autocorrect, shouldAutocorrect { correction = engine.correction(for: word) }
            if let correction {
                list.append(Suggestion(text: word, kind: .typed, display: "„\(word)“"))
                list.append(Suggestion(text: correction, kind: .correction))
            } else {
                list.append(Suggestion(text: word, kind: .typed, display: "„\(word)“"))
            }
            for c in engine.completions(prefix: word, previousWord: previousWord, limit: 3) where !list.contains(where: { $0.text == c }) {
                list.append(Suggestion(text: c, kind: .word))
            }
        } else {
            for p in engine.predictions(after: previousWord, limit: 3) {
                list.append(Suggestion(text: p, kind: .word))
            }
        }
        suggestions = Array(list.prefix(3))

        if store.aiSuggestions, hasFullAccess, store.hasAPIKey, before.count > 8 {
            let context = before
            aiSuggestionTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled, let self else { return }
                guard let result = try? await self.client.suggestions(context: context), !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.before == context else { return }
                    var merged = self.suggestions.filter { $0.kind == .typed || $0.kind == .correction || $0.kind == .macro }
                    for r in result where !merged.contains(where: { $0.text == r }) {
                        merged.append(Suggestion(text: r, kind: .ai))
                    }
                    self.suggestions = Array(merged.prefix(3))
                }
            }
        }
    }

    func pickSuggestion(_ s: Suggestion) {
        feedback()
        switch s.kind {
        case .macro:
            if let macro = store.macros.first(where: { $0.shortcut == s.text }) {
                deleteChars(currentWord.count)
                runMacro(macro, trailing: " ")
            }
        case .accent:
            if composeMode { composeText += s.text } else { proxy?.insertText(s.text) }
            if shift == .on { shift = .off }
            refreshSuggestions()
        case .typed:
            engine.learn(word: s.text, previous: previousWord, weight: 2)
            proxy?.insertText(" ")
            undoCorrection = nil
            afterCommit()
        case .ai:
            // KI-Vorschläge können Wortfortsetzung oder neue Wörter sein
            let word = currentWord
            if !word.isEmpty, s.text.lowercased().hasPrefix(word.lowercased()) {
                deleteChars(word.count)
            } else if !word.isEmpty {
                proxy?.insertText(" ")
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

    /// Long-Press-Alternativen (Umlaute, Akzente) in der Vorschlagsleiste anzeigen.
    func showAlternates(for key: String) {
        guard let alts = KeyLayouts.alternates[key.lowercased()] else { return }
        feedback(.medium)
        let upper = shift != .off
        suggestions = alts.map { Suggestion(text: upper ? $0.uppercased() : $0, kind: .accent) }
    }

    // MARK: - Makros

    func runMacro(_ macro: Macro, trailing: String = "") {
        store.incrementStat("macros")
        if macro.isAI {
            let context = before + after
            runAI(title: macro.title, replace: .none) { [client = self.client] in
                try await client.compose(prompt: macro.text, context: context)
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
            showToast("Kein API-Schlüssel – öffne die App Tastatur KI.")
            return false
        }
        return true
    }

    /// Ermittelt den Text, auf den eine KI-Aktion angewendet wird.
    private func sourceText() -> (text: String, target: ReplaceTarget, context: String?) {
        let sel = selected
        let b = before
        let a = after
        switch store.aiScope {
        case .selection:
            return (sel, .selection, store.useAppContext ? b + a : nil)
        case .all:
            if !sel.isEmpty { return (sel, .selection, store.useAppContext ? b + a : nil) }
            return (b + a, .all(before: b.count, after: a.count), nil)
        case .sentence:
            if !sel.isEmpty { return (sel, .selection, store.useAppContext ? b + a : nil) }
            let startIdx = b.lastIndex(where: { $0 == "\n" }).map { b.index(after: $0) } ?? b.startIndex
            let head = String(b[startIdx...])
            let endIdx = a.firstIndex(where: { $0 == "\n" }) ?? a.endIndex
            let tail = String(a[..<endIdx])
            return (head + tail, .range(before: head.count, after: tail.count), store.useAppContext ? b + a : nil)
        case .auto:
            if !sel.isEmpty { return (sel, .selection, store.useAppContext ? b + a : nil) }
            return (b + a, .all(before: b.count, after: a.count), nil)
        }
    }

    func runAction(_ action: AIAction) {
        guard requireAI() else { return }
        let source = sourceText()
        guard !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Kein Text vorhanden – tippe oder markiere zuerst etwas.")
            return
        }
        let instruction = action.prompt
        let ctx = source.context
        let text = source.text
        runAI(title: action.title, replace: source.target) { [client = self.client] in
            try await client.transform(text: text, instruction: instruction, appContext: ctx)
        }
    }

    func runAI(title: String, replace: ReplaceTarget, _ work: @escaping () async throws -> String) {
        guard requireAI() else { return }
        aiTitle = title
        aiResult = ""
        aiError = nil
        aiBusy = true
        replaceTarget = replace
        composeMode = false
        panel = .result
        lastAIAction = { [weak self] in self?.runAI(title: title, replace: replace, work) }
        store.incrementStat("aiActions")
        Task { [weak self] in
            do {
                let result = try await work()
                await MainActor.run {
                    self?.aiResult = result
                    self?.aiBusy = false
                }
            } catch {
                await MainActor.run {
                    self?.aiError = error.localizedDescription
                    self?.aiBusy = false
                }
            }
        }
    }

    func retryAI() { lastAIAction?() }

    func startCompose() {
        guard requireAI() else { return }
        composeText = ""
        composeMode = true
        panel = .none
        layer = .letters
        shift = .on
    }

    func cancelCompose() {
        composeMode = false
        composeText = ""
        updateAutoShift()
        refreshSuggestions()
    }

    func sendCompose() {
        let prompt = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { cancelCompose(); return }
        composeMode = false
        composeText = ""
        let context = store.useAppContext ? before + after : nil
        runAI(title: "„\(prompt.prefix(30))“", replace: .none) { [client = self.client] in
            try await client.compose(prompt: prompt, context: context)
        }
    }

    /// Ergebnis anwenden.
    func applyResult(replace: Bool) {
        let result = aiResult
        guard !result.isEmpty, let proxy else { return }
        feedback(.medium)
        if replace {
            switch replaceTarget {
            case .selection:
                proxy.insertText(result)
            case .all(let b, let a), .range(let b, let a):
                if a > 0 { proxy.adjustTextPosition(byCharacterOffset: a) }
                let total = b + a
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.deleteChars(total)
                    self?.proxy?.insertText(result)
                    self?.afterCommit()
                }
            case .none:
                proxy.insertText(result)
            }
        } else {
            var text = result
            if let last = before.last, !last.isWhitespace { text = " " + text }
            proxy.insertText(text)
        }
        panel = .none
        aiResult = ""
        afterCommit()
    }

    func copyResult() {
        guard hasFullAccess else { return }
        UIPasteboard.general.string = aiResult
        store.addClip(aiResult)
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
        let t = selected.isEmpty ? before + after : selected
        guard !t.isEmpty else { return }
        UIPasteboard.general.string = t
        clips = store.addClip(t)
        showToast("Kopiert ✓")
    }

    // MARK: - Diktat

    private var observersSet = false

    private func setupDictationObservers() {
        guard !observersSet else { return }
        observersSet = true
        let n = DarwinNotifier.shared
        n.observe(.pong) { [weak self] in self?.gotPong = true }
        n.observe(.recording) { [weak self] in self?.pollDictation() }
        n.observe(.processing) { [weak self] in self?.pollDictation() }
        n.observe(.result) { [weak self] in self?.pollDictation() }
        n.observe(.failed) { [weak self] in self?.pollDictation() }
        n.observe(.sessionEnded) { [weak self] in
            guard let self, self.panel == .dictation, self.dictation == .recording else { return }
            self.dictation = .failed("Diktat-Sitzung wurde beendet.")
        }
    }

    func startDictation() {
        feedback(.medium)
        guard hasFullAccess else {
            showToast("Für Diktat bitte „Vollen Zugriff“ erlauben.")
            return
        }
        guard store.hasAPIKey else {
            showToast("Kein API-Schlüssel – öffne die App Tastatur KI.")
            return
        }
        composeMode = false
        panel = .dictation
        dictation = .connecting
        lastHandledStatus = DictationFiles.read(DictationFiles.status) ?? ""
        gotPong = false
        dictationStartedAt = Date()
        DarwinNotifier.shared.post(.ping)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.panel == .dictation, self.dictation == .connecting else { return }
            if self.gotPong {
                DarwinNotifier.shared.post(.start)
            } else {
                self.dictation = .openingApp
                if let url = URL(string: "tastatur://dictate") { self.controller?.openURL(url) }
            }
        }
        startDictationTimer()
    }

    private func resumeDictationCheck() {
        gotPong = false
        DarwinNotifier.shared.post(.ping)
        startDictationTimer()
        pollDictation()
    }

    private func startDictationTimer() {
        dictationTimer?.invalidate()
        dictationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.pollDictation()
        }
    }

    private func pollDictation() {
        guard panel == .dictation else {
            dictationTimer?.invalidate()
            return
        }
        let status = DictationFiles.read(DictationFiles.status) ?? ""
        if status == "recording" {
            if dictation != .recording { dictation = .recording; feedback(.medium) }
            if let l = DictationFiles.read(DictationFiles.level), let v = Float(l) { dictationLevel = v }
        } else if status == "processing" {
            dictation = .processing
        } else if status.hasPrefix("done:"), status != lastHandledStatus {
            lastHandledStatus = status
            let text = DictationFiles.read(DictationFiles.result) ?? ""
            finishDictation(with: text)
        } else if status.hasPrefix("failed:"), status != lastHandledStatus {
            lastHandledStatus = status
            dictation = .failed(DictationFiles.read(DictationFiles.error) ?? "Unbekannter Fehler")
        } else if dictation == .connecting, Date().timeIntervalSince(dictationStartedAt) > 3 {
            dictation = .openingApp
        }
    }

    private func finishDictation(with text: String) {
        dictationTimer?.invalidate()
        panel = .none
        guard !text.isEmpty else { return }
        var t = text
        if let last = before.last, !last.isWhitespace, !last.isNewline { t = " " + t }
        proxy?.insertText(t)
        feedback(.medium)
        afterCommit()
    }

    func stopDictation() {
        feedback(.medium)
        DarwinNotifier.shared.post(.stop)
        dictation = .processing
    }

    func cancelDictation() {
        DarwinNotifier.shared.post(.cancel)
        dictationTimer?.invalidate()
        panel = .none
    }

    func openApp(_ path: String = "") {
        if let url = URL(string: "tastatur://\(path)") { controller?.openURL(url) }
    }

    // MARK: - Panels

    func toggle(_ p: Panel) {
        feedback()
        if composeMode { cancelCompose() }
        panel = panel == p ? .none : p
        if panel == .clipboard { reloadClips() }
        if panel == .none { refreshSuggestions() }
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
        feedback()
        layer = l
        onHeightChange?(totalHeight)
    }
}
