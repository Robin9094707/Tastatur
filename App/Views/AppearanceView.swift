import SwiftUI
import PhotosUI
import UIKit

struct AppearanceView: View {
    @EnvironmentObject var store: SharedStore
    @State private var photoItem: PhotosPickerItem?
    @State private var customColor: Color = .indigo
    @State private var keyColor: Color = .white
    @State private var textColor: Color = .black
    @State private var loadingPhoto = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                KeyboardPreview()
                    .environmentObject(store)

                GlassCard {
                    CardHeader(title: "Themes", symbol: "swatchpalette", subtitle: "Komplett-Looks mit einem Tipp")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ThemePreset.all) { theme in
                                Button {
                                    withAnimation(.snappy) { theme.apply(to: store) }
                                    keyColor = Theme.color(hex: theme.keyColorHex)
                                } label: {
                                    VStack(spacing: 6) {
                                        ThemeThumbnail(theme: theme)
                                            .frame(width: 92, height: 64)
                                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(.white, lineWidth: store.themeID == theme.id ? 3 : 0))
                                        Text(theme.name).font(.caption2.weight(.semibold)).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                GlassCard {
                    CardHeader(title: "Tastenstil", symbol: "keyboard.badge.ellipsis")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(KeyStyle.allCases) { style in
                            Button {
                                store.keyStyle = style.rawValue
                                store.themeID = ""
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: style.symbol).font(.title3)
                                    Text(style.label).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .foregroundStyle(store.keyStyle == style.rawValue ? Color.white : Color.primary)
                                .glass(cornerRadius: 14, tint: store.keyStyle == style.rawValue ? Theme.tint(store.keyboardTint) : nil, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if store.keyStyle == KeyStyle.solid.rawValue || store.keyStyle == KeyStyle.bubble.rawValue {
                        ColorPicker("Tastenfarbe", selection: $keyColor, supportsOpacity: false)
                            .onChange(of: keyColor) { _, c in store.keyColorHex = Theme.hex(from: c) }
                    }
                    Toggle("Eigene Schriftfarbe", isOn: Binding(
                        get: { !store.keyTextColorHex.isEmpty },
                        set: { store.keyTextColorHex = $0 ? Theme.hex(from: textColor) : "" }))
                    if !store.keyTextColorHex.isEmpty {
                        ColorPicker("Schriftfarbe", selection: $textColor, supportsOpacity: false)
                            .onChange(of: textColor) { _, c in store.keyTextColorHex = Theme.hex(from: c) }
                    }
                    Picker("Schriftart", selection: $store.keyFontDesign) {
                        Text("Standard").tag("default")
                        Text("Rund").tag("rounded")
                        Text("Serif").tag("serif")
                        Text("Mono").tag("mono")
                    }
                    .pickerStyle(.segmented)
                }

                GlassCard {
                    CardHeader(title: "Hintergrund", symbol: "photo.on.rectangle.angled")
                    Picker("Stil", selection: $store.backgroundStyle) {
                        Text("System").tag("system")
                        Text("Verlauf").tag("gradient")
                        Text("Farbe").tag("color")
                        Text("Foto").tag("image")
                    }
                    .pickerStyle(.segmented)

                    switch store.backgroundStyle {
                    case "gradient":
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(Array(Theme.backgroundPresets.enumerated()), id: \.offset) { i, preset in
                                Button { store.backgroundPreset = i } label: {
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(height: 48)
                                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: store.backgroundPreset == i ? 3 : 0))
                                        Text(preset.name).font(.caption2).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    case "color":
                        ColorPicker("Eigene Farbe", selection: $customColor, supportsOpacity: false)
                            .onChange(of: customColor) { _, c in store.backgroundColorHex = Theme.hex(from: c) }
                    case "image":
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(loadingPhoto ? "Lade Foto …" : "Foto auswählen", systemImage: "photo")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .glass(cornerRadius: 14, tint: .accentColor, interactive: true)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading) {
                            Text("Abdunkeln: \(Int(store.backgroundDim * 100)) %").font(.subheadline)
                            Slider(value: $store.backgroundDim, in: 0...0.8)
                        }
                    default:
                        Text("Nutzt den Glas-Hintergrund von iOS mit deiner Akzentfarbe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard {
                    CardHeader(title: "Akzentfarbe", symbol: "paintpalette")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(Theme.tints.enumerated()), id: \.offset) { index, tint in
                                Button { store.keyboardTint = index } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(tint.color.gradient)
                                            .frame(width: 40, height: 40)
                                            .overlay(Circle().strokeBorder(.white, lineWidth: store.keyboardTint == index ? 3 : 0))
                                        Text(tint.name).font(.caption2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                GlassCard {
                    CardHeader(title: "Tasten", symbol: "keyboard")
                    sliderRow("Deckkraft", value: $store.keyOpacity, range: 0.2...1, format: "\(Int(store.keyOpacity * 100)) %")
                    sliderRow("Eckenrundung", value: $store.keyCornerRadius, range: 2...18, format: "\(Int(store.keyCornerRadius)) pt")
                    sliderRow("Schriftgröße", value: $store.keyFontScale, range: 0.8...1.25, format: "\(Int(store.keyFontScale * 100)) %")
                    Toggle("Zahlenreihe oben", isOn: $store.showNumberRow)
                    Toggle("Tasten-Vorschau beim Tippen", isOn: $store.keyPopups)
                    Button("Tasten zurücksetzen") {
                        store.keyOpacity = 1
                        store.keyCornerRadius = 8.5
                        store.keyFontScale = 1
                    }
                    .font(.caption)
                }
            }
            .padding(16)
        }
        .glassBackground()
        .navigationTitle("Design")
        .onAppear {
            customColor = Theme.color(hex: store.backgroundColorHex)
            keyColor = Theme.color(hex: store.keyColorHex)
            if !store.keyTextColorHex.isEmpty { textColor = Theme.color(hex: store.keyTextColorHex) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            loadingPhoto = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = Self.downscaled(image).jpegData(compressionQuality: 0.82) {
                    await MainActor.run {
                        store.saveBackgroundImage(jpeg)
                        loadingPhoto = false
                    }
                } else {
                    await MainActor.run { loadingPhoto = false }
                }
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(format).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    /// Verkleinert das Foto, damit die Tastatur wenig Speicher braucht.
    static func downscaled(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 1400
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Live-Vorschau der Tastatur mit aktuellem Design.
struct KeyboardPreview: View {
    @EnvironmentObject var store: SharedStore

    private let rows = [
        ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "ü"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä"],
        ["⇧", "y", "x", "c", "v", "b", "n", "m", "⌫"],
    ]

    private var dark: Bool { Theme.backgroundIsDark(store) ?? true }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Theme.tint(store.keyboardTint))
                    .frame(width: 30, height: 30).glass(cornerRadius: 15)
                HStack {
                    Text("„Hallo“").foregroundStyle(.secondary)
                    Spacer()
                    Text("Hallo")
                    Spacer()
                    Label("wie geht's dir?", systemImage: "sparkles").font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.tint(store.keyboardTint).opacity(0.3)))
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .glassCapsule()
            }
            if store.showNumberRow {
                keyRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
            }
            ForEach(rows, id: \.self) { keyRow($0) }
            HStack(spacing: 5) {
                key("123", special: true).frame(width: 46)
                key("😊", special: true).frame(width: 34)
                key("Leerzeichen", special: false)
                key("⏎", special: true).frame(width: 64)
            }
        }
        .padding(8)
        .background(KeyboardBackgroundView(store: store, scheme: dark ? .dark : .light))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.2)))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { k in key(k, special: k == "⇧" || k == "⌫") }
        }
    }

