import SwiftUI

/// Bus annotation with circular design (no timer)
struct BusAnnotationView: View {
    let routeShortName: String
    let routeColor: Color
    let onTap: () -> Void
    
    var body: some View {
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
            
            // Bus icon
            Image(systemName: "bus.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(routeColor)
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
            // Different route numbers
            HStack(spacing: 35) {
                VStack(spacing: 8) {
                    BusAnnotationView(routeShortName: "1", routeColor: Color(red: 0.8, green: 0.2, blue: 0.2), onTap: {})
                    Text("Route 1").font(.caption2).foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    BusAnnotationView(routeShortName: "6", routeColor: Color(red: 1.0, green: 0.6, blue: 0.0), onTap: {})
                    Text("Route 6").font(.caption2).foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    BusAnnotationView(routeShortName: "9", routeColor: Color(red: 0.2, green: 0.4, blue: 0.9), onTap: {})
                    Text("Route 9").font(.caption2).foregroundStyle(.white)
                }
            }
            
            // More route numbers
            HStack(spacing: 35) {
                BusAnnotationView(routeShortName: "3E", routeColor: Color(red: 0.3, green: 0.7, blue: 0.3), onTap: {})
                BusAnnotationView(routeShortName: "12", routeColor: Color(red: 0.6, green: 0.2, blue: 0.8), onTap: {})
                BusAnnotationView(routeShortName: "2W", routeColor: Color(red: 0.0, green: 0.7, blue: 0.8), onTap: {})
            }
        }
        .padding(40)
    }
}

