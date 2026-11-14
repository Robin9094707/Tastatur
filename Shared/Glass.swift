import SwiftUI
import UIKit

/// Liquid-Glass-Helfer: nutzt unter iOS 26 die echten Glas-Effekte,
/// fällt auf älteren Systemen auf Material zurück.
extension View {
    @ViewBuilder
    func glass(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill((tint ?? .clear).opacity(0.25))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                )
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: Capsule())
        } else {
            self.background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill((tint ?? .clear).opacity(0.25)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
            )
        }
    }
}

/// Container, der unter iOS 26 benachbarte Glas-Elemente verschmelzen lässt.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

enum Theme {
    static let tints: [(name: String, color: Color)] = [
        ("Aurora", Color(red: 0.42, green: 0.36, blue: 1.0)),
        ("Ozean", Color(red: 0.15, green: 0.6, blue: 1.0)),
        ("Minze", Color(red: 0.2, green: 0.8, blue: 0.6)),
        ("Sonne", Color(red: 1.0, green: 0.6, blue: 0.2)),
        ("Kirsche", Color(red: 1.0, green: 0.3, blue: 0.5)),
        ("Graphit", Color(white: 0.5)),
    ]

    static func tint(_ index: Int) -> Color {
        tints[max(0, min(index, tints.count - 1))].color
    }

    static var appBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.08, blue: 0.35), Color(red: 0.05, green: 0.05, blue: 0.15)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 1.0, green: 0.35, blue: 0.75).opacity(0.45)).frame(width: 380).blur(radius: 120).offset(x: -140, y: -300)
            Circle().fill(Color(red: 0.2, green: 0.8, blue: 1.0).opacity(0.40)).frame(width: 420).blur(radius: 130).offset(x: 160, y: 320)
            Circle().fill(Color(red: 0.5, green: 0.4, blue: 1.0).opacity(0.35)).frame(width: 300).blur(radius: 110).offset(x: 120, y: -60)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Tastatur-Hintergründe

extension Theme {
    static let backgroundPresets: [(name: String, colors: [Color])] = [
        ("Aurora", [Color(red: 0.30, green: 0.16, blue: 0.60), Color(red: 0.08, green: 0.35, blue: 0.62)]),
        ("Sonnenuntergang", [Color(red: 0.85, green: 0.33, blue: 0.35), Color(red: 0.42, green: 0.16, blue: 0.52)]),
        ("Ozean", [Color(red: 0.02, green: 0.30, blue: 0.50), Color(red: 0.05, green: 0.55, blue: 0.60)]),
        ("Wald", [Color(red: 0.06, green: 0.30, blue: 0.20), Color(red: 0.20, green: 0.45, blue: 0.25)]),
        ("Mitternacht", [Color(red: 0.05, green: 0.05, blue: 0.12), Color(red: 0.16, green: 0.12, blue: 0.30)]),
        ("Pfirsich", [Color(red: 0.98, green: 0.60, blue: 0.45), Color(red: 0.90, green: 0.40, blue: 0.60)]),
        ("Neon", [Color(red: 0.95, green: 0.10, blue: 0.60), Color(red: 0.10, green: 0.80, blue: 0.95)]),
        ("Graphit", [Color(white: 0.18), Color(white: 0.30)]),
    ]

    static func color(hex: String) -> Color {
        Color(uiColor: uiColor(hex: hex))
    }

    static func uiColor(hex: String) -> UIColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .systemIndigo }
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func hex(from color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }

    /// Ob der gewählte Hintergrund dunkel ist (dann helle Schrift / dunkle Tasten).
    static func backgroundIsDark(_ store: SharedStore) -> Bool? {
        switch store.backgroundStyle {
        case "gradient":
            return store.backgroundPreset != 5
        case "color":
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor(hex: store.backgroundColorHex).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (0.299 * r + 0.587 * g + 0.114 * b) < 0.6
        case "image":
            return true
        default:
            return nil
        }
    }
}

/// Lädt das Hintergrundbild nur einmal pro Version.
enum BackgroundImageCache {
    private static var cached: (version: Int, image: UIImage)?

    static func image(version: Int) -> UIImage? {
        if let c = cached, c.version == version { return c.image }
        guard let img = UIImage(contentsOfFile: SharedStore.backgroundImageURL.path) else { return nil }
        cached = (version, img)
        return img
    }
}

/// Hintergrund der Tastatur – genutzt in der Tastatur und als Vorschau in der App.
struct KeyboardBackgroundView: View {
    @ObservedObject var store: SharedStore
    var scheme: ColorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch store.backgroundStyle {
                case "gradient":
                    let preset = Theme.backgroundPresets[max(0, min(store.backgroundPreset, Theme.backgroundPresets.count - 1))]
                    LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                case "color":
                    Theme.color(hex: store.backgroundColorHex)
                case "image":
                    if let img = BackgroundImageCache.image(version: store.backgroundVersion) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        Color.black.opacity(store.backgroundDim)
                    } else {
                        Color.clear
                    }
                default:
                    LinearGradient(colors: [Theme.tint(store.keyboardTint).opacity(scheme == .dark ? 0.20 : 0.10), Color.clear], startPoint: .top, endPoint: .bottom)
                    LinearGradient(colors: [Color.clear, Theme.tint(store.keyboardTint).opacity(scheme == .dark ? 0.10 : 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
