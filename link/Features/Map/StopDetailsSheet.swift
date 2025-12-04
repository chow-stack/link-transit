import SwiftUI

/// Bottom sheet displaying stop details and upcoming arrivals
struct StopDetailsSheet: View {
    let stop: Stop
    let arrivals: [Arrival]
    let servingRoutes: [Route]  // All routes serving this stop
    @Environment(\.dismiss) private var dismiss
    @Environment(FavoriteStore.self) private var favoriteStore
    @Environment(NotificationService.self) private var notificationService
    @State private var showingNotificationConfig = false
    
    // Group arrivals by route
    private var arrivalsByRoute: [(route: String, color: String?, arrivals: [Arrival])] {
        let grouped = Dictionary(grouping: arrivals) { $0.routeShortName }
        return grouped.map { (route: $0.key, color: $0.value.first?.routeColor, arrivals: $0.value.sorted { $0.arrivalTime < $1.arrivalTime }) }
            .sorted { $0.route < $1.route }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                stopHeader
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Arrivals list
                if arrivals.isEmpty {
                    emptyState
                } else {
                    arrivalsList
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        // Favorite button
                        Button { 
                            // Haptic feedback
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            
                            Task {
                                await favoriteStore.toggleStopFavorite(stopId: stop.id, name: stop.name)
                            }
                        } label: {
                            Image(systemName: favoriteStore.isStopFavorited(stop.id) ? "heart.fill" : "heart")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(favoriteStore.isStopFavorited(stop.id) ? Color("AlertRed") : .secondary)
                                .scaleEffect(favoriteStore.isStopFavorited(stop.id) ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: favoriteStore.isStopFavorited(stop.id))
                        }
                        
                        // Notification button
                        Button { 
                            showingNotificationConfig = true
                        } label: {
                            Image(systemName: notificationService.hasNotification(for: stop.id) ? "bell.fill" : "bell")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(notificationService.hasNotification(for: stop.id) ? Color("PrimaryAccent") : .secondary)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showingNotificationConfig) {
                StopNotificationConfigSheet(stop: stop, servingRoutes: servingRoutes)
            }
        }
        .background(Color("Background"))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - UI Components
    
    private var stopHeader: some View {
        VStack(spacing: 16) {
            // Stop name only (no stop ID)
            Text(stop.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 8)
            
            // Horizontal scrolling routes
            if !servingRoutes.isEmpty {
                HStack(spacing: 12) {
                    Text("Routes:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(servingRoutes, id: \.id) { route in
                                RouteBadge(route: route)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
    }
    
    private var arrivalsList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(arrivalsByRoute, id: \.route) { routeGroup in
                    RouteGroupSection(
                        routeName: routeGroup.route,
                        routeColor: routeGroup.color,
                        arrivals: routeGroup.arrivals
                    )
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 6) {
                Text("No Active Buses")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("No buses are currently active at this stop")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Supporting Components

/// Route group section showing all buses for a specific route
struct RouteGroupSection: View {
    let routeName: String
    let routeColor: String?
    let arrivals: [Arrival]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Route header
            HStack(spacing: 12) {
                Circle()
                    .fill(routeColor != nil ? Color(hex: routeColor!) : Color("PrimaryAccent"))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(routeName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    )
                
                Text("Route \(routeName)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("ETA")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            // Individual buses for this route
            VStack(spacing: 8) {
                ForEach(arrivals) { arrival in
                    BusArrivalRow(arrival: arrival)
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

/// Individual bus arrival row within a route group
struct BusArrivalRow: View {
    let arrival: Arrival
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side: Bus ID
            VStack(alignment: .leading, spacing: 2) {
                Text("Bus \(arrival.busDisplayName)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            // Right side: ETA and status
            VStack(alignment: .trailing, spacing: 4) {
                Text(arrival.formattedTime)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(timeColor)
                
                if let badge = arrival.statusBadge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badgeTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(badgeBackgroundColor)
                        )
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color("Background").opacity(0.6))
        )
    }
    
    private var timeColor: Color {
        if arrival.isArriving {
            return .green
        } else {
            return .primary
        }
    }
    
    private var badgeTextColor: Color {
        switch arrival.statusColor {
        case "green": return .green // Semantic color for success
        case "blue": return Color("PrimaryAccent")
        case "gray": return .secondary
        default: return .secondary
        }
    }
    
    private var badgeBackgroundColor: Color {
        switch arrival.statusColor {
        case "green": return Color.green.opacity(0.15) // Semantic color for success
        case "blue": return Color("PrimaryAccent").opacity(0.15)
        case "gray": return Color("Background").opacity(0.5)
        default: return Color("Background").opacity(0.5)
        }
    }
}

/// Route badge displayed in horizontal scrolling view
struct RouteBadge: View {
    let route: Route
    
    var body: some View {
        Text(route.route_short_name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(route.route_color != nil ? Color(hex: route.route_color!) : Color("PrimaryAccent"))
            )
    }
}

/// Simple loader for stop details from favorites/notifications
struct StopDetailsSheetLoaderSimple: View {
    let stop: Stop
    let servingRoutes: [Route]
    @Environment(DataSyncService.self) private var dataSyncService
    @State private var arrivals: [Arrival] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                StopLoadingView(stopName: stop.name)
                    .transition(.opacity)
            } else {
                StopDetailsSheet(stop: stop, arrivals: arrivals, servingRoutes: servingRoutes)
                    .transition(.opacity)
            }
        }
        .task {
            // Fetch data immediately - no initial delay
            arrivals = await dataSyncService.stopTimesService.getUpcomingArrivals(for: stop.id, maxArrivals: 10)
            
            // Ensure loading was visible for minimum time
            try? await Task.sleep(for: .milliseconds(300))
            
            // Smooth transition to content
            withAnimation(.easeInOut(duration: 0.25)) {
                isLoading = false
            }
        }
    }
}

#Preview {
    // Sample stop
    let stop = Stop(
        id: 45121,
        name: "Kirkwood Ave & Maple St",
        lat: 39.166595,
        lon: -86.542137
    )
    
    // Sample arrivals with real-time data
    let arrivals = [
        Arrival(
            id: "1",
            stopId: 45121,
            tripId: "trip1",
            routeId: "1",
            routeShortName: "6",
            routeColor: "EC0E0E",
            arrivalTime: Date().addingTimeInterval(45),
            scheduledTime: "14:30:00",
            isRealtime: true,
            vehicleId: "bus123",
            busNumber: "123"
        ),
        Arrival(
            id: "2",
            stopId: 45121,
            tripId: "trip2",
            routeId: "1",
            routeShortName: "6",
            routeColor: "EC0E0E",
            arrivalTime: Date().addingTimeInterval(900),
            scheduledTime: "14:45:00",
            isRealtime: false,
            vehicleId: "bus456",
            busNumber: "456"
        ),
        Arrival(
            id: "3",
            stopId: 45121,
            tripId: "trip3",
            routeId: "2",
            routeShortName: "3E",
            routeColor: "0066CC",
            arrivalTime: Date().addingTimeInterval(420),
            scheduledTime: "14:37:00",
            isRealtime: true,
            vehicleId: "bus789",
            busNumber: "789"
        ),
        Arrival(
            id: "4",
            stopId: 45121,
            tripId: "trip4",
            routeId: "2",
            routeShortName: "3E",
            routeColor: "0066CC",
            arrivalTime: Date().addingTimeInterval(1200),
            scheduledTime: "14:50:00",
            isRealtime: false,
            vehicleId: "bus101",
            busNumber: "101"
        ),
        Arrival(
            id: "5",
            stopId: 45121,
            tripId: "trip5",
            routeId: "3",
            routeShortName: "9",
            routeColor: "FF9900",
            arrivalTime: Date().addingTimeInterval(30), // Arriving now
            scheduledTime: "14:40:00",
            isRealtime: true,
            vehicleId: "bus202",
            busNumber: "202"
        )
    ]
    
    // Sample serving routes
    let servingRoutes = [
        Route(route_id: "1", route_short_name: "6", route_long_name: "Campus Shuttle", route_color: "80471C"),
        Route(route_id: "2", route_short_name: "3E", route_long_name: "3 East College Mall", route_color: "0066CC"),
        Route(route_id: "3", route_short_name: "9", route_long_name: "IU Campus Express", route_color: "FF9900")
    ]
    
    return StopDetailsSheet(stop: stop, arrivals: arrivals, servingRoutes: servingRoutes)
}

