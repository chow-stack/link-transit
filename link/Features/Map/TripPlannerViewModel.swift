import Foundation
import CoreLocation
import Observation
import SwiftUI

/// View model orchestrating trip planning search, routing, and live updates
@Observable
@MainActor
class TripPlannerViewModel {
    // MARK: - Dependencies
    
    private let routingEngine: TripRoutingEngine
    let dataSyncService: DataSyncService // Made public for RouteChip to access route colors
    private let stopIndex: StopIndex
    
    // MARK: - State Properties
    
    /// Origin location for trip planning
    var origin: PlannedLocation?
    
    /// Destination location for trip planning
    var destination: PlannedLocation?
    
    /// Found itineraries sorted by arrival time (earliest first), then by transfer count, then by total time
    var itineraries: [Itinerary] = []
    
    /// Whether a route search is currently in progress
    var isLoading: Bool = false
    
    /// Error message if route search fails
    var errorMessage: String?
    
    /// Currently selected itinerary for detail view
    var selectedItinerary: Itinerary?
    
    /// Last update timestamp for live refresh indicator
    var lastUpdated: Date?
    
    /// Last time OTP was queried (only set when user clicks "Search Routes")
    var lastOTPQuery: Date?
    
    // MARK: - Guidance Mode State
    
    /// Whether guidance mode is currently active
    var isGuidanceMode: Bool = false
    
    /// Formatted itinerary for guidance overlays
    var formattedSelectedItinerary: FormattedItinerary?
    
    /// Computed walking polylines for guidance mode
    var computedWalkPolylines: [[CLLocationCoordinate2D]] = []
    
    /// Computed ride polylines for guidance mode
    var computedRidePolylines: [([CLLocationCoordinate2D], Color)] = []
    
    /// Whether directions banner is expanded
    var isDirectionsBannerExpanded: Bool = false
    
    // MARK: - Timer Management
    
    /// Task for periodic ETA refresh
    private var refreshTask: Task<Void, Never>?
    
    /// Refresh interval in seconds (aligned with GTFS-RT cadence)
    private let refreshInterval: TimeInterval = TripPlannerConfig.liveRefreshSec
    
    /// Whether refresh is currently paused (e.g., detail view not visible)
    private var isRefreshPaused: Bool = false
    
    // MARK: - Initialization
    
    init(
        routingEngine: TripRoutingEngine,
        dataSyncService: DataSyncService,
        stopIndex: StopIndex
    ) {
        self.routingEngine = routingEngine
        self.dataSyncService = dataSyncService
        self.stopIndex = stopIndex
    }
    
    // MARK: - Route Search
    
