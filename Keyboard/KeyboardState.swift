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
}

struct Suggestion: Identifiable, Equatable {
    enum Kind { case word, typed, correction, macro, ai }
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
    @Published var returnTitle = "⏎"
    @Published var toast: String?

    // KI
    @Published var sourceMode: AIScope = .auto
    @Published var aiBusy = false
    @Published var aiStatus = ""
    @Published var aiResult = ""
    @Published var aiOriginal = ""
    @Published var aiShowDiff = false
    @Published var aiError: String?
    @Published var aiTitle = ""
    @Published var composeMode = false
    @Published var composeIsRefine = false
    @Published var composeText = ""
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

    let toolbarHeight: CGFloat = 48
    var keyRowHeight: CGFloat {
        let size = controller?.view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        return size.width > size.height ? 40 : 54
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
        controller?.requestSupplementaryLexicon { [weak self] lex in self?.engine.setLexicon(lex) }
        onHeightChange?(totalHeight)
        impact.prepare()
        updateReturnKey()
        updateAutoShift()
        refreshSuggestionsNow()
        startClipboardWatch()
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
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                guard let self else { return }
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
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshSuggestionsNow() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    func refreshSuggestionsNow() {
        aiSuggestionTask?.cancel()
        if composeMode || (panel != .none && panel != .tools) { return }
        let word = currentWord
        var list: [Suggestion] = []

        if !word.isEmpty {
            if let macro = store.macros.first(where: { !$0.shortcut.isEmpty && $0.shortcut.lowercased() == word.lowercased() }) {
                list.append(Suggestion(text: macro.shortcut, kind: .macro, display: "⚡︎ " + macro.title))
            }
            var correction: String?
            if store.autocorrect, shouldAutocorrect { correction = engine.correction(for: word) }
            list.append(Suggestion(text: word, kind: .typed, display: "„\(word)“"))
            if let correction { list.append(Suggestion(text: correction, kind: .correction)) }
            for c in engine.completions(prefix: word, previousWord: previousWord, limit: 3) where !list.contains(where: { $0.text == c }) {
                list.append(Suggestion(text: c, kind: .word))
            }
        } else {
            for p in engine.predictions(after: previousWord, limit: 3) {
                list.append(Suggestion(text: p, kind: .word))
            }
        }
        let newList = Array(list.prefix(3))
        if newList.map(\.text) != suggestions.map(\.text) || newList.map(\.kind) != suggestions.map(\.kind) {
            suggestions = newList
        }

        if store.aiSuggestions, hasFullAccess, store.hasAPIKey, before.count > 8 {
            let context = before
            aiSuggestionTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
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
        case .typed:
            engine.learn(word: s.text, previous: previousWord, weight: 2)
            proxy?.insertText(" ")
            undoCorrection = nil
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
            showToast("Kein API-Schlüssel – öffne die App Tastatur KI.")
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
        } catch {
            guard !Task.isCancelled else { return }
            aiError = error.localizedDescription
            aiBusy = false
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
        composeText = ""
        composeIsRefine = refine
        composeMode = true
        if !refine { panel = .none } else { panel = .none }
        layer = .letters
        shift = .on
        updateReturnKey()
    }

    func cancelCompose() {
        composeMode = false
        composeText = ""
        updateReturnKey()
        if composeIsRefine, !aiResult.isEmpty { panel = .result }
        composeIsRefine = false
        updateAutoShift()
        scheduleRefresh()
    }

    func sendCompose() {
        let prompt = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { cancelCompose(); return }
        let isRefine = composeIsRefine
        composeMode = false
        composeIsRefine = false
        composeText = ""
        updateReturnKey()
        if isRefine {
            refine(prompt)
            return
        }
        let context = store.useAppContext ? String((before + after).suffix(8000)) : nil
        runAI(title: "„\(prompt.prefix(30))“", original: "", target: .none, showDiff: false) { [client = self.client] partial in
            try await client.compose(prompt: prompt, context: context, onPartial: partial)
        }
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

    // MARK: - Panels

    func toggle(_ p: Panel) {
        feedback()
        if composeMode { cancelCompose() }
        if panel == .result, p == .result, aiBusy { cancelAI() }
        panel = panel == p ? .none : p
        if panel == .clipboard { reloadClips() }
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
