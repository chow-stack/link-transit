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
    
    /// Retry configuration
    static let maxRetries = 3
    static let retryDelay: TimeInterval = 2.0
    
    /// Refresh intervals (in seconds)
    static let vehicleRefreshInterval: TimeInterval = 5.0 // Changed from 10.0 to 5.0
    static let alertRefreshInterval: TimeInterval = 60.0
    
    /// Cache durations (in seconds)
    static let vehicleCacheDuration: TimeInterval = 15.0
    static let stopCacheDuration: TimeInterval = 300.0 // 5 minutes
    
    // MARK: - OpenTripPlanner API Configuration
    
    /// OTP API endpoint for trip planning
    static let otpBaseURL = "https://api.bloombus.app/otp/gtfs/v1"
    
    /// OTP request timeout
    static let otpTimeout: TimeInterval = 15.0
    
    /// OTP refresh interval during guidance (re-query every 60s)
    static let otpRefreshInterval: TimeInterval = 60.0
}

