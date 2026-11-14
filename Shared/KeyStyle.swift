import UIKit
import SwiftUI

/// Darstellungsstile der Tasten.
enum KeyStyle: String, CaseIterable, Identifiable {
    case glass, classic, solid, outline, neon, minimal, bubble

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Glas"
        case .classic: return "iOS Klassik"
        case .solid: return "Farbig"
        case .outline: return "Umriss"
        case .neon: return "Neon"
        case .minimal: return "Minimal"
        case .bubble: return "Bubbles"
        }
    }

    var symbol: String {
        switch self {
        case .glass: return "square.on.square.dashed"
        case .classic: return "apple.logo"
        case .solid: return "square.fill"
        case .outline: return "square"
        case .neon: return "light.max"
        case .minimal: return "textformat"
        case .bubble: return "capsule.fill"
        }
    }
}

/// Fertig berechnete Farben für eine Taste.
struct KeyColors {
    var fill: UIColor
    var fillPressed: UIColor
    var specialFill: UIColor
    var specialFillPressed: UIColor
    var border: UIColor = .clear
    var borderWidth: CGFloat = 0
    var text: UIColor
    var specialText: UIColor
    var shadowColor: UIColor = .black
    var shadowOpacity: Float = 0.3
    var shadowRadius: CGFloat = 0
    var shadowOffsetY: CGFloat = 1
    var capsule = false
}

enum KeyStyleKit {
    static func colors(style: KeyStyle, dark: Bool, tint: UIColor, keyColor: UIColor, textColor: UIColor?, opacity k: CGFloat) -> KeyColors {
        func auto(_ bg: UIColor) -> UIColor { luminance(bg) > 0.6 ? .black : .white }
        switch style {
        case .glass:
            if dark {
                return KeyColors(fill: .init(white: 1, alpha: 0.30 * k), fillPressed: .init(white: 1, alpha: 0.55),
                                 specialFill: .init(white: 1, alpha: 0.13 * k), specialFillPressed: .init(white: 1, alpha: 0.40),
                                 text: textColor ?? .white, specialText: textColor ?? .white, shadowOpacity: Float(0.45 * k))
            }
            return KeyColors(fill: .init(white: 1, alpha: 0.95 * k), fillPressed: .init(white: 0.72, alpha: 0.95),
                             specialFill: .init(white: 0.68, alpha: 0.85 * k), specialFillPressed: .init(white: 0.98, alpha: 0.95),
                             text: textColor ?? .black, specialText: textColor ?? .black, shadowOpacity: Float(0.25 * k))
        case .classic:
            if dark {
                return KeyColors(fill: .init(white: 0.42, alpha: k), fillPressed: .init(white: 0.62, alpha: 1),
                                 specialFill: .init(white: 0.26, alpha: k), specialFillPressed: .init(white: 0.42, alpha: 1),
                                 text: textColor ?? .white, specialText: textColor ?? .white, shadowOpacity: 0.5)
            }
            return KeyColors(fill: .init(white: 1, alpha: k), fillPressed: .init(red: 0.69, green: 0.71, blue: 0.75, alpha: 1),
                             specialFill: .init(red: 0.69, green: 0.71, blue: 0.75, alpha: k), specialFillPressed: .white,
                             text: textColor ?? .black, specialText: textColor ?? .black, shadowOpacity: 0.35)
        case .solid:
            let special = blend(keyColor, with: dark ? .black : .black, amount: 0.22)
            return KeyColors(fill: keyColor.withAlphaComponent(k), fillPressed: blend(keyColor, with: .white, amount: 0.35),
                             specialFill: special.withAlphaComponent(k), specialFillPressed: blend(special, with: .white, amount: 0.35),
                             text: textColor ?? auto(keyColor), specialText: textColor ?? auto(special), shadowOpacity: 0.3)
        case .outline:
            let line: UIColor = dark ? .init(white: 1, alpha: 0.55) : .init(white: 0, alpha: 0.35)
            return KeyColors(fill: .init(white: dark ? 1 : 0, alpha: 0.04), fillPressed: .init(white: dark ? 1 : 0, alpha: 0.22),
                             specialFill: .init(white: dark ? 1 : 0, alpha: 0.10), specialFillPressed: .init(white: dark ? 1 : 0, alpha: 0.28),
                             border: line, borderWidth: 1.2,
                             text: textColor ?? (dark ? .white : .black), specialText: textColor ?? (dark ? .white : .black),
                             shadowOpacity: 0)
        case .neon:
            let glowText = textColor ?? blend(tint, with: .white, amount: 0.45)
            return KeyColors(fill: .init(white: 0, alpha: 0.38 * k), fillPressed: tint.withAlphaComponent(0.45),
                             specialFill: .init(white: 0, alpha: 0.55 * k), specialFillPressed: tint.withAlphaComponent(0.55),
                             border: tint.withAlphaComponent(0.95), borderWidth: 1.3,
                             text: glowText, specialText: glowText,
                             shadowColor: tint, shadowOpacity: 0.75, shadowRadius: 5, shadowOffsetY: 0)
        case .minimal:
            return KeyColors(fill: .clear, fillPressed: .init(white: dark ? 1 : 0, alpha: 0.18),
                             specialFill: .clear, specialFillPressed: .init(white: dark ? 1 : 0, alpha: 0.18),
                             text: textColor ?? (dark ? .white : .black), specialText: textColor ?? (dark ? .init(white: 1, alpha: 0.7) : .init(white: 0, alpha: 0.6)),
                             shadowOpacity: 0)
        case .bubble:
            let base = keyColor
            return KeyColors(fill: base.withAlphaComponent(0.88 * k), fillPressed: blend(base, with: .white, amount: 0.4),
                             specialFill: blend(base, with: .black, amount: 0.25).withAlphaComponent(0.88 * k), specialFillPressed: blend(base, with: .white, amount: 0.3),
                             text: textColor ?? auto(base), specialText: textColor ?? auto(blend(base, with: .black, amount: 0.25)),
                             shadowOpacity: 0.25, shadowRadius: 2, shadowOffsetY: 1.5, capsule: true)
        }
    }

