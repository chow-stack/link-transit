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
    
    /// Route lookup by short name for O(1) access
    private var routeLookupByShortName: [String: Route] = [:]
    
    /// Route lookup by ID for O(1) access
    private var routeLookupById: [String: Route] = [:]
    
    /// Trip lookup by ID for O(1) access
    private var tripLookupById: [String: Trip] = [:]
    
    // MARK: - Computed Properties from DataSyncService
    
    var vehicles: [Vehicle] { dataSyncService.vehicles }
    
    /// Stops filtered by enabled routes and active buses
    var stops: [StopWithColor] {
        let allStops = dataSyncService.stops
        let enabledRouteIds = getEnabledRouteIds()
        let routesWithActiveBuses = getRoutesWithActiveBuses()
        
        let stopsForActiveRoutes = dataSyncService.stopTimesService.getStopsForRoutes(routesWithActiveBuses)
        
        // For each stop, determine which routes serve it and get the appropriate color
        return allStops
            .filter { stopsForActiveRoutes.contains($0.id) }
            .compactMap { stop -> StopWithColor? in
                let servingRoutes = dataSyncService.stopTimesService.getRoutesForStop(stop.id)
                let filteredServingRoutes = servingRoutes.filter { enabledRouteIds.contains($0.route_id) }
                
                guard let primaryRoute = filteredServingRoutes.first else { return nil }
                
                // Determine route color
                let routeColor: Color
                if let hex = primaryRoute.route_color, !hex.isEmpty {
                    routeColor = Color(hex: hex)
                } else {
                    routeColor = .blue
                }
                
                return StopWithColor(stop: stop, routeColor: routeColor)
            }
    }
    
    /// Enriched vehicles filtered by user's route selection and favorites
    var enrichedVehicles: [EnrichedVehicle] {
        let allVehicles = dataSyncService.enrichedVehicles()
        let enabledRouteIds = getEnabledRouteIds()
        
        if favoriteStore.showFavoritesOnly {
            let favoritedRouteIds = Set(favoriteStore.routeFavorites.map { $0.itemId })
            return allVehicles.filter { vehicle in
                let routeId = vehicle.vehicle.routeId
                return enabledRouteIds.contains(routeId) && favoritedRouteIds.contains(routeId)
            }
        } else {
            return allVehicles.filter { vehicle in
                enabledRouteIds.contains(vehicle.vehicle.routeId)
            }
        }
    }
    
    /// Route polylines filtered by user's route selection and favorites
    var routePolylines: [RoutePolyline] {
        let allPolylines = dataSyncService.getActiveRoutePolylines()
        let enabledRouteIds = getEnabledRouteIds()
        
        let favoritedRouteIds: Set<String>? = favoriteStore.showFavoritesOnly 
            ? Set(favoriteStore.routeFavorites.map { $0.itemId })
            : nil
        
        // Filter polylines using dictionary lookup
        return allPolylines.compactMap { polyline -> RoutePolyline? in
            guard let route = routeLookupByShortName[polyline.routeName],
                  enabledRouteIds.contains(route.route_id) else {
                return nil
            }
            
            // Apply favorites filter if enabled
            if let favoritedIds = favoritedRouteIds {
                guard favoritedIds.contains(route.route_id) else {
                    return nil
                }
            }
            
            return polyline
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
        let tripUpdates = dataSyncService.getCachedTripUpdates()
        let viewModel = BusInfoViewModel(
            stopTimesService: dataSyncService.stopTimesService,
            trips: dataSyncService.trips,
            stops: dataSyncService.stops,
            tripUpdates: tripUpdates
        )
        return await viewModel.getBusInfo(for: bus)
    }
    
    /// Check if no buses are active (considering filters)
    var hasNoBuses: Bool {
        enrichedVehicles.isEmpty && lastUpdated != nil && !isOffline
    }
    
    /// Get filtered route counts for status bar display
    /// Format: selected routes / total routes active (or total favorited routes in favorites mode)
    var filteredRouteCounts: (active: Int, total: Int) {
        if favoriteStore.showFavoritesOnly {
            // When favorites-only is active, show counts for favorited routes only
            let favoritedRouteIds = Set(favoriteStore.routeFavorites.map { $0.itemId })
            let activeFavoritedRoutes = favoritedRouteIds.intersection(filterStore.enabledRouteIds)
            return (active: activeFavoritedRoutes.count, total: favoritedRouteIds.count)
        } else {
            // Normal filtering: show selected routes / total routes with active buses
            let activeRouteIds = getActiveRouteIds()
            return (active: filterStore.activeRouteCount, total: activeRouteIds.count)
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
    }
    
    /// Manually refresh vehicle data
    func refresh() async {
        await dataSyncService.refresh(forceRefresh: true)
    }
    
    // MARK: - Lookup Dictionaries
    
    /// Build lookup dictionaries for O(1) route/trip access
    private func buildLookupDictionaries() {
        routeLookupByShortName = Dictionary(uniqueKeysWithValues: dataSyncService.routes.compactMap { route -> (String, Route)? in
            // route_short_name is non-optional String, but may be empty
            if route.route_short_name.isEmpty {
                return nil
            }
            return (route.route_short_name, route)
        })
        
        routeLookupById = Dictionary(uniqueKeysWithValues: dataSyncService.routes.map { ($0.route_id, $0) })
        
        tripLookupById = Dictionary(uniqueKeysWithValues: dataSyncService.trips.map { ($0.trip_id, $0) })
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
    
    // MARK: - Lookup Methods
    
    /// Get route by short name (O(1) lookup)
    func route(byShortName shortName: String) -> Route? {
        return routeLookupByShortName[shortName]
    }
    
    /// Get route by ID (O(1) lookup)
    func route(byId routeId: String) -> Route? {
        return routeLookupById[routeId]
    }
    
    /// Get trip by ID (O(1) lookup)
    func trip(byId tripId: String) -> Trip? {
        return tripLookupById[tripId]
    }
    
}

/// Stop with route color information
struct StopWithColor: Identifiable {
    let stop: Stop
    let routeColor: Color
    
    var id: Int { stop.id }
    var name: String { stop.name }
    var coordinate: CLLocationCoordinate2D { stop.coordinate }
}

