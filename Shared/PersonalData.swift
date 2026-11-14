import Foundation

// MARK: - Kontakte (von der App bereitgestellt, nur lokal)

struct ContactEntry: Codable {
    var name: String
    var phones: [String]
    var emails: [String]
}

enum ContactsCache {
    static var url: URL { SharedStore.containerURL.appendingPathComponent("contacts.json") }
    static func load() -> [ContactEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ContactEntry].self, from: data)) ?? []
    }
}

/// Letzter Standort, den die App gespeichert hat (Notlösung, falls die Tastatur selbst keinen Standort bekommt).
struct SavedLocation: Codable {
    var lat: Double
    var lon: Double
    var address: String
    var date: Date
    static var url: URL { SharedStore.containerURL.appendingPathComponent("last-location.json") }
    static func load() -> SavedLocation? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedLocation.self, from: data)
    }
}