    static func luminance(_ c: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    static func blend(_ a: UIColor, with b: UIColor, amount t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    static func font(size: CGFloat, weight: UIFont.Weight, design: String) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let d: UIFontDescriptor.SystemDesign
        switch design {
        case "rounded": d = .rounded
        case "serif": d = .serif
        case "mono": d = .monospaced
        default: return base
        }
        guard let desc = base.fontDescriptor.withDesign(d) else { return base }
        return UIFont(descriptor: desc, size: size)
    }

    static func swiftUIDesign(_ design: String) -> Font.Design {
        switch design {
        case "rounded": return .rounded
        case "serif": return .serif
        case "mono": return .monospaced
        default: return .default
        }
    }
}

/// Komplett-Themes: setzen Hintergrund, Tastenstil, Farben und Schrift auf einmal.
struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let backgroundStyle: String
    let backgroundPreset: Int
    let backgroundColorHex: String
    let keyStyle: KeyStyle
    let keyColorHex: String
    let textColorHex: String
    let tint: Int
    let font: String
    let radius: Double
    let opacity: Double

    static let all: [ThemePreset] = [
        ThemePreset(id: "ios", name: "iOS Klassik", backgroundStyle: "system", backgroundPreset: 0, backgroundColorHex: "#000000", keyStyle: .classic, keyColorHex: "#FFFFFF", textColorHex: "", tint: 1, font: "default", radius: 5.5, opacity: 1),
        ThemePreset(id: "glass", name: "Liquid Glass", backgroundStyle: "system", backgroundPreset: 0, backgroundColorHex: "#000000", keyStyle: .glass, keyColorHex: "#FFFFFF", textColorHex: "", tint: 0, font: "default", radius: 9, opacity: 0.85),
        ThemePreset(id: "aurora", name: "Aurora", backgroundStyle: "gradient", backgroundPreset: 0, backgroundColorHex: "#000000", keyStyle: .glass, keyColorHex: "#FFFFFF", textColorHex: "", tint: 0, font: "rounded", radius: 11, opacity: 0.8),
        ThemePreset(id: "neon", name: "Neon Nacht", backgroundStyle: "gradient", backgroundPreset: 4, backgroundColorHex: "#000000", keyStyle: .neon, keyColorHex: "#000000", textColorHex: "", tint: 4, font: "rounded", radius: 10, opacity: 1),
        ThemePreset(id: "cyber", name: "Cyber", backgroundStyle: "color", backgroundPreset: 0, backgroundColorHex: "#05060A", keyStyle: .neon, keyColorHex: "#000000", textColorHex: "", tint: 1, font: "mono", radius: 4, opacity: 1),
        ThemePreset(id: "sunset", name: "Sonnenuntergang", backgroundStyle: "gradient", backgroundPreset: 1, backgroundColorHex: "#000000", keyStyle: .glass, keyColorHex: "#FFFFFF", textColorHex: "", tint: 3, font: "rounded", radius: 12, opacity: 0.75),
        ThemePreset(id: "peach", name: "Pfirsich", backgroundStyle: "gradient", backgroundPreset: 5, backgroundColorHex: "#000000", keyStyle: .bubble, keyColorHex: "#FFF4EC", textColorHex: "#7A3B2E", tint: 4, font: "rounded", radius: 20, opacity: 1),
        ThemePreset(id: "ocean", name: "Ozean", backgroundStyle: "gradient", backgroundPreset: 2, backgroundColorHex: "#000000", keyStyle: .outline, keyColorHex: "#FFFFFF", textColorHex: "", tint: 1, font: "default", radius: 10, opacity: 1),
        ThemePreset(id: "forest", name: "Wald", backgroundStyle: "gradient", backgroundPreset: 3, backgroundColorHex: "#000000", keyStyle: .solid, keyColorHex: "#2E5E43", textColorHex: "#E8FFF1", tint: 2, font: "rounded", radius: 9, opacity: 0.95),
        ThemePreset(id: "minimal", name: "Minimal", backgroundStyle: "gradient", backgroundPreset: 7, backgroundColorHex: "#000000", keyStyle: .minimal, keyColorHex: "#FFFFFF", textColorHex: "", tint: 5, font: "default", radius: 8, opacity: 1),
        ThemePreset(id: "paper", name: "Papier", backgroundStyle: "color", backgroundPreset: 0, backgroundColorHex: "#EFE8DC", keyStyle: .solid, keyColorHex: "#FBF8F2", textColorHex: "#3B3227", tint: 3, font: "serif", radius: 6, opacity: 1),
        ThemePreset(id: "candy", name: "Candy", backgroundStyle: "gradient", backgroundPreset: 6, backgroundColorHex: "#000000", keyStyle: .bubble, keyColorHex: "#FFFFFF", textColorHex: "#C2185B", tint: 4, font: "rounded", radius: 20, opacity: 1),
        ThemePreset(id: "sakura", name: "Sakura", backgroundStyle: "gradient", backgroundPreset: 8, backgroundColorHex: "#000000", keyStyle: .glass, keyColorHex: "#FFFFFF", textColorHex: "#8E2450", tint: 4, font: "rounded", radius: 14, opacity: 0.9),
        ThemePreset(id: "lava", name: "Lava", backgroundStyle: "gradient", backgroundPreset: 9, backgroundColorHex: "#000000", keyStyle: .neon, keyColorHex: "#000000", textColorHex: "", tint: 3, font: "default", radius: 8, opacity: 1),
        ThemePreset(id: "polar", name: "Polarlicht", backgroundStyle: "gradient", backgroundPreset: 10, backgroundColorHex: "#000000", keyStyle: .glass, keyColorHex: "#FFFFFF", textColorHex: "", tint: 2, font: "rounded", radius: 12, opacity: 0.7),
        ThemePreset(id: "gold", name: "Gold", backgroundStyle: "gradient", backgroundPreset: 11, backgroundColorHex: "#000000", keyStyle: .outline, keyColorHex: "#FFFFFF", textColorHex: "#FFE7A8", tint: 3, font: "serif", radius: 6, opacity: 1),
        ThemePreset(id: "matrix", name: "Matrix", backgroundStyle: "gradient", backgroundPreset: 12, backgroundColorHex: "#000000", keyStyle: .minimal, keyColorHex: "#000000", textColorHex: "#39FF7A", tint: 2, font: "mono", radius: 4, opacity: 1),
        ThemePreset(id: "vapor", name: "Vaporwave", backgroundStyle: "gradient", backgroundPreset: 13, backgroundColorHex: "#000000", keyStyle: .bubble, keyColorHex: "#2A1B4D", textColorHex: "#FFFFFF", tint: 4, font: "rounded", radius: 20, opacity: 0.85),
        ThemePreset(id: "arctic", name: "Arktis", backgroundStyle: "gradient", backgroundPreset: 14, backgroundColorHex: "#000000", keyStyle: .classic, keyColorHex: "#FFFFFF", textColorHex: "#1B3A57", tint: 1, font: "default", radius: 9, opacity: 0.95),
        ThemePreset(id: "espresso", name: "Espresso", backgroundStyle: "gradient", backgroundPreset: 15, backgroundColorHex: "#000000", keyStyle: .solid, keyColorHex: "#5A3D2B", textColorHex: "#F5E6D3", tint: 3, font: "serif", radius: 8, opacity: 1),
        ThemePreset(id: "obsidian", name: "Obsidian", backgroundStyle: "color", backgroundPreset: 0, backgroundColorHex: "#0B0B0F", keyStyle: .glass, keyColorHex: "#FFFFFF", textColorHex: "", tint: 0, font: "default", radius: 10, opacity: 0.7),
    ]

