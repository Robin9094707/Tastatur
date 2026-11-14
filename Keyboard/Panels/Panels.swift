import SwiftUI

// MARK: - KI-Aktionen

struct AIPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !state.hasFullAccess || !store.hasAPIKey {
                    MissingSetupBanner(state: state)
                }
                sourcePicker
                quickFormat
                ForEach([ActionCategory.summary, .format, .edit, .tone, .translate, .custom]) { cat in
                    let items = store.actions.filter { $0.enabled && $0.category == cat }
                    if !items.isEmpty {
                        section(cat, items)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var sourcePicker: some View {
        HStack(spacing: 6) {
            Text("Quelle").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            sourceChip("Feld", "text.cursor", .auto)
            sourceChip("Absatz", "paragraphsign", .paragraph)
            sourceChip("Ablage", "doc.on.clipboard", .clipboard)
            Spacer(minLength: 0)
        }
    }

    /// Sofort-Formatierung ohne KI.
    private var quickFormat: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOFORT (OHNE KI)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    formatChip("ABC", "Großbuchstaben") { state.localFormat(.upper) }
                    formatChip("abc", "Kleinbuchstaben") { state.localFormat(.lower) }
                    formatChip("Abc", "Wortanfänge groß") { state.localFormat(.title) }
                    formatChip("Satz.", "Satzanfänge groß") { state.localFormat(.sentence) }
                    formatChip("␣", "Leerzeichen bereinigen") { state.localFormat(.cleanSpaces) }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func formatChip(_ label: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(state.tint)
                Text(title).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func sourceChip(_ title: String, _ symbol: String, _ mode: AIScope) -> some View {
        let selected = state.sourceMode == mode
        return Button {
            state.sourceMode = mode
            state.feedback()
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .glassCapsule(tint: selected ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func section(_ cat: ActionCategory, _ items: [AIAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cat.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                GlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(items) { action in
                            Button { state.runAction(action) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: action.symbol)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(cat == .summary ? Color.white : state.tint)
                                    Text(action.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(cat == .summary ? Color.white : Color.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 13)
                                .frame(height: 40)
                                .glass(cornerRadius: 14, tint: cat == .summary ? state.tint.opacity(0.85) : nil, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
}

struct MissingSetupBanner: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !state.hasFullAccess {
                Label("Aktiviere „Vollen Zugriff erlauben“ in Einstellungen → Allgemein → Tastatur → Tastaturen → Tastatur KI.", systemImage: "lock.fill")
            } else if !state.store.hasAPIKey {
                Label("Kein API-Schlüssel. Füge ihn aus der Zwischenablage ein oder tippe ihn direkt hier ein:", systemImage: "key.fill")
                HStack {
                    Button("Einfügen") { state.pasteAPIKey() }
                    Button("Eintippen") { state.beginInput(.apiKey) }
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 12, tint: .orange.opacity(0.5))
    }
}

// MARK: - Ergebnis

struct ResultPanel: View {
    @ObservedObject var state: KeyboardState
    @State private var shimmer = false
    @State private var diffMode = true

    var body: some View {
        VStack(spacing: 6) {
            resultCard
            if !state.aiBusy, !state.aiResult.isEmpty {
                refineStrip
            }
            actionRow
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .padding(.top, 2)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = state.aiError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    if error.contains("Schlüssel") {
                        Button("Schlüssel aus Zwischenablage einfügen") { state.pasteAPIKey() }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if state.aiResult.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.tint.opacity(shimmer ? 0.38 : 0.12))
                            .frame(height: 11)
                            .frame(maxWidth: i == 3 ? 150 : .infinity, alignment: .leading)
                    }
                    Text(state.aiStatus).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever()) { shimmer = true }
                }
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        resultText
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onChange(of: state.aiResult) { _, _ in
                        if state.aiBusy { reader.scrollTo("end", anchor: .bottom) }
                    }
                }
                statsLine
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(cornerRadius: 16)
    }

    private var resultText: Text {
        if state.aiShowDiff, diffMode, !state.aiBusy, let segs = state.aiDiff {
            var attr = AttributedString()
            for s in segs {
                var part = AttributedString(s.text)
                if s.changed {
                    part.swiftUI.foregroundColor = state.tint
                    part.swiftUI.font = .system(size: 15, weight: .bold)
                }
                attr += part
            }
            return Text(attr)
        }
        return Text(state.aiResult)
    }

    @ViewBuilder
    private var statsLine: some View {
        if !state.aiBusy {
            HStack(spacing: 8) {
                if !state.aiOriginal.isEmpty {
                    Text("\(state.aiOriginal.wordCount) → \(state.aiResult.wordCount) Wörter")
                }
                if state.aiShowDiff, !state.aiOriginal.isEmpty {
                    if state.aiDiff != nil {
                        let changes = state.aiChangeCount
                        Text(changes == 0 ? "✓ Keine Fehler gefunden" : "\(changes) Änderungen markiert")
                    }
                    Spacer()
                    Button(diffMode ? "Markierung aus" : "Markierung an") { diffMode.toggle() }
                } else {
                    Spacer()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var refineStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { state.startCompose(refine: true) } label: {
                    Label("Anpassen …", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .glassCapsule(tint: state.tint.opacity(0.35), interactive: true)
                }
                .buttonStyle(.plain)
                ForEach(AIAction.refinements, id: \.title) { r in
                    Button { state.refine(r.prompt) } label: {
                        Text(r.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .glassCapsule(interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 32)
    }

    private var actionRow: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                let canApply = !state.aiBusy && !state.aiResult.isEmpty
                if replaceAvailable {
                    actionButton("Ersetzen", "arrow.2.squarepath", prominent: true) { state.applyResult(replace: true) }
                        .disabled(!canApply)
                }
                actionButton("Einfügen", "text.insert", prominent: !replaceAvailable) { state.applyResult(replace: false) }
                    .disabled(!canApply)
                actionButton("", "doc.on.doc", prominent: false) { state.copyResult() }
                    .disabled(!canApply)
                    .frame(width: 48)
                actionButton("", "arrow.clockwise", prominent: false) { state.retryAI() }
                    .disabled(state.aiBusy)
                    .frame(width: 48)
            }
        }
    }

    private var replaceAvailable: Bool {
        if case .none = state.replaceTarget { return false }
        return true
    }

    private func actionButton(_ title: String, _ symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                if !title.isEmpty { Text(title) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .glass(cornerRadius: 14, tint: prominent ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Zwischenablage

struct ClipboardPanel: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        Group {
            if !state.hasFullAccess {
                VStack {
                    MissingSetupBanner(state: state).padding(10)
                    Spacer()
                }
            } else if state.clips.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Noch nichts kopiert").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(state.clips) { item in
                            HStack(alignment: .center, spacing: 10) {
                                Button { state.pasteClip(item) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(item.text.prefix(240)))
                                            .font(.system(size: 14))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        HStack(spacing: 4) {
                                            Text(item.date, style: .relative)
                                            Text("· \(item.text.wordCount) Wörter")
                                        }
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if item.text.wordCount > 40 {
                                    Button { state.summarizeClip(item) } label: {
                                        Image(systemName: "text.append").foregroundStyle(state.tint)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button { state.togglePin(item) } label: {
                                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                                        .foregroundStyle(item.pinned ? Color.yellow : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                Button { state.deleteClip(item) } label: {
                                    Image(systemName: "xmark").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .glass(cornerRadius: 12)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}

// MARK: - Makros

struct MacroPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(store.macros) { macro in
                    Button { state.runMacro(macro) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                if macro.isAI { Image(systemName: "sparkles").foregroundStyle(state.tint) }
                                Text(macro.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            }
                            Text(macro.shortcut.isEmpty ? macro.text : "⚡︎ \(macro.shortcut)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .glass(cornerRadius: 12, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                Button { state.openApp("makros") } label: {
                    Label("Bearbeiten", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(4)
                        .glass(cornerRadius: 12, tint: state.tint.opacity(0.3), interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
        }
    }
}

// MARK: - Emoji

struct EmojiPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared
    @State private var selected = "fav"

    private struct Item: Identifiable {
        let id: String
        let emoji: String
    }

    private struct Section {
        let key: String
        let name: String
        let symbol: String
        let emojis: [String]
    }

    private var sections: [Section] {
        var list: [Section] = []
        list.append(Section(key: "fav", name: "Favoriten", symbol: "star.fill", emojis: store.emojiFavorites))
        if !store.emojiRecents.isEmpty {
            list.append(Section(key: "recent", name: "Zuletzt", symbol: "clock", emojis: store.emojiRecents))
        }
        for (i, c) in EmojiCatalog.categories.enumerated() {
            list.append(Section(key: "c\(i)", name: c.name, symbol: c.symbol, emojis: c.emojis))
        }
        return list
    }

    var body: some View {
        let secs = sections
        VStack(spacing: 4) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(secs, id: \.key) { sec in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sec.name.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 6)
                                if sec.emojis.isEmpty {
                                    Text("Halte ein Emoji gedrückt,\num es zu favorisieren ⭐️")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 180, alignment: .leading)
                                        .padding(.leading, 6)
                                        .padding(.top, 8)
                                } else {
                                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(40), spacing: 0), count: 4), spacing: 0) {
                                        ForEach(Array(sec.emojis.enumerated()), id: \.offset) { _, e in
                                            EmojiCell(emoji: e, isFavorite: store.emojiFavorites.contains(e)) {
                                                state.insertEmoji(e)
                                            } onLong: {
                                                state.toggleFavoriteEmoji(e)
                                            }
                                        }
                                    }
                                }
                            }
                            .id(sec.key)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .onChange(of: selected) { _, key in
                    withAnimation(.snappy) { reader.scrollTo(key, anchor: .leading) }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 0) {
                Button { state.toggle(.emoji) } label: {
                    Text("ABC").font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 34)
                }
                .buttonStyle(.plain)
                ForEach(secs, id: \.key) { sec in
                    Button {
                        state.feedback()
                        selected = sec.key
                    } label: {
                        Image(systemName: sec.symbol)
                            .font(.system(size: 14, weight: selected == sec.key ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .foregroundStyle(selected == sec.key ? state.tint : Color.secondary)
                            .background {
                                if selected == sec.key {
                                    Circle().fill(state.tint.opacity(0.18)).frame(width: 30, height: 30)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Button { state.feedback(); state.tapDelete() } label: {
                    Image(systemName: "delete.left").frame(width: 40, height: 34)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .glassCapsule()
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .padding(.top, 4)
    }
}

private struct EmojiCell: View {
    let emoji: String
    let isFavorite: Bool
    let onTap: () -> Void
    let onLong: () -> Void
    @State private var pressed = false

    var body: some View {
        Text(emoji)
            .font(.system(size: 29))
            .frame(width: 42, height: 40)
            .scaleEffect(pressed ? 1.3 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .contentShape(Rectangle())
            .onTapGesture {
                pressed = true
                onTap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                onLong()
            }
    }
}

// MARK: - Einstellungen (komplett in der Tastatur)

struct KeyboardSettingsPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        VStack(spacing: 0) {
            if state.settingsPage != .main {
                HStack {
                    Button {
                        state.feedback()
                        state.settingsPage = .main
                    } label: {
                        Label("Einstellungen", systemImage: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(pageTitle).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch state.settingsPage {
                    case .main: mainPage
                    case .ai: aiPage
                    case .context: contextPage
                    case .design: designPage
                    case .typing: typingPage
                    case .macros: macrosPage
                    case .actions: actionsPage
                    case .toolbar: toolbarPage
                    }
                }
                .padding(10)
            }
        }
        .onChange(of: store.showNumberRow) { _, _ in state.onHeightChange?(state.totalHeight) }
    }

    private var pageTitle: String {
        switch state.settingsPage {
        case .main: return ""
        case .ai: return "KI & API"
        case .context: return "Kontext & Profile"
        case .design: return "Design"
        case .typing: return "Tippen"
        case .macros: return "Makros"
        case .actions: return "KI-Aktionen"
        case .toolbar: return "Schnellleiste"
        }
    }

    // MARK: Seiten

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.usesAppGroup {
                Label("App Group nicht verfügbar – alle Einstellungen werden direkt hier in der Tastatur gespeichert.", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Profil").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            profileChips
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                navTile("KI & API", "key.fill", store.hasAPIKey ? "Verbunden" : "Schlüssel fehlt", .ai)
                navTile("Kontext", "person.text.rectangle", store.personalContext.isEmpty ? "Leer" : "Aktiv", .context)
                navTile("Design", "paintbrush.pointed", (KeyStyle(rawValue: store.keyStyle) ?? .glass).label, .design)
                navTile("Tippen", "keyboard", store.autocorrect ? "Autokorrektur an" : "Autokorrektur aus", .typing)
                navTile("Makros", "text.badge.star", "\(store.macros.count) Makros", .macros)
                navTile("KI-Aktionen", "wand.and.stars", "\(store.actions.filter(\.enabled).count) aktiv", .actions)
                navTile("Schnellleiste", "rectangle.grid.1x2", "\(store.toolbarItems.count) Werkzeuge", .toolbar)
            }
            HStack {
                actionButton("Text kopieren", "doc.on.doc") { state.copyAll() }
                actionButton("App öffnen", "arrow.up.forward.app") { state.openApp("settings") }
            }
        }
    }

    private var aiPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("API-Schlüssel", store.hasAPIKey ? maskedKey : "Nicht gesetzt", "key.fill") {
                state.beginInput(.apiKey, prefill: "")
            }
            HStack {
                actionButton("Aus Ablage einfügen", "doc.on.clipboard") { state.pasteAPIKey() }
                if store.hasAPIKey {
                    actionButton("Entfernen", "trash") { store.apiKey = ""; state.showToast("API-Schlüssel entfernt") }
                }
            }
            Text("Modell").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SharedStore.fallbackModels, id: \.self) { m in
                        chip(m, selected: store.chatModel == m) {
                            store.chatModel = m
                            store.fastModel = m
                        }
                    }
                    chip("Eigenes …", selected: !SharedStore.fallbackModels.contains(store.chatModel)) {
                        state.beginInput(.chatModel, prefill: store.chatModel)
                    }
                }
            }
            grid {
                toggle("Live-Korrektur", "checkmark.seal", $store.liveAICorrection)
                toggle("Live-Antwort", "text.cursor", $store.streamResponses)
                toggle("Umfeld senden", "text.viewfinder", $store.useAppContext)
            }
            Text("KI-Vorschläge in der Leiste").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("Auf Knopfdruck ✨", selected: store.aiSuggestMode == "manual") { store.aiSuggestMode = "manual" }
                chip("Gelegentlich", selected: store.aiSuggestMode == "occasional") { store.aiSuggestMode = "occasional" }
                chip("Aus", selected: store.aiSuggestMode == "off") { store.aiSuggestMode = "off" }
            }
            Text("Antwortsprache").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("Wie Original", selected: store.outputLanguage == "auto") { store.outputLanguage = "auto" }
                chip("Deutsch", selected: store.outputLanguage == "Deutsch") { store.outputLanguage = "Deutsch" }
                chip("Englisch", selected: store.outputLanguage == "Englisch") { store.outputLanguage = "Englisch" }
            }
            row("API-Adresse", store.baseURL, "server.rack") { state.beginInput(.baseURL, prefill: store.baseURL) }
        }
    }

    private var contextPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Über mich", store.personalContext.isEmpty ? "Tippen zum Ausfüllen" : store.personalContext, "person.crop.circle") {
                state.beginInput(.personalContext, prefill: store.personalContext)
            }
            row("Schreibstil", store.writingStyle.isEmpty ? "Tippen zum Ausfüllen" : store.writingStyle, "pencil.and.scribble") {
                state.beginInput(.writingStyle, prefill: store.writingStyle)
            }
            Text("Profile").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            profileChips
            ForEach(store.profiles) { p in
                HStack {
                    Text("\(p.emoji) \(p.name)").font(.footnote.weight(.semibold))
                    Text(p.context).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { state.beginInput(.profileContext(p.id), prefill: p.context) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain)
                    Button { store.profiles.removeAll { $0.id == p.id } } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
                .padding(8)
                .glass(cornerRadius: 10)
            }
            actionButton("Neues Profil", "plus") { state.beginInput(.profileName) }
        }
    }

    private var designPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Themes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { state.randomTheme() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "dice.fill").font(.title2).foregroundStyle(state.tint)
                                .frame(width: 70, height: 48)
                                .glass(cornerRadius: 10, interactive: true)
                            Text("Überrasch mich").font(.system(size: 9, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(ThemePreset.all) { t in
                        Button {
                            state.feedback()
                            t.apply(to: store)
                        } label: {
                            VStack(spacing: 3) {
                                ThemeThumbnail(theme: t)
                                    .frame(width: 70, height: 48)
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(.white, lineWidth: store.themeID == t.id ? 2.5 : 0))
                                Text(t.name).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                actionButton("Bild aus Zwischenablage", "photo.on.rectangle") { state.setBackgroundFromClipboard() }
                if store.backgroundStyle == "image" {
                    actionButton("Bild entfernen", "xmark") { store.backgroundStyle = "system" }
                }
            }
            if store.backgroundStyle == "image" {
                stepper("Abdunkeln", "\(Int(store.backgroundDim * 100)) %",
                        minus: { store.backgroundDim = max(0, store.backgroundDim - 0.1) },
                        plus: { store.backgroundDim = min(0.8, store.backgroundDim + 0.1) })
            }
            Text("Tastenstil").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(KeyStyle.allCases) { k in
                        chip(k.label, selected: store.keyStyle == k.rawValue) { store.keyStyle = k.rawValue; store.themeID = "" }
                    }
                }
            }
            Text("Hintergrund").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("System", selected: store.backgroundStyle == "system") { store.backgroundStyle = "system" }
                    ForEach(Array(Theme.backgroundPresets.enumerated()), id: \.offset) { i, p in
                        Button {
                            store.backgroundStyle = "gradient"
                            store.backgroundPreset = i
                            store.themeID = ""
                        } label: {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white, lineWidth: store.backgroundStyle == "gradient" && store.backgroundPreset == i ? 2.5 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Akzentfarbe").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Array(Theme.tints.enumerated()), id: \.offset) { i, t in
                    Button { store.keyboardTint = i } label: {
                        Circle().fill(t.color).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white, lineWidth: store.keyboardTint == i ? 2.5 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Schrift").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("Standard", selected: store.keyFontDesign == "default") { store.keyFontDesign = "default" }
                chip("Rund", selected: store.keyFontDesign == "rounded") { store.keyFontDesign = "rounded" }
                chip("Serif", selected: store.keyFontDesign == "serif") { store.keyFontDesign = "serif" }
                chip("Mono", selected: store.keyFontDesign == "mono") { store.keyFontDesign = "mono" }
            }
            stepper("Deckkraft", "\(Int(store.keyOpacity * 100)) %",
                    minus: { store.keyOpacity = max(0.2, store.keyOpacity - 0.1) },
                    plus: { store.keyOpacity = min(1, store.keyOpacity + 0.1) })
            stepper("Ecken", "\(Int(store.keyCornerRadius)) pt",
                    minus: { store.keyCornerRadius = max(2, store.keyCornerRadius - 2) },
                    plus: { store.keyCornerRadius = min(20, store.keyCornerRadius + 2) })
            stepper("Schriftgröße", "\(Int(store.keyFontScale * 100)) %",
                    minus: { store.keyFontScale = max(0.8, store.keyFontScale - 0.05) },
                    plus: { store.keyFontScale = min(1.3, store.keyFontScale + 0.05) })
        }
    }

    private var typingPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            typingToggles
            LearnedTokensView(state: state)
        }
    }

    private var typingToggles: some View {
        grid {
            toggle("Autokorrektur", "textformat.abc.dottedunderline", $store.autocorrect)
            toggle("Trefferzonen", "hand.point.up.braille", $store.smartTouch)
            toggle("Großschreibung", "textformat.size.larger", $store.autocapitalize)
            toggle("Doppel-Leer = .", "circle.fill", $store.doubleSpacePeriod)
            toggle("Wörter lernen", "brain", $store.learnWords)
            toggle("Zahlenreihe", "number", $store.showNumberRow)
            toggle("Tasten-Vorschau", "rectangle.on.rectangle", $store.keyPopups)
            toggle("Haptik", "hand.tap", $store.haptics)
            toggle("Klick-Ton", "speaker.wave.2", $store.keySound)
            toggle("Makros auto", "bolt", $store.macroAutoExpand)
            toggle("Ablage-Verlauf", "clock.arrow.circlepath", $store.clipboardEnabled)
        }
    }

    private var macrosPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButton("Neues Makro", "plus") { state.beginInput(.macroShortcut) }
            ForEach(store.macros) { m in
                HStack {
                    Text(m.shortcut.isEmpty ? "–" : m.shortcut)
                        .font(.caption.monospaced().weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .glassCapsule(tint: state.tint.opacity(0.3))
                    Text(m.text).font(.caption).lineLimit(1)
                    Spacer()
                    Button { store.macros.removeAll { $0.id == m.id } } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .glass(cornerRadius: 10)
            }
        }
    }

    private var actionsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionButton("Eigene KI-Aktion", "plus") { state.beginInput(.actionTitle) }
            ForEach(store.actions) { a in
                HStack {
                    Image(systemName: a.symbol).foregroundStyle(state.tint).frame(width: 20)
                    Text(a.title).font(.footnote.weight(.semibold))
                    Text(a.category.label).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if !a.builtIn {
                        Button { store.actions.removeAll { $0.id == a.id } } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        if let i = store.actions.firstIndex(where: { $0.id == a.id }) { store.actions[i].enabled.toggle() }
                        state.feedback()
                    } label: {
                        Image(systemName: a.enabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(a.enabled ? state.tint : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .glass(cornerRadius: 10)
            }
            Button("Standard-Aktionen wiederherstellen") {
                store.actions = AIAction.defaults + store.actions.filter { !$0.builtIn }
            }
            .font(.caption)
        }
    }

    private var toolbarPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aktiv – in dieser Reihenfolge").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(store.toolbarItems.enumerated()), id: \.element) { index, id in
                if let item = ToolItem.item(id) {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).foregroundStyle(state.tint).frame(width: 22)
                        Text(item.title).font(.footnote.weight(.semibold))
                        Spacer()
                        Button { moveTool(index, -1) } label: { Image(systemName: "chevron.up.circle.fill") }
                            .buttonStyle(.plain).disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                        Button { moveTool(index, 1) } label: { Image(systemName: "chevron.down.circle.fill") }
                            .buttonStyle(.plain).disabled(index == store.toolbarItems.count - 1).opacity(index == store.toolbarItems.count - 1 ? 0.3 : 1)
                        Button {
                            store.toolbarItems.removeAll { $0 == id }
                            state.feedback()
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain)
                    }
                    .font(.title3)
                    .padding(8)
                    .glass(cornerRadius: 10)
                }
            }
            let hidden = ToolItem.all.filter { !store.toolbarItems.contains($0.id) }
            if !hidden.isEmpty {
                Text("Verfügbar").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(hidden) { item in
                    Button {
                        store.toolbarItems.append(item.id)
                        state.feedback()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).frame(width: 22)
                            Text(item.title).font(.footnote.weight(.semibold))
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
                        .padding(8)
                        .glass(cornerRadius: 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Standard wiederherstellen") { store.toolbarItems = ToolItem.defaultOrder }
                .font(.caption)
        }
    }

    private func moveTool(_ index: Int, _ delta: Int) {
        var items = store.toolbarItems
        let target = index + delta
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        items.swapAt(index, target)
        store.toolbarItems = items
        state.feedback()
    }

    // MARK: Bausteine

    private var maskedKey: String {
        let k = store.apiKey
        guard k.count > 10 else { return "••••" }
        return String(k.prefix(5)) + "••••" + String(k.suffix(4))
    }

    private var profileChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Keins", selected: store.activeProfileID.isEmpty) { state.setProfile("") }
                ForEach(store.profiles) { p in
                    chip("\(p.emoji) \(p.name)", selected: store.activeProfileID == p.id.uuidString) {
                        state.setProfile(p.id.uuidString)
                    }
                }
            }
        }
    }

    private func navTile(_ title: String, _ symbol: String, _ subtitle: String, _ page: KeyboardState.SettingsPage) -> some View {
        Button {
            state.feedback()
            state.settingsPage = page
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(state.tint).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.footnote.weight(.semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .glass(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, _ value: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(state.tint).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.footnote.weight(.semibold))
                    Text(value).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .glass(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            content()
        }
    }

    private func stepper(_ title: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.footnote.weight(.medium))
            Spacer()
            Button { minus(); state.feedback() } label: { Image(systemName: "minus.circle.fill").font(.title3) }
                .buttonStyle(.plain)
            Text(value).font(.caption.monospacedDigit()).frame(width: 50)
            Button { plus(); state.feedback() } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                .buttonStyle(.plain)
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .glass(cornerRadius: 12)
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .glass(cornerRadius: 12, tint: state.tint.opacity(0.3), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            state.feedback()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .glassCapsule(tint: selected ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ title: String, _ symbol: String, _ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle(); state.feedback() } label: {
            HStack {
                Image(systemName: symbol)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: binding.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(binding.wrappedValue ? state.tint : Color.secondary)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .glass(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

/// Gelernte persönliche Einträge (E-Mails, Links, Nummern) – mit Löschen.
struct LearnedTokensView: View {
    @ObservedObject var state: KeyboardState
    @State private var items: [(String, Int)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gelernte Einträge").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Noch nichts gelernt. E-Mail-Adressen, Links und Nummern, die du öfter tippst, erscheinen hier und werden vorgeschlagen.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(items.prefix(30).enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.0).font(.caption).lineLimit(1)
                    Spacer()
                    Text("\(item.1)×").font(.caption2).foregroundStyle(.secondary)
                    Button {
                        state.engine.forgetToken(item.0)
                        items = state.engine.allTokens
                    } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .glass(cornerRadius: 10)
            }
        }
        .onAppear { items = state.engine.allTokens }
    }
}

// MARK: - Sticker

struct StickerPanel: View {
    @ObservedObject var state: KeyboardState
    @State private var thumbs: [URL: UIImage] = [:]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                Button { state.addStickerFromClipboard() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.title2.weight(.semibold))
                        Text("Aus Ablage").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(state.tint)
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .glass(cornerRadius: 14, interactive: true)
                }
                .buttonStyle(.plain)
                ForEach(state.stickers, id: \.self) { url in
                    StickerCell(url: url, image: thumbs[url]) {
                        state.copySticker(url)
                    } onDelete: {
                        state.deleteSticker(url)
                    }
                    .onAppear {
                        if thumbs[url] == nil {
                            DispatchQueue.global(qos: .userInitiated).async {
                                let img = StickerStore.thumbnail(url)
                                DispatchQueue.main.async { thumbs[url] = img }
                            }
                        }
                    }
                }
            }
            .padding(8)
            if state.stickers.isEmpty {
                Text("Noch keine Sticker. Kopiere ein Bild und tippe auf „Aus Ablage“ – oder lege in der App Sticker mit automatischem Freistellen an.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            } else {
                Text("Tippen = kopieren, dann im Chat einfügen · Gedrückt halten = löschen")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        }
        .onAppear { state.reloadStickers() }
    }
}

private struct StickerCell: View {
    let url: URL
    let image: UIImage?
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var confirm = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74)
            .padding(4)
            .glass(cornerRadius: 14, interactive: true)
            .onTapGesture {
                if confirm { onDelete() } else { onTap() }
                confirm = false
            }
            .onLongPressGesture(minimumDuration: 0.45) { confirm = true }
            if confirm {
                Image(systemName: "trash.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .red)
                    .padding(2)
            }
        }
    }
}

// MARK: - Cursor & Text

struct CursorPanel: View {
    @ObservedObject var state: KeyboardState
    @State private var lastStep = 0

    var body: some View {
        VStack(spacing: 8) {
            // Trackpad: wischen bewegt den Cursor
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                VStack(spacing: 4) {
                    Image(systemName: "hand.draw").font(.title2).foregroundStyle(state.tint)
                    Text("Wischen bewegt den Cursor").font(.caption).foregroundStyle(.secondary)
                }
            }
            .glass(cornerRadius: 18)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        let step = Int(v.translation.width / 9) + Int(v.translation.height / 18) * 12
                        if step != lastStep {
                            state.moveCursor(step - lastStep)
                            lastStep = step
                        }
                    }
                    .onEnded { _ in lastStep = 0; state.cursorMoveEnded() }
            )
            HStack(spacing: 6) {
                key("arrow.left.to.line", "Anfang") { state.cursorAction(.start) }
                key("chevron.left.2", "Wort") { state.cursorAction(.wordLeft) }
                key("chevron.left", "") { state.cursorAction(.left) }
                key("chevron.right", "") { state.cursorAction(.right) }
                key("chevron.right.2", "Wort") { state.cursorAction(.wordRight) }
                key("arrow.right.to.line", "Ende") { state.cursorAction(.end) }
            }
            HStack(spacing: 6) {
                key("delete.left", "Wort löschen") { state.cursorAction(.deleteWord) }
                key("doc.on.doc", "Alles kopieren") { state.copyAll() }
                key("doc.on.clipboard", "Einfügen") { state.pasteCurrent() }
                key("keyboard", "Tasten") { state.toggle(.cursor) }
            }
        }
        .padding(8)
    }

    private func key(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                if !title.isEmpty { Text(title).font(.system(size: 9, weight: .semibold)).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .glass(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
