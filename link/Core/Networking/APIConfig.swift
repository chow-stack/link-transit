import Foundation

/// API Configuration for GTFS-realtime feeds
/// Note: Not @MainActor so it can be accessed from actors
struct APIConfig {
    /// GTFS-Realtime Protocol Buffer Feed URLs
    /// Direct feeds from Bloomington Transit
    static let vehiclePositionsFeedURL = "https://s3.amazonaws.com/etatransit.gtfs/bloomingtontransit.etaspot.net/position_updates.pb"
    static let tripUpdatesFeedURL = "https://s3.amazonaws.com/etatransit.gtfs/bloomingtontransit.etaspot.net/trip_updates.pb"
    static let alertsFeedURL = "https://s3.amazonaws.com/etatransit.gtfs/bloomingtontransit.etaspot.net/alerts.pb"
    
    /// Network timeouts (reduced for faster failure on weak connections)
    /// Faster timeouts prevent app from hanging on slow/no internet connections
    static let requestTimeout: TimeInterval = 15.0
    static let resourceTimeout: TimeInterval = 20.0
    
    /// Retry configuration. Backoff is exponential starting from this base
    /// (0.5s, 1.0s, ...) rather than a large fixed delay: a cold-connection
    /// hiccup on the first attempt (radio wake, TLS handshake) usually
    /// resolves itself immediately on retry, so a long fixed wait before
    /// retrying only adds dead time to the first realtime fetch of a launch.
    static let maxRetries = 3
    static let retryDelay: TimeInterval = 0.5
    
    /// Refresh intervals (in seconds)
    static let vehicleRefreshInterval: TimeInterval = 15.0
    static let alertRefreshInterval: TimeInterval = 60.0
    
    /// Cache durations (in seconds)
    static let vehicleCacheDuration: TimeInterval = 15.0
    static let stopCacheDuration: TimeInterval = 300.0 // 5 minutes
    
}
