import SwiftUI

/// Stop annotation with route-based color coding and adaptive outline
/// Outline is black in dark mode and white in light mode for optimal visibility
struct StopAnnotationView: View {
    let stop: Stop
    let routeColor: Color
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Circle()
            .fill(routeColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 0.5)
            .onTapGesture {
                // Haptic feedback for tap interaction
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                
                onTap()
            }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack(spacing: 30) {
            Text("Stop Annotations")
                .font(.headline)
                .foregroundStyle(.white)
            
            HStack(spacing: 25) {
                VStack(spacing: 8) {
                    StopAnnotationView(
                        stop: Stop(id: 1, name: "Test Stop", lat: 0, lon: 0),
                        routeColor: .blue,
                        onTap: {}
                    )
                    Text("Route 1").font(.caption2).foregroundStyle(.white)
                }
                
                VStack(spacing: 8) {
                    StopAnnotationView(
                        stop: Stop(id: 2, name: "Test Stop 2", lat: 0, lon: 0),
                        routeColor: .red,
                        onTap: {}
                    )
                    Text("Route 2").font(.caption2).foregroundStyle(.white)
                }
                
                VStack(spacing: 8) {
                    StopAnnotationView(
                        stop: Stop(id: 3, name: "Test Stop 3", lat: 0, lon: 0),
                        routeColor: .green,
                        onTap: {}
                    )
                    Text("Route 3").font(.caption2).foregroundStyle(.white)
                }
            }
        }
        .padding(40)
    }
}

