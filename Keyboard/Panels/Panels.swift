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
                Label("Kein API-Schlüssel. Öffne die App oder kopiere deinen Schlüssel und tippe hier:", systemImage: "key.fill")
                HStack {
                    Button("Schlüssel einfügen") { state.pasteAPIKey() }
                    Button("App öffnen") { state.openApp("settings") }
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

// MARK: - Schnelleinstellungen

struct KeyboardSettingsPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Profil").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    toggle("Autokorrektur", "textformat.abc.dottedunderline", $store.autocorrect)
                    toggle("KI-Vorschläge", "sparkle", $store.aiSuggestions)
                    toggle("Haptik", "hand.tap", $store.haptics)
                    toggle("Klick-Ton", "speaker.wave.2", $store.keySound)
                    toggle("Tasten-Vorschau", "rectangle.on.rectangle", $store.keyPopups)
                    toggle("Zahlenreihe", "number", $store.showNumberRow)
                    toggle("Makros auto", "bolt", $store.macroAutoExpand)
                    toggle("Live-Antwort", "text.cursor", $store.streamResponses)
                }
                if !store.usesAppGroup || !store.hasAPIKey {
                    Button { state.pasteAPIKey() } label: {
                        Label("API-Schlüssel aus Zwischenablage", systemImage: "key")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .glass(cornerRadius: 12, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                Button { state.openApp("settings") } label: {
                    Label("App öffnen", systemImage: "arrow.up.forward.app")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .glass(cornerRadius: 12, tint: state.tint.opacity(0.4), interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
        .onChange(of: store.showNumberRow) { _, _ in state.onHeightChange?(state.totalHeight) }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 32)
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
