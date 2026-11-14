import SwiftUI
import UIKit
import Contacts
import CoreLocation
import EventKit
import UniformTypeIdentifiers

// MARK: - Persönliche Daten (Kontakte, Standort, Kalender) – alles optional

/// Holt mit Erlaubnis Kontakte und Standort für die Tastatur (iOS zeigt Tastaturen keinen eigenen Zugriffs-Dialog)
/// und speichert Termine, die die Tastatur vorschlägt.
final class PersonalDataManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PersonalDataManager()

    @Published var contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published var contactCount = 0
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastAddress = ""
    @Published var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var message: String?

    private let location = CLLocationManager()
    private let events = EKEventStore()

    override init() {
        super.init()
        location.delegate = self
        locationStatus = location.authorizationStatus
        contactCount = ContactsCache.load().count
        lastAddress = SavedLocation.load()?.address ?? ""
    }

    /// Beim Öffnen der App: Kontakte und Standort auffrischen (nur wenn eingeschaltet und erlaubt).
    func refreshIfEnabled() {
        let store = SharedStore.shared
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        locationStatus = location.authorizationStatus
        if store.useContacts, contactsAllowed { syncContacts() }
        if store.useLocation, locationAllowed { location.requestLocation() }
    }

    var contactsAllowed: Bool {
        if #available(iOS 18.0, *), contactsStatus == .limited { return true }
        return contactsStatus == .authorized
    }
    var locationAllowed: Bool { locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways }
    var calendarAllowed: Bool { calendarStatus == .fullAccess || calendarStatus == .writeOnly }

    // MARK: Kontakte

    func enableContacts() {
        SharedStore.shared.useContacts = true
        CNContactStore().requestAccess(for: .contacts) { [weak self] ok, _ in
            DispatchQueue.main.async {
                self?.contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
                if ok { self?.syncContacts() } else { self?.message = "Kein Zugriff – in den iOS-Einstellungen → Tastatur KI → Kontakte erlauben." }
            }
        }
    }

    func disableContacts() {
        SharedStore.shared.useContacts = false
        try? FileManager.default.removeItem(at: ContactsCache.url)
        contactCount = 0
    }

    func syncContacts() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor,
            ]
            var list: [ContactEntry] = []
            let req = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: req) { c, stop in
                var name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                if name.isEmpty { name = c.nickname.isEmpty ? c.organizationName : c.nickname }
                guard !name.isEmpty else { return }
                let phones = c.phoneNumbers.map { $0.value.stringValue }.prefix(3)
                let mails = c.emailAddresses.map { $0.value as String }.prefix(3)
                guard !phones.isEmpty || !mails.isEmpty || name.contains(" ") else { return }
                list.append(ContactEntry(name: name, phones: Array(phones), emails: Array(mails)))
                if list.count >= 3000 { stop.pointee = true }
            }
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: ContactsCache.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            DispatchQueue.main.async {
                self?.contactCount = list.count
                self?.message = "\(list.count) Kontakte für die Tastatur bereit ✓"
            }
        }
    }

    // MARK: Standort

    func enableLocation() {
        SharedStore.shared.useLocation = true
        if locationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        } else if locationAllowed {
            location.requestLocation()
        } else {
            message = "Standort ist gesperrt – in den iOS-Einstellungen → Tastatur KI → Standort erlauben."
        }
    }

    func disableLocation() {
        SharedStore.shared.useLocation = false
        try? FileManager.default.removeItem(at: SavedLocation.url)
        lastAddress = ""
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.locationStatus = manager.authorizationStatus
            if self.locationAllowed, SharedStore.shared.useLocation { manager.requestLocation() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "de_DE")) { [weak self] marks, _ in
            var address = ""
            if let p = marks?.first {
                let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                let city = [p.postalCode, p.locality].compactMap { $0 }.joined(separator: " ")
                address = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
                if address.isEmpty { address = p.name ?? "" }
            }
            let saved = SavedLocation(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, address: address, date: Date())
            if let data = try? JSONEncoder().encode(saved) {
                try? data.write(to: SavedLocation.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            DispatchQueue.main.async { self?.lastAddress = address.isEmpty ? "Standort gespeichert" : address }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Kalender

    func enableCalendar(_ done: ((Bool) -> Void)? = nil) {
        events.requestWriteOnlyAccessToEvents { [weak self] ok, _ in
            DispatchQueue.main.async {
                self?.calendarStatus = EKEventStore.authorizationStatus(for: .event)
                if !ok { self?.message = "Kein Kalender-Zugriff – in den iOS-Einstellungen → Tastatur KI → Kalender erlauben." }
                done?(ok)
            }
        }
    }

    /// tastatur://event?title=…&start=…&end=…&allDay=0 – Termin aus der Tastatur speichern.
    func handleEventURL(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
        guard let s = v("start").flatMap(Double.init) else { return }
        let start = Date(timeIntervalSince1970: s)
        let end = v("end").flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? start.addingTimeInterval(3600)
        let title = v("title") ?? "Termin"
        let allDay = v("allDay") == "1"
        let save = { [weak self] in
            guard let self else { return }
            let ev = EKEvent(eventStore: self.events)
            ev.title = title
            ev.startDate = start
            ev.endDate = end
            ev.isAllDay = allDay
            ev.calendar = self.events.defaultCalendarForNewEvents
            do {
                try self.events.save(ev, span: .thisEvent)
                let f = DateFormatter()
                f.locale = Locale(identifier: "de_DE")
                f.dateFormat = allDay ? "EEEE, dd.MM." : "EEEE, dd.MM. 'um' HH:mm"
                self.message = "📅 „\(title)“ gespeichert – \(f.string(from: start)). Wische zurück zu deiner App."
            } catch {
                self.message = "Termin konnte nicht gespeichert werden."
            }
        }
        if calendarAllowed { save() } else { enableCalendar { ok in if ok { save() } } }
    }
}

// MARK: - Sicherung (Export/Import, z. B. in iCloud Drive)

enum BackupManager {
    /// Dateien, die nie in eine Sicherung gehören (Anmeldung, Kontakte, Standort).
    static let excludedFiles: Set<String> = ["chatgpt-session.json", "contacts.json", "last-location.json"]

    private static var domainName: String? {
        SharedStore.shared.usesAppGroup ? SharedStore.appGroup : Bundle.main.bundleIdentifier
    }

    /// Erstellt eine Sicherungsdatei mit allen Einstellungen und allem Gelernten.
    static func makeBackup(includeKey: Bool, in folder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let store = SharedStore.shared
        var defaults = domainName.flatMap { store.defaults.persistentDomain(forName: $0) } ?? [:]
        if !includeKey { defaults["apiKey"] = nil }
        var files: [String: Data] = [:]
        let root = SharedStore.containerURL
        var total = 0
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in e {
                let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                let ext = url.pathExtension.lowercased()
                guard ["json", "jpg", "png"].contains(ext), !excludedFiles.contains(rel), !rel.hasPrefix("Library/"),
                      let data = try? Data(contentsOf: url), total + data.count < 40_000_000 else { continue }
                files[rel] = data
                total += data.count
            }
        }
        let plist: [String: Any] = ["format": "tastatur-backup", "version": 1, "date": Date(), "defaults": defaults, "files": files]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        let url = folder.appendingPathComponent("Tastatur-KI-Sicherung_\(f.string(from: Date())).tastatur")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Spielt eine Sicherung ein (überschreibt Einstellungen und Gelerntes).
    static func restore(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["format"] as? String == "tastatur-backup" else {
            throw NSError(domain: "Tastatur", code: 1, userInfo: [NSLocalizedDescriptionKey: "Keine Tastatur-KI-Sicherung."])
        }
        let store = SharedStore.shared
        if let defaults = plist["defaults"] as? [String: Any] {
            for (k, v) in defaults { store.defaults.set(v, forKey: k) }
        }
        var count = 0
        if let files = plist["files"] as? [String: Data] {
            let root = SharedStore.containerURL
            for (rel, d) in files where !rel.contains("..") && !excludedFiles.contains(rel) {
                let target = root.appendingPathComponent(rel)
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? d.write(to: target, options: .atomic)) != nil { count += 1 }
            }
        }
        store.reload()
        store.backgroundVersion += 1
        return count
    }

    /// Automatische Sicherung (einmal am Tag) im Dokumente-Ordner der App – sichtbar in der Dateien-App
    /// und Teil des iCloud-Backups des iPhones. Behält die letzten 5.
    static func autoBackupIfDue() {
        let d = UserDefaults.standard
        guard d.object(forKey: "autoBackup") as? Bool ?? true else { return }
        let last = d.double(forKey: "autoBackup.last")
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        DispatchQueue.global(qos: .utility).async {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let folder = docs.appendingPathComponent("Sicherungen", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? makeBackup(includeKey: false, in: folder)) != nil else { return }
            d.set(Date().timeIntervalSince1970, forKey: "autoBackup.last")
            let all = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "tastatur" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in all.dropFirst(5) { try? FileManager.default.removeItem(at: old) }
        }
    }
}

extension UTType {
    static var tastaturBackup: UTType { UTType(filenameExtension: "tastatur") ?? .data }
}

// MARK: - Ansicht

struct PrivacyView: View {
    @EnvironmentObject var store: SharedStore
    @ObservedObject var data = PersonalDataManager.shared
    @AppStorage("autoBackup") private var autoBackup = true
    @State private var includeKey = false
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var info: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    CardHeader(title: "Was die Tastatur sehen kann", symbol: "eye.slash.fill")
                    Text("iOS lässt Tastaturen nur das Textfeld sehen, in dem du gerade schreibst – nie den Bildschirm, andere Apps oder empfangene Nachrichten. Das gilt auch für installierte (Sideload-)Apps. Für Antwortvorschläge: Nachricht kopieren, dann schlägt die Tastatur Antworten vor.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                contactsCard
                locationCard
                calendarCard
                backupCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .glassBackground()
        .navigationTitle("Persönliches & Sicherung")
        .onAppear { data.refreshIfEnabled() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.tastaturBackup, .data, .propertyList]) { result in
            switch result {
            case .success(let url):
                do {
                    let n = try BackupManager.restore(from: url)
                    info = "Sicherung eingespielt ✓ (\(n) Dateien). Tastatur einmal schließen und öffnen."
                } catch {
                    info = error.localizedDescription
                }
            case .failure(let e):
                info = e.localizedDescription
            }
        }
        .alert(item: Binding(get: { (data.message ?? info).map { AlertText(text: $0) } },
                             set: { _ in data.message = nil; info = nil })) { a in
            Alert(title: Text(a.text))
        }
    }

    private var contactsCard: some View {
        GlassCard {
            CardHeader(title: "Kontakte", symbol: "person.2.fill", subtitle: "Namen werden nicht mehr „korrigiert“, nach einem Namen schlägt die Tastatur Nummer/E-Mail vor")
            Toggle("Kontakte in der Tastatur nutzen", isOn: Binding(get: { store.useContacts }, set: { $0 ? data.enableContacts() : data.disableContacts() }))
            if store.useContacts {
                HStack {
                    Text(data.contactsAllowed ? "\(data.contactCount) Kontakte bereit" : "Zugriff fehlt").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Aktualisieren") { data.contactsAllowed ? data.syncContacts() : data.enableContacts() }.font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var locationCard: some View {
        GlassCard {
            CardHeader(title: "Standort", symbol: "location.fill", subtitle: "Werkzeug „Standort“ in der Tastatur fügt Adresse + Karten-Link ein")
            Toggle("Standort senden erlauben", isOn: Binding(get: { store.useLocation }, set: { $0 ? data.enableLocation() : data.disableLocation() }))
            if store.useLocation {
                Text(data.locationAllowed ? (data.lastAddress.isEmpty ? "Wird ermittelt …" : "Zuletzt: \(data.lastAddress)") : "Zugriff fehlt – Schalter erneut tippen oder in den iOS-Einstellungen erlauben.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Die Tastatur fragt den Standort selbst ab, wenn iOS es zulässt – sonst nimmt sie den letzten aus der App (wird beim Öffnen der App aktualisiert).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var calendarCard: some View {
        GlassCard {
            CardHeader(title: "Kalender", symbol: "calendar.badge.plus", subtitle: "Schreibst du „morgen um 15 Uhr“, bietet die Tastatur „Termin speichern“ an")
            Toggle("Termine erkennen", isOn: $store.calendarSuggest)
            HStack {
                Text(data.calendarAllowed ? "Kalender-Zugriff erlaubt ✓" : "Noch kein Zugriff (nur Schreiben, kein Lesen)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !data.calendarAllowed {
                    Button("Erlauben") { data.enableCalendar() }.font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var backupCard: some View {
        GlassCard {
            CardHeader(title: "Sicherung & iCloud Drive", symbol: "icloud.and.arrow.up.fill", subtitle: "Einstellungen, Gelerntes, Makros, Ablage, Sticker, KI-Gedächtnis")
            Text("Echte iCloud-Synchronisierung braucht ein bezahltes Apple-Entwicklerkonto (bei installierten Apps nicht möglich). Stattdessen: Sicherung exportieren und „In Dateien sichern“ → iCloud Drive wählen. Auf dem anderen iPhone einfach importieren.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("API-Schlüssel mitsichern", isOn: $includeKey)
            HStack {
                GlassButton(title: "Exportieren", symbol: "square.and.arrow.up", prominent: true) {
                    exportURL = try? BackupManager.makeBackup(includeKey: includeKey)
                    if exportURL == nil { info = "Sicherung fehlgeschlagen." }
                }
                GlassButton(title: "Importieren", symbol: "square.and.arrow.down") { importing = true }
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Sicherung teilen / in iCloud Drive sichern", systemImage: "icloud.and.arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glass(cornerRadius: 14, tint: .accentColor, interactive: true)
                }
                .buttonStyle(.plain)
            }
            Toggle("Täglich automatisch sichern", isOn: $autoBackup)
            Text("Automatische Sicherungen liegen in der Dateien-App unter „Auf meinem iPhone → Tastatur KI → Sicherungen“ (die letzten 5) und sind im iCloud-Backup des iPhones enthalten.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct AlertText: Identifiable {
    let text: String
    var id: String { text }
}
