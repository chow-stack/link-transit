import SwiftUI

/// View displaying list of trip itinerary options with summaries
struct TripPlannerResultsView: View {
    @Bindable var viewModel: TripPlannerViewModel
    let onSelectItinerary: (Itinerary) -> Void
    let onGo: (Itinerary) -> Void
    
    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
            } else if viewModel.itineraries.isEmpty {
                emptyView
            } else {
                resultsList
            }
        }
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color("PrimaryAccent")))
                .scaleEffect(1.5)
                .accessibilityLabel("Searching for routes")
            
            Text("Finding routes...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Finding routes")
        }
    }
    
    // MARK: - Error State
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityLabel("Error: \(message)")
            
            Button(action: {
                Task {
                    await viewModel.searchRoutes()
                }
            }) {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("PrimaryAccent"))
                    )
            }
            .accessibilityLabel("Try searching again")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            
            Text("No routes found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            
            Text("Try adjusting your search time or destination")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityLabel("No routes found. Try adjusting your search time or destination")
        }
    }
    
    // MARK: - Results List
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.itineraries) { itinerary in
                    ItineraryCard(
                        itinerary: itinerary,
                        viewModel: viewModel,
                        onTap: {
                            onSelectItinerary(itinerary)
                        },
                        onGo: {
                            onGo(itinerary)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Itinerary Card

/// Individual itinerary card displaying route summary
struct ItineraryCard: View {
    let itinerary: Itinerary
    @Bindable var viewModel: TripPlannerViewModel
    let onTap: () -> Void
    let onGo: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Total time and arrival time
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(itinerary.formattedTotalTime)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Arrive at \(itinerary.formattedArrivalTime)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Departure guidance
                    Text(itinerary.departureGuidance)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(departureGuidanceColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(departureGuidanceBackgroundColor)
                        )
                }
                
                // Route chips: WALK → Bus (with bus number if available) → WALK
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(itinerary.segments.enumerated()), id: \.offset) { index, segment in
                            RouteChip(
                                segment: segment,
                                busNumber: busNumberFor(segment: segment),
                                dataSyncService: viewModel.dataSyncService
                            )
                            
                            if index < itinerary.segments.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                
                // Footer: Transfer badge and Go button
                HStack(spacing: 8) {
                    // Transfer badge
                    if itinerary.hasTransfers {
                        TransferBadge(count: itinerary.transferCount)
                    }
                    
                    Spacer()

                    Button(action: onGo) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Go")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color("PrimaryAccent"))
                        )
                    }
                    .accessibilityLabel("Start navigation for this route")
                    .accessibilityHint("Double tap to begin turn-by-turn directions")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private func busNumberFor(segment: TripSegment) -> String? {
        switch segment {
        case .walk:
            return nil
        case .ride(_, _, _, _, _, _, _, _, let tripId):
            // Use the same source as BusInfo (trip.block_id) for consistency
            return viewModel.getBusNumberForTrip(tripId: tripId)
        }
    }
    private var departureGuidanceColor: Color {
        let seconds = Int(itinerary.timeUntilDeparture)
        if seconds < 60 {
            return .orange
        } else {
            return Color("PrimaryAccent")
        }
    }
    
    private var departureGuidanceBackgroundColor: Color {
        let seconds = Int(itinerary.timeUntilDeparture)
        if seconds < 60 {
            return Color.orange.opacity(0.15)
        } else {
            return Color("PrimaryAccent").opacity(0.15)
        }
    }
}

// MARK: - Route Chip

/// Chip displaying a single route segment (walk or bus)
struct RouteChip: View {
    let segment: TripSegment
    let busNumber: String?
    let dataSyncService: DataSyncService
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: segmentIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(chipTextColor)
            
            Text(chipText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(chipTextColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(chipBackgroundColor)
        )
    }
    
    private var segmentIcon: String {
        switch segment {
        case .walk:
            return "figure.walk"
        case .ride:
            return "bus.fill"
        }
    }
    
    private var chipText: String {
        switch segment {
        case .walk(_, _, let duration, _, _):
            let minutes = Int(duration / 60)
            return "WALK \(minutes) min"
        case .ride(_, _, let routeName, _, _, _, let duration, _, _):
            let minutes = Int(duration / 60)
            if let busNumber = busNumber {
                return "\(routeName) • Bus \(busNumber) • \(minutes) min"
            } else {
                return "\(routeName) \(minutes) min"
            }
        }
    }
    
    private var chipTextColor: Color {
        switch segment {
        case .walk:
            return .secondary
        case .ride:
            return .white
        }
    }
    
    private var chipBackgroundColor: Color {
        switch segment {
        case .walk:
            return Color("Background").opacity(0.6)
        case .ride(_, let routeId, _, _, _, _, _, _, _):
            // Get exact route color from GTFS data instead of OTP routeColor
            // Use efficient lookup if available (through dataSyncService which may have lookups)
            // This is acceptable as TripPlannerResultsView is not in the critical rendering path
            if let route = dataSyncService.routes.first(where: { $0.route_id == routeId }),
               let routeColorHex = route.route_color,
               !routeColorHex.isEmpty {
                return Color(hex: routeColorHex)
            } else {
                return Color("PrimaryAccent")
            }
        }
    }
}

// MARK: - Transfer Badge

/// Badge displaying transfer count
struct TransferBadge: View {
    let count: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 10, weight: .semibold))
            Text("\(count) transfer\(count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color("Background").opacity(0.6))
        )
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
            TripPlannerResultsView(
                viewModel: viewModel,
                onSelectItinerary: { itinerary in
                    print("Selected: \(itinerary.id)")
                },
                onGo: { itinerary in
                    print("Go: \(itinerary.id)")
                }
            )
        }
    }
    
    return PreviewWrapper()
}

