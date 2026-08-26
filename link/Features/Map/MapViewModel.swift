import Foundation
import Observation
import SwiftUI
import CoreLocation

/// View model managing map state and vehicle data
@Observable
@MainActor
class MapViewModel {
    let dataSyncService: DataSyncService
    let filterStore: RouteFilterStore
    let favoriteStore: FavoriteStore
    
    // MARK: - Lookup Dictionaries (built once during initialization)
    
    /// Trip lookup by ID for O(1) access
    private var tripLookupById: [String: Trip] = [:]
    private var stopLookupById: [Int: Stop] = [:]
    private var firstTripByRouteId: [String: Trip] = [:]

    private var busInfoCache: [String: (info: BusInfo, vehicleUpdate: Date, tripUpdate: Date?, cachedAt: Date)] = [:]
    private let busInfoCacheDuration: TimeInterval = 10

    /// Memoized `Color(hex:)` results by route ID. `Color(hex:)` allocates a
    /// `CharacterSet`/`Scanner` per call; parsing it for every stop on every
    /// `rebuildMapSnapshot()` (~every 15s) is unnecessary since a route's
    /// color never changes after static data loads.
    private var routeColorCache: [String: Color] = [:]

    /// Resolve and cache a route's display color.
    private func color(for route: Route) -> Color {
        if let cached = routeColorCache[route.route_id] {
            return cached
        }
        let color: Color
        if let hex = route.route_color, !hex.isEmpty {
            color = Color(hex: hex)
        } else {
            color = .blue
        }
        routeColorCache[route.route_id] = color
        return color
    }
    
    // MARK: - Computed Properties from DataSyncService
    
    var vehicles: [Vehicle] { dataSyncService.vehicles }
    
    /// Prepared map content. SwiftUI reads these stable arrays instead of
    /// rebuilding the network graph during every view-body evaluation.
    private(set) var stops: [StopWithColor] = []
    private(set) var enrichedVehicles: [EnrichedVehicle] = []
    private(set) var routePolylines: [RoutePolyline] = []

    /// Rebuild map content only when realtime data or user filters change.
    func rebuildMapSnapshot() {
        let allStops = dataSyncService.stops
        let enabledRouteIds = getEnabledRouteIds()
        let routesWithActiveBuses = getRoutesWithActiveBuses()
        let stopsForActiveRoutes = dataSyncService.stopTimesService.getStopsForRoutes(routesWithActiveBuses)

        stops = allStops
            .filter { stopsForActiveRoutes.contains($0.id) }
            .compactMap { stop -> StopWithColor? in
                let servingRoutes = dataSyncService.stopTimesService.getRoutesForStop(stop.id)
                let filteredServingRoutes = servingRoutes.filter { enabledRouteIds.contains($0.route_id) }
                
                guard !filteredServingRoutes.isEmpty else { return nil }

                return StopWithColor(
                    stop: stop,
                    routeColors: filteredServingRoutes.map { color(for: $0) },
                    routeShortNames: filteredServingRoutes.map(\.route_short_name)
                )
            }

        let allVehicles = dataSyncService.enrichedVehicles()
        if favoriteStore.showFavoritesOnly {
            let favoritedRouteIds = Set(favoriteStore.routeFavorites.map { $0.itemId })
            enrichedVehicles = allVehicles.filter { vehicle in
                let routeId = vehicle.vehicle.routeId
                return enabledRouteIds.contains(routeId) && favoritedRouteIds.contains(routeId)
            }
        } else {
            enrichedVehicles = allVehicles.filter { vehicle in
                enabledRouteIds.contains(vehicle.vehicle.routeId)
            }
        }

        let allPolylines = dataSyncService.getActiveRoutePolylines()
        let favoritedRouteIds: Set<String>? = favoriteStore.showFavoritesOnly 
            ? Set(favoriteStore.routeFavorites.map { $0.itemId })
            : nil

        routePolylines = allPolylines.filter { polyline in
            guard enabledRouteIds.contains(polyline.routeId) else { return false }
            if let favoritedIds = favoritedRouteIds {
                return favoritedIds.contains(polyline.routeId)
            }
            return true
        }
    }
    
    var errorMessage: String? { dataSyncService.errorMessage }
    var lastUpdated: Date? { dataSyncService.lastUpdated }
    var lastPositionUpdate: Date? { dataSyncService.lastPositionUpdate }
    var isOffline: Bool { dataSyncService.isOffline }
    
    /// Get upcoming arrivals for a specific stop with real-time ETAs
    func getArrivals(for stopId: Int) async -> [Arrival] {
        let tripUpdates = dataSyncService.getCachedTripUpdates()
        return await dataSyncService.stopTimesService.getUpcomingArrivals(for: stopId, maxArrivals: 10, tripUpdates: tripUpdates)
    }
    
