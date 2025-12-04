import Foundation

/// Service for fetching real-time transit data directly from GTFS-realtime Protocol Buffer feeds
actor RealtimeService {
    static let shared = RealtimeService()
    
    private let gtfsService: GTFSRealtimeService
    
    private init() {
        self.gtfsService = GTFSRealtimeService.shared
    }
    
    /// Fetch real-time vehicle positions with caching
    func fetchVehicles(forceRefresh: Bool = false) async throws -> [Vehicle] {
        // Delegate to GTFS-realtime service which handles caching
        return try await gtfsService.fetchVehicles(forceRefresh: forceRefresh)
    }
    
    /// Check if service is available (always true for direct GTFS-RT feeds)
    func isServiceAvailable() -> Bool {
        true
    }
    
    /// Clear cache
    func clearCache() async {
        await gtfsService.clearCache()
    }
}

