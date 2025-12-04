import SwiftUI

/// Loading phase for progressive loading feedback
enum LoadingPhase {
    case loading
    case complete
    
    var title: String {
        switch self {
        case .loading:
            return "Loading map..."
        case .complete:
            return "Ready!"
        }
    }
    
    var icon: String {
        switch self {
        case .loading:
            return "map.fill"
        case .complete:
            return "checkmark.circle.fill"
        }
    }
    
    var progress: Double {
        switch self {
        case .loading:
            return 0.5
        case .complete:
            return 1.0
        }
    }
}

/// Modern, professional loading spinner
struct ProfessionalLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Modern circular progress indicator
            ZStack {
                Circle()
                    .stroke(
                        Color.gray.opacity(0.2),
                        lineWidth: 8
                    )
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        Color("PrimaryAccent"),
                        style: StrokeStyle(
                            lineWidth: 8,
                            lineCap: .round
                        )
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        Animation
                            .linear(duration: 1)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            
            Text("Loading...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background"))
        .onAppear {
            isAnimating = true
        }
    }
}

/// Phased loading view with progress indicator - Apple design style
struct PhasedLoadingView: View {
    let phase: LoadingPhase
    @State private var isAnimating = false
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon with pulsing animation
            ZStack {
                // Background pulse
                Circle()
                    .fill(Color("PrimaryAccent").opacity(0.15))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(
                        Animation
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                // Icon
                Image(systemName: phase.icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color("PrimaryAccent"))
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showContent)
            }
            .frame(height: 100)
            
            // Progress and text
            VStack(spacing: 16) {
                // Loading text with fade in
                Text(phase.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showContent)
                
                // Progress bar
                ProgressBar(progress: phase.progress)
                    .frame(width: 200, height: 8)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeIn(duration: 0.3).delay(0.1), value: showContent)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background"))
        .onAppear {
            isAnimating = true
            withAnimation {
                showContent = true
            }
        }
    }
}

/// Progress bar component
struct ProgressBar: View {
    let progress: Double
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                
                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color("PrimaryAccent"), Color("PrimaryAccent").opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedProgress)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
    }
}

/// Simple loading view for smaller components
struct SimpleLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color("PrimaryAccent"))
            
            Text("Loading...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Skeleton loading view for list items - Apple style
struct SkeletonLoadingView: View {
    @State private var isAnimating = false
    let itemCount: Int
    
    init(itemCount: Int = 5) {
        self.itemCount = itemCount
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<itemCount, id: \.self) { index in
                    SkeletonRow()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

/// Individual skeleton row with shimmer effect
struct SkeletonRow: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon placeholder
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    ShimmerOverlay(phase: phase)
                )
            
            VStack(alignment: .leading, spacing: 8) {
                // Title placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .overlay(
                        ShimmerOverlay(phase: phase)
                    )
                
                // Subtitle placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(maxWidth: 150, alignment: .leading)
                    .overlay(
                        ShimmerOverlay(phase: phase)
                    )
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("Background").opacity(0.6))
        )
        .onAppear {
            withAnimation(
                Animation
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }
}

/// Shimmer overlay effect
struct ShimmerOverlay: View {
    let phase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.3),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 2)
            .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
        }
        .mask(Rectangle())
    }
}

#Preview("Professional Loading") {
    ProfessionalLoadingView()
}

#Preview("Phased Loading - Loading") {
    PhasedLoadingView(phase: .loading)
}

#Preview("Phased Loading - Complete") {
    PhasedLoadingView(phase: .complete)
}

/// Context-aware loading view for stop details sheets
struct StopLoadingView: View {
    let stopName: String
    @State private var isAnimating = false
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Stop icon with pulse
            ZStack {
                Circle()
                    .fill(Color("PrimaryAccent").opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(
                        Animation
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color("PrimaryAccent"))
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showContent)
            }
            
            // Stop name and status
            VStack(spacing: 12) {
                Text(stopName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showContent)
                
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(Color("PrimaryAccent"))
                    
                    Text("Loading arrivals...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(showContent ? 1 : 0)
                .animation(.easeIn(duration: 0.3).delay(0.1), value: showContent)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = true
            withAnimation {
                showContent = true
            }
        }
    }
}

