import SwiftUI

struct MacrosView: View {
    @EnvironmentObject var store: SharedStore
    @State private var editing: Macro?
    @State private var search = ""

    private var filtered: [Macro] {
        guard !search.isEmpty else { return store.macros }
        return store.macros.filter {
            $0.shortcut.localizedCaseInsensitiveContains(search) || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $store.macroAutoExpand) {
                    Label("Kürzel automatisch ersetzen", systemImage: "bolt.fill")
                }
            } footer: {
                Text("Tippe z. B. „mfg“ + Leertaste und es wird automatisch ersetzt. Platzhalter: {datum}, {uhrzeit}, {wochentag}, {zwischenablage}.")
            }
            .glassRow()

            Section("Makros") {
                ForEach(filtered) { macro in
                    Button { editing = macro } label: {
                        HStack(spacing: 12) {
                            Text(macro.shortcut)
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassCapsule(tint: macro.isAI ? .purple : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(macro.title).foregroundStyle(.primary)
                                    if macro.isAI { Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple) }
                                }
                                Text(macro.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let ids = offsets.map { filtered[$0].id }
                    store.macros.removeAll { ids.contains($0.id) }
                }
                .onMove { store.macros.move(fromOffsets: $0, toOffset: $1) }
            }
            .glassRow()
        }
        .glassBackground()
        .searchable(text: $search, prompt: "Makros durchsuchen")
        .navigationTitle("Makros")
        .toolbar {
            EditButton()
            Button {
                editing = Macro(shortcut: "", title: "", text: "")
            } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { macro in
            MacroEditor(macro: macro) { updated in
                if let i = store.macros.firstIndex(where: { $0.id == updated.id }) {
                    store.macros[i] = updated
                } else {
                    store.macros.append(updated)
                }
            }
        }
    }
}

struct MacroEditor: View {
    @State var macro: Macro
    var onSave: (Macro) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kürzel (z. B. adr)", text: $macro.shortcut)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Titel", text: $macro.title)
                }
                .glassRow()
                Section {
                    Toggle(isOn: $macro.isAI) {
                        Label("KI-Makro", systemImage: "sparkles")
                    }
                } footer: {
                    Text(macro.isAI ? "Der Text unten ist eine Anweisung an die KI. Sie bekommt den bisherigen Text als Kontext und fügt das Ergebnis ein." : "Der Text unten wird 1:1 eingefügt.")
                }
                .glassRow()
                Section(macro.isAI ? "Anweisung" : "Text") {
                    TextField(macro.isAI ? "z. B. Schreibe eine höfliche Absage" : "Text, der eingefügt wird", text: $macro.text, axis: .vertical)
                        .lineLimit(4...14)
                    HStack {
                        ForEach(["{datum}", "{uhrzeit}", "{wochentag}", "{zwischenablage}"], id: \.self) { p in
                            Button(p) { macro.text += p }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .glassRow()
            }
            .glassBackground()
            .navigationTitle(macro.title.isEmpty ? "Neues Makro" : macro.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        macro.shortcut = macro.shortcut.trimmingCharacters(in: .whitespaces)
                        if macro.title.isEmpty { macro.title = macro.shortcut }
                        onSave(macro)
                        dismiss()
                    }
                    .disabled(macro.text.isEmpty || (macro.shortcut.isEmpty && macro.title.isEmpty))
                }
            }
        }
    }
}

struct ClipboardView: View {
    @EnvironmentObject var store: SharedStore
    @State private var items: [ClipItem] = []
    @State private var search = ""
    @State private var copiedID: UUID?

    private var filtered: [ClipItem] {
        search.isEmpty ? items : items.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $store.clipboardEnabled) {
                    Label("Verlauf speichern", systemImage: "clock.arrow.circlepath")
                }
                Stepper("Max. \(store.clipboardLimit) Einträge", value: $store.clipboardLimit, in: 10...500, step: 10)
            } footer: {
                Text("Kopierte Texte werden gespeichert, sobald die Tastatur oder diese App geöffnet wird. Angeheftete Einträge bleiben immer.")
            }
            .glassRow()

            Section("Verlauf") {
                if filtered.isEmpty {
                    Text("Noch nichts kopiert.").foregroundStyle(.secondary)
                }
                ForEach(filtered) { item in
                    Button {
                        UIPasteboard.general.string = item.text
                        copiedID = item.id
                    } label: {
                        HStack(alignment: .top) {
                            if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.yellow).font(.caption) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text).lineLimit(4).foregroundStyle(.primary)
                                Text(item.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if copiedID == item.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button { togglePin(item) } label: {
                            Label(item.pinned ? "Lösen" : "Anheften", systemImage: item.pinned ? "pin.slash" : "pin")
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(item) } label: { Label("Löschen", systemImage: "trash") }
                        Button { makeMacro(item) } label: { Label("Als Makro", systemImage: "text.badge.star") }
                            .tint(.purple)
                    }
                }
            }
            .glassRow()
        }
        .glassBackground()
        .searchable(text: $search, prompt: "Verlauf durchsuchen")
        .navigationTitle("Zwischenablage")
        .toolbar {
            Menu {
                Button("Alle nicht angehefteten löschen", role: .destructive) {
                    items.removeAll { !$0.pinned }
                    store.saveClips(items)
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .onAppear { reload() }
        .refreshable { reload() }
    }

    private func reload() {
        if store.clipboardEnabled, let s = UIPasteboard.general.string { store.addClip(s) }
        items = store.loadClips()
    }

    private func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].pinned.toggle()
        store.saveClips(items)
        items = store.loadClips()
    }

    private func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        store.saveClips(items)
    }

    private func makeMacro(_ item: ClipItem) {
        let title = String(item.text.prefix(24))
        store.macros.append(Macro(shortcut: "", title: title, text: item.text))
    }
}