    /// Get bus information including current stop and upcoming stops
    func getBusInfo(for bus: EnrichedVehicle) async -> BusInfo? {
        if let cached = busInfoCache[bus.id],
           cached.vehicleUpdate == bus.lastUpdated,
           cached.tripUpdate == dataSyncService.tripUpdatesGeneration,
           Date().timeIntervalSince(cached.cachedAt) < busInfoCacheDuration {
            return cached.info
        }

        let tripUpdates = dataSyncService.getCachedTripUpdates()
        let viewModel = BusInfoViewModel(
            stopTimesService: dataSyncService.stopTimesService,
            tripLookup: tripLookupById,
            stopLookup: stopLookupById,
            firstTripByRouteId: firstTripByRouteId,
            tripUpdates: tripUpdates
        )
        guard let info = await viewModel.getBusInfo(for: bus) else { return nil }
        busInfoCache[bus.id] = (
            info: info,
            vehicleUpdate: bus.lastUpdated,
            tripUpdate: dataSyncService.tripUpdatesGeneration,
            cachedAt: Date()
        )
        return info
    }
    
    /// Check if no buses are active (NOT considering filters)
    /// This distinguishes between "no buses running" vs "all routes filtered out"
    /// We check the actual vehicle count from dataSyncService, not filtered enrichedVehicles,
    /// to ensure we only show NoBusesView when there are truly no buses,
    /// not when all routes are just filtered out
    var hasNoBuses: Bool {
        vehicles.isEmpty && lastUpdated != nil && !isOffline
    }
    
    /// Get filtered route counts for status bar display
    /// Format: selected active routes / total active routes (or total favorited active routes in favorites mode)
    /// Only counts routes that currently have active buses
    var filteredRouteCounts: (active: Int, total: Int) {
        let activeRouteIds = getActiveRouteIds()
        
        if favoriteStore.showFavoritesOnly {
            // When favorites-only is active, show counts for favorited routes only
            let favoritedRouteIds = Set(favoriteStore.routeFavorites.map { $0.itemId })
            // Only count favorited routes that are both enabled AND active
            let activeFavoritedEnabledRoutes = favoritedRouteIds.intersection(filterStore.enabledRouteIds).intersection(activeRouteIds)
            // Only count favorited routes that are active
            let activeFavoritedRoutes = favoritedRouteIds.intersection(activeRouteIds)
            return (active: activeFavoritedEnabledRoutes.count, total: activeFavoritedRoutes.count)
        } else {
            // Only count enabled routes that are active
            let activeEnabledRoutes = filterStore.enabledRouteIds.intersection(activeRouteIds)
            return (active: activeEnabledRoutes.count, total: activeRouteIds.count)
        }
    }
    
    /// Check if all filtered routes are selected
    var allFilteredRoutesSelected: Bool {
        if favoriteStore.showFavoritesOnly {
            let favoritedRouteIds = Set(favoriteStore.routeFavorites.map { $0.itemId })
            return favoritedRouteIds.isSubset(of: filterStore.enabledRouteIds)
        } else {
            return filterStore.allRoutesSelected
        }
    }
    
    init(dataSyncService: DataSyncService, filterStore: RouteFilterStore, favoriteStore: FavoriteStore) {
        self.dataSyncService = dataSyncService
        self.filterStore = filterStore
        self.favoriteStore = favoriteStore
    }
    
    /// Initialize data sync (loads static + starts realtime polling)
    func initialize() async {
        await dataSyncService.initialize()
        // Build lookup dictionaries after data is loaded
        buildLookupDictionaries()
        rebuildMapSnapshot()
    }
    
    /// Manually refresh vehicle data
    func refresh() async {
        await dataSyncService.refresh(forceRefresh: true)
        rebuildMapSnapshot()
    }
    
    // MARK: - Lookup Dictionaries
    
    /// Build lookup dictionaries for O(1) trip and stop access
    private func buildLookupDictionaries() {
        tripLookupById = Dictionary(uniqueKeysWithValues: dataSyncService.trips.map { ($0.trip_id, $0) })
        stopLookupById = Dictionary(uniqueKeysWithValues: dataSyncService.stops.map { ($0.id, $0) })
        firstTripByRouteId = Dictionary(
            dataSyncService.trips.map { ($0.route_id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
    
    // MARK: - Filtering Logic
    
    /// Get enabled route IDs considering favorites filter
    private func getEnabledRouteIds() -> Set<String> {
        if favoriteStore.showFavoritesOnly {
            let favoritedRouteIds = Set(favoriteStore.routeFavorites.map { $0.itemId })
            return favoritedRouteIds.intersection(filterStore.enabledRouteIds)
        } else {
            return filterStore.enabledRouteIds
        }
    }
    
    /// Get route IDs that have active buses
    private func getActiveRouteIds() -> Set<String> {
        return Set(vehicles.map { $0.routeId })
    }
    
    /// Get routes that are both enabled AND have active buses
    private func getRoutesWithActiveBuses() -> Set<String> {
        let enabledRouteIds = getEnabledRouteIds()
        let activeRouteIds = getActiveRouteIds()
        return enabledRouteIds.intersection(activeRouteIds)
    }
    
}

/// Stop with all selected serving-route colors for segmented map markers.
struct StopWithColor: Identifiable {
    let stop: Stop
    let routeColors: [Color]
    let routeShortNames: [String]
    
    var id: Int { stop.id }
    var name: String { stop.name }
    var coordinate: CLLocationCoordinate2D { stop.coordinate }
}
