import SwiftUI

/// A larger stop marker split into equal route-color slices. The visible marker
/// stays compact enough for dense downtown stops while the tap target is larger.
struct StopAnnotationView: View {
    let stop: Stop
    let routeColors: [Color]
    let routeShortNames: [String]
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let markerSize: CGFloat = 18

    var body: some View {
        ZStack {
            segmentedMarker

            Circle()
                .strokeBorder(
                    colorScheme == .dark ? Color.black.opacity(0.9) : Color.white.opacity(0.95),
                    lineWidth: 2
                )
        }
        .frame(width: markerSize, height: markerSize)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .frame(width: 34, height: 34)
        .contentShape(Circle())
        // `.simultaneousGesture` (not `.gesture`/`Button`) so a touch that starts on a stop
        // doesn't claim exclusivity and block the map's own pinch/pan gesture recognizers.
        .simultaneousGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows stop details")
    }

    @ViewBuilder
    private var segmentedMarker: some View {
        if routeColors.count <= 1 {
            Circle()
                .fill(routeColors.first ?? Color("PrimaryAccent"))
        } else {
            ZStack {
                ForEach(routeColors.indices, id: \.self) { index in
                    EqualPieSlice(index: index, count: routeColors.count)
                        .fill(routeColors[index])
                }
            }
        }
    }

    private var accessibilityLabel: String {
        guard !routeShortNames.isEmpty else { return "\(stop.name), bus stop" }
        return "\(stop.name), routes \(routeShortNames.joined(separator: ", "))"
    }
}

private struct EqualPieSlice: SwiftUI.Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle.degrees(-90 + (360 * Double(index) / Double(count)))
        let endAngle = Angle.degrees(-90 + (360 * Double(index + 1) / Double(count)))
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.35).ignoresSafeArea()
        HStack(spacing: 28) {
            StopAnnotationView(
                stop: Stop(id: 1, name: "Single-route stop", lat: 0, lon: 0),
                routeColors: [.red],
                routeShortNames: ["1"],
                onTap: {}
            )
            StopAnnotationView(
                stop: Stop(id: 2, name: "Two-route stop", lat: 0, lon: 0),
                routeColors: [.red, .blue],
                routeShortNames: ["1", "6"],
                onTap: {}
            )
            StopAnnotationView(
                stop: Stop(id: 3, name: "Four-route stop", lat: 0, lon: 0),
                routeColors: [.red, .blue, .green, .orange],
                routeShortNames: ["1", "3E", "6", "9"],
                onTap: {}
            )
        }
    }
}
