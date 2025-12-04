import SwiftUI
import MapKit
import UIKit

/// Bottom sheet displaying detailed itinerary information with step-by-step instructions
struct TripPlannerDetailSheet: View {
    let itinerary: Itinerary
    @Bindable var viewModel: TripPlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var formattedItinerary: FormattedItinerary?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    
    private let formatter = ItineraryFormatter()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background")
                    .ignoresSafeArea()
                
                if let formatted = formattedItinerary {
                    TripPlannerDetailView(
                        formattedItinerary: formatted,
                        itinerary: itinerary,
                        viewModel: viewModel,
                        mapCameraPosition: $mapCameraPosition
                    )
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color("PrimaryAccent")))
                }
            }
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            formattedItinerary = formatter.formatItinerary(itinerary)
            updateMapCamera()
        }
        .onChange(of: itinerary) { oldValue, newValue in
            formattedItinerary = formatter.formatItinerary(newValue)
            updateMapCamera()
        }
    }
    
    private func updateMapCamera() {
        // Calculate bounding box for all coordinates
        let allCoordinates = getAllCoordinates()
        guard !allCoordinates.isEmpty else { return }
        
        let minLat = allCoordinates.map { $0.latitude }.min()!
        let maxLat = allCoordinates.map { $0.latitude }.max()!
        let minLon = allCoordinates.map { $0.longitude }.min()!
        let maxLon = allCoordinates.map { $0.longitude }.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.01) * 1.3,
            longitudeDelta: max(maxLon - minLon, 0.01) * 1.3
        )
        
        let region = MKCoordinateRegion(center: center, span: span)
        mapCameraPosition = .region(region)
    }
    
    private func getAllCoordinates() -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        
        // Add origin and destination
        if let origin = viewModel.origin {
            coordinates.append(origin.coordinate)
        }
        if let destination = viewModel.destination {
            coordinates.append(destination.coordinate)
        }
        
        // Add all step locations
        if let formatted = formattedItinerary {
            coordinates.append(contentsOf: formatted.steps.map { $0.location })
        }
        
        return coordinates
    }
}

/// Main detail view showing step-by-step instructions and map
struct TripPlannerDetailView: View {
    let formattedItinerary: FormattedItinerary
    let itinerary: Itinerary
    @Bindable var viewModel: TripPlannerViewModel
    @Binding var mapCameraPosition: MapCameraPosition
    
    @State private var currentStepIndex: Int = 0
    @State private var lastUpdateTime: Date?
    @State private var refreshTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Map overlay
            mapSection
            
            Divider()
            
