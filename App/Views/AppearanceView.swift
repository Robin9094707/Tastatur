import SwiftUI
import PhotosUI
import UIKit

struct AppearanceView: View {
    @EnvironmentObject var store: SharedStore
    @State private var photoItem: PhotosPickerItem?
    @State private var customColor: Color = .indigo
    @State private var loadingPhoto = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                KeyboardPreview()
                    .environmentObject(store)

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
        .onAppear { customColor = Theme.color(hex: store.backgroundColorHex) }
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
        let o = store.keyOpacity
        let fill: Color = dark
            ? Color.white.opacity((special ? 0.13 : 0.30) * o)
            : (special ? Color(white: 0.68).opacity(0.85 * o) : Color.white.opacity(0.95 * o))
        return Text(text)
            .font(.system(size: (text.count > 2 ? 11 : 17) * store.keyFontScale))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: store.keyCornerRadius * 0.85, style: .continuous).fill(fill))
            .shadow(color: .black.opacity(0.3 * o), radius: 0, y: 1)
    }
}
