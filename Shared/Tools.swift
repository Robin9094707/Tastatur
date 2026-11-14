import Foundation
import UIKit
import ImageIO

/// Werkzeuge der Schnellleiste – frei anordnungsfähig.
struct ToolItem: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String

    static let all: [ToolItem] = [
        ToolItem(id: "ai", title: "KI", symbol: "wand.and.stars"),
        ToolItem(id: "translate", title: "Übersetzen", symbol: "character.bubble"),
        ToolItem(id: "translateLive", title: "Live übersetzen", symbol: "text.bubble"),
        ToolItem(id: "translateClip", title: "Ablage übersetzen", symbol: "doc.on.clipboard.fill"),
        ToolItem(id: "write", title: "Schreiben", symbol: "pencil.line"),
        ToolItem(id: "clipboard", title: "Ablage", symbol: "doc.on.clipboard"),
        ToolItem(id: "stickers", title: "Sticker", symbol: "face.dashed"),
        ToolItem(id: "emoji", title: "Emoji", symbol: "face.smiling"),
        ToolItem(id: "macros", title: "Makros", symbol: "text.badge.star"),
        ToolItem(id: "cursor", title: "Cursor", symbol: "cursorarrow.motionlines"),
        ToolItem(id: "calc", title: "Rechner", symbol: "plus.forwardslash.minus"),
        ToolItem(id: "paste", title: "Einfügen", symbol: "doc.on.doc"),
        ToolItem(id: "copyAll", title: "Alles kopieren", symbol: "square.on.square"),
        ToolItem(id: "theme", title: "Zufalls-Look", symbol: "dice"),
        ToolItem(id: "settings", title: "Einstellungen", symbol: "gearshape"),
        ToolItem(id: "hide", title: "Ausblenden", symbol: "keyboard.chevron.compact.down"),
    ]

    static let defaultOrder = ["ai", "translate", "write", "clipboard", "stickers", "emoji", "cursor", "calc", "macros", "paste", "settings", "hide"]

    static func item(_ id: String) -> ToolItem? { all.first { $0.id == id } }
}

/// Sprachen für den Übersetzungsmodus.
enum Languages {
    static let all: [(name: String, flag: String)] = [
        ("Englisch", "🇬🇧"), ("Deutsch", "🇩🇪"), ("Spanisch", "🇪🇸"), ("Französisch", "🇫🇷"), ("Italienisch", "🇮🇹"),
        ("Türkisch", "🇹🇷"), ("Polnisch", "🇵🇱"), ("Russisch", "🇷🇺"), ("Ukrainisch", "🇺🇦"), ("Arabisch", "🇸🇦"),
        ("Portugiesisch", "🇵🇹"), ("Niederländisch", "🇳🇱"), ("Griechisch", "🇬🇷"), ("Kroatisch", "🇭🇷"), ("Rumänisch", "🇷🇴"),
        ("Chinesisch", "🇨🇳"), ("Japanisch", "🇯🇵"), ("Koreanisch", "🇰🇷"), ("Hindi", "🇮🇳"), ("Persisch", "🇮🇷"),
    ]

    static func flag(_ name: String) -> String { all.first { $0.name == name }?.flag ?? "🌐" }
}

/// Gespeicherte Sticker (PNG) im gemeinsamen Container.
enum StickerStore {
    static var folder: URL {
        let url = SharedStore.containerURL.appendingPathComponent("Stickers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func list() -> [URL] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension.lowercased() == "png" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }
    }

    /// Speichert Bilddaten als PNG-Sticker (verkleinert, Transparenz bleibt erhalten).
    @discardableResult
    static func add(imageData: Data, maxPixel: Int = 512) -> URL? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let png = UIImage(cgImage: cg).pngData() else { return nil }
        let url = folder.appendingPathComponent("sticker-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        try? png.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func add(image: UIImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        return add(imageData: data)
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Kleines Vorschaubild ohne das ganze Bild zu dekodieren.
    static func thumbnail(_ url: URL, maxPixel: Int = 220) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Sicherer Mini-Rechner (ohne NSExpression, das bei Fehleingaben abstürzen kann).
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        var s = input.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "X", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ":", with: "/")
            .replacingOccurrences(of: " ", with: "")
        if s.hasSuffix("=") { s.removeLast() }
        guard !s.isEmpty, s.allSatisfy({ "0123456789.+-*/()%^".contains($0) }) else { return nil }
        var parser = Parser(chars: Array(s))
        guard let v = parser.expression(), parser.pos == parser.chars.count, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.maximumFractionDigits = 8
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while pos < chars.count, chars[pos] == "+" || chars[pos] == "-" {
                let op = chars[pos]; pos += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while pos < chars.count, chars[pos] == "*" || chars[pos] == "/" {
                let op = chars[pos]; pos += 1
                guard let r = power() else { return nil }
                if op == "/" { if r == 0 { return nil }; v /= r } else { v *= r }
            }
            return v
        }

        mutating func power() -> Double? {
            guard let b = factor() else { return nil }
            if pos < chars.count, chars[pos] == "^" {
                pos += 1
                guard let e = power() else { return nil }
                return pow(b, e)
            }
            return b
        }

        mutating func factor() -> Double? {
            guard pos < chars.count else { return nil }
            var result: Double?
            if chars[pos] == "-" { pos += 1; return factor().map { -$0 } }
            if chars[pos] == "+" { pos += 1; return factor() }
            if chars[pos] == "(" {
                pos += 1
                result = expression()
                guard pos < chars.count, chars[pos] == ")" else { return nil }
                pos += 1
            } else {
                let start = pos
                while pos < chars.count, chars[pos].isNumber || chars[pos] == "." { pos += 1 }
                guard pos > start else { return nil }
                result = Double(String(chars[start..<pos]))
            }
            if var r = result, pos < chars.count, chars[pos] == "%" { pos += 1; r /= 100; result = r }
            return result
        }
    }
}
