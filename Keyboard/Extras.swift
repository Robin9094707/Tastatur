import UIKit
import SwiftUI
import EventKit
import CoreLocation

// MARK: - Angebote in der Vorschlagsleiste

struct EventDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
}

struct BarOffer: Equatable {
    enum Kind: Equatable {
        case restore
        case undoAI
        case event(EventDraft)
        case replies
    }
    var kind: Kind
    var icon: String
    var title: String
}

// MARK: - Verlauf (lokal, sicher, max. 7 Tage)

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    /// "deleted" (gelöscht), "replaced" (vor KI-Änderung), "text" (geschriebener Text)
    var kind: String
    var text: String
}

enum HistoryStore {
    private static let queue = DispatchQueue(label: "tastatur.history", qos: .utility)
    static var url: URL { SharedStore.containerURL.appendingPathComponent("writing-history.json") }
    static let maxAge: TimeInterval = 7 * 24 * 3600
    static let maxCount = 80

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
        let limit = Date().addingTimeInterval(-maxAge)
        return list.filter { $0.date > limit }
    }

    private static func save(_ list: [HistoryEntry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        // Nur auf dem Gerät, mit Dateischutz
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Fügt einen Eintrag hinzu. Wächst ein Text nur weiter (gleicher Anfang), wird der letzte Eintrag ersetzt.
    static func add(_ entry: HistoryEntry, done: (([HistoryEntry]) -> Void)? = nil) {
        queue.async {
            var list = load()
            if entry.kind == "text", let i = list.firstIndex(where: { $0.kind == "text" }),
               entry.text.hasPrefix(String(list[i].text.prefix(40))) || list[i].text.hasPrefix(String(entry.text.prefix(40))),
               Date().timeIntervalSince(list[i].date) < 3600 {
                list.remove(at: i)
            }
            list.removeAll { $0.text == entry.text }
            list.insert(entry, at: 0)
            if list.count > maxCount { list.removeLast(list.count - maxCount) }
            save(list)
            if let done { DispatchQueue.main.async { done(list) } }
        }
    }

    static func remove(_ id: UUID, done: @escaping ([HistoryEntry]) -> Void) {
        queue.async {
            var list = load()
            list.removeAll { $0.id == id }
            save(list)
            DispatchQueue.main.async { done(list) }
        }
    }

    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - Zusatz-Zustand

final class ExtrasState: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var history: [HistoryEntry] = []

    /// Text, der im aktuellen Lösch-Vorgang entfernt wurde (für „Wiederherstellen“).
    var deleted = ""
    /// Letzte KI-Ersetzung des ganzen Textes (Original, neuer Text).
    var aiUndo: (original: String, newText: String)?
    var lastSnapshot = ""
    var lastEventKey = ""
    var replySource = ""

    // Kontakte
    var contacts: [ContactEntry] = []
    var contactsLoadedAt = Date.distantPast
    var contactsLoading = false

    // Standort
    private var manager: CLLocationManager?
    private var locationDone: ((CLLocation?) -> Void)?

    func requestLocation(_ done: @escaping (CLLocation?) -> Void) {
        let m = manager ?? CLLocationManager()
        manager = m
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationDone = done
        m.requestLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finishLocation(nil)
        }
    }

    var locationAuthorized: Bool {
        let s = (manager ?? CLLocationManager()).authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    private func finishLocation(_ loc: CLLocation?) {
        guard let done = locationDone else { return }
        locationDone = nil
        done(loc)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async { self.finishLocation(locations.last) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.finishLocation(nil) }
    }
}

// MARK: - Funktionen

extension KeyboardState {

    // MARK: Gelöschtes wiederherstellen

    /// Merkt sich gelöschten Text (wird vorne angefügt, weil rückwärts gelöscht wird).
    func captureDeleted(_ text: String) {
        guard store.writeHistory, !text.isEmpty, !composeMode else { return }
        extras.deleted = text + extras.deleted
        if extras.deleted.count > 20_000 { extras.deleted = String(extras.deleted.suffix(20_000)) }
    }

    /// Nach dem Loslassen der Löschtaste: bei größeren Mengen „Wiederherstellen“ anbieten.
    func updateRestoreOffer() {
        let d = extras.deleted
        guard d.count >= 10 || d.split(separator: " ").count >= 3 else { return }
        let preview = d.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let short = preview.count > 28 ? "…" + preview.suffix(26) : preview
        bar.offer = BarOffer(kind: .restore, icon: "arrow.uturn.backward.circle.fill", title: "„\(short)“ wiederherstellen")
    }

    /// Ein anderer Tastendruck beendet den Lösch-Vorgang: Größeres kommt in den Verlauf.
    func finishDeletionBurst() {
        if !extras.deleted.isEmpty {
            let d = extras.deleted
            extras.deleted = ""
            if d.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 {
                HistoryStore.add(HistoryEntry(kind: "deleted", text: d))
            }
        }
        if let o = bar.offer {
            switch o.kind {
            case .restore, .undoAI: bar.offer = nil; extras.aiUndo = nil
            case .event, .replies: break
            }
        }
    }

    func restoreDeleted() {
        let d = extras.deleted
        guard !d.isEmpty else { return }
        extras.deleted = ""
        bar.offer = nil
        proxy?.insertText(d)
        feedback(.medium)
        showToast("Wiederhergestellt ✓")
        afterCommit()
    }

    // MARK: KI-Änderung rückgängig

    func rememberBeforeAIReplace(_ original: String, newText: String) {
        guard !original.isEmpty else { return }
        extras.aiUndo = (original, newText)
        if store.writeHistory { HistoryStore.add(HistoryEntry(kind: "replaced", text: original)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.extras.aiUndo != nil else { return }
            self.bar.offer = BarOffer(kind: .undoAI, icon: "arrow.uturn.backward.circle.fill", title: "KI-Änderung rückgängig")
        }
    }

    func undoAIReplace() {
        guard let u = extras.aiUndo else { return }
        extras.aiUndo = nil
        bar.offer = nil
        feedback(.medium)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.replaceAll(with: u.original, expectedLength: u.newText.count)
            self.showToast("Original wiederhergestellt ✓")
            self.afterCommit()
        }
    }

    /// Werkzeug „Rückgängig“: macht die letzte Aktion rückgängig (Löschen, KI, Autokorrektur).
    func undoLast() {
        if panel == .tools { panel = .none; onHeightChange?(totalHeight) }
        if !extras.deleted.isEmpty { restoreDeleted(); return }
        if extras.aiUndo != nil { undoAIReplace(); return }
        if let undo = undoCorrection, before.hasSuffix(undo.corrected + undo.trailing) {
            tapDelete()
            showToast("Autokorrektur zurückgenommen")
            return
        }
        // Zuletzt Gelöschtes aus dem Verlauf (bis 15 Minuten)
        let recent = HistoryStore.load().first { $0.kind == "deleted" && Date().timeIntervalSince($0.date) < 900 }
        if let recent {
            proxy?.insertText(recent.text)
            HistoryStore.remove(recent.id) { [weak self] list in self?.extras.history = list }
            feedback(.medium)
            showToast("Gelöschtes wiederhergestellt ✓")
            afterCommit()
            return
        }
        showToast("Nichts zum Rückgängigmachen – siehe „Verlauf“.")
    }

    // MARK: Schreibverlauf

    /// Sichert den aktuellen Text (lokal). Passiert beim Senden und beim Schließen der Tastatur.
    func snapshotHistory() {
        guard store.writeHistory, !composeMode, shouldAutocorrect, !isCommandLine else { return }
        let text = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12, text != extras.lastSnapshot else { return }
        extras.lastSnapshot = text
        HistoryStore.add(HistoryEntry(kind: "text", text: String(text.prefix(6000))))
    }

    func reloadHistory() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = HistoryStore.load()
            DispatchQueue.main.async { self?.extras.history = list }
        }
    }

    func insertHistory(_ e: HistoryEntry) {
        feedback()
        var text = e.text
        if let last = before.last, !last.isWhitespace { text = " " + text }
        proxy?.insertText(text)
        panel = .none
        onHeightChange?(totalHeight)
        showToast("Eingefügt ✓")
        afterCommit()
    }

    func copyHistory(_ e: HistoryEntry) {
        guard hasFullAccess else { showToast("Kopieren braucht „Vollen Zugriff“."); return }
        UIPasteboard.general.string = e.text
        lastChangeCount = UIPasteboard.general.changeCount
        feedback()
        showToast("Kopiert ✓")
    }

    func deleteHistory(_ e: HistoryEntry) {
        HistoryStore.remove(e.id) { [weak self] list in self?.extras.history = list }
    }

    func clearWritingHistory() {
        HistoryStore.clear()
        extras.history = []
        extras.deleted = ""
        showToast("Verlauf gelöscht")
    }

    // MARK: Text-Helfer

    /// Der zuletzt geschriebene Satz.
    var lastSentence: String {
        var b = before
        while let l = b.last, l.isWhitespace { b.removeLast() }
        guard !b.isEmpty else { return "" }
        let body = b.dropLast()
        let start = body.lastIndex(where: { ".!?\n".contains($0) }).map { body.index(after: $0) } ?? body.startIndex
        return String(b[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Kontakte

    func loadContactsIfNeeded() {
        guard store.useContacts, !extras.contactsLoading else {
            if !store.useContacts, !extras.contacts.isEmpty { extras.contacts = []; engine.setExtraKnown([]) }
            return
        }
        let modified = (try? ContactsCache.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        guard modified > extras.contactsLoadedAt else { return }
        extras.contactsLoading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = ContactsCache.load()
            var names = Set<String>()
            for c in list {
                for part in c.name.split(separator: " ") where part.count >= 2 { names.insert(part.lowercased()) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.extras.contacts = list
                self.extras.contactsLoadedAt = modified
                self.extras.contactsLoading = false
                self.engine.setExtraKnown(names)
            }
        }
    }

    /// Kontakt-Vorschläge: Namen vervollständigen, nach vollem Namen Nummer/E-Mail anbieten.
    func addContactSuggestions(word: String, to list: [Suggestion]) -> [Suggestion] {
        guard store.useContacts, !extras.contacts.isEmpty, word.count >= 2, word.first?.isLetter == true else { return list }
        let lw = word.lowercased()
        var out = list
        var added: [Suggestion] = []
        let exact = extras.contacts.filter { c in c.name.split(separator: " ").contains { $0.lowercased() == lw } }
        if exact.count == 1, let c = exact.first {
            if let phone = c.phones.first {
                added.append(Suggestion(text: phone, kind: .contact, display: "📞 \(phone)", rest: "append"))
            }
            if let mail = c.emails.first, added.count < 1 || c.phones.isEmpty {
                added.append(Suggestion(text: mail, kind: .contact, display: "✉️ \(mail)", rest: "append"))
            }
            if c.name.lowercased() != lw, c.name.contains(" "), c.name.lowercased().hasPrefix(lw) {
                added.insert(Suggestion(text: c.name, kind: .contact, display: "👤 \(c.name)"), at: 0)
            }
        } else if word.count >= 3 {
            let hits = extras.contacts.lazy.filter { c in c.name.split(separator: " ").contains { $0.lowercased().hasPrefix(lw) } }.prefix(1)
            for c in hits where c.name.lowercased() != lw {
                added.append(Suggestion(text: c.name, kind: .contact, display: "👤 \(c.name)"))
            }
        }
        guard !added.isEmpty else { return list }
        out.removeAll { s in added.contains { $0.text.lowercased() == s.text.lowercased() } }
        out.insert(contentsOf: added.prefix(2), at: min(1, out.count))
        return out
    }

    // MARK: Standort

    func insertLocation() {
        if panel == .tools { panel = .none; onHeightChange?(totalHeight) }
        guard store.useLocation else {
            showToast("Standort ist aus – in der App unter „Persönliches“ einschalten.")
            openApp("location")
            return
        }
        guard hasFullAccess else { showToast("Standort braucht „Vollen Zugriff“."); return }
        if extras.locationAuthorized {
            showToast("Standort wird ermittelt …")
            extras.requestLocation { [weak self] loc in
                guard let self else { return }
                if let loc { self.insertLocation(loc) } else { self.insertSavedLocation(fallbackReason: true) }
            }
        } else {
            insertSavedLocation(fallbackReason: false)
        }
    }

    private func insertSavedLocation(fallbackReason: Bool) {
        guard let saved = SavedLocation.load() else {
            showToast("Kein Standort – öffne kurz die App, um ihn zu aktualisieren.")
            openApp("location")
            return
        }
        let age = Date().timeIntervalSince(saved.date)
        let ageText = age < 120 ? "" : " (Stand: \(Self.relative(saved.date)))"
        insertLocationText(address: saved.address, lat: saved.lat, lon: saved.lon, suffix: ageText)
        if age > 3600 { showToast("Standort ist älter – App öffnen aktualisiert ihn.") }
    }

    private func insertLocation(_ loc: CLLocation) {
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "de_DE")) { [weak self] marks, _ in
            DispatchQueue.main.async {
                let address = marks?.first.map(Self.address) ?? ""
                self?.insertLocationText(address: address, lat: lat, lon: lon, suffix: "")
            }
        }
    }

    private func insertLocationText(address: String, lat: Double, lon: Double, suffix: String) {
        let link = String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=Standort", lat, lon)
        var text = "📍 " + (address.isEmpty ? "Mein Standort" : address) + suffix + "\n" + link
        if let last = before.last, !last.isWhitespace { text = " " + text }
        proxy?.insertText(text + " ")
        feedback(.medium)
        afterCommit()
    }

    static func address(_ p: CLPlacemark) -> String {
        var parts: [String] = []
        let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        if !street.isEmpty { parts.append(street) }
        let city = [p.postalCode, p.locality].compactMap { $0 }.joined(separator: " ")
        if !city.isEmpty { parts.append(city) }
        if parts.isEmpty, let name = p.name { parts.append(name) }
        return parts.joined(separator: ", ")
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    // MARK: Termine

    /// Sucht in einem Satz nach einem Termin (lokal, ohne KI) und bietet „Im Kalender speichern“ an.
    func detectEvent(in text: String, force: Bool = false) {
        guard store.calendarSuggest || force, text.count >= 6, text.count < 1500 else { return }
        guard let draft = EventParser.parse(text) else { return }
        let key = "\(draft.start.timeIntervalSince1970)|\(draft.title)"
        guard key != extras.lastEventKey else { return }
        extras.lastEventKey = key
        bar.offer = BarOffer(kind: .event(draft), icon: "calendar.badge.plus", title: "Termin speichern · \(EventParser.label(draft))")
    }

    /// Werkzeug „Termin“: sucht im markierten bzw. letzten Text.
    func eventFromText() {
        if panel == .tools { panel = .none; onHeightChange?(totalHeight) }
        let src = selected.isEmpty ? String(before.suffix(400)) : selected
        extras.lastEventKey = ""
        detectEvent(in: src, force: true)
        if case .event = bar.offer?.kind {} else { showToast("Kein Datum gefunden – z. B. „morgen um 15 Uhr“.") }
    }

    func saveEvent(_ d: EventDraft) {
        bar.offer = nil
        feedback(.medium)
        let status = EKEventStore.authorizationStatus(for: .event)
        if hasFullAccess, status == .fullAccess || status == .writeOnly {
            let es = EKEventStore()
            let ev = EKEvent(eventStore: es)
            ev.title = d.title
            ev.startDate = d.start
            ev.endDate = d.end
            ev.isAllDay = d.allDay
            ev.calendar = es.defaultCalendarForNewEvents
            do {
                try es.save(ev, span: .thisEvent)
                showToast("Im Kalender gespeichert ✓")
                return
            } catch {}
        }
        // Über die App speichern (fragt dort einmalig nach dem Kalender-Zugriff)
        var c = URLComponents()
        c.scheme = "tastatur"
        c.host = "event"
        c.queryItems = [
            URLQueryItem(name: "title", value: d.title),
            URLQueryItem(name: "start", value: String(Int(d.start.timeIntervalSince1970))),
            URLQueryItem(name: "end", value: String(Int(d.end.timeIntervalSince1970))),
            URLQueryItem(name: "allDay", value: d.allDay ? "1" : "0"),
        ]
        if let url = c.url { controller?.openURL(url) }
        showToast("Öffne die App zum Speichern …")
    }

    // MARK: Antwortvorschläge

    func clipboardDidChange(_ s: String) {
        let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 3000 else { return }
        if store.calendarSuggest { detectEvent(in: text) }
        guard store.replySuggestions, hasFullAccess, store.hasAPIKey, !composeMode,
              !text.hasPrefix("http"), text.wordCount >= 2 else { return }
        // Nur für wirklich neu kopierte Nachrichten (nicht beim erneuten Öffnen der Tastatur)
        let count = UIPasteboard.general.changeCount
        guard store.defaults.integer(forKey: "reply.lastCount") != count else { return }
        store.defaults.set(count, forKey: "reply.lastCount")
        extras.replySource = text
        if case .event = bar.offer?.kind { return }
        bar.offer = BarOffer(kind: .replies, icon: "bubble.left.and.text.bubble.right.fill", title: "Antworten auf kopierte Nachricht")
    }

    /// Lässt die KI 3 Antworten auf die kopierte Nachricht vorschlagen (Tipp setzt sie ein).
    func suggestReplies(manual: Bool) {
        if panel == .tools { panel = .none; onHeightChange?(totalHeight) }
        guard requireAI() else { return }
        var source = extras.replySource
        if source.isEmpty || manual, let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
            source = clip
        }
        guard !source.isEmpty else {
            showToast("Kopiere zuerst die Nachricht, auf die du antworten willst.")
            return
        }
        bar.offer = nil
        bar.thinking = true
        let draft = before + after
        Task { [weak self] in
            guard let self else { return }
            let replies = (try? await self.client.replies(to: source, draft: draft)) ?? []
            await MainActor.run {
                self.bar.thinking = false
                guard !replies.isEmpty else { self.showToast("Keine Antwort erhalten – später nochmal."); return }
                self.suggestions = []
                self.bar.phrases = replies.map { Suggestion(text: $0, kind: .reply, display: $0) }
                self.markPredictionContext()
            }
        }
    }

    // MARK: KI-Gedächtnis

    /// Werkzeug „Merken“: markierten Text bzw. letzten Satz im KI-Gedächtnis speichern.
    func rememberCurrent() {
        if panel == .tools { panel = .none; onHeightChange?(totalHeight) }
        guard store.memoryEnabled else { showToast("KI-Gedächtnis ist aus (Einstellungen → Kontext)."); return }
        var text = selected.isEmpty ? lastSentence : selected
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { showToast("Markiere den Text, den sich die KI merken soll."); return }
        let note = String(text.prefix(300))
        var notes = store.memoryNotes.filter { $0 != note }
        notes.insert(note, at: 0)
        store.memoryNotes = Array(notes.prefix(60))
        feedback(.medium)
        showToast("Gemerkt 🧠")
    }

    // MARK: Leisten-Angebote

    func performOffer(_ o: BarOffer) {
        switch o.kind {
        case .restore: restoreDeleted()
        case .undoAI: undoAIReplace()
        case .event(let d): saveEvent(d)
        case .replies: suggestReplies(manual: false)
        }
    }

    func dismissOffer() {
        if case .restore = bar.offer?.kind {
            // Nicht verloren: kommt in den Verlauf
            finishDeletionBurst()
        }
        bar.offer = nil
        extras.aiUndo = nil
    }
}

// MARK: - Termin-Erkennung (Deutsch, lokal)

enum EventParser {
    private static let weekdays: [String: Int] = [
        "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6, "samstag": 7, "sonnabend": 7,
    ]
    private static let months: [String: Int] = [
        "januar": 1, "jan": 1, "februar": 2, "feb": 2, "märz": 3, "maerz": 3, "april": 4, "apr": 4, "mai": 5, "juni": 6, "jun": 6,
        "juli": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "oktober": 10, "okt": 10,
        "november": 11, "nov": 11, "dezember": 12, "dez": 12,
    ]

    static func parse(_ raw: String, now: Date = Date()) -> EventDraft? {
        let text = raw.lowercased()
        let cal = Calendar(identifier: .gregorian)
        var day: Date?
        func m(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let r = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<r.numberOfRanges).map { i in
                Range(r.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
        let today = cal.startOfDay(for: now)
        if m("\\bübermorgen\\b") != nil {
            day = cal.date(byAdding: .day, value: 2, to: today)
        } else if m("\\bheute morgen\\b") == nil, m("\\bmorgen\\b") != nil {
            day = cal.date(byAdding: .day, value: 1, to: today)
        } else if m("\\bheute\\b") != nil {
            day = today
        }
        if let g = m("\\b(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2,4})?"), let d = Int(g[1]), let mo = Int(g[2]), (1...31).contains(d), (1...12).contains(mo) {
            var y = Int(g[3]) ?? cal.component(.year, from: now)
            if y < 100 { y += 2000 }
            var c = DateComponents(year: y, month: mo, day: d)
            if var date = cal.date(from: c) {
                if g[3].isEmpty, date < today { c.year = y + 1; date = cal.date(from: c) ?? date }
                day = date
            }
        } else if let g = m("\\b(\\d{1,2})\\.? ?(januar|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan|feb|apr|jun|jul|aug|sept?|okt|nov|dez)\\b"),
                  let d = Int(g[1]), let mo = months[g[2]] {
            let y = cal.component(.year, from: now)
            if var date = cal.date(from: DateComponents(year: y, month: mo, day: d)) {
                if date < today { date = cal.date(from: DateComponents(year: y + 1, month: mo, day: d)) ?? date }
                day = date
            }
        } else if day == nil, let g = m("\\b(nächsten |kommenden |am )?(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag)\\b"),
                  let wd = weekdays[g[2]] {
            let current = cal.component(.weekday, from: today)
            var diff = (wd - current + 7) % 7
            if diff == 0 { diff = 7 }
            day = cal.date(byAdding: .day, value: diff, to: today)
        }

        // Uhrzeit
        var hour: Int?, minute = 0
        if let g = m("\\b(\\d{1,2}):(\\d{2})\\b"), let h = Int(g[1]), let mi = Int(g[2]), h < 24, mi < 60 {
            hour = h; minute = mi
        } else if let g = m("\\b(\\d{1,2})\\.(\\d{2}) ?uhr\\b"), let h = Int(g[1]), let mi = Int(g[2]), h < 24, mi < 60 {
            hour = h; minute = mi
        } else if let g = m("\\b(?:um|ab|gegen) (\\d{1,2})(?: ?uhr| ?h)?(?![\\d.:])\\b"), let h = Int(g[1]), h < 24 {
            hour = h
        } else if let g = m("\\b(\\d{1,2}) ?uhr\\b"), let h = Int(g[1]), h < 24 {
            hour = h
        }
        if let h = hour, h < 8, m("\\b(abends?|nachmittags?|heute abend|morgen abend)\\b") != nil { hour = h + 12 }

        guard day != nil || hour != nil else { return nil }
        // Nur eine Uhrzeit ohne Tag: heute (oder morgen, falls schon vorbei) – aber nur mit klarem „um … Uhr“
        if day == nil {
            guard m("\\b(um|ab|gegen) \\d{1,2}([:.]\\d{2})? ?uhr\\b") != nil else { return nil }
            day = today
        }
        guard var start = day else { return nil }
        let allDay = hour == nil
        if let h = hour { start = cal.date(bySettingHour: h, minute: minute, second: 0, of: start) ?? start }
        if !allDay, start < now.addingTimeInterval(-600) {
            if day == today { start = cal.date(byAdding: .day, value: 1, to: start) ?? start } else { return nil }
        }
        guard start < now.addingTimeInterval(400 * 24 * 3600), start >= today else { return nil }
        let end = allDay ? (cal.date(byAdding: .day, value: 1, to: start) ?? start) : start.addingTimeInterval(3600)
        return EventDraft(title: title(from: raw), start: start, end: end, allDay: allDay)
    }

    /// Titel: der Satz ohne Datums-/Zeitangaben, kurz.
    static func title(from raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\n", with: " ")
        let patterns = [
            "(?i)\\b(am |nächsten |kommenden )?(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag)\\b",
            "(?i)\\b(übermorgen|morgen|heute)( abend| früh| nachmittag| vormittag)?\\b",
            "(?i)\\b(um |ab |gegen )?\\d{1,2}([:.]\\d{2})? ?(uhr|h)\\b",
            "(?i)\\bum \\d{1,2}[:.]\\d{2}\\b",
            "(?i)\\b(am )?\\d{1,2}\\.\\d{1,2}\\.(\\d{2,4})?",
        ]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?-:"))
        if t.count < 3 { t = "Termin" }
        if t.count > 60 { t = String(t.prefix(57)) + "…" }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    static func label(_ d: EventDraft) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = d.allDay ? "EE dd.MM." : "EE dd.MM. HH:mm"
        return f.string(from: d.start)
    }
}

// MARK: - Verlauf-Panel

struct HistoryPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var extras: ExtrasState
    @ObservedObject var store = SharedStore.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { state.undoLast() } label: {
                    Label("Rückgängig", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).frame(height: 30)
                        .glassCapsule(tint: state.tint.opacity(0.35), interactive: true)
                }
                .buttonStyle(.plain)
                Toggle(isOn: $store.writeHistory) {
                    Text("Verlauf speichern").font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
                Spacer()
                Button { confirmClear = true } label: {
                    Image(systemName: "trash").font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
            }
            if confirmClear {
                HStack {
                    Text("Ganzen Verlauf löschen?").font(.caption)
                    Spacer()
                    Button("Abbrechen") { confirmClear = false }.font(.caption)
                    Button("Löschen", role: .destructive) { state.clearWritingHistory(); confirmClear = false }.font(.caption.weight(.bold))
                }
                .padding(8).glass(cornerRadius: 10)
            }
            if extras.history.isEmpty {
                Spacer()
                Text(store.writeHistory
                     ? "Noch nichts im Verlauf.\nGelöschtes, gesendete Texte und KI-Änderungen landen hier – nur auf diesem iPhone, höchstens 7 Tage."
                     : "Verlauf ist aus.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(extras.history) { e in row(e) }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func row(_ e: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(e.kind)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(e.kind == "deleted" ? Color.orange : state.tint)
                .frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.text).font(.caption).lineLimit(3)
                Text("\(label(e.kind)) · \(KeyboardState.relative(e.date))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: 4) {
                smallButton("text.insert") { state.insertHistory(e) }
                HStack(spacing: 4) {
                    smallButton("doc.on.doc") { state.copyHistory(e) }
                    smallButton("trash") { state.deleteHistory(e) }
                }
            }
        }
        .padding(8)
        .glass(cornerRadius: 10)
    }

    private func smallButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 26)
                .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "deleted": return "delete.backward"
        case "replaced": return "wand.and.stars"
        default: return "text.alignleft"
        }
    }

    private func label(_ kind: String) -> String {
        switch kind {
        case "deleted": return "Gelöscht"
        case "replaced": return "Vor KI-Änderung"
        default: return "Geschrieben"
        }
    }
}
