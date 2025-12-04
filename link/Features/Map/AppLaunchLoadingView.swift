import SwiftUI

/// Loading phase for app launch with progress stages
enum AppLoadingPhase {
    case loadingRoutes
    case fetchingBuses
    case complete
    
    var title: String {
        switch self {
        case .loadingRoutes: return "Loading routes..."
        case .fetchingBuses: return "Fetching bus locations..."
        case .complete: return "Ready!"
        }
    }
    
    var progress: Double {
        switch self {
        case .loadingRoutes: return 0.5
        case .fetchingBuses: return 0.85
        case .complete: return 1.0
        }
    }
    
    var icon: String {
        switch self {
        case .loadingRoutes: return "map.fill"
        case .fetchingBuses: return "bus.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

/// Dynamic loading view for app launches with progress stages
/// Shows progress bar and stage descriptions to provide user feedback
struct AppLaunchLoadingView: View {
    let phase: AppLoadingPhase
    @State private var isAnimating = false
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Pulsing icon with animation
            ZStack {
                // Background pulse effect
                Circle()
                    .fill(Color("PrimaryAccent").opacity(0.15))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                // Phase icon
                Image(systemName: phase.icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color("PrimaryAccent"))
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showContent)
            }
            .frame(height: 100)
            
            // Progress bar and text
            VStack(spacing: 16) {
                ProgressBar(progress: phase.progress)
                    .frame(height: 8)
                    .padding(.horizontal, 40)
                
                Text(phase.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("\(Int(phase.progress * 100))%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background"))
        .onAppear {
            isAnimating = true
            withAnimation(.easeIn(duration: 0.3)) {
                showContent = true
            }
        }
    }
}

