import Foundation

/// Prozessübergreifende Kommunikation zwischen Tastatur und App per Darwin-Notifications.
/// Tastatur-Erweiterungen dürfen unter iOS nicht aufs Mikrofon zugreifen – deshalb nimmt
/// die Haupt-App im Hintergrund auf und die Tastatur steuert sie fern.
final class DarwinNotifier {
    static let shared = DarwinNotifier()

    enum Name: String {
        case ping = "de.tastatur.ping"
        case pong = "de.tastatur.pong"
        case start = "de.tastatur.dictation.start"
        case stop = "de.tastatur.dictation.stop"
        case cancel = "de.tastatur.dictation.cancel"
        case recording = "de.tastatur.dictation.recording"
        case processing = "de.tastatur.dictation.processing"
        case result = "de.tastatur.dictation.result"
        case failed = "de.tastatur.dictation.failed"
        case sessionEnded = "de.tastatur.dictation.ended"
    }

    private var handlers: [String: () -> Void] = [:]
    private let lock = NSLock()

    func post(_ name: Name) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name.rawValue as CFString), nil, nil, true)
    }

    func observe(_ name: Name, handler: @escaping () -> Void) {
        lock.lock()
        let isNew = handlers[name.rawValue] == nil
        handlers[name.rawValue] = handler
        lock.unlock()
        guard isNew else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let me = Unmanaged<DarwinNotifier>.fromOpaque(observer).takeUnretainedValue()
            let key = name.rawValue as String
            DispatchQueue.main.async { me.fire(key) }
        }, name.rawValue as CFString, nil, .deliverImmediately)
    }

    func removeAll() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }

    private func fire(_ key: String) {
        lock.lock()
        let h = handlers[key]
        lock.unlock()
        h?()
    }
}

/// Dateien im gemeinsamen Container für den Diktat-Austausch.
enum DictationFiles {
    static var dir: URL {
        let url = SharedStore.containerURL.appendingPathComponent("Dictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var audio: URL { dir.appendingPathComponent("aufnahme.m4a") }
    static var result: URL { dir.appendingPathComponent("ergebnis.txt") }
    static var error: URL { dir.appendingPathComponent("fehler.txt") }
    static var level: URL { dir.appendingPathComponent("pegel.txt") }
    static var status: URL { dir.appendingPathComponent("status.txt") }

    static func write(_ text: String, to url: URL) {
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
