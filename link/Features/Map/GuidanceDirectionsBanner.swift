import SwiftUI
import MapKit

/// Apple Maps-style top directions banner that expands/collapses like an inverted bottom sheet
/// Displays current step when collapsed, full directions list when expanded
struct GuidanceDirectionsBanner: View {
    let formatted: FormattedItinerary
    @Binding var isExpanded: Bool
    
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragValue: CGFloat = 0
    
    // Adaptive heights based on screen size
    private var collapsedHeight: CGFloat {
        min(70, UIScreen.main.bounds.height * 0.1)
    }
    
    private var expandedHeight: CGFloat {
        min(400, UIScreen.main.bounds.height * 0.6)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Expanded: Full directions list
                expandedContent
            } else {
                // Collapsed: Current step summary
                collapsedContent
            }
        }
        .frame(height: currentHeight)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 18)
                .fill(Color("Background").opacity(0.95))
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: dragOffset)
    }
    
    // MARK: - Collapsed Content
    
    private var collapsedContent: some View {
        VStack(spacing: 0) {
            // Current step
            HStack(alignment: .center, spacing: 12) {
                // Step icon
                ZStack {
                    Circle()
                        .fill(currentStepIconBackground)
                        .frame(width: 36, height: 36)
                    Image(systemName: currentStepIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(currentStepIconColor)
                }
                
                // Step text
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentStepTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let subtitle = currentStepSubtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    isExpanded = true
                }
            }
            .accessibilityLabel("Current step: \(currentStepTitle)")
            .accessibilityHint("Double tap to expand full directions list")

            // Bottom grabber
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.bottom, 8)
        }
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Header with title
            VStack(spacing: 8) {
                // Header row
                HStack {
                    Text("Directions")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        isExpanded = false
                    }
                }
            }
            
            Divider()
            
            // Trip summary
            HStack {
                Text(formatted.summary.formattedTotalTime)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("Arrive \(formatted.summary.formattedArrivalTime)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Distance row (miles)
            HStack {
                Text("Distance")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(milesText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Divider()
            
            // Directions list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(formatted.steps.enumerated()), id: \.offset) { index, step in
                        directionRow(step: step, index: index)
                        
                        if index < formatted.steps.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            // Bottom grabber
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.bottom, 8)
        }
    }
    
    private func directionRow(step: InstructionStep, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor(for: step))
                    .frame(width: 32, height: 32)
                Image(systemName: step.type.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor(for: step))
            }
            
            // Step details
            VStack(alignment: .leading, spacing: 4) {
                Text(step.instruction)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 8) {
                    Label(step.formattedTime, systemImage: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    if step.duration > 0 {
                        Text("• \(formatDuration(step.duration))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Computed Properties
    
    private var currentHeight: CGFloat {
        if isExpanded {
            return expandedHeight + dragOffset
        } else {
            return collapsedHeight + dragOffset
        }
    }
    
    private var currentStepIcon: String {
        guard let step = formatted.steps.first else { return "figure.walk" }
        return step.type.iconName
    }
    
    private var currentStepIconColor: Color {
        guard let step = formatted.steps.first else { return .white }
        return iconColor(for: step)
    }
    
    private var currentStepIconBackground: Color {
        guard let step = formatted.steps.first else { return Color("PrimaryAccent") }
        return iconBackgroundColor(for: step)
    }
    
    private var currentStepTitle: String {
        formatted.steps.first?.instruction ?? "Trip guidance"
    }
    
    private var currentStepSubtitle: String? {
        formatted.summary.departureGuidance
    }
    
    // MARK: - Helper Methods
    
    private func iconColor(for step: InstructionStep) -> Color {
        switch step.type {
        case .walk: return .secondary
        case .board: return .white
        case .ride: return .white
        case .alight: return .secondary
        case .transfer: return .white
        }
    }
    
    private func iconBackgroundColor(for step: InstructionStep) -> Color {
        switch step.type {
        case .walk: 
            return Color("Background").opacity(0.6)
        case .board, .ride:
            // Use route color if available, otherwise fallback to PrimaryAccent
            if let routeColorHex = step.routeColor, !routeColorHex.isEmpty {
                return Color(hex: routeColorHex)
            }
            return Color("PrimaryAccent")
        case .alight: 
            return Color("Background").opacity(0.6)
        case .transfer: 
            return Color.orange
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
    
    private var milesText: String {
        // Convert meters to miles with one decimal
        let meters = formatted.summary.totalDistance
        let miles = meters / 1609.344
        return String(format: "%.1f mi", miles)
    }
    
    // MARK: - Gesture Handling
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        let translation = value.translation.height
        
        if isExpanded {
            // When expanded, allow drag up to collapse (negative translation)
            if translation < 0 { dragOffset = translation }
        } else {
            // When collapsed, allow drag down to expand (positive translation)
            if translation > 0 { dragOffset = translation }
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        let translation = value.translation.height
        let velocity = value.predictedEndTranslation.height - value.translation.height
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            if isExpanded {
                // Dragged up significantly or with velocity -> collapse
                if translation < -80 || velocity < -400 {
                    isExpanded = false
                }
            } else {
                // Dragged down significantly or with velocity -> expand
                if translation > 80 || velocity > 400 {
                    isExpanded = true
                }
            }
            
            // Reset drag offset
            dragOffset = 0
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isExpanded = false
        
        var body: some View {
            ZStack {
                Color.gray.opacity(0.2)
                    .ignoresSafeArea()
                
                VStack {
                    GuidanceDirectionsBanner(
                        formatted: sampleItinerary(),
                        isExpanded: $isExpanded
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    
                    Spacer()
                }
            }
        }
        
        func sampleItinerary() -> FormattedItinerary {
            // Create sample data for preview
            let step1 = InstructionStep(
                type: .walk,
                instruction: "Walk to Stop 123",
                time: Date(),
                duration: 300,
                location: CLLocationCoordinate2D(latitude: 39.1653, longitude: -86.5264),
                routeColor: nil
            )
            let step2 = InstructionStep(
                type: .board,
                instruction: "Board Route 6 at Stop 123",
                time: Date().addingTimeInterval(300),
                duration: 0,
                location: CLLocationCoordinate2D(latitude: 39.1653, longitude: -86.5264),
                routeColor: "0066CC" // Sample route color
            )
            let step3 = InstructionStep(
                type: .ride,
                instruction: "Ride Route 6 for 14 minutes",
                time: Date().addingTimeInterval(300),
                duration: 840,
                location: CLLocationCoordinate2D(latitude: 39.1653, longitude: -86.5264),
                routeColor: "0066CC" // Sample route color
            )
            
            let summary = ItinerarySummary(
                totalTime: 1200,
                totalDistance: 3000,
                transferCount: 0,
                departureTime: Date(),
                arrivalTime: Date().addingTimeInterval(1200)
            )
            
            return FormattedItinerary(
                steps: [step1, step2, step3],
                mapAnnotations: MapAnnotations(
                    walkPolylines: [],
                    ridePolylines: [],
                    stopMarkers: []
                ),
                summary: summary
            )
        }
    }
    
    return PreviewWrapper()
}

