import SwiftUI

/// Custom arrowhead view for directional indicators
struct ArrowheadView: View {
    let color: Color
    let size: CGSize
    
    var body: some View {
        Path { path in
            let width = size.width
            let height = size.height
            
            // Arrowhead pointing up: triangle shape
            path.move(to: CGPoint(x: width / 2, y: 0)) // Top point
            path.addLine(to: CGPoint(x: 0, y: height)) // Bottom left
            path.addLine(to: CGPoint(x: width, y: height)) // Bottom right
            path.closeSubpath()
        }
        .fill(color)
        .frame(width: size.width, height: size.height)
    }
}

/// Bus annotation with circular design (no timer)
struct BusAnnotationView: View {
    let routeShortName: String
    let routeColor: Color
    let heading: Double?
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            // Bus circle and icon (stays upright, no rotation)
            ZStack {
                // White background circle
                Circle()
                    .fill(.white)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                
                // Colored thick outline
                Circle()
                    .stroke(routeColor, lineWidth: 4)
                    .frame(width: 32, height: 32)
                
                // Bus icon (stays upright)
                Image(systemName: "bus.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(routeColor)
            }
            
            // Directional arrow indicator (only shown when heading is available)
            // Arrow rotates independently while bus stays upright
            if let headingValue = heading {
                ZStack {
                    // White outline layer (slightly larger, creates thin white outline effect)
                    ArrowheadView(color: .white, size: CGSize(width: 14, height: 12))
                    
                    // Colored arrowhead fill layer (on top, slightly smaller)
                    ArrowheadView(color: routeColor, size: CGSize(width: 12, height: 10))
                }
                .offset(y: -20) // Position arrow above the circle, pointing outward
                .rotationEffect(.degrees(headingValue)) // Rotate only the arrow
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
        }
        .onTapGesture {
            // Haptic feedback for tap interaction
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            onTap()
        }
    }
}

/// Universal timer component showing elapsed time since last position change
/// Uses theme colors for consistent appearance in light/dark mode
struct UniversalTimer: View {
    let lastPositionUpdate: Date
    @State private var currentTime = Date()
    @State private var timer: Timer?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let elapsed = currentTime.timeIntervalSince(lastPositionUpdate)
        let timeString = formatElapsedTime(elapsed)
        
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 11))
            Text(timeString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(colorScheme == .dark ? .white : .black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color("Background").opacity(0.9))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatElapsedTime(_ elapsed: TimeInterval) -> String {
        let seconds = Int(elapsed)
        
        if seconds < 60 {
            return "Updated \(seconds)s ago"
        } else {
            let minutes = seconds / 60
            return "Updated \(minutes)m ago"
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack(spacing: 50) {
            // Different route numbers with headings
            HStack(spacing: 35) {
                VStack(spacing: 8) {
                    BusAnnotationView(routeShortName: "1", routeColor: Color(red: 0.8, green: 0.2, blue: 0.2), heading: 0, onTap: {})
                    Text("Route 1 (N)").font(.caption2).foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    BusAnnotationView(routeShortName: "6", routeColor: Color(red: 1.0, green: 0.6, blue: 0.0), heading: 90, onTap: {})
                    Text("Route 6 (E)").font(.caption2).foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    BusAnnotationView(routeShortName: "9", routeColor: Color(red: 0.2, green: 0.4, blue: 0.9), heading: 180, onTap: {})
                    Text("Route 9 (S)").font(.caption2).foregroundStyle(.white)
                }
            }
            
            // More route numbers with different headings
            HStack(spacing: 35) {
                BusAnnotationView(routeShortName: "3E", routeColor: Color(red: 0.3, green: 0.7, blue: 0.3), heading: 270, onTap: {})
                BusAnnotationView(routeShortName: "12", routeColor: Color(red: 0.6, green: 0.2, blue: 0.8), heading: 45, onTap: {})
                BusAnnotationView(routeShortName: "2W", routeColor: Color(red: 0.0, green: 0.7, blue: 0.8), heading: nil, onTap: {})
            }
        }
        .padding(40)
    }
}

