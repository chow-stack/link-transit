import SwiftUI

struct RouteIdentityBadge: View {
    let shortName: String
    let colorHex: String?
    var compact = false

    private var background: Color {
        guard let colorHex, !colorHex.isEmpty else { return Color("PrimaryAccent") }
        return Color(hex: colorHex)
    }

    var body: some View {
        Text(shortName)
            .font(compact ? .caption.weight(.bold) : .headline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Route \(shortName)")
    }

    private var foregroundColor: Color {
        guard let colorHex else { return .white }
        let hex = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return .white }
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.62 ? .black : .white
    }
}

private struct AppSheetCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color("PrimaryAccent").opacity(0.10), lineWidth: 1)
            }
    }
}

extension View {
    func appSheetCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(AppSheetCardModifier(cornerRadius: cornerRadius))
    }
}
