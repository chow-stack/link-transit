import Foundation
import SwiftData
import Observation

/// Store managing favorites state and persistence
@Observable
@MainActor
class FavoriteStore {
    private var modelContext: ModelContext?
    
    /// All favorites loaded from SwiftData
    private var allFavorites: [Favorite] = []
    
    /// Whether to show only favorites in route filtering
    var showFavoritesOnly: Bool = false
    private(set) var isInitialized = false
    private(set) var revision = 0
    
    /// Get all favorites
    var favorites: [Favorite] {
        allFavorites.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }
    
    /// Get route favorites only
    var routeFavorites: [Favorite] {
        allFavorites.filter { $0.type == .route }
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }
    
    /// Get stop favorites only
    var stopFavorites: [Favorite] {
        allFavorites.filter { $0.type == .stop }
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }
    
    /// Get favorite route IDs for filtering
    var favoriteRouteIds: Set<String> {
        Set(routeFavorites.map { $0.itemId })
    }
    
    /// Get favorite stop IDs for filtering
    var favoriteStopIds: Set<Int> {
        Set(stopFavorites.compactMap { Int($0.itemId) })
    }
    
    /// Check if a route is favorited
    func isRouteFavorited(_ routeId: String) -> Bool {
        allFavorites.contains { $0.type == .route && $0.itemId == routeId }
    }
    
    /// Check if a stop is favorited
    func isStopFavorited(_ stopId: Int) -> Bool {
        allFavorites.contains { $0.type == .stop && $0.itemId == String(stopId) }
    }
    
    init() {}
    
    /// Initialize store with model context
    /// Idempotent: skips if already initialized to prevent unnecessary SwiftData fetches
    func initialize(modelContext: ModelContext) async {
        // Skip if already initialized (modelContext already set)
        guard self.modelContext == nil else { return }
        
        self.modelContext = modelContext
        await loadFavorites()
        isInitialized = true
    }
    
    /// Load favorites from SwiftData
    private func loadFavorites() async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Favorite>()
            allFavorites = try modelContext.fetch(descriptor)
            revision &+= 1
            print("✅ Loaded \(allFavorites.count) favorites from storage")
            
            // Auto-disable favorites-only mode if no route favorites remain
            checkAndDisableFavoritesOnlyIfNeeded()
        } catch {
            print("⚠️ Failed to load favorites: \(error)")
            allFavorites = []
            revision &+= 1
        }
    }
    
    /// Check if favorites-only mode should be disabled and disable it if needed
    private func checkAndDisableFavoritesOnlyIfNeeded() {
        if showFavoritesOnly && routeFavorites.isEmpty {
            showFavoritesOnly = false
            print("🔄 Auto-disabled favorites-only mode (no route favorites remaining)")
        }
    }
    
    /// Add a route to favorites
    func addRouteFavorite(routeId: String, name: String, routeColor: String?) async {
        guard let modelContext = modelContext else { return }
        
        // Check if already favorited
        if isRouteFavorited(routeId) {
            return
        }
        
        let favorite = Favorite(
            type: .route,
            itemId: routeId,
            name: name,
            routeColor: routeColor
        )
        
        do {
            modelContext.insert(favorite)
            try modelContext.save()
            await loadFavorites()
            print("✅ Added route \(routeId) to favorites")
        } catch {
            print("⚠️ Failed to add route favorite: \(error)")
        }
    }
    
    /// Add a stop to favorites
    func addStopFavorite(stopId: Int, name: String) async {
        guard let modelContext = modelContext else { return }
        
        // Check if already favorited
        if isStopFavorited(stopId) {
            return
        }
        
        let favorite = Favorite(
            type: .stop,
            itemId: String(stopId),
            name: name
        )
        
        do {
            modelContext.insert(favorite)
            try modelContext.save()
            await loadFavorites()
            print("✅ Added stop \(stopId) to favorites")
        } catch {
            print("⚠️ Failed to add stop favorite: \(error)")
        }
    }
    
    /// Remove a route from favorites
    func removeRouteFavorite(routeId: String) async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Favorite>(
                predicate: #Predicate<Favorite> { favorite in
                    favorite.itemId == routeId
                }
            )
            let favorites = try modelContext.fetch(descriptor)
            
            // Filter for route favorites only
            let routeFavorites = favorites.filter { $0.type == .route }
            
            for favorite in routeFavorites {
                modelContext.delete(favorite)
            }
            
            try modelContext.save()
            await loadFavorites()
            
            // Check if favorites-only mode should be disabled
            checkAndDisableFavoritesOnlyIfNeeded()
            
            print("✅ Removed route \(routeId) from favorites")
        } catch {
            print("⚠️ Failed to remove route favorite: \(error)")
        }
    }
    
    /// Remove a stop from favorites
    func removeStopFavorite(stopId: Int) async {
        guard let modelContext = modelContext else { return }
        
        do {
            let stopIdString = String(stopId)
            let descriptor = FetchDescriptor<Favorite>(
                predicate: #Predicate<Favorite> { favorite in
                    favorite.itemId == stopIdString
                }
            )
            let favorites = try modelContext.fetch(descriptor)
            
            // Filter for stop favorites only
            let stopFavorites = favorites.filter { $0.type == .stop }
            
            for favorite in stopFavorites {
                modelContext.delete(favorite)
            }
            
            try modelContext.save()
            await loadFavorites()
            print("✅ Removed stop \(stopId) from favorites")
        } catch {
            print("⚠️ Failed to remove stop favorite: \(error)")
        }
    }
    
    /// Toggle route favorite status
    func toggleRouteFavorite(routeId: String, name: String, routeColor: String?) async {
        if isRouteFavorited(routeId) {
            await removeRouteFavorite(routeId: routeId)
        } else {
            await addRouteFavorite(routeId: routeId, name: name, routeColor: routeColor)
        }
    }
    
    /// Toggle stop favorite status
    func toggleStopFavorite(stopId: Int, name: String) async {
        if isStopFavorited(stopId) {
            await removeStopFavorite(stopId: stopId)
        } else {
            await addStopFavorite(stopId: stopId, name: name)
        }
    }
    
    /// Update last accessed time for a favorite
    func updateLastAccessed(for favorite: Favorite) async {
        guard let modelContext = modelContext else { return }
        
        favorite.updateLastAccessed()
        
        do {
            try modelContext.save()
            await loadFavorites()
        } catch {
            print("⚠️ Failed to update last accessed: \(error)")
        }
    }
    
    /// Clear all favorites
    func clearAllFavorites() async {
        guard let modelContext = modelContext else { return }
        
        do {
            try modelContext.delete(model: Favorite.self)
            await loadFavorites()
            
            // If favorites-only mode was active, disable it since there are no favorites left
            if showFavoritesOnly {
                showFavoritesOnly = false
            }
            
            print("✅ Cleared all favorites")
        } catch {
            print("⚠️ Failed to clear favorites: \(error)")
        }
    }
    
    /// Toggle favorites-only filtering
    func toggleFavoritesOnly() {
        showFavoritesOnly.toggle()
    }
}