/// Context-aware loading view for bus info sheets
struct BusLoadingView: View {
    let routeShortName: String
    let routeLongName: String
    let routeColor: Color
    @State private var isAnimating = false
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Bus icon with pulse
            ZStack {
                Circle()
                    .fill(routeColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(
                        Animation
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                Circle()
                    .fill(routeColor)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(routeShortName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showContent)
            }
            
            // Route name and status
            VStack(spacing: 12) {
                Text(routeLongName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showContent)
                
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(routeColor)
                    
                    Text("Loading bus details...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(showContent ? 1 : 0)
                .animation(.easeIn(duration: 0.3).delay(0.1), value: showContent)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = true
            withAnimation {
                showContent = true
            }
        }
    }
}

/// Skeleton loading for stop arrivals list
struct StopArrivalsSkeleton: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stop header skeleton
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 28)
                        .frame(maxWidth: 200)
                        .overlay(ShimmerOverlay(phase: phase))
                    
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 60, height: 32)
                                .overlay(ShimmerOverlay(phase: phase))
                        }
                    }
                }
                .padding(.top, 20)
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Arrival groups skeleton
                VStack(spacing: 20) {
                    ForEach(0..<2, id: \.self) { _ in
                        StopArrivalGroupSkeleton(phase: phase)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            withAnimation(
                Animation
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }
}

/// Skeleton for a route group in stop details
struct StopArrivalGroupSkeleton: View {
    let phase: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Route header skeleton
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(ShimmerOverlay(phase: phase))
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 20)
                    .overlay(ShimmerOverlay(phase: phase))
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 20)
                    .overlay(ShimmerOverlay(phase: phase))
            }
            
            // Arrival rows skeleton
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 16)
                            .overlay(ShimmerOverlay(phase: phase))
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 60, height: 20)
                                .overlay(ShimmerOverlay(phase: phase))
                            
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 70, height: 18)
                                .overlay(ShimmerOverlay(phase: phase))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color("Background").opacity(0.6))
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("Background").opacity(0.8))
        )
    }
}

/// Skeleton loading for bus info sheet
struct BusInfoSkeleton: View {
    let routeColor: Color
    @State private var phase: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Route color bar
            Rectangle()
                .fill(routeColor)
                .frame(height: 4)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header skeleton
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 48, height: 48)
                            .overlay(ShimmerOverlay(phase: phase))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 20)
                                .frame(maxWidth: 180)
                                .overlay(ShimmerOverlay(phase: phase))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .frame(maxWidth: 100)
                                .overlay(ShimmerOverlay(phase: phase))
                        }
                        
                        Spacer()
                        
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 70, height: 26)
                            .overlay(ShimmerOverlay(phase: phase))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Current stop skeleton
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 20, height: 20)
                                .overlay(ShimmerOverlay(phase: phase))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 100, height: 16)
                                .overlay(ShimmerOverlay(phase: phase))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 18)
                                .frame(maxWidth: 200)
                                .overlay(ShimmerOverlay(phase: phase))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 80, height: 16)
                                .overlay(ShimmerOverlay(phase: phase))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color("Background").opacity(0.8))
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Upcoming stops skeleton
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 16, height: 16)
                                .overlay(ShimmerOverlay(phase: phase))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 120, height: 16)
                                .overlay(ShimmerOverlay(phase: phase))
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { index in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(spacing: 0) {
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 8, height: 8)
                                        
                                        if index < 2 {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 2, height: 30)
                                        }
                                    }
                                    .padding(.top, 6)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 15)
                                            .frame(maxWidth: 180)
                                            .overlay(ShimmerOverlay(phase: phase))
                                        
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 60, height: 14)
                                            .overlay(ShimmerOverlay(phase: phase))
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            withAnimation(
                Animation
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }
}

#Preview("Skeleton Loading") {
    SkeletonLoadingView(itemCount: 5)
}

#Preview("Stop Loading") {
    StopLoadingView(stopName: "Kirkwood Ave & Indiana Ave")
}

#Preview("Bus Loading") {
    BusLoadingView(
        routeShortName: "6",
        routeLongName: "Campus Loop",
        routeColor: Color(hex: "EC0E0E")
    )
}

#Preview("Stop Arrivals Skeleton") {
    StopArrivalsSkeleton()
}

#Preview("Bus Info Skeleton") {
    BusInfoSkeleton(routeColor: Color(hex: "EC0E0E"))
}