            // Instructions list
            instructionsSection
        }
        .onAppear {
            viewModel.resumeRefresh()
            lastUpdateTime = viewModel.lastUpdated
            startAutoRefresh()
            updateCurrentStep()
        }
        .onDisappear {
            viewModel.pauseRefresh()
            refreshTask?.cancel()
        }
        .onChange(of: itinerary) { oldValue, newValue in
            updateCurrentStep()
        }
    }
    
    // MARK: - Map Section
    
    private var mapSection: some View {
        Map(position: $mapCameraPosition) {
            // Origin marker
            if let origin = viewModel.origin {
                Annotation("Origin", coordinate: origin.coordinate) {
                    OriginDestinationMarker(isOrigin: true)
                }
            }
            
            // Destination marker
            if let destination = viewModel.destination {
                Annotation("Destination", coordinate: destination.coordinate) {
                    OriginDestinationMarker(isOrigin: false)
                }
            }
            
            // Walking polylines (dashed)
            ForEach(Array(formattedItinerary.mapAnnotations.walkPolylines.enumerated()), id: \.offset) { _, polyline in
                MapPolyline(coordinates: polyline.coordinates)
                    .stroke(.gray, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [10, 5]))
            }
            
            // Bus polylines (solid with route color)
            ForEach(Array(formattedItinerary.mapAnnotations.ridePolylines.enumerated()), id: \.offset) { _, polyline in
                MapPolyline(coordinates: polyline.coordinates)
                    .stroke(polyline.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            
            // Stop markers
            ForEach(formattedItinerary.mapAnnotations.stopMarkers) { marker in
                Annotation(marker.stopName, coordinate: marker.coordinate) {
                    StopMarkerView(marker: marker)
                }
            }
        }
        .frame(height: 250)
        .disabled(true) // Disable interaction - just for display
    }
    
    // MARK: - Instructions Section
    
    private var instructionsSection: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Summary header
                summaryHeader
                
                Divider()
                
                // Step-by-step instructions
                ForEach(Array(formattedItinerary.steps.enumerated()), id: \.offset) { index, step in
                    InstructionStepRow(
                        step: step,
                        isCurrent: index == currentStepIndex,
                        itinerary: itinerary,
                        viewModel: viewModel,
                        currentStepIndex: $currentStepIndex
                    )
                    
                    if index < formattedItinerary.steps.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
                
                // Footer with status and actions
                footerSection
            }
        }
    }
    
    private var summaryHeader: some View {
        VStack(spacing: 12) {
            // Total time and arrival
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedItinerary.summary.formattedTotalTime)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Arrive at \(formattedItinerary.summary.formattedArrivalTime)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Update time indicator
            if let lastUpdate = lastUpdateTime {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Text(timeAgoString(from: lastUpdate))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
    }
    
    private var footerSection: some View {
        VStack(spacing: 12) {
            Divider()
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.searchRoutes()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Reroute")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color("PrimaryAccent"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("PrimaryAccent").opacity(0.1))
                    )
                }
                
                Button(action: {
                    shareTrip()
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Share")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("Background"))
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Auto Refresh
    
    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await viewModel.refreshETAs()
                lastUpdateTime = viewModel.lastUpdated
                updateCurrentStep()
            }
        }
    }
    
    private func updateCurrentStep() {
        // Determine current step based on time
        let now = Date()
        for (index, step) in formattedItinerary.steps.enumerated() {
            if step.time <= now {
                // Check if this step is still active (hasn't ended yet)
                let stepEndTime = step.time.addingTimeInterval(step.duration)
                if stepEndTime > now || index == formattedItinerary.steps.count - 1 {
                    withAnimation {
                        currentStepIndex = index
                    }
                    break
                }
            } else {
                // Step hasn't started yet, stop here
                break
            }
        }
    }
    
    // MARK: - Share Functionality
    
    private func shareTrip() {
        let summary = formattedItinerary.summary
        let text = """
        Trip from \(viewModel.origin?.displayName ?? "origin") to \(viewModel.destination?.displayName ?? "destination")
        
        Total time: \(summary.formattedTotalTime)
        Arrival: \(summary.formattedArrivalTime)
        
        Steps:
        \(formattedItinerary.steps.map { "• \($0.instruction) at \($0.formattedTime)" }.joined(separator: "\n"))
        """
        
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        // Find the topmost view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            // For iPad, configure popover presentation
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topController.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "Updated \(seconds)s ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "Updated \(minutes)m ago"
        } else {
            return "Updated \(seconds / 3600)h ago"
        }
    }
}

// MARK: - Instruction Step Row

/// Individual instruction step row
struct InstructionStepRow: View {
    let step: InstructionStep
    let isCurrent: Bool
    let itinerary: Itinerary
    @Bindable var viewModel: TripPlannerViewModel
    @Binding var currentStepIndex: Int
    
