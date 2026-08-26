import Foundation
import SwiftData
import Observation

/// Store managing route filter state and persistence
@Observable
@MainActor
class RouteFilterStore {
    private var modelContext: ModelContext?
    private var routes: [Route] = []
    private var persistedRouteIds: Set<String> = []
    private var hasPersistedFilters = false
    
    /// Active filters stored in memory for quick access
    var enabledRouteIds: Set<String> = []
    
    /// Whether all routes are currently selected
    var allRoutesSelected: Bool {
        enabledRouteIds.count == routes.count
    }
    
    /// Count of active routes (considering favorites filter)
    var activeRouteCount: Int {
        enabledRouteIds.count
    }
    
    /// Total route count (considering favorites filter)
    var totalRouteCount: Int {
        routes.count
    }
    
    /// Get filtered active route count (for favorites-only mode)
    func getFilteredActiveRouteCount(filteredRoutes: [Route]) -> Int {
        filteredRoutes.filter { enabledRouteIds.contains($0.route_id) }.count
    }
    
    /// Get filtered total route count (for favorites-only mode)
    func getFilteredTotalRouteCount(filteredRoutes: [Route]) -> Int {
        filteredRoutes.count
    }
    
    /// Check if all filtered routes are selected
    func areAllFilteredRoutesSelected(filteredRoutes: [Route]) -> Bool {
        let filteredRouteIds = Set(filteredRoutes.map { $0.route_id })
        return filteredRouteIds.isSubset(of: enabledRouteIds)
    }
    
    /// Select all filtered routes
    func selectAllFiltered(filteredRoutes: [Route]) {
        let filteredRouteIds = Set(filteredRoutes.map { $0.route_id })
        enabledRouteIds.formUnion(filteredRouteIds)
        // Persist asynchronously without blocking
        Task { await saveAllFilters() }
    }
    
    /// Deselect all filtered routes
    func deselectAllFiltered(filteredRoutes: [Route]) {
        let filteredRouteIds = Set(filteredRoutes.map { $0.route_id })
        enabledRouteIds.subtract(filteredRouteIds)
        // Persist asynchronously without blocking
        Task { await saveAllFilters() }
    }
    
    init() {}
    
    /// Initialize store with model context and available routes
    /// Idempotent: skips if already initialized with same routes to prevent unnecessary SwiftData fetches
    func initialize(modelContext: ModelContext, routes: [Route]) async {
        // Skip if already initialized with same routes (compare by route IDs)
        if self.modelContext != nil {
            let currentRouteIds = Set(self.routes.map { $0.route_id })
            let newRouteIds = Set(routes.map { $0.route_id })
            if currentRouteIds == newRouteIds {
                return
            }
        }
        
        self.modelContext = modelContext
        self.routes = routes
        
        // Load saved filters from SwiftData
        await loadFilters()

        let currentRouteIds = Set(routes.map { $0.route_id })
        if hasPersistedFilters {
            // Remove routes retired by a GTFS update and enable newly introduced
            // routes by default. Existing user selections remain unchanged.
            enabledRouteIds.formIntersection(currentRouteIds)
            enabledRouteIds.formUnion(currentRouteIds.subtracting(persistedRouteIds))
            await saveAllFilters()
        } else {
            // A genuinely new install defaults to the full network. Do not use an
            // empty enabled set as the signal: users are allowed to deselect all.
            enabledRouteIds = Set(routes.map { $0.route_id })
            await saveAllFilters()
        }
    }
    
    /// Load filters from SwiftData
    private func loadFilters() async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<RouteFilter>()
            let filters = try modelContext.fetch(descriptor)

            hasPersistedFilters = !filters.isEmpty
            persistedRouteIds = Set(filters.map { $0.routeId })

            // Build set of enabled route IDs
            enabledRouteIds = Set(filters.filter { $0.isEnabled }.map { $0.routeId })
        } catch {
            print("⚠️ Failed to load route filters: \(error)")
            // Default to all routes enabled
            hasPersistedFilters = false
            persistedRouteIds = []
            enabledRouteIds = Set(routes.map { $0.route_id })
        }
    }
    
    /// Save all current filters to SwiftData
    private func saveAllFilters() async {
        guard let modelContext = modelContext else { return }
        
        do {
            // Delete existing filters
            try modelContext.delete(model: RouteFilter.self)
            
            // Save new filters
            for route in routes {
                let filter = RouteFilter(
                    routeId: route.route_id,
                    isEnabled: enabledRouteIds.contains(route.route_id)
                )
                modelContext.insert(filter)
            }
            
            try modelContext.save()
        } catch {
            print("⚠️ Failed to save route filters: \(error)")
        }
    }
    
    /// Toggle a specific route
    func toggleRoute(_ routeId: String) {
        let isEnabled: Bool
        if enabledRouteIds.contains(routeId) {
            enabledRouteIds.remove(routeId)
            isEnabled = false
        } else {
            enabledRouteIds.insert(routeId)
            isEnabled = true
        }
        
        // Persist asynchronously without blocking
        Task { await updateFilter(routeId: routeId, isEnabled: isEnabled) }
    }
    
    /// Enable all routes
    func selectAll() {
        enabledRouteIds = Set(routes.map { $0.route_id })
        // Persist asynchronously without blocking
        Task { await saveAllFilters() }
    }
    
    /// Disable all routes
    func deselectAll() {
        enabledRouteIds.removeAll()
        // Persist asynchronously without blocking
        Task { await saveAllFilters() }
    }
    
    /// Update a single filter in SwiftData
    private func updateFilter(routeId: String, isEnabled: Bool) async {
        guard let modelContext = modelContext else { return }
        
        do {
            // Try to find existing filter
            let descriptor = FetchDescriptor<RouteFilter>(
                predicate: #Predicate<RouteFilter> { filter in
                    filter.routeId == routeId
                }
            )
            let existingFilters = try modelContext.fetch(descriptor)
            
            if let existing = existingFilters.first {
                // Update existing
                existing.isEnabled = isEnabled
                existing.timestamp = Date()
            } else {
                // Create new
                let filter = RouteFilter(routeId: routeId, isEnabled: isEnabled)
                modelContext.insert(filter)
            }
            
            try modelContext.save()
        } catch {
            print("⚠️ Failed to update filter for route \(routeId): \(error)")
        }
    }
    
    /// Check if a route is enabled
    func isRouteEnabled(_ routeId: String) -> Bool {
        enabledRouteIds.contains(routeId)
    }
}
