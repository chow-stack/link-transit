import Foundation

/// Configuration values for trip planning algorithm
/// All values are tunable defaults that can be adjusted without code changes
struct TripPlannerConfig {
    /// Number of candidate origin stops to consider
    static let kOriginStops: Int = 5
    
    /// Number of candidate destination stops to consider
    static let kTargetStops: Int = 5
    
    /// Maximum radius (meters) to search for origin stops
    static let originRadiusM: Double = 800.0
    
    /// Maximum radius (meters) to search for destination stops
    static let targetRadiusM: Double = 800.0
    
    /// Maximum distance (meters) between stops for transfer detection
    static let transferRadiusM: Double = 200.0
    
    /// Average walking speed in meters per second (1.4 m/s ≈ 5 km/h)
    static let walkingSpeedMps: Double = 1.4
    
    /// Penalty in seconds added to itinerary weight for each transfer
    static let transferPenaltySec: TimeInterval = 180.0
    
    /// Refresh interval in seconds for live ETA updates (matches GTFS-RT cadence)
    static let liveRefreshSec: TimeInterval = 15.0
    
    /// Threshold in seconds for marking real-time feed as stale
    static let staleFeedSec: TimeInterval = 120.0
    
    /// Maximum walking distance (meters) for walk-only fallback route
    static let maxWalkingDistanceM: Double = 3000.0
    
    /// Safety buffer in seconds added to transfer time
    static let transferSafetyBufferSec: TimeInterval = 90.0
    
    /// Maximum number of itineraries to return from routing engine
    static let maxItineraries: Int = 5
    
    /// Maximum radius (meters) for pre-computing transfer adjacency matrix
    static let transferMatrixRadiusM: Double = 500.0
}