    /// Zufälliger, aber stimmiger Look.
    static func random() -> ThemePreset {
        let styles = KeyStyle.allCases
        let bg = Int.random(in: 0..<Theme.backgroundPresets.count)
        let style = styles.randomElement() ?? .glass
        let colors = ["#FFFFFF", "#2A1B4D", "#FFF4EC", "#2E5E43", "#1E2A44", "#5A3D2B", "#F0E6FF"]
        return ThemePreset(id: "random-\(UUID().uuidString.prefix(6))", name: "Zufall", backgroundStyle: "gradient", backgroundPreset: bg,
                           backgroundColorHex: "#000000", keyStyle: style, keyColorHex: colors.randomElement() ?? "#FFFFFF",
                           textColorHex: "", tint: Int.random(in: 0..<Theme.tints.count),
                           font: ["default", "rounded", "serif", "mono"].randomElement() ?? "default",
                           radius: [5, 8, 10, 12, 16].randomElement() ?? 9, opacity: [0.7, 0.85, 1].randomElement() ?? 1)
    }

    func apply(to store: SharedStore) {
        store.backgroundStyle = backgroundStyle
        store.backgroundPreset = backgroundPreset
        store.backgroundColorHex = backgroundColorHex
        store.keyStyle = keyStyle.rawValue
        store.keyColorHex = keyColorHex
        store.keyTextColorHex = textColorHex
        store.keyboardTint = tint
        store.keyFontDesign = font
        store.keyCornerRadius = radius
        store.keyOpacity = opacity
        store.themeID = id
    }
}

