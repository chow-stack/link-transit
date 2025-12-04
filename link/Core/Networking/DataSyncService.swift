import Foundation
import Observation
import SwiftUI
import CoreLocation
import MapKit

/// Service that coordinates static and realtime data with auto-refresh
@Observable
@MainActor
class DataSyncService {
    // Static data (loaded once)
    var routes: [Route] = []
    var shapes: [Shape] = []
    var trips: [Trip] = []
    var stops: [Stop] = []
    var routeServiceHours: [RouteServiceHours] = []
    
    // Performance optimization: Trip lookup dictionary
    private var tripLookup: [String: String] = [:]
    
    // Performance optimization: Cached route polylines
    private var cachedPolylines: [RoutePolyline] = []
    private var lastPolylineUpdate: Date?
    
    // Realtime data (refreshed periodically)
    var vehicles: [Vehicle] = []
    
    // Track previous vehicles to detect changes
    private var previousVehicles: [Vehicle] = []
    
    // State
    var lastUpdated: Date?
    var lastPositionUpdate: Date?
    var errorMessage: String?
    var isOffline = false
    var hasNoBuses: Bool {
        vehicles.isEmpty && lastUpdated != nil && !isOffline
    }
    
    // Stop times service for calculating arrivals
    let stopTimesService = StopTimesService()
    
    // Cached trip updates for better performance
    private var cachedTripUpdates: [String: TripUpdate] = [:]
    private var lastTripUpdateTimestamp: Date?
    
    private let realtimeService = RealtimeService.shared
    private let realtimeETAService = RealtimeETAService.shared
    private let staticDataService = StaticDataService.shared
    
    // Auto-refresh configuration
    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = APIConfig.vehicleRefreshInterval
    private var retryDelay: TimeInterval = 5.0
    private let maxRetryDelay: TimeInterval = 20.0
    
    // Track initialization state
    private var isInitialized = false
    
    init() {}
    
    /// Initialize service by loading static data
    /// Idempotent: skips if already initialized to prevent reloading static data and restarting refresh cycle
    /// Static data loads synchronously, then realtime refresh starts in background without blocking
    func initialize() async {
        // Skip if already initialized
        guard !isInitialized else { return }
        
        // Load static data from bundle (fast, local - doesn't require network)
        routes = staticDataService.loadRoutes()
        shapes = staticDataService.loadShapes()
        trips = staticDataService.loadTrips()
        stops = staticDataService.loadStops()
        routeServiceHours = staticDataService.loadRouteServiceHours()
        
        let stopTimesData = staticDataService.loadStopTimes()
        
        // Build trip lookup dictionary for O(1) access
        tripLookup = Dictionary(uniqueKeysWithValues: trips.map { ($0.trip_id, $0.route_id) })
        
        // Initialize stop times service
        stopTimesService.initialize(stopTimesData: stopTimesData, routes: routes, trips: trips)
        
        print("✅ Loaded static data: \(routes.count) routes, \(trips.count) trips, \(stops.count) stops")
        print("🔍 Built trip lookup dictionary with \(tripLookup.count) entries")
        
        // Mark as initialized BEFORE starting realtime refresh
        // This allows the UI to proceed immediately while realtime data loads in background
        isInitialized = true
        
        // Start auto-refresh for realtime data (runs asynchronously, doesn't block initialization)
        startAutoRefresh()
    }
    
