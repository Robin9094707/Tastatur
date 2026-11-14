import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(state: state)
                .frame(height: state.toolbarHeight)
            content
                .frame(height: state.keysHeight)
        }
        .background(background)
        .overlay(alignment: .top) {
            if let toast = state.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule(tint: state.tint)
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.panel)
        .animation(.easeInOut(duration: 0.2), value: state.toast)
        .tint(state.tint)
    }

    @ViewBuilder
    private var content: some View {
        switch state.panel {
        case .none, .tools:
            KeysView(state: state)
        case .ai:
            AIPanel(state: state)
        case .result:
            ResultPanel(state: state)
        case .clipboard:
            ClipboardPanel(state: state)
        case .macros:
            MacroPanel(state: state)
        case .emoji:
            EmojiPanel(state: state)
        case .dictation:
            DictationPanel(state: state)
        case .settings:
            KeyboardSettingsPanel(state: state)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [state.tint.opacity(scheme == .dark ? 0.22 : 0.12), Color.clear], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Color.clear, state.tint.opacity(scheme == .dark ? 0.12 : 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Toolbar

struct Toolbar: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        HStack(spacing: 6) {
            if state.composeMode {
                composeBar
            } else if state.panel == .none {
                circleButton("sparkles", active: false) { state.toggle(.tools) }
                suggestionBar
                circleButton("mic.fill", active: false) { state.startDictation() }
            } else if state.panel == .tools {
                circleButton("xmark", active: true) { state.toggle(.tools) }
                ToolStrip(state: state)
            } else {
                circleButton("chevron.left", active: true) { state.toggle(state.panel) }
                Text(panelTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if state.panel == .result && state.aiBusy {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private var panelTitle: String {
        switch state.panel {
        case .ai: return "KI-Aktionen"
        case .result: return state.aiTitle
        case .clipboard: return "Zwischenablage"
        case .macros: return "Makros"
        case .emoji: return "Emojis"
        case .dictation: return "Diktat"
        case .settings: return "Schnelleinstellungen"
        default: return ""
        }
    }

    private var suggestionBar: some View {
        HStack(spacing: 4) {
            if state.suggestions.isEmpty {
                Spacer()
                if let profile = state.store.activeProfile {
                    Text("\(profile.emoji) \(profile.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ForEach(state.suggestions) { s in
                    Button { state.pickSuggestion(s) } label: {
                        HStack(spacing: 3) {
                            if s.kind == .ai { Image(systemName: "sparkle").font(.system(size: 9)) }
                            Text(s.display ?? s.text)
                                .font(.system(size: 16, weight: s.kind == .correction ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(s.kind == .typed ? Color.secondary : Color.primary)
                        .background {
                            if s.kind == .correction || s.kind == .macro {
                                Capsule().fill(state.tint.opacity(0.25))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 36)
        .glassCapsule()
    }

    private var composeBar: some View {
        HStack(spacing: 6) {
            circleButton("xmark", active: true) { state.cancelCompose() }
            HStack {
                Image(systemName: "sparkles").foregroundStyle(state.tint)
                Text(state.composeText.isEmpty ? "Was soll die KI schreiben?" : state.composeText)
                    .foregroundStyle(state.composeText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glassCapsule(tint: state.tint.opacity(0.4))
            circleButton("arrow.up", active: true) { state.sendCompose() }
        }
    }

    private func circleButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.primary : state.tint)
                .frame(width: 36, height: 36)
                .glass(cornerRadius: 18, tint: active ? state.tint.opacity(0.35) : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct ToolStrip: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tool("KI", "wand.and.stars") { state.toggle(.ai) }
                tool("Schreiben", "pencil.line") { state.startCompose() }
                tool("Ablage", "doc.on.clipboard") { state.toggle(.clipboard) }
                tool("Makros", "text.badge.star") { state.toggle(.macros) }
                tool("Emoji", "face.smiling") { state.toggle(.emoji) }
                tool("Diktat", "mic") { state.startDictation() }
                tool("Einfügen", "doc.on.doc") { state.pasteCurrent() }
                tool("Optionen", "gearshape") { state.toggle(.settings) }
                tool("Ausblenden", "keyboard.chevron.compact.down") { state.controller?.dismissKeyboard() }
            }
            .padding(.vertical, 2)
        }
    }

    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tasten

struct KeysView: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 6
            let unit = state.layer == .letters ? w / 11 : w / 10
            VStack(spacing: 0) {
                if store.showNumberRow && state.layer == .letters {
                    row(KeyLayouts.numberRow.map { KeyKind.char($0) }, unit: w / 10)
                }
                switch state.layer {
                case .letters:
                    row(KeyLayouts.letters[0].map { KeyKind.char($0) }, unit: unit)
                    row(KeyLayouts.letters[1].map { KeyKind.char($0) }, unit: unit)
                    thirdRow(KeyLayouts.letters[2], total: w, unit: unit, left: .shift)
                case .numbers:
                    row(KeyLayouts.numbers[0].map { KeyKind.char($0) }, unit: unit)
                    row(KeyLayouts.numbers[1].map { KeyKind.char($0) }, unit: unit)
                    thirdRow(KeyLayouts.numbers[2], total: w, unit: w / 7.5, left: .symbols)
                case .symbols:
                    row(KeyLayouts.symbols[0].map { KeyKind.char($0) }, unit: unit)
                    row(KeyLayouts.symbols[1].map { KeyKind.char($0) }, unit: unit)
                    thirdRow(KeyLayouts.symbols[2], total: w, unit: w / 7.5, left: .numbersFromSymbols)
                }
                bottomRow(total: w)
            }
            .padding(.horizontal, 3)
            .padding(.top, 4)
        }
    }

    private func row(_ keys: [KeyKind], unit: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                KeyButton(kind: k, state: state).frame(width: unit)
            }
        }
        .frame(height: state.keyRowHeight)
        .frame(maxWidth: .infinity)
    }

    private func thirdRow(_ chars: [String], total: CGFloat, unit: CGFloat, left: KeyKind) -> some View {
        let side = (total - CGFloat(chars.count) * unit) / 2
        return HStack(spacing: 0) {
            KeyButton(kind: left, state: state).frame(width: max(side - 4, 40))
            Spacer(minLength: 0)
            ForEach(Array(chars.enumerated()), id: \.offset) { _, c in
                KeyButton(kind: .char(c), state: state).frame(width: unit)
            }
            Spacer(minLength: 0)
            KeyButton(kind: .delete, state: state).frame(width: max(side - 4, 40))
        }
        .frame(height: state.keyRowHeight)
    }

    private func bottomRow(total: CGFloat) -> some View {
        HStack(spacing: 0) {
            KeyButton(kind: state.layer == .letters ? .numbers : .letters, state: state)
                .frame(width: total * 0.125)
            if state.needsGlobe {
                KeyButton(kind: .globe, state: state).frame(width: total * 0.1)
            }
            KeyButton(kind: .emoji, state: state).frame(width: total * 0.1)
            KeyButton(kind: .space, state: state)
            KeyButton(kind: .char("."), state: state).frame(width: total * 0.09)
            KeyButton(kind: .returnKey, state: state).frame(width: total * 0.2)
        }
        .frame(height: state.keyRowHeight)
    }
}

enum KeyKind: Equatable {
    case char(String)
    case shift, delete, space, returnKey, numbers, letters, symbols, numbersFromSymbols, globe, emoji
}

struct KeyButton: View {
    let kind: KeyKind
    @ObservedObject var state: KeyboardState
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var longPressFired = false
    @State private var longPressWork: DispatchWorkItem?
    @State private var dragStartX: CGFloat?
    @State private var cursorMode = false
    @State private var lastStep = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.25 : 0.9), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.18), radius: 0.5, y: 1)
            label
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 5)
        .scaleEffect(pressed && isCharacter ? 1.08 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .contentShape(Rectangle())
        .gesture(gesture)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private var isCharacter: Bool {
        if case .char = kind { return true }
        return false
    }

    private var isSpecial: Bool {
        switch kind {
        case .char, .space: return false
        case .returnKey: return false
        default: return true
        }
    }

    private var fill: AnyShapeStyle {
        if case .returnKey = kind, state.returnTitle != "⏎" {
            return AnyShapeStyle(state.tint.opacity(pressed ? 0.6 : 0.85))
        }
        if case .shift = kind, state.shift != .off {
            return AnyShapeStyle(Color.white.opacity(scheme == .dark ? 0.85 : 1))
        }
        let base: Double
        if scheme == .dark {
            base = isSpecial ? 0.10 : 0.22
        } else {
            base = isSpecial ? 0.45 : 0.92
        }
        let color = scheme == .dark ? Color.white : Color.white
        let adjusted = pressed ? (scheme == .dark ? base + 0.2 : base - 0.35) : base
        if scheme == .light && isSpecial {
            return AnyShapeStyle(Color(white: 0.72).opacity(pressed ? 0.95 : 0.75))
        }
        return AnyShapeStyle(color.opacity(adjusted))
    }

    @ViewBuilder
    private var label: some View {
        switch kind {
        case .char(let c):
            Text(displayChar(c))
                .font(.system(size: c.count > 1 ? 16 : 23, weight: .regular))
                .foregroundStyle(.primary)
        case .shift:
            Image(systemName: state.shift == .caps ? "capslock.fill" : (state.shift == .on ? "shift.fill" : "shift"))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(state.shift != .off ? Color.black : Color.primary)
        case .delete:
            Image(systemName: pressed ? "delete.left.fill" : "delete.left")
                .font(.system(size: 18, weight: .medium))
        case .space:
            if cursorMode {
                Image(systemName: "arrow.left.and.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
            } else {
                Text("Leerzeichen").font(.system(size: 15)).foregroundStyle(.secondary)
            }
        case .returnKey:
            if state.returnTitle == "⏎" {
                Image(systemName: "return").font(.system(size: 18, weight: .medium))
            } else {
                Text(state.returnTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
        case .numbers, .numbersFromSymbols:
            Text("123").font(.system(size: 16))
        case .letters:
            Text("ABC").font(.system(size: 16))
        case .symbols:
            Text("#+=").font(.system(size: 16))
        case .globe:
            Image(systemName: "globe").font(.system(size: 18))
        case .emoji:
            Image(systemName: "face.smiling").font(.system(size: 18))
        }
    }

    private func displayChar(_ c: String) -> String {
        if state.layer == .letters, state.shift != .off { return c.uppercased() }
        return c
    }

    private var accessibility: String {
        switch kind {
        case .char(let c): return c
        case .shift: return "Umschalt"
        case .delete: return "Löschen"
        case .space: return "Leerzeichen"
        case .returnKey: return "Zeilenumbruch"
        case .numbers, .numbersFromSymbols: return "Zahlen"
        case .letters: return "Buchstaben"
        case .symbols: return "Symbole"
        case .globe: return "Nächste Tastatur"
        case .emoji: return "Emoji"
        }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !pressed {
                    pressed = true
                    longPressFired = false
                    dragStartX = value.location.x
                    began()
                }
                if case .space = kind { spaceDrag(value) }
            }
            .onEnded { _ in
                pressed = false
                longPressWork?.cancel()
                if !longPressFired && !cursorMode { ended() }
                if case .delete = kind { state.stopDelete() }
                if cursorMode { state.cursorMoveEnded() }
                cursorMode = false
                lastStep = 0
                dragStartX = nil
            }
    }

    private func began() {
        switch kind {
        case .delete:
            longPressFired = true
            state.startDelete()
        case .char(let c):
            let work = DispatchWorkItem {
                if KeyLayouts.alternates[c.lowercased()] != nil {
                    longPressFired = true
                    state.showAlternates(for: c)
                }
            }
            longPressWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        case .globe:
            break
        default:
            break
        }
    }

    private func spaceDrag(_ value: DragGesture.Value) {
        guard let start = dragStartX else { return }
        let dx = value.location.x - start
        if !cursorMode, abs(dx) > 14 {
            cursorMode = true
            state.feedback(.medium)
        }
        if cursorMode {
            let step = Int(dx / 9)
            if step != lastStep {
                state.moveCursor(step - lastStep)
                lastStep = step
            }
        }
    }

    private func ended() {
        switch kind {
        case .char(let c): state.tapKey(c)
        case .shift: state.tapShift()
        case .delete: break
        case .space: state.tapSpace()
        case .returnKey: state.tapReturn()
        case .numbers, .numbersFromSymbols: state.setLayer(.numbers)
        case .letters: state.setLayer(.letters)
        case .symbols: state.setLayer(.symbols)
        case .globe: state.controller?.advanceToNextInputMode()
        case .emoji: state.toggle(.emoji)
        }
    }
}