/// Kleine Vorschau eines Themes.
struct ThemeThumbnail: View {
    let theme: ThemePreset

    var body: some View {
        let dark = theme.backgroundStyle == "system" ? true : (theme.backgroundStyle == "gradient" ? !Theme.lightPresets.contains(theme.backgroundPreset) : KeyStyleKit.luminance(Theme.uiColor(hex: theme.backgroundColorHex)) < 0.6)
        let c = KeyStyleKit.colors(style: theme.keyStyle, dark: dark, tint: UIColor(Theme.tint(theme.tint)),
                                   keyColor: Theme.uiColor(hex: theme.keyColorHex),
                                   textColor: theme.textColorHex.isEmpty ? nil : Theme.uiColor(hex: theme.textColorHex),
                                   opacity: theme.opacity)
        ZStack {
            background
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 3) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: c.capsule ? 5 : min(theme.radius / 3, 4), style: .continuous)
                                .fill(Color(uiColor: c.fill))
                                .overlay(RoundedRectangle(cornerRadius: c.capsule ? 5 : min(theme.radius / 3, 4), style: .continuous)
                                    .strokeBorder(Color(uiColor: c.border), lineWidth: c.borderWidth * 0.6))
                                .frame(height: 12)
                        }
                    }
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        switch theme.backgroundStyle {
        case "gradient":
            LinearGradient(colors: Theme.backgroundPresets[min(theme.backgroundPreset, Theme.backgroundPresets.count - 1)].colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case "color":
            Theme.color(hex: theme.backgroundColorHex)
        default:
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
        }
    }
}
