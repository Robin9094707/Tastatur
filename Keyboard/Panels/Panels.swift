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
                AppPicker(state: state)
                sourcePicker
                let appActions = store.actions.filter { $0.enabled && !$0.apps.isEmpty && $0.fits(store.activeApp) }
                if let app = store.activeApp, !appActions.isEmpty {
                    section(title: "FÜR \(app.name.uppercased()) \(app.emoji)", highlight: true, appActions)
                }
                quickFormat
                ForEach([ActionCategory.summary, .format, .edit, .tone, .translate, .custom]) { cat in
                    let items = store.actions.filter { $0.enabled && $0.category == cat && $0.apps.isEmpty }
                    if !items.isEmpty {
                        section(title: cat.label.uppercased(), highlight: cat == .summary, items)
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

    private func section(title: String, highlight: Bool, _ items: [AIAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
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
                                        .foregroundStyle(highlight ? Color.white : state.tint)
                                    Text(action.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(highlight ? Color.white : Color.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 13)
                                .frame(height: 40)
                                .glass(cornerRadius: 14, tint: highlight ? state.tint.opacity(0.85) : nil, interactive: true)
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

/// Auswahl der Ziel-App (iOS verrät sie ab 26.4 nicht mehr automatisch).
struct AppPicker: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Für").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                chip(store.detectedApp.isEmpty ? "Auto" : "Auto: \(AppProfiles.profile(store.detectedApp)?.name ?? "")", "auto")
                chip("Keine", "none")
                ForEach(AppProfiles.all) { p in chip("\(p.emoji) \(p.name)", p.id) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ title: String, _ id: String) -> some View {
        let selected = store.appProfile == id
        return Button { state.setAppProfile(id) } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .glassCapsule(tint: selected ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct MissingSetupBanner: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !state.hasFullAccess {
                Label("Aktiviere „Vollen Zugriff erlauben“ in Einstellungen → Allgemein → Tastatur → Tastaturen → Tastatur KI.", systemImage: "lock.fill")
            } else if !state.store.hasAPIKey {
                Label("Kein KI-Zugang. Melde dich mit deinem ChatGPT-Abo an oder füge einen API-Schlüssel ein:", systemImage: "key.fill")
                HStack {
                    Button("ChatGPT") { state.openApp("chatgpt-login") }
                    Button("Code") { state.pasteChatGPTCode() }
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
                if state.lastResultIsCommand {
                    Button { state.saveResultAsCommands() } label: {
                        Label("Als Befehl speichern", systemImage: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .glassCapsule(tint: state.tint.opacity(0.5), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
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
    @ObservedObject var store = SharedStore.shared
    @State private var confirmDeleteID: UUID?
    @State private var confirmFolder: String?
    @State private var confirmClear = false

    var body: some View {
        Group {
            if !state.hasFullAccess {
                VStack {
                    MissingSetupBanner(state: state).padding(10)
                    Spacer()
                }
            } else {
                VStack(spacing: 5) {
                    folderBar
                    actionBar
                    if let folder = confirmFolder { folderConfirm(folder) }
                    if confirmClear { clearConfirm }
                    list
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
    }

    // MARK: Ordner

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("Alle", "tray.full", "", count: state.clips.count)
                filterChip("Angeheftet", "pin.fill", "★", count: state.clips.filter(\.pinned).count)
                filterChip("Verlauf", "clock", "⏱", count: state.clips.filter { $0.folder == nil }.count)
                ForEach(store.clipFolders, id: \.self) { f in
                    filterChip(f, "folder.fill", f, count: state.clips.filter { $0.folder == f }.count)
                        .contextMenu {
                            Button { state.beginInput(.clipFolderRename(f), prefill: f) } label: { Label("Umbenennen", systemImage: "pencil") }
                            Button(role: .destructive) { confirmFolder = f } label: { Label("Ordner löschen …", systemImage: "trash") }
                        }
                }
                Button { state.beginInput(.clipFolderNew) } label: {
                    Label("Ordner", systemImage: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .glassCapsule(tint: state.tint.opacity(0.25), interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(_ title: String, _ symbol: String, _ key: String, count: Int) -> some View {
        let selected = state.clipFilter == key
        return Button { state.setClipFilter(key) } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).lineLimit(1)
                Text("\(count)").font(.system(size: 10, weight: .bold).monospacedDigit()).opacity(0.7)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .glassCapsule(tint: selected ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: Aktionen

    private var actionBar: some View {
        HStack(spacing: 6) {
            barButton("Neu", "plus") { state.beginInput(.clipNew) }
            barButton("Feld sichern", "square.and.arrow.down") { state.saveFieldAsClip() }
            if state.clipQuery.isEmpty {
                barButton("Suchen", "magnifyingglass") { state.beginInput(.clipSearch) }
            } else {
                Button { state.clipQuery = ""; state.feedback() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("„\(state.clipQuery)“").lineLimit(1)
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .glassCapsule(tint: state.tint, interactive: true)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button { confirmClear = true; state.feedback() } label: {
                Image(systemName: "trash.slash").font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32).glass(cornerRadius: 16, interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func barButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: Bestätigungen

    private func folderConfirm(_ f: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ordner „\(f)“ löschen?").font(.footnote.weight(.semibold))
            HStack(spacing: 6) {
                confirmButton("Abbrechen", nil) { confirmFolder = nil }
                confirmButton("Inhalt behalten", .orange) { state.deleteFolder(f, keepItems: true); confirmFolder = nil }
                confirmButton("Alles löschen", .red) { state.deleteFolder(f, keepItems: false); confirmFolder = nil }
            }
        }
        .padding(9)
        .glass(cornerRadius: 12, tint: .red.opacity(0.25))
    }

    private var clearConfirm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verlauf leeren? Angeheftetes und Ordner bleiben erhalten.").font(.footnote.weight(.semibold))
            HStack(spacing: 6) {
                confirmButton("Abbrechen", nil) { confirmClear = false }
                confirmButton("Verlauf leeren", .red) { state.clearHistory(); confirmClear = false }
            }
        }
        .padding(9)
        .glass(cornerRadius: 12, tint: .red.opacity(0.25))
    }

    private func confirmButton(_ title: String, _ color: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color == nil ? Color.primary : Color.white)
                .frame(maxWidth: .infinity, minHeight: 32)
                .glass(cornerRadius: 10, tint: color, interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: Liste

    @ViewBuilder
    private var list: some View {
        let items = state.visibleClips
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: state.clipQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.title).foregroundStyle(.secondary)
                Text(state.clipQuery.isEmpty ? (state.clipFilter.isEmpty ? "Noch nichts kopiert" : "Hier ist noch nichts") : "Nichts gefunden")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !state.clipQuery.isEmpty || !state.clipFilter.isEmpty {
                    Text("Mit „Neu“ legst du Einträge an, über ⋯ verschiebst du sie in Ordner.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(items) { item in
                        if confirmDeleteID == item.id {
                            HStack(spacing: 6) {
                                Text("Wirklich löschen?").font(.footnote.weight(.semibold))
                                Spacer(minLength: 0)
                                confirmButton("Abbrechen", nil) { confirmDeleteID = nil }.frame(width: 100)
                                confirmButton("Löschen", .red) { state.deleteClip(item); confirmDeleteID = nil }.frame(width: 90)
                            }
                            .padding(10)
                            .glass(cornerRadius: 12, tint: .red.opacity(0.25))
                        } else {
                            row(item)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button { state.pasteClip(item) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = item.title, !title.isEmpty {
                        Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    }
                    Text(String(item.text.prefix(400)))
                        .font(.system(size: 14))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        if let f = item.folder { Label(f, systemImage: "folder.fill").labelStyle(.titleAndIcon) }
                        Text(item.date, style: .relative)
                        Text("· \(item.text.wordCount) Wörter")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { state.togglePin(item) } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.pinned ? Color.yellow : Color.secondary)
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
            Menu {
                Button { state.pasteClip(item) } label: { Label("Einfügen", systemImage: "text.insert") }
                Button { state.copyClip(item) } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                Button { state.beginInput(.clipEdit(item.id), prefill: item.text) } label: { Label("Bearbeiten", systemImage: "pencil") }
                Button { state.beginInput(.clipRename(item.id), prefill: item.title ?? "") } label: { Label("Umbenennen", systemImage: "character.cursor.ibeam") }
                Menu {
                    Button { state.moveClip(item, to: nil) } label: { Label("Kein Ordner", systemImage: item.folder == nil ? "checkmark" : "tray") }
                    ForEach(store.clipFolders, id: \.self) { f in
                        Button { state.moveClip(item, to: f) } label: { Label(f, systemImage: item.folder == f ? "checkmark" : "folder") }
                    }
                    Button { state.beginInput(.clipFolderNew) } label: { Label("Neuer Ordner …", systemImage: "folder.badge.plus") }
                } label: { Label("In Ordner", systemImage: "folder") }
                Button { state.summarizeClip(item) } label: { Label("Zusammenfassen", systemImage: "text.append") }
                Button { state.translateClipItem(item) } label: { Label("Übersetzen (\(store.translateTarget))", systemImage: "character.bubble") }
                Button(role: .destructive) { confirmDeleteID = item.id } label: { Label("Löschen …", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(state.tint)
                    .frame(width: 30, height: 30)
            }
            Button { confirmDeleteID = item.id; state.feedback() } label: {
                Image(systemName: "trash").foregroundStyle(.secondary).frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .glass(cornerRadius: 12)
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
                                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(40), spacing: 0), count: state.keysHeight < 200 ? 2 : 4), spacing: 0) {
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
                navTile("KI & API", "key.fill", store.usesChatGPT ? "ChatGPT-Abo" : (store.hasKey ? "API-Schlüssel" : "Nicht verbunden"), .ai)
                navTile("Kontext & Lernen", "brain.head.profile", store.contextCheck == "off" ? "Prüfung aus" : (store.contextCheck == "intense" ? "Prüfung intensiv" : "Prüfung normal"), .context)
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
            Text("KI-Zugang").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("ChatGPT-Abo", selected: store.aiProvider == "chatgpt") {
                    if store.chatgptAccount.isEmpty { state.openApp("chatgpt-login") } else { store.aiProvider = "chatgpt" }
                }
                chip("API-Schlüssel", selected: store.aiProvider != "chatgpt") { store.aiProvider = "apikey" }
            }
            if store.aiProvider == "chatgpt" || !store.chatgptAccount.isEmpty {
                if store.chatgptAccount.isEmpty {
                    row("ChatGPT", "Nicht angemeldet – tippen zum Anmelden", "person.crop.circle.badge.plus") { state.openApp("chatgpt-login") }
                } else {
                    row("ChatGPT", store.chatgptAccount, "person.crop.circle.badge.checkmark") { state.openApp("chatgpt-login") }
                }
                if store.usesChatGPT {
                    HStack {
                        Text("Modell (Abo)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(store.chatgptModel.isEmpty ? ChatGPTAuth.defaultModel : store.chatgptModel)
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                        ForEach(store.chatgptModels, id: \.self) { m in
                            Button { store.chatgptModel = m[0]; state.feedback() } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.count > 1 ? m[1] : m[0]).font(.caption.weight(.semibold)).lineLimit(1)
                                    if m.count > 1, m[1] != m[0] {
                                        Text(m[0]).font(.system(size: 9).monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                .foregroundStyle(store.chatgptModel == m[0] ? Color.white : Color.primary)
                                .glass(cornerRadius: 10, tint: store.chatgptModel == m[0] ? state.tint : nil, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 6) {
                        chip(state.loadingModels ? "Lade …" : (store.chatgptModels.isEmpty ? "Modelle laden" : "Aktualisieren"), selected: false) {
                            state.refreshChatGPTModels()
                        }
                        chip("Eigenes …", selected: !store.chatgptModels.contains { $0.first == store.chatgptModel }) {
                            state.beginInput(.chatModel, prefill: store.chatgptModel)
                        }
                    }
                    .onAppear { if store.chatgptModels.isEmpty { state.refreshChatGPTModels(silent: true) } }
                }
                actionButton("Kopplungscode einfügen", "link") { state.pasteChatGPTCode() }
                Text("In der App anmelden → „Code kopieren“ → hier einfügen (passiert auch automatisch beim Öffnen der Tastatur).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if store.aiProvider != "chatgpt" {
            row("API-Schlüssel", store.hasStoredKey ? (store.apiKeyEnabled ? maskedKey : "Deaktiviert · \(maskedKey)") : "Nicht gesetzt", "key.fill") {
                state.beginInput(.apiKey, prefill: "")
            }
            HStack {
                actionButton("Aus Ablage einfügen", "doc.on.clipboard") { state.pasteAPIKey() }
                if store.hasStoredKey {
                    actionButton(store.apiKeyEnabled ? "Deaktivieren" : "Aktivieren", store.apiKeyEnabled ? "pause.circle" : "play.circle") {
                        store.apiKeyEnabled.toggle()
                        state.showToast(store.apiKeyEnabled ? "API-Schlüssel aktiviert ✓" : "API-Schlüssel deaktiviert")
                    }
                    actionButton("Löschen", "trash") { store.deleteAPIKey(); state.showToast("API-Schlüssel gelöscht") }
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
            }
            Text("Denkaufwand").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("Schnell", selected: store.reasoningEffort == "low" || store.reasoningEffort == "minimal") { store.reasoningEffort = "low" }
                chip("Mittel", selected: store.reasoningEffort == "medium") { store.reasoningEffort = "medium" }
                chip("Gründlich", selected: store.reasoningEffort == "high") { store.reasoningEffort = "high" }
            }
            Text("KI-Korrektur").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("Am Ende ✓", selected: store.aiCorrectMode == "end") { store.aiCorrectMode = "end" }
                chip("Wort für Wort", selected: store.aiCorrectMode == "word") { store.aiCorrectMode = "word"; store.liveAICorrection = true }
                chip("Aus", selected: store.aiCorrectMode == "off") { store.aiCorrectMode = "off" }
            }
            Text(store.aiCorrectMode == "end" ? "Du tippst ungestört. Sobald du kurz pausierst, liest die KI den ganzen Text und korrigiert ihn direkt – mit Rückgängig. Jederzeit auch über „Korrigieren“ in der Schnellleiste." : store.aiCorrectMode == "word" ? "Die KI prüft schon während des Tippens alle paar Wörter (mehr Anfragen)." : "Nur lokale Autokorrektur – KI nur auf Knopfdruck („Korrigieren“).")
                .font(.caption2).foregroundStyle(.secondary)
            grid {
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
            row("KI-Verhalten (eigene Regeln)", store.aiBehavior.isEmpty ? "z. B. „Duze immer, kurz & locker, keine Emojis“" : store.aiBehavior, "slider.horizontal.below.square.and.square.filled") {
                state.beginInput(.aiBehavior, prefill: store.aiBehavior)
            }
            Text("Schreibe für").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            AppPicker(state: state)
            Text("Kontextprüfung beim Schreiben").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("Aus", selected: store.contextCheck == "off") { store.contextCheck = "off" }
                chip("Normal", selected: store.contextCheck == "normal") { store.contextCheck = "normal" }
                chip("Intensiv", selected: store.contextCheck == "intense") { store.contextCheck = "intense" }
            }
            Text(store.contextCheck == "intense" ? "Prüft nach jedem Satz bzw. alle paar Wörter – auch Logik, Fakten und Ton. Ideal mit ChatGPT-Abo." : store.contextCheck == "normal" ? "Prüft nach jedem Satz auf falsche Wörter, Grammatik und Widersprüche. Auffällige Stellen erscheinen orange." : "Keine automatische Prüfung – nur über „Prüfen“.")
                .font(.caption2).foregroundStyle(.secondary)
            grid {
                toggle("KI lernt mich", "brain.head.profile", $store.learnProfile)
            }
            row("Gelerntes Profil", store.learnedProfile.isEmpty ? "Noch leer – füllt sich beim Schreiben" : store.learnedProfile, "person.text.rectangle") {
                state.beginInput(.learnedProfile, prefill: store.learnedProfile)
            }
            HStack {
                actionButton("Jetzt lernen", "sparkles") { state.learnNow() }
                actionButton("Vergessen", "trash") { state.forgetProfile() }
            }
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
            Text("Power-Tippen: „Lernende Zonen“ passt die Tasten an deine Finger an, „Tipp-Korrektur“ repariert Vertipper über die echten Tipp-Positionen, „KI-Turbo“ korrigiert schon nach wenigen Wörtern.")
                .font(.caption2).foregroundStyle(.secondary)
            actionButton("Trefferzonen zurücksetzen", "scope") { state.resetTouchModel() }
            if store.haptics { hapticSettings }
            LearnedTokensView(state: state)
        }
    }

    private var hapticSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Haptik").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(store.hapticStrength < 0.02 ? "Aus" : "\(Int(store.hapticStrength * 100)) %")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "hand.tap").foregroundStyle(.secondary)
                Slider(value: $store.hapticStrength, in: 0...1, step: 0.05, onEditingChanged: { editing in
                    if !editing { state.hapticPreview() }
                })
                Image(systemName: "hand.tap.fill").foregroundStyle(state.tint)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    hapticChip("Wie iOS", "light", 0.6)
                    hapticChip("Sanft", "soft", 0.5)
                    hapticChip("Knackig", "rigid", 0.65)
                    hapticChip("Mittel", "medium", 0.7)
                    hapticChip("Kräftig", "heavy", 0.85)
                }
            }
        }
        .padding(10)
        .glass(cornerRadius: 12)
    }

    private func hapticChip(_ title: String, _ style: String, _ strength: Double) -> some View {
        chip(title, selected: store.hapticStyle == style) {
            store.hapticStyle = style
            store.hapticStrength = strength
            state.hapticPreview()
        }
    }

    private var typingToggles: some View {
        grid {
            toggle("Autokorrektur", "textformat.abc.dottedunderline", $store.autocorrect)
            toggle("Wischen", "scribble.variable", $store.swipeTyping)
            toggle("KI beim Wischen", "sparkles", $store.swipeAI)
            toggle("Trefferzonen", "hand.point.up.braille", $store.smartTouch)
            toggle("Lernende Zonen", "scope", $store.adaptiveTouch)
            toggle("Tipp-Korrektur", "hand.tap", $store.tapCorrection)
            toggle("KI-Turbo", "bolt.fill", $store.aiTypoTurbo)
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
            Text("📱-Knopf: Aktion nur in bestimmten Apps zeigen (z. B. nur Discord). ✏️ ändert die Anweisung.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(store.actions) { a in
                HStack {
                    Image(systemName: a.symbol).foregroundStyle(state.tint).frame(width: 20)
                    Text(a.title).font(.footnote.weight(.semibold))
                    Text(a.category.label).font(.caption2).foregroundStyle(.secondary)
                    if !a.apps.isEmpty {
                        Text(a.apps.compactMap { AppProfiles.profile($0)?.emoji }.joined()).font(.caption2)
                    }
                    Spacer()
                    Menu {
                        Button { setApps(a, []) } label: { Label("Überall anzeigen", systemImage: a.apps.isEmpty ? "checkmark" : "globe") }
                        ForEach(AppProfiles.all) { p in
                            Button { toggleApp(a, p.id) } label: {
                                Label("\(p.emoji) \(p.name)", systemImage: a.apps.contains(p.id) ? "checkmark" : "app")
                            }
                        }
                    } label: {
                        Image(systemName: "app.badge").foregroundStyle(a.apps.isEmpty ? Color.secondary : state.tint)
                    }
                    if !a.builtIn {
                        Button { state.beginInput(.actionEdit(a.id), prefill: a.prompt) } label: {
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
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
                        if let emoji = item.emoji {
                            Text(emoji).font(.system(size: 18)).frame(width: 22)
                        } else {
                            Image(systemName: item.symbol).foregroundStyle(state.tint).frame(width: 22)
                        }
                        Text(item.emoji != nil ? "Übersetzen → \(item.title)" : item.title).font(.footnote.weight(.semibold))
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
            Text("Sofort übersetzen – ein Tipp übersetzt & ersetzt den Text (oder die Markierung)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                ForEach(Languages.all, id: \.name) { lang in
                    let id = ToolItem.translateID(lang.name)
                    let active = store.toolbarItems.contains(id)
                    Button {
                        if active { store.toolbarItems.removeAll { $0 == id } } else { store.toolbarItems.append(id) }
                        state.feedback()
                    } label: {
                        HStack(spacing: 6) {
                            Text(lang.flag).font(.system(size: 16))
                            Text(lang.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                            Image(systemName: active ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(active ? state.tint : Color.secondary)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .glass(cornerRadius: 10, tint: active ? state.tint.opacity(0.3) : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Standard wiederherstellen") { store.toolbarItems = ToolItem.defaultOrder }
                .font(.caption)
        }
    }

    private func setApps(_ a: AIAction, _ apps: [String]) {
        if let i = store.actions.firstIndex(where: { $0.id == a.id }) { store.actions[i].apps = apps }
        state.feedback()
    }

    private func toggleApp(_ a: AIAction, _ id: String) {
        var apps = a.apps
        if apps.contains(id) { apps.removeAll { $0 == id } } else { apps.append(id) }
        setApps(a, apps)
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

// MARK: - Übersetzen (Text aus dem Feld)

struct TranslatePanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !state.hasFullAccess || !store.hasAPIKey {
                    MissingSetupBanner(state: state)
                }
                Text(state.selected.isEmpty ? "Übersetzt den ganzen Text im Feld – tippe auf eine Sprache:" : "Übersetzt den markierten Text – tippe auf eine Sprache:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(isOn: $store.translateDirect) {
                    Text("Sofort ersetzen (ohne Vorschau)").font(.caption.weight(.semibold))
                }
                .tint(state.tint)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                    ForEach(Languages.all, id: \.name) { lang in
                        Button { state.translateField(to: lang.name, direct: store.translateDirect) } label: {
                            HStack(spacing: 6) {
                                Text(lang.flag).font(.system(size: 18))
                                Text(lang.name).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .foregroundStyle(store.translateTarget == lang.name ? Color.white : Color.primary)
                            .glass(cornerRadius: 12, tint: store.translateTarget == lang.name ? state.tint : nil, interactive: true)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            let id = ToolItem.translateID(lang.name)
                            if store.toolbarItems.contains(id) {
                                Button(role: .destructive) { store.toolbarItems.removeAll { $0 == id } } label: {
                                    Label("Aus Schnellleiste entfernen", systemImage: "pin.slash")
                                }
                            } else {
                                Button { store.toolbarItems.append(id); state.showToast("\(lang.flag) \(lang.name) in der Schnellleiste ✓") } label: {
                                    Label("Als Ein-Klick-Knopf in die Schnellleiste", systemImage: "pin")
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Button { state.startTranslateMode() } label: {
                        Label("Live tippen & übersetzen", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .glass(cornerRadius: 12, tint: state.tint.opacity(0.3), interactive: true)
                    }
                    .buttonStyle(.plain)
                    Button { state.translateClipboard() } label: {
                        Label("Ablage übersetzen", systemImage: "doc.on.clipboard")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .glass(cornerRadius: 12, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Befehle (Minecraft & Co.)

struct CommandsPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared
    @State private var filter = "fav"
    @State private var confirmDelete: UUID?

    private var groups: [String] {
        var seen: [String] = []
        for c in store.commands where !seen.contains(c.group) { seen.append(c.group) }
        return seen
    }

    private var filtered: [SavedCommand] {
        switch filter {
        case "fav":
            let favs = store.commands.filter(\.favorite)
            return favs.isEmpty ? store.commands : favs
        case "all": return store.commands
        default: return store.commands.filter { $0.group == filter }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    action("✨ KI-Befehl", "terminal") { state.startCommandAI() }
                    action("Zeile speichern", "square.and.arrow.down") { state.saveFieldAsCommand() }
                    action("Aus Ablage", "doc.on.clipboard") { state.saveClipboardAsCommand() }
                    Button {
                        store.commandEdition = store.commandEdition == "Bedrock" ? "Java" : "Bedrock"
                        state.feedback()
                    } label: {
                        Text(store.commandEdition == "Bedrock" ? "🧱 Bedrock" : "☕️ Java")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).frame(height: 30)
                            .glassCapsule(interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("★ Favoriten", "fav")
                    chip("Alle", "all")
                    ForEach(groups, id: \.self) { g in chip(g, g) }
                }
                .padding(.horizontal, 8)
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filtered) { c in
                        HStack(spacing: 8) {
                            Button { state.toggleCommandFavorite(c) } label: {
                                Image(systemName: c.favorite ? "star.fill" : "star")
                                    .foregroundStyle(c.favorite ? Color.yellow : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.title).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(c.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if confirmDelete == c.id {
                                Button { state.deleteCommand(c); confirmDelete = nil } label: {
                                    Image(systemName: "trash.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glass(cornerRadius: 10, interactive: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if confirmDelete == c.id { confirmDelete = nil } else { state.runCommandItem(c) }
                        }
                        .onLongPressGesture(minimumDuration: 0.45) {
                            confirmDelete = c.id
                            state.feedback(.medium)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .padding(.top, 4)
    }

    private func chip(_ title: String, _ key: String) -> some View {
        Button {
            filter = key
            state.feedback()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).frame(height: 28)
                .foregroundStyle(filter == key ? Color.white : Color.primary)
                .glassCapsule(tint: filter == key ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).frame(height: 30)
                .glassCapsule(tint: state.tint.opacity(0.3), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Discord

struct DiscordPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    private var now: Int { Int(Date().timeIntervalSince1970) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !state.hasFullAccess || !store.hasAPIKey {
                    MissingSetupBanner(state: state)
                }
                label("ANKÜNDIGUNG MIT KI")
                HStack(spacing: 6) {
                    chip("🇩🇪 Deutsch", store.discordLanguages == "de") { store.discordLanguages = "de" }
                    chip("🇬🇧 Englisch", store.discordLanguages == "en") { store.discordLanguages = "en" }
                    chip("🇩🇪+🇬🇧 Beides", store.discordLanguages == "both") { store.discordLanguages = "both" }
                }
                HStack(spacing: 6) {
                    chip("Ohne Ping", store.discordMention.isEmpty) { store.discordMention = "" }
                    chip("@everyone", store.discordMention == "@everyone") { store.discordMention = "@everyone" }
                    chip("@here", store.discordMention == "@here") { store.discordMention = "@here" }
                    Spacer(minLength: 0)
                    chip(store.discordAutoCopy ? "📋 Auto-Kopie an" : "📋 Auto-Kopie aus", store.discordAutoCopy) { store.discordAutoCopy.toggle() }
                }
                HStack(spacing: 6) {
                    bigButton("Beschreiben …", "megaphone.fill", prominent: true) {
                        guard state.hasFullAccess, store.hasAPIKey else { state.showToast("Erst KI-Zugang einrichten."); return }
                        state.beginInput(.discordAnnounce)
                    }
                    bigButton("Aus Feldtext", "text.badge.star") { state.discordAnnouncementFromField() }
                    bigButton("Formatieren", "wand.and.stars") { state.discordFormatField() }
                }
                label("FORMATIEREN (MARKIERUNG ODER CURSOR)")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    fmt("B", "Fett", bold: true) { state.discordWrap("**", "**") }
                    fmt("I", "Kursiv") { state.discordWrap("*", "*") }
                    fmt("U", "Unterstr.") { state.discordWrap("__", "__") }
                    fmt("S", "Durch") { state.discordWrap("~~", "~~") }
                    fmt("▮▮", "Spoiler") { state.discordWrap("||", "||") }
                    fmt("#", "Titel") { state.discordLine("# ") }
                    fmt("##", "Unter") { state.discordLine("## ") }
                    fmt("###", "Klein") { state.discordLine("### ") }
                    fmt("-#", "Fußtext") { state.discordLine("-# ") }
                    fmt(">", "Zitat") { state.discordLine("> ") }
                    fmt("•", "Liste") { state.discordLine("- ") }
                    fmt("1.", "Nummer") { state.discordLine("1. ") }
                    fmt("</>", "Code") { state.discordWrap("`", "`") }
                    fmt("```", "Block") { state.discordWrap("```\n", "\n```") }
                    fmt("🔗", "Link") { state.discordWrap("[", "](https://)") }
                }
                label("EINFÜGEN · LANG DRÜCKEN = KOPIEREN")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        snippet("🕒 Jetzt (relativ)", "<t:\(now):R>")
                        snippet("📅 Datum + Uhrzeit", "<t:\(now):f>")
                        snippet("📆 Datum", "<t:\(now):D>")
                        snippet("@everyone", "@everyone")
                        snippet("@here", "@here")
                        snippet("Trennlinie", "\n━━━━━━━━━━━━━━━━━━\n")
                        snippet("Unsichtbar", "\u{200B}")
                    }
                }
                Text("Zeitstempel zeigen jedem die Uhrzeit in seiner Zeitzone. Für andere Zeiten: KI-Ankündigung mit Datum beschreiben.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.leading, 4)
    }

    private func chip(_ title: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); state.feedback() } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .glassCapsule(tint: selected ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func bigButton(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .glass(cornerRadius: 14, tint: prominent ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func fmt(_ symbol: String, _ title: String, bold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(symbol).font(.system(size: 15, weight: bold ? .heavy : .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .glass(cornerRadius: 11, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        Button { state.discordInsert(text) } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: 32)
                .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { state.discordInsert(text, copy: true) } label: { Label("Kopieren", systemImage: "doc.on.doc") }
            Button { state.discordInsert(text) } label: { Label("Einfügen", systemImage: "text.insert") }
        }
    }
}

// MARK: - Kontextprüfung

struct CheckPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var bar: BarModel

    init(state: KeyboardState) {
        _state = ObservedObject(wrappedValue: state)
        _bar = ObservedObject(wrappedValue: state.bar)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if bar.checking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("KI prüft deinen Text im Zusammenhang …").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !state.checkedText.isEmpty {
                    Text(highlighted)
                        .font(.system(size: 14))
                        .lineLimit(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .glass(cornerRadius: 12)
                }
                if !bar.checking && bar.issues.isEmpty {
                    Label("Keine Auffälligkeiten gefunden.", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
                ForEach(bar.issues) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(issue.kind)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.25)))
                            if !issue.reason.isEmpty {
                                Text(issue.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 6) {
                            Text(issue.original).strikethrough().foregroundStyle(.red).lineLimit(2)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                            Text(issue.suggestion).fontWeight(.semibold).foregroundStyle(.green).lineLimit(2)
                            Spacer(minLength: 0)
                            Button { state.dismissIssue(issue) } label: {
                                Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 30, height: 30).glass(cornerRadius: 15, interactive: true)
                            }
                            .buttonStyle(.plain)
                            Button { state.applyIssue(issue) } label: {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30).glass(cornerRadius: 15, tint: state.tint, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.footnote)
                    }
                    .padding(9)
                    .glass(cornerRadius: 12)
                }
                HStack(spacing: 6) {
                    if bar.issues.count > 1 {
                        Button { state.applyAllIssues() } label: {
                            Label("Alle übernehmen", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .glass(cornerRadius: 12, tint: state.tint, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { state.runContextCheck(manual: true) } label: {
                        Label("Erneut prüfen", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .glass(cornerRadius: 12, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    /// Text mit orange markierten, möglicherweise falschen Stellen.
    private var highlighted: AttributedString {
        var attr = AttributedString(state.checkedText)
        for issue in bar.issues {
            if let r = attr.range(of: issue.original, options: .backwards) {
                attr[r].backgroundColor = Color.orange.opacity(0.35)
                attr[r].underlineStyle = .single
            }
        }
        return attr
    }
}