    /// Search for routes from origin to destination
    /// - Parameter departureTime: Optional departure time (nil = now)
    func searchRoutes(departureTime: Date? = nil) async {
        // Validate origin and destination
        guard let origin = origin, let destination = destination else {
            errorMessage = "Please select both origin and destination"
            isLoading = false
            return
        }
        
        // Validate coordinates are valid
        guard CLLocationCoordinate2DIsValid(origin.coordinate) && CLLocationCoordinate2DIsValid(destination.coordinate) else {
            errorMessage = "Invalid location. Please try selecting a different destination."
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        itineraries = []
        
        // Find routes using routing engine
        // Note: Geocoding should already be done when user selects location via search bar
        let foundRoutes = await routingEngine.findRoutes(
            from: origin,
            to: destination,
            departureTime: departureTime
        )
        
        // Update state with results
        self.itineraries = foundRoutes
        self.lastUpdated = Date()
        self.lastOTPQuery = Date() // Track when OTP was queried (only happens here)
        
        if foundRoutes.isEmpty {
            // Check if it's a walk-only route that was too far
            let distance = CLLocation(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude)
                .distance(from: CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude))
            if distance > TripPlannerConfig.maxWalkingDistanceM {
                errorMessage = "No transit routes found. The destination is too far to walk (\(Int(distance / 1609.344)) miles). Try selecting a different destination or check back later for service."
            } else {
                errorMessage = "No routes found. This may be due to limited service at this time. Try adjusting your search time or destination."
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Live Updates
    
    /// Refresh ETAs for current itineraries using latest real-time data
    /// Only refreshes local bus positions - does NOT re-query OTP
    /// OTP is only called when user explicitly clicks "Search Routes"
    func refreshETAs() async {
        // Only refresh if we have active itineraries
        guard !itineraries.isEmpty else { return }
        
        // Refresh real-time data from DataSyncService (local bus positions only)
        // This updates vehicle positions and trip updates, which are used for
        // live ETAs and bus tracking - but does NOT re-query OTP API
        await dataSyncService.refresh()
        
        self.lastUpdated = Date()
    }
    
    /// Start automatic refresh cycle for live ETA updates
    func startAutoRefresh() {
        // Cancel existing task if any
        refreshTask?.cancel()
        
        // Only start if we have itineraries
        guard !itineraries.isEmpty else { return }
        
        refreshTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Wait for initial interval before first refresh
            try? await Task.sleep(for: .seconds(self.refreshInterval))
            
            // Periodic refresh
            while !Task.isCancelled {
                if !self.isRefreshPaused {
                    await self.refreshETAs()
                }
                
                try? await Task.sleep(for: .seconds(self.refreshInterval))
            }
        }
    }
    
    /// Stop automatic refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    /// Pause refresh (e.g., when detail view is not visible)
    func pauseRefresh() {
        isRefreshPaused = true
    }
    
    /// Resume refresh (e.g., when detail view becomes visible)
    func resumeRefresh() {
        isRefreshPaused = false
    }
    
    // MARK: - Helper Methods
    
    /// Clear search results and reset state
    func clearResults() {
        itineraries = []
        selectedItinerary = nil
        errorMessage = nil
        lastUpdated = nil
        stopAutoRefresh()
    }
    
    /// Exit guidance mode and clear guidance state
    func exitGuidanceMode() {
        isGuidanceMode = false
        formattedSelectedItinerary = nil
        computedWalkPolylines = []
        computedRidePolylines = []
        isDirectionsBannerExpanded = false
        stopAutoRefresh()
        // Cancel guidance refresh task
        guidanceRefreshTask?.cancel()
        guidanceRefreshTask = nil
    }
    
    /// Enter guidance mode with a formatted itinerary
    func startGuidanceMode(with formatted: FormattedItinerary) {
        isGuidanceMode = true
        formattedSelectedItinerary = formatted
        isDirectionsBannerExpanded = false
        // Start guidance refresh task
        startGuidanceRefresh()
    }
    
    // MARK: - Guidance Refresh Task
    
    /// Task for guidance mode refresh (separate from auto-refresh)
    private var guidanceRefreshTask: Task<Void, Never>?
    
    /// Start guidance refresh task that updates overlays during guidance
    /// This task runs continuously while guidance is active, updating bus positions and overlays
    func startGuidanceRefresh() {
        // Cancel existing task if any
        guidanceRefreshTask?.cancel()
        
        // Only start if guidance is active
        guard isGuidanceMode else { return }
        
        guidanceRefreshTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.isGuidanceMode {
                // Refresh local bus positions and trip updates (no OTP re-query)
                // Note: This may log "cancelled" warnings if the task is cancelled mid-request,
                // but this is expected behavior and safe to ignore
                await dataSyncService.refresh()
                
                // Wait for next refresh cycle
                try? await Task.sleep(for: .seconds(TripPlannerConfig.liveRefreshSec))
            }
        }
    }
    
    /// Stop guidance refresh task
    func stopGuidanceRefresh() {
        guidanceRefreshTask?.cancel()
        guidanceRefreshTask = nil
    }
    
    /// Set origin location
    func setOrigin(_ location: PlannedLocation?) {
        origin = location
    }
    
    /// Set destination location
    func setDestination(_ location: PlannedLocation?) {
        destination = location
    }
    
    /// Select an itinerary for detail view
    func selectItinerary(_ itinerary: Itinerary?) {
        selectedItinerary = itinerary
    }

    /// Resolve a human-friendly bus number for a trip (matches BusInfo sheet logic)
    func getBusNumberForTrip(tripId: String?) -> String? {
        guard let tripId = tripId else { return nil }
        if let trip = dataSyncService.trips.first(where: { $0.trip_id == tripId }) {
            return trip.block_id
        }
        return nil
    }
}

