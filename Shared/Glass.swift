import SwiftUI

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