    private func key(_ text: String, special: Bool) -> some View {
        let style = KeyStyle(rawValue: store.keyStyle) ?? .glass
        let c = KeyStyleKit.colors(style: style, dark: dark, tint: UIColor(Theme.tint(store.keyboardTint)),
                                   keyColor: Theme.uiColor(hex: store.keyColorHex),
                                   textColor: store.keyTextColorHex.isEmpty ? nil : Theme.uiColor(hex: store.keyTextColorHex),
                                   opacity: store.keyOpacity)
        let radius = c.capsule ? 18 : store.keyCornerRadius * 0.85
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Text(text)
            .font(.system(size: (text.count > 2 ? 11 : 17) * store.keyFontScale, design: KeyStyleKit.swiftUIDesign(store.keyFontDesign)))
            .foregroundStyle(Color(uiColor: special ? c.specialText : c.text))
            .shadow(color: style == .neon ? Theme.tint(store.keyboardTint) : .clear, radius: 3)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(shape.fill(Color(uiColor: special ? c.specialFill : c.fill)))
            .overlay(shape.strokeBorder(Color(uiColor: c.border), lineWidth: c.borderWidth))
            .shadow(color: Color(uiColor: c.shadowColor).opacity(Double(c.shadowOpacity)), radius: c.shadowRadius, y: c.shadowOffsetY)
    }
}

/// Kleine Vorschau eines Themes.
struct ThemeThumbnail: View {
    let theme: ThemePreset

    var body: some View {
        let dark = theme.backgroundStyle == "system" ? true : (theme.backgroundStyle == "gradient" ? theme.backgroundPreset != 5 : KeyStyleKit.luminance(Theme.uiColor(hex: theme.backgroundColorHex)) < 0.6)
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