    @State private var currentTime = Date()
    @State private var timerTask: Task<Void, Never>?
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 40, height: 40)
                
                Image(systemName: step.type.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(step.instruction)
                    .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 12) {
                    Label(step.formattedTime, systemImage: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    
                    if step.duration > 0 {
                        Text("• \(formatDuration(step.duration))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Live countdown for boarding steps
                    if step.type == .board && isCurrent {
                        Text("• \(liveCountdownText)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color("PrimaryAccent"))
                    }
                    
                    // Stop counter for ride steps
                    if step.type == .ride && isCurrent, let stopCount = remainingStopsCount {
                        Text("• \(stopCount) stop\(stopCount == 1 ? "" : "s") left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color("PrimaryAccent"))
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isCurrent ? Color("PrimaryAccent").opacity(0.05) : Color.clear
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timerTask?.cancel()
        }
    }
    
    private var liveCountdownText: String {
        let seconds = Int(step.time.timeIntervalSince(currentTime))
        if seconds <= 0 {
            return "Arriving now"
        } else if seconds < 60 {
            return "Arrives in \(seconds)s"
        } else {
            let minutes = seconds / 60
            return "Arrives in \(minutes) min"
        }
    }
    
    private var remainingStopsCount: Int? {
        // Count remaining stops in this ride segment
        // Full implementation would track current stop position using real-time vehicle data
        // For now, return nil to avoid showing incorrect information
        // This can be enhanced in Phase 2 with real-time vehicle position tracking
        return nil
    }
    
    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                currentTime = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    
    private var iconColor: Color {
        switch step.type {
        case .walk:
            return .secondary
        case .board:
            return Color("PrimaryAccent")
        case .ride:
            return .white
        case .alight:
            return .secondary
        case .transfer:
            return .orange
        }
    }
    
    private var iconBackgroundColor: Color {
        switch step.type {
        case .walk:
            return Color("Background").opacity(0.6)
        case .board:
            return Color("PrimaryAccent")
        case .ride:
            return Color("PrimaryAccent")
        case .alight:
            return Color("Background").opacity(0.6)
        case .transfer:
            return Color.orange.opacity(0.15)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// MARK: - Map Markers

/// Origin or destination marker
struct OriginDestinationMarker: View {
    let isOrigin: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isOrigin ? Color.green : Color("AlertRed"))
                .frame(width: 24, height: 24)
            
            Image(systemName: isOrigin ? "mappin.circle.fill" : "flag.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
        }
    }
}

/// Stop marker view
struct StopMarkerView: View {
    let marker: StopMarker
    
    var body: some View {
        ZStack {
            Circle()
                .fill(markerColor)
                .frame(width: 20, height: 20)
            
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
        }
    }
    
    private var markerColor: Color {
        switch marker.type {
        case .boarding:
            return Color("PrimaryAccent")
        case .alighting:
            return Color("AlertRed")
        case .transfer:
            return .orange
        }
    }
}

/// Sheet that lists all directions (steps) for the selected itinerary
struct DirectionsListSheet: View {
    let formatted: FormattedItinerary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background")
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Summary header
                        directionsSummary
                            .padding(16)

                        Divider()

                        // All steps
                        VStack(spacing: 0) {
                            ForEach(Array(formatted.steps.enumerated()), id: \.offset) { index, step in
                                directionsRow(step)
                                if index < formatted.steps.count - 1 {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var directionsSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(formatted.summary.formattedTotalTime)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Arrive at \(formatted.summary.formattedArrivalTime)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("Distance")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(formatted.summary.formattedTotalDistance)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func directionsRow(_ step: InstructionStep) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill({ () -> Color in
                        switch step.type {
                        case .walk: return Color("Background").opacity(0.6)
                        case .board: return Color("PrimaryAccent")
                        case .ride: return Color("PrimaryAccent")
                        case .alight: return Color("Background").opacity(0.6)
                        case .transfer: return Color.orange.opacity(0.15)
                        }
                    }())
                    .frame(width: 40, height: 40)
                Image(systemName: step.type.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle({ () -> Color in
                        switch step.type {
                        case .walk: return .secondary
                        case .board: return Color("PrimaryAccent")
                        case .ride: return .white
                        case .alight: return .secondary
                        case .transfer: return .orange
                        }
                    }())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(step.instruction)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label(step.formattedTime, systemImage: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if step.duration > 0 {
                        Text("• \(formatDuration(step.duration))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}
#Preview {
    struct PreviewWrapper: View {
        @State private var viewModel = TripPlannerViewModel(
            routingEngine: TripRoutingEngine(
                walkingRouteService: WalkingRouteService.shared,
                dataSyncService: DataSyncService()
            ),
            dataSyncService: DataSyncService(),
            stopIndex: StopIndex(stops: [])
        )
        
        var body: some View {
            TripPlannerDetailSheet(
                itinerary: Itinerary(
                    segments: [],
                    totalTime: 1200,
                    totalDistance: 5000,
                    transferCount: 0,
                    departureTime: Date(),
                    arrivalTime: Date().addingTimeInterval(1200)
                ),
                viewModel: viewModel
            )
        }
    }
    
    return PreviewWrapper()
}

