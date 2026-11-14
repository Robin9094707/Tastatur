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
                .frame(height: state.contentHeight)
                .zIndex(1)
        }
        .padding(.horizontal, state.sideInset)
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
        case .stickers:
            StickerPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .cursor:
            CursorPanel(state: state).transition(.opacity)
        case .translate:
            TranslatePanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .commands:
            CommandsPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .discord:
            DiscordPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .check:
            CheckPanel(state: state).transition(.move(edge: .bottom).combined(with: .opacity))
        case .history:
            HistoryPanel(state: state, extras: state.extras).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var forcedScheme: ColorScheme? {
        Theme.backgroundIsDark(store).map { $0 ? .dark : .light }
    }
}

// MARK: - Toolbar

struct Toolbar: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var bar: BarModel
    @Environment(\.colorScheme) private var scheme

    init(state: KeyboardState) {
        _state = ObservedObject(wrappedValue: state)
        _bar = ObservedObject(wrappedValue: state.bar)
    }

    var body: some View {
        HStack(spacing: 6) {
            if state.composeMode {
                composeBar
            } else if state.panel == .none {
                Button { state.toggle(.tools) } label: {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(state.tint)
                        .frame(width: 38, height: 38)
                        .glass(cornerRadius: 19, interactive: true, force: true)
                }
                .buttonStyle(PressableStyle())
                suggestionBar
                if !bar.issues.isEmpty && !bar.offerFixes {
                    Button { state.toggle(.check) } label: {
                        ZStack {
                            Circle().fill(Color.orange.gradient)
                            Text("\(bar.issues.count)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        }
                        .frame(width: 30, height: 30)
                        .frame(width: 34, height: 38)
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.scale.combined(with: .opacity))
                }
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
                    .buttonStyle(PressableStyle())
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
        case .settings: return "Einstellungen"
        case .stickers: return "Sticker"
        case .cursor: return "Cursor & Text"
        case .translate: return "Übersetzen"
        case .commands: return "Befehle"
        case .discord: return "Discord"
        case .history: return "Verlauf & Rückgängig"
        case .check: return bar.issues.isEmpty ? "Textprüfung" : "Textprüfung · \(bar.issues.count) Hinweis\(bar.issues.count == 1 ? "" : "e")"
        default: return ""
        }
    }

    private var suggestionBar: some View {
        Group {
            if bar.offerFixes, !bar.issues.isEmpty, bar.liveFix == nil {
                HStack(spacing: 6) {
                    Button { state.applyAllIssues() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                            Text(bar.issues.count == 1 ? "\(bar.issues[0].original) → \(bar.issues[0].suggestion)" : "\(bar.issues.count) Korrekturen übernehmen")
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(Color.green.gradient))
                    }
                    .buttonStyle(PressableStyle())
                    Button { state.toggle(.check) } label: {
                        Image(systemName: "eye").font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let peek = bar.clip, !bar.clipHidden, bar.liveFix == nil, !(bar.login && peek.kind != .secret) {
                ClipPeekRow(state: state, peek: peek, replies: isReplyOffer)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if bar.login, bar.liveFix == nil {
                LoginRow(state: state)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let offer = bar.offer, bar.liveFix == nil {
                HStack(spacing: 6) {
                    Button { state.performOffer(offer) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: offer.icon)
                            Text(offer.title).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(state.tint.gradient))
                    }
                    .buttonStyle(PressableStyle())
                    Button { state.dismissOffer() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 32)
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let fix = bar.liveFix {
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
                .buttonStyle(PressableStyle())
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if bar.manySuggestions || !bar.phrases.isEmpty {
                // Viele Vorschläge / KI-Sätze: horizontal scrollbar
                WideSuggestions(bar: bar, item: { suggestionButton($0, flexible: false) }, phrase: { phraseButton($0) })
            } else {
                // Klassische iOS-Leiste: drei gleich breite Felder – in UIKit, ohne SwiftUI-Neuberechnung
                SuggestionStrip(state: state, placeholder: placeholderText, tint: state.tint, dark: scheme == .dark)
            }
        }
        .animation(.easeOut(duration: 0.18), value: bar.phrases.map(\.text))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bar.liveFix)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bar.issues.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bar.offerFixes)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bar.offer)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: bar.clip)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: bar.clipHidden)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: bar.login)
        .padding(.trailing, showsThinkButton ? 36 : 0)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { thinkButton }
        .glassCapsule(force: true)
    }

    /// Text in der leeren Leiste (KI-Status oder aktives Profil/App).
    private var placeholderText: String {
        if bar.thinking { return "KI denkt mit …" }
        if bar.checking { return "KI liest deinen Text …" }
        let profile = state.store.activeProfile.map { "\($0.emoji) \($0.name)" }
        let app = state.store.activeApp.map { "\($0.emoji) \($0.name)" }
        return [profile, app].compactMap { $0 }.joined(separator: " · ")
    }

    /// „KI denk mit“ – Vorschläge nur auf Knopfdruck (spart Anfragen).
    /// Eine eigene Zeile (Angebot, Kopiertes, Passwörter) belegt die ganze Leiste.
    private var rowTakesBar: Bool {
        bar.offer != nil || (bar.clip != nil && !bar.clipHidden) || bar.login
    }

    private var showsThinkButton: Bool {
        state.store.aiSuggestMode != "off" && bar.liveFix == nil && !rowTakesBar
    }

    private var isReplyOffer: Bool {
        if case .replies = bar.offer?.kind { return true }
        return false
    }

    @ViewBuilder
    private var thinkButton: some View {
        if showsThinkButton {
            Button { state.predictNow() } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, isActive: bar.thinking)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(state.tint.gradient))
                    .padding(.trailing, 4)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func phraseButton(_ phrase: Suggestion) -> some View {
        Button { state.pickSuggestion(phrase) } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                Text(phrase.display ?? phrase.text)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(state.tint.opacity(0.30)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ViewBuilder
    private func suggestionButton(_ s: Suggestion, flexible: Bool) -> some View {
        let label = Button { state.pickSuggestion(s) } label: {
            HStack(spacing: 3) {
                if s.kind == .ai { Image(systemName: "sparkle").font(.system(size: 9)).foregroundStyle(state.tint) }
                if s.kind == .token { Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 11)).foregroundStyle(state.tint) }
                Text(s.display ?? s.text)
                    .font(.system(size: 16, weight: s.kind == .correction ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(flexible ? 0.6 : 1)
                    .fixedSize(horizontal: !flexible, vertical: false)
            }
            .padding(.horizontal, flexible ? 6 : 10)
            .frame(maxWidth: flexible ? .infinity : nil, maxHeight: .infinity)
            .frame(minWidth: flexible ? nil : 54)
            .foregroundStyle(s.kind == .typed ? Color.secondary : Color.primary)
            .background {
                if s.kind == .correction || s.kind == .macro || s.kind == .token {
                    Capsule().fill(state.tint.opacity(0.28)).padding(3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        label
    }

    @ViewBuilder
    private var composeBar: some View {
        if state.composeTarget == .translate {
            translateBar
        } else if state.composeTarget.isLongText {
            longTextEditor
        } else {
            HStack(spacing: 6) {
                circleButton("xmark", active: true) { state.cancelCompose() }
                HStack {
                    Image(systemName: state.composeTarget.symbol).foregroundStyle(state.tint)
                    Text(state.composeText.isEmpty ? state.composeTarget.placeholder : displayedComposeText)
                        .foregroundStyle(state.composeText.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                    if !state.composeText.isEmpty {
                        Rectangle().fill(state.tint).frame(width: 2, height: 18).opacity(0.8)
                    }
                    if state.composeTarget == .calc, !state.calcResult.isEmpty {
                        Text("= \(state.calcResult)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(state.tint)
                    }
                    if state.composeTarget.isSetting {
                        Button { state.pasteIntoCompose() } label: {
                            Image(systemName: "doc.on.clipboard").font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .glassCapsule(tint: state.tint.opacity(0.35), force: true)
                circleButton(state.composeTarget.isSetting || state.composeTarget == .calc ? "checkmark" : "arrow.up", active: true) { state.sendCompose() }
            }
        }
    }

    /// Großer Editor für lange Texte (Ablage, KI-Regeln, Profile …): Return = neue Zeile, ✓ = speichern.
    private var longTextEditor: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                circleButton("xmark", active: true) { state.cancelCompose() }
                Label(state.composeTarget.placeholder, systemImage: state.composeTarget.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(state.composeText.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                smallButton("doc.on.clipboard") { state.pasteIntoCompose() }
                smallButton("trash") { state.composeText = ""; state.feedback() }
                circleButton("checkmark", active: true) { state.sendCompose() }
            }
            ScrollViewReader { reader in
                ScrollView {
                    (Text(state.composeText.isEmpty ? " " : state.composeText)
                        .foregroundColor(state.composeText.isEmpty ? .secondary : .primary)
                     + Text("▏").foregroundColor(state.tint))
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: state.composeText) { _, _ in reader.scrollTo("end", anchor: .bottom) }
                .onAppear { reader.scrollTo("end", anchor: .bottom) }
            }
            .frame(maxHeight: .infinity)
            .glass(cornerRadius: 14, tint: state.tint.opacity(0.2), force: true)
        }
    }

    private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .glass(cornerRadius: 16, interactive: true, force: true)
        }
        .buttonStyle(PressableStyle())
    }

    /// Zweizeilige Übersetzungsleiste: oben deine Eingabe, unten die Live-Übersetzung.
    private var translateBar: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                circleButton("xmark", active: true) { state.cancelCompose() }
                Button {
                    state.feedback()
                    state.showLanguagePicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(Languages.flag(state.store.translateTarget))
                        Text(state.store.translateTarget).font(.caption.weight(.bold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .glassCapsule(tint: state.tint.opacity(0.4), interactive: true, force: true)
                }
                .buttonStyle(PressableStyle())
                HStack {
                    Text(state.composeText.isEmpty ? "Tippe in deiner Sprache …" : state.composeText)
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
                .glassCapsule(force: true)
            }
            if state.showLanguagePicker {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button { state.showLanguagePicker = false; state.translateClipboard() } label: {
                            Label("Ablage", systemImage: "doc.on.clipboard")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).frame(height: 34)
                                .glassCapsule(interactive: true)
                        }
                        .buttonStyle(PressableStyle())
                        ForEach(Languages.all, id: \.name) { lang in
                            Button { state.setTranslateTarget(lang.name) } label: {
                                Text("\(lang.flag) \(lang.name)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).frame(height: 34)
                                    .foregroundStyle(state.store.translateTarget == lang.name ? Color.white : Color.primary)
                                    .glassCapsule(tint: state.store.translateTarget == lang.name ? state.tint : nil, interactive: true)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 40)
            } else {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: state.translating ? "ellipsis" : "character.bubble.fill")
                            .foregroundStyle(state.tint)
                            .symbolEffect(.pulse, options: .repeating, isActive: state.translating)
                        Text(state.translatePreview.isEmpty ? (state.translating ? "Übersetze …" : "Die Übersetzung erscheint hier") : state.translatePreview)
                            .foregroundStyle(state.translatePreview.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .glassCapsule(tint: state.tint.opacity(0.25), force: true)
                    circleButton("arrow.up", active: true) { state.sendCompose() }
                }
            }
        }
    }

    /// API-Schlüssel nicht im Klartext zeigen.
    private var displayedComposeText: String {
        let t = state.composeText
        if state.composeTarget == .apiKey, t.count > 8 {
            return String(t.prefix(5)) + String(repeating: "•", count: min(12, t.count - 9)) + String(t.suffix(4))
        }
        return t
    }

    private func circleButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.primary : state.tint)
                .frame(width: 38, height: 38)
                .glass(cornerRadius: 19, tint: active ? state.tint.opacity(0.35) : nil, interactive: true, force: true)
        }
        .buttonStyle(PressableStyle())
    }
}

struct ToolStrip: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(store.toolbarItems.compactMap(ToolItem.item), id: \.id) { item in
                        tool(item.title, item.symbol, emoji: item.emoji) { state.runTool(item.id) }
                    }
                    tool("Anpassen", "slider.horizontal.3") {
                        state.settingsPage = .toolbar
                        state.toggle(.settings)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func tool(_ title: String, _ symbol: String, emoji: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let emoji {
                    Text(emoji).font(.system(size: 16))
                } else {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(PressableStyle())
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
