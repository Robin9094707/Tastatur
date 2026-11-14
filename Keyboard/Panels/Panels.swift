import SwiftUI

// MARK: - KI-Aktionen

struct AIPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !state.hasFullAccess || !store.hasAPIKey {
                    MissingSetupBanner(state: state)
                }
                Button { state.startCompose() } label: {
                    HStack {
                        Image(systemName: "pencil.line")
                        Text("KI schreiben lassen …")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .glass(cornerRadius: 14, tint: state.tint.opacity(0.5), interactive: true)
                }
                .buttonStyle(.plain)

                GlassGroup(spacing: 8) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.actions.filter(\.enabled)) { action in
                            Button { state.runAction(action) } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: action.symbol)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(state.tint)
                                    Text(action.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .glass(cornerRadius: 14, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Wirkt auf: \(scopeHint)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private var scopeHint: String {
        if !state.selected.isEmpty { return "markierten Text" }
        switch store.aiScope {
        case .auto, .all: return "gesamten Text im Feld (markiere Text, um nur diesen zu ändern)"
        case .sentence: return "aktuellen Absatz"
        case .selection: return "nur markierten Text"
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

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if state.aiBusy {
                    VStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.tint.opacity(shimmer ? 0.35 : 0.12))
                                .frame(height: 12)
                                .frame(maxWidth: i == 3 ? 160 : .infinity, alignment: .leading)
                        }
                        Text("KI denkt nach …").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever()) { shimmer = true }
                    }
                } else if let error = state.aiError {
                    VStack(spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        if error.contains("Schlüssel") {
                            Button("Schlüssel aus Zwischenablage einfügen") { state.pasteAPIKey() }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                } else {
                    ScrollView {
                        Text(state.aiResult)
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glass(cornerRadius: 16)

            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    actionButton("Ersetzen", "arrow.2.squarepath", prominent: true) { state.applyResult(replace: true) }
                        .disabled(state.aiBusy || state.aiResult.isEmpty)
                    actionButton("Einfügen", "text.insert", prominent: false) { state.applyResult(replace: false) }
                        .disabled(state.aiBusy || state.aiResult.isEmpty)
                    actionButton("", "doc.on.doc", prominent: false) { state.copyResult() }
                        .disabled(state.aiBusy || state.aiResult.isEmpty)
                        .frame(width: 50)
                    actionButton("", "arrow.clockwise", prominent: false) { state.retryAI() }
                        .disabled(state.aiBusy)
                        .frame(width: 50)
                }
            }
        }
        .padding(8)
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
            .frame(height: 44)
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
                MissingSetupBanner(state: state).padding(10)
                Spacer()
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
                            HStack(alignment: .top, spacing: 8) {
                                Button { state.pasteClip(item) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.text)
                                            .font(.system(size: 14))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(item.date, style: .relative)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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
    @State private var category = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 2) {
                    ForEach(EmojiData.categories[category].emojis, id: \.self) { e in
                        Button { state.insert(e); state.feedback() } label: {
                            Text(e).font(.system(size: 28)).frame(height: 40).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            HStack(spacing: 2) {
                Button { state.toggle(.emoji) } label: {
                    Text("ABC").font(.system(size: 14, weight: .semibold)).frame(width: 46, height: 34)
                }
                .buttonStyle(.plain)
                ForEach(Array(EmojiData.categories.enumerated()), id: \.offset) { i, cat in
                    Button { category = i } label: {
                        Image(systemName: cat.symbol)
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(category == i ? state.tint : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button { state.tapDelete() } label: {
                    Image(systemName: "delete.left").frame(width: 40, height: 34)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .glassCapsule()
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Diktat

struct DictationPanel: View {
    @ObservedObject var state: KeyboardState
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            switch state.dictation {
            case .connecting:
                ProgressView()
                Text("Verbinde mit Tastatur KI …").font(.subheadline)
            case .openingApp:
                Image(systemName: "arrow.up.forward.app").font(.system(size: 34)).foregroundStyle(state.tint)
                Text("Die App startet die Diktat-Sitzung.")
                    .font(.subheadline.weight(.semibold))
                Text("Wische danach oben links über „◀︎ Zurück“ hierher – die Aufnahme läuft dann schon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack {
                    Button("Erneut versuchen") { state.startDictation() }
                    Button("App öffnen") { state.openApp("dictate") }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            case .recording:
                Button { state.stopDictation() } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.25))
                            .frame(width: 96 + CGFloat(state.dictationLevel) * 50, height: 96 + CGFloat(state.dictationLevel) * 50)
                            .animation(.easeOut(duration: 0.12), value: state.dictationLevel)
                        Image(systemName: "stop.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .glass(cornerRadius: 40, tint: .red, interactive: true)
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 130)
                Text("Ich höre zu … tippe zum Beenden").font(.subheadline)
            case .processing:
                ProgressView().controlSize(.large)
                Text("Wird transkribiert …").font(.subheadline)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                Text(message).font(.footnote).multilineTextAlignment(.center).padding(.horizontal)
                Button("Erneut versuchen") { state.startDictation() }.buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
            Button("Abbrechen") { state.cancelDictation() }
                .font(.footnote)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
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
                    toggle("Zahlenreihe", "number", $store.showNumberRow)
                    toggle("Makros auto", "bolt", $store.macroAutoExpand)
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
                HStack {
                    Button { state.copyAll() } label: {
                        Label("Text kopieren", systemImage: "doc.on.doc")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .glass(cornerRadius: 12, interactive: true)
                    }
                    .buttonStyle(.plain)
                    Button { state.openApp("settings") } label: {
                        Label("App öffnen", systemImage: "arrow.up.forward.app")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .glass(cornerRadius: 12, tint: state.tint.opacity(0.4), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
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