    /// Manually refresh realtime data
    func refresh(forceRefresh: Bool = false) async {
        errorMessage = nil
        
        do {
            let refreshStart = Date()
            
            // Fetch vehicles and trip updates in parallel for better performance
            async let vehiclesTask = realtimeService.fetchVehicles(forceRefresh: forceRefresh)
            async let tripUpdatesTask = realtimeETAService.fetchTripUpdates(forceRefresh: false)
            
            var fetchedVehicles = try await vehiclesTask
            let tripUpdates = try? await tripUpdatesTask
            
            // Cache trip updates
            if let tripUpdates = tripUpdates {
                cachedTripUpdates = tripUpdates
                lastTripUpdateTimestamp = Date()
            }
            
            // Performance timing - Route resolution
            let resolveStart = Date()
            // Resolve vehicles that have tripId but no routeId using O(1) lookup
            fetchedVehicles = fetchedVehicles.map { vehicle in
                if vehicle.routeId.isEmpty && !vehicle.routeName.isEmpty {
                    // Use dictionary lookup instead of linear search
                    if let routeId = tripLookup[vehicle.routeName] {
                        return Vehicle(
                            id: vehicle.id,
                            routeId: routeId,
                            tripId: vehicle.tripId,
                            routeName: routeId,
                            latitude: vehicle.latitude,
                            longitude: vehicle.longitude,
                            heading: vehicle.heading,
                            speed: vehicle.speed,
                            lastUpdated: vehicle.lastUpdated
                        )
                    }
                }
                return vehicle
            }
            _ = Date().timeIntervalSince(resolveStart)
            
            // Update vehicles with smart timestamp management
            let updatedVehicles = updateVehicleTimestamps(fetchedVehicles)
            vehicles = updatedVehicles
            previousVehicles = fetchedVehicles
            lastUpdated = Date()
            isOffline = false
            
            // Reset retry delay on success
            retryDelay = 5.0
            
            _ = Date().timeIntervalSince(refreshStart)
        } catch {
            errorMessage = error.localizedDescription
            isOffline = true
            
            // Apply exponential backoff
            retryDelay = min(retryDelay * 2, maxRetryDelay)
        }
    }
    
