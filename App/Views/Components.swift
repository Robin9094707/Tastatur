import SwiftUI

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 24, tint: tint)
    }
}

struct CardHeader: View {
    var title: String
    var symbol: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .glass(cornerRadius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct GlassButton: View {
    var title: String
    var symbol: String? = nil
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .glass(cornerRadius: 18, tint: prominent ? Color.accentColor : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.appBackground)
    }
}

extension View {
    func glassBackground() -> some View { modifier(GlassBackground()) }

    func glassRow() -> some View {
        listRowBackground(Color.white.opacity(0.07))
    }
}

struct StatusPill: View {
    var ok: Bool
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule()
    }
}
