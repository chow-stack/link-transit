import SwiftUI

/// Google Maps-style marker for the user's own location: a blue dot with a
/// heading cone that rotates to show which way the device is facing. Built as
/// a custom view (rather than MapKit's stock `UserAnnotation()`) because the
/// built-in heading cone only appears in `.followWithHeading` tracking mode,
/// which also rotates the whole map - we want the map to stay north-up.
struct UserLocationAnnotationView: View {
    let heading: Double?

    var body: some View {
        ZStack {
            if let heading {
                HeadingConeView()
                    .rotationEffect(.degrees(heading))
            }

            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)

            Circle()
                .fill(Color.blue)
                .frame(width: 16, height: 16)
        }
        .allowsHitTesting(false)
    }
}

/// A wide, fading wedge pointing "up" (north) at rotation 0, meant to be
/// rotated by heading degrees so it points wherever the device is facing.
private struct HeadingConeView: View {
    private let radius: CGFloat = 42
    private let halfAngle: Double = 32

    var body: some View {
        Path { path in
            let center = CGPoint(x: radius, y: radius)
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(-90 - halfAngle),
                endAngle: .degrees(-90 + halfAngle),
                clockwise: false
            )
            path.closeSubpath()
        }
        .fill(
            RadialGradient(
                colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.0)],
                center: .center,
                startRadius: 0,
                endRadius: radius
            )
        )
        .frame(width: radius * 2, height: radius * 2)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()

        HStack(spacing: 40) {
            VStack(spacing: 8) {
                UserLocationAnnotationView(heading: 0)
                Text("Facing N").font(.caption2)
            }
            VStack(spacing: 8) {
                UserLocationAnnotationView(heading: 135)
                Text("Facing SE").font(.caption2)
            }
            VStack(spacing: 8) {
                UserLocationAnnotationView(heading: nil)
                Text("No heading").font(.caption2)
            }
        }
    }
}
