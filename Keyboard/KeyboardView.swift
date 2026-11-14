import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(state: state)
                .frame(height: state.toolbarHeight)
                .zIndex(0)
            content
                .frame(height: state.keysHeight)
                .zIndex(1)
        }
        .background(KeyboardBackgroundView(store: store, scheme: scheme))
        .environment(\.colorScheme, forcedScheme ?? scheme)
        .overlay(alignment: .top) {
            if let toast = state.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule(tint: state.tint.opacity(0.6))
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.snappy(duration: 0.22), value: state.panel)
        .animation(.easeInOut(duration: 0.2), value: state.toast)
        .tint(state.tint)
    }

    @ViewBuilder
    private var content: some View {
        switch state.panel {
        case .none, .tools:
            KeysRepresentable(state: state)
                .transition(.opacity)
        case .ai:
            AIPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .result:
            ResultPanel(state: state).transition(.opacity)
        case .clipboard:
            ClipboardPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .macros:
            MacroPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .emoji:
            EmojiPanel(state: state).transition(.opacity)
        case .settings:
            KeyboardSettingsPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var forcedScheme: ColorScheme? {
        Theme.backgroundIsDark(store).map { $0 ? .dark : .light }
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
                Button { state.toggle(.tools) } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(state.tint)
                        .symbolEffect(.pulse, options: .repeating, isActive: state.aiThinking)
                        .frame(width: 38, height: 38)
                        .glass(cornerRadius: 19, interactive: true, force: true)
                }
                .buttonStyle(.plain)
                suggestionBar
                circleButton("wand.and.stars", active: false) { state.toggle(.ai) }
            } else if state.panel == .tools {
                circleButton("xmark", active: true) { state.toggle(.tools) }
                ToolStrip(state: state)
            } else {
                circleButton("chevron.down", active: true) { state.toggle(state.panel) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(panelTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if state.panel == .result, state.aiBusy {
                        Text(state.aiStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if state.panel == .result && state.aiBusy {
                    Button { state.cancelAI() } label: {
                        Label("Stopp", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .glassCapsule(interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                if state.panel == .ai || state.panel == .clipboard {
                    circleButton("pencil.line", active: false) { state.startCompose() }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 5)
        .padding(.bottom, 2)
    }

    private var panelTitle: String {
        switch state.panel {
        case .ai: return "KI-Aktionen"
        case .result: return state.aiTitle
        case .clipboard: return "Zwischenablage"
        case .macros: return "Makros"
        case .emoji: return "Emojis"
        case .settings: return "Schnelleinstellungen"
        default: return ""
        }
    }

    private var suggestionBar: some View {
        HStack(spacing: 0) {
            if let fix = state.liveFix {
                Button { state.undoLiveFix() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(state.tint)
                        Text(fix.label).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Label("Rückgängig", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if state.suggestions.isEmpty && state.aiPhrase == nil {
                Spacer()
                if let profile = state.store.activeProfile {
                    Text("\(profile.emoji) \(profile.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if state.aiThinking {
                    Text("KI denkt mit …").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { index, s in
                    if index > 0 {
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18)
                    }
                    suggestionButton(s)
                }
                if let phrase = state.aiPhrase {
                    Button { state.pickSuggestion(phrase) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                            Text(phrase.display ?? phrase.text)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Capsule().fill(state.tint.opacity(0.30)).padding(3))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.aiPhrase?.text)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.liveFix)
        .frame(height: 38)
        .glassCapsule(force: true)
    }

    private func suggestionButton(_ s: Suggestion) -> some View {
        Button { state.pickSuggestion(s) } label: {
            HStack(spacing: 3) {
                if s.kind == .ai { Image(systemName: "sparkle").font(.system(size: 9)).foregroundStyle(state.tint) }
                Text(s.display ?? s.text)
                    .font(.system(size: 16, weight: s.kind == .correction ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(s.kind == .typed ? Color.secondary : Color.primary)
            .background {
                if s.kind == .correction || s.kind == .macro {
                    Capsule().fill(state.tint.opacity(0.28)).padding(3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var composeBar: some View {
        HStack(spacing: 6) {
            circleButton("xmark", active: true) { state.cancelCompose() }
            HStack {
                Image(systemName: state.composeIsRefine ? "slider.horizontal.3" : "sparkles").foregroundStyle(state.tint)
                Text(state.composeText.isEmpty ? (state.composeIsRefine ? "Wie soll das Ergebnis geändert werden?" : "Was soll die KI schreiben?") : state.composeText)
                    .foregroundStyle(state.composeText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
                if !state.composeText.isEmpty {
                    Rectangle().fill(state.tint).frame(width: 2, height: 18).opacity(0.8)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .glassCapsule(tint: state.tint.opacity(0.35), force: true)
            circleButton("arrow.up", active: true) { state.sendCompose() }
        }
    }

    private func circleButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.primary : state.tint)
                .frame(width: 38, height: 38)
                .glass(cornerRadius: 19, tint: active ? state.tint.opacity(0.35) : nil, interactive: true, force: true)
        }
        .buttonStyle(.plain)
    }
}

struct ToolStrip: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    tool("KI", "wand.and.stars") { state.toggle(.ai) }
                    tool("Schreiben", "pencil.line") { state.startCompose() }
                    tool("Ablage", "doc.on.clipboard") { state.toggle(.clipboard) }
                    tool("Makros", "text.badge.star") { state.toggle(.macros) }
                    tool("Emoji", "face.smiling") { state.toggle(.emoji) }
                    tool("Einfügen", "doc.on.doc") { state.pasteCurrent() }
                    tool("Alles kopieren", "doc.on.clipboard.fill") { state.copyAll() }
                    tool("Optionen", "gearshape") { state.toggle(.settings) }
                    tool("Ausblenden", "keyboard.chevron.compact.down") { state.controller?.dismissKeyboard() }
                }
                .padding(.vertical, 2)
            }
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
            .frame(height: 36)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
    }
}