    /// Start automatic refresh cycle
    /// Initial fetch runs in background without blocking initialization, then periodic refreshes continue
    func startAutoRefresh() {
        // Cancel existing task if any
        refreshTask?.cancel()
        
        // Start initial fetch in background task (non-blocking)
        // This allows the UI to proceed immediately after static data loads
        Task { [weak self] in
            await self?.refresh()
        }
        
        // Start periodic refresh loop in separate task
        refreshTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Wait for initial delay before first periodic refresh
            // This gives the initial fetch time to complete
            while !Task.isCancelled {
                let delay = self.isOffline ? self.retryDelay : self.refreshInterval
                try? await Task.sleep(for: .seconds(delay))
                
                if !Task.isCancelled {
                    await self.refresh()
                }
            }
        }
    }
    
    /// Stop automatic refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    /// Update vehicle timestamps only when data actually changes
    private func updateVehicleTimestamps(_ newVehicles: [Vehicle]) -> [Vehicle] {
        var hasPositionChange = false
        
        let updatedVehicles = newVehicles.map { newVehicle in
            // Find previous vehicle with same ID
            if let previousVehicle = previousVehicles.first(where: { $0.id == newVehicle.id }) {
                // Check if data has actually changed
                if newVehicle.hasChanged(from: previousVehicle) {
                    // Data changed, update timestamp
                    hasPositionChange = true
                    return Vehicle(
                        id: newVehicle.id,
                        routeId: newVehicle.routeId,
                        tripId: newVehicle.tripId,
                        routeName: newVehicle.routeName,
                        latitude: newVehicle.latitude,
                        longitude: newVehicle.longitude,
                        heading: newVehicle.heading,
                        speed: newVehicle.speed,
                        lastUpdated: Date()
                    )
                } else {
                    // Data unchanged, keep previous timestamp
                    return previousVehicle
                }
            } else {
                // New vehicle, set current timestamp
                hasPositionChange = true
                return Vehicle(
                    id: newVehicle.id,
                    routeId: newVehicle.routeId,
                    tripId: newVehicle.tripId,
                    routeName: newVehicle.routeName,
                    latitude: newVehicle.latitude,
                    longitude: newVehicle.longitude,
                    heading: newVehicle.heading,
                    speed: newVehicle.speed,
                    lastUpdated: Date()
                )
            }
        }
        
        // Update lastPositionUpdate only when positions actually change
        if hasPositionChange {
            lastPositionUpdate = Date()
        }
        
        return updatedVehicles
    }
    
    /// Get cached trip updates (used by sheets to avoid redundant fetching)
    func getCachedTripUpdates() -> [String: TripUpdate] {
        cachedTripUpdates
    }
    
    /// Refresh trip updates in background
    func refreshTripUpdates() async {
        do {
            let updates = try await realtimeETAService.fetchTripUpdates(forceRefresh: false)
            cachedTripUpdates = updates
            lastTripUpdateTimestamp = Date()
        } catch {
            // Silently fail - trip updates are not critical
            print("⚠️ Failed to fetch trip updates: \(error)")
        }
    }
    
    /// Get route by ID
    func route(for routeId: String) -> Route? {
        routes.first { $0.route_id == routeId }
    }
    
    /// Get enriched vehicle data with route information
    func enrichedVehicles() -> [EnrichedVehicle] {
        vehicles.map { vehicle in
            let route = self.route(for: vehicle.routeId)
            return EnrichedVehicle(
                vehicle: vehicle,
                route: route
            )
        }
    }
    
    /// Get route polylines for all active routes
    func getActiveRoutePolylines() -> [RoutePolyline] {
        // Performance optimization: Cache polylines for 30 seconds
        if let lastUpdate = lastPolylineUpdate,
           Date().timeIntervalSince(lastUpdate) < 30.0,
           !cachedPolylines.isEmpty {
            return cachedPolylines
        }
        
        let polylineStart = Date()
        // Get unique route IDs from active vehicles
        let activeRouteIds = Set(vehicles.map { $0.routeId })
        
        // For each active route, get all its shapes
        var polylines: [RoutePolyline] = []
        
        for routeId in activeRouteIds {
            guard let route = routes.first(where: { $0.route_id == routeId }) else {
                continue
            }
            
            // Get all trips for this route to find shape_ids
            let routeTrips = trips.filter { $0.route_id == routeId }
            let shapeIds = Set(routeTrips.compactMap { $0.shape_id })
            
            let routeColor = route.route_color != nil && !route.route_color!.isEmpty
                ? Color(hex: route.route_color!)
                : Color.blue
            
            // For each shape, create a polyline
            for shapeId in shapeIds {
                let shapePoints = shapes
                    .filter { $0.shape_id == shapeId }
                    .sorted { $0.shape_pt_sequence < $1.shape_pt_sequence }
                
                if !shapePoints.isEmpty {
                    let coordinates = shapePoints.map { shape in
                        CLLocationCoordinate2D(
                            latitude: shape.shape_pt_lat,
                            longitude: shape.shape_pt_lon
                        )
                    }
                    
                    polylines.append(RoutePolyline(
                        id: shapeId,
                        coordinates: coordinates,
                        color: routeColor,
                        routeName: route.route_short_name
                    ))
                }
            }
        }
        
        // Cache the results
        cachedPolylines = polylines
        lastPolylineUpdate = Date()
        
        _ = Date().timeIntervalSince(polylineStart)
        
        return polylines
    }
    
    // Note: deinit for @MainActor classes cannot call async methods
    // The refreshTask will be automatically cancelled when the instance is deallocated
}

/// Vehicle enriched with static route data
struct EnrichedVehicle: Identifiable {
    let vehicle: Vehicle
    let route: Route?
    
    var id: String { vehicle.id }
    var routeColor: Color {
        if let hex = route?.route_color, !hex.isEmpty {
            return Color(hex: hex)
        }
        return .blue
    }
    var routeShortName: String { route?.route_short_name ?? vehicle.routeName }
    var routeLongName: String { route?.route_long_name ?? vehicle.routeName }
    var coordinate: CLLocationCoordinate2D { vehicle.coordinate }
    var heading: Double? { vehicle.heading }
    var lastUpdated: Date { vehicle.lastUpdated }
}

/// Extension to convert hex color string to SwiftUI Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// Represents a route polyline with its color
struct RoutePolyline: Identifiable {
    let id: String // shape_id
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    let routeName: String
}

