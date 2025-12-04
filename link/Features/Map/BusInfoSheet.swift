import SwiftUI

/// Bottom sheet displaying live bus information
struct BusInfoSheet: View {
    let bus: EnrichedVehicle
    let busInfo: BusInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(FavoriteStore.self) private var favoriteStore
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Route color bar at top
                Rectangle()
                    .fill(bus.routeColor)
                    .frame(height: 4)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header section
                        busHeader
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // Current/Next stop section
                        currentStopSection
                        
                        // Upcoming stops section
                        if !busInfo.upcomingStops.isEmpty {
                            upcomingStopsSection
                        }
                        
                        // Last updated timestamp
                        lastUpdatedSection
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button { 
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        
                        Task {
                            await favoriteStore.toggleRouteFavorite(
                                routeId: bus.vehicle.routeId,
                                name: "Route \(bus.routeShortName)",
                                routeColor: bus.route?.route_color
                            )
                        }
                    } label: {
                        Image(systemName: favoriteStore.isRouteFavorited(bus.vehicle.routeId) ? "heart.fill" : "heart")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(favoriteStore.isRouteFavorited(bus.vehicle.routeId) ? Color("AlertRed") : .secondary)
                            .scaleEffect(favoriteStore.isRouteFavorited(bus.vehicle.routeId) ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: favoriteStore.isRouteFavorited(bus.vehicle.routeId))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            })
        }
        .background(Color("Background"))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - UI Components
    
    private var busHeader: some View {
        HStack(spacing: 16) {
            // Route circle
            Circle()
                .fill(bus.routeColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(bus.routeShortName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(bus.routeLongName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                Text("Bus #\(busInfo.busNumber)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Delay status badge
            DelayStatusBadge(delayStatus: busInfo.delayStatus)
        }
        .padding(.horizontal, 20)
    }
    
    private var currentStopSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section title
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(bus.routeColor)
                
                Text(busInfo.atStop ? "At Stop" : "Next Stop")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            
            // Current/Next stop card
            VStack(alignment: .leading, spacing: 8) {
                Text(busInfo.currentStopName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                
                if !busInfo.atStop, let eta = busInfo.currentStopETA {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color("PrimaryAccent"))
                        
                        Text(eta)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color("PrimaryAccent"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("Background").opacity(0.8))
            )
            .padding(.horizontal, 20)
        }
    }
    
    private var upcomingStopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section title
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                
                Text("Upcoming Stops")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            
            // Stop list
            VStack(spacing: 8) {
                ForEach(Array(busInfo.upcomingStops.enumerated()), id: \.offset) { index, stopInfo in
                    UpcomingStopRow(
                        stopName: stopInfo.name,
                        eta: stopInfo.eta,
                        isLast: index == busInfo.upcomingStops.count - 1
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var lastUpdatedSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            Text("Updated \(timeAgo(from: bus.lastUpdated))")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    // MARK: - Helper Methods
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        } else if seconds < 120 {
            return "1 min ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) mins ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
}

// MARK: - Supporting Components

/// Delay status badge
struct DelayStatusBadge: View {
    let delayStatus: DelayStatus
    
    var body: some View {
        Text(delayStatus.displayText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
    }
    
    private var textColor: Color {
        switch delayStatus {
        case .onTime: return .green // Semantic color for success
        case .early: return Color("PrimaryAccent")
        case .delayed: return .orange // Semantic color for warning
        case .unknown: return .secondary
        }
    }
    
    private var backgroundColor: Color {
        switch delayStatus {
        case .onTime: return Color.green.opacity(0.15) // Semantic color for success
        case .early: return Color("PrimaryAccent").opacity(0.15)
        case .delayed: return Color.orange.opacity(0.15) // Semantic color for warning
        case .unknown: return Color("Background").opacity(0.5)
        }
    }
}

/// Individual upcoming stop row
struct UpcomingStopRow: View {
    let stopName: String
    let eta: String?
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Stop indicator with connecting line
            VStack(spacing: 0) {
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: 8, height: 8)
                
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2, height: 30)
                }
            }
            .padding(.top, 6)
            
            // Stop info
            VStack(alignment: .leading, spacing: 4) {
                Text(stopName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                
                if let eta = eta {
                    Text(eta)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Data Models

/// Bus information including current stop and upcoming stops
struct BusInfo {
    let busNumber: String
    let currentStopName: String
    let currentStopETA: String?
    let atStop: Bool
    let delayStatus: DelayStatus
    let upcomingStops: [StopInfo]
    
    struct StopInfo {
        let name: String
        let eta: String?
    }
}

/// Delay status for a bus
enum DelayStatus {
    case onTime
    case early
    case delayed(minutes: Int)
    case unknown
    
    var displayText: String {
        switch self {
        case .onTime: return "On Time"
        case .early: return "Early"
        case .delayed(let minutes): return "\(minutes) min late"
        case .unknown: return "Unknown"
        }
    }
}

#Preview {
    // Sample bus
    let sampleVehicle = Vehicle(
        id: "bus123",
        routeId: "6",
        tripId: "trip123",
        routeName: "6",
        latitude: 39.166595,
        longitude: -86.542137,
        heading: 45.0,
        speed: 25.0,
        lastUpdated: Date()
    )
    
    let sampleRoute = Route(
        route_id: "6",
        route_short_name: "6",
        route_long_name: "Campus Loop",
        route_color: "EC0E0E"
    )
    
    let enrichedBus = EnrichedVehicle(
        vehicle: sampleVehicle,
        route: sampleRoute
    )
    
    let busInfo = BusInfo(
        busNumber: "123",
        currentStopName: "Kirkwood Ave & Indiana Ave",
        currentStopETA: "2 min",
        atStop: false,
        delayStatus: .onTime,
        upcomingStops: [
            BusInfo.StopInfo(name: "IMU - Indiana Memorial Union", eta: "5 min"),
            BusInfo.StopInfo(name: "Sample Gates", eta: "8 min"),
            BusInfo.StopInfo(name: "Memorial Stadium", eta: "12 min")
        ]
    )
    
    BusInfoSheet(bus: enrichedBus, busInfo: busInfo)
}

