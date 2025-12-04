import Foundation
import CoreLocation
import MapKit

/// Service for calculating walking routes and times using MKDirections
/// Uses actor for thread-safe access to MKDirections
actor WalkingRouteService {
    // MARK: - Singleton
    
    static let shared = WalkingRouteService()
    
    // MARK: - Private Properties
    
    private var cache: [String: CachedWalkingRoute] = [:]
    private let cacheTimeout: TimeInterval = 3600 // 1 hour
    private let requestTimeout: TimeInterval = 10.0 // 10 seconds
    private let cachePrecision: Double = 100.0 // Round coordinates to 100m precision for cache key
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Walking Route Calculation
    
    /// Calculate walking route from one coordinate to another
    /// - Parameters:
    ///   - from: Starting coordinate
    ///   - to: Destination coordinate
    /// - Returns: WalkingRoute with distance, duration, and polyline
    /// - Throws: WalkingRouteError if route calculation fails
    func calculateWalkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> WalkingRoute {
        // Check cache first
        let cacheKey = makeCacheKey(from: from, to: to)
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.route
        }
        
        // Try MapKit first, fallback to great-circle distance if unavailable
        do {
            return try await calculateRouteWithMapKit(from: from, to: to, cacheKey: cacheKey)
        } catch {
            // Fallback to great-circle distance calculation
            print("⚠️ MKDirections failed, using fallback: \(error.localizedDescription)")
            return calculateFallbackRoute(from: from, to: to, cacheKey: cacheKey)
        }
    }
    
    // MARK: - Private Methods
    
    /// Calculate route using MKDirections
    private func calculateRouteWithMapKit(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        cacheKey: String
    ) async throws -> WalkingRoute {
        let sourcePlacemark = MKPlacemark(coordinate: from)
        let destinationPlacemark = MKPlacemark(coordinate: to)
        
        let sourceMapItem = MKMapItem(placemark: sourcePlacemark)
        let destinationMapItem = MKMapItem(placemark: destinationPlacemark)
        
        let request = MKDirections.Request()
        request.source = sourceMapItem
        request.destination = destinationMapItem
        request.transportType = .walking
        
        let directions = MKDirections(request: request)
        
        // Perform route calculation with timeout
        return try await withThrowingTaskGroup(of: WalkingRoute.self) { group in
            group.addTask {
                let response = try await directions.calculate()
                guard let route = response.routes.first else {
                    throw WalkingRouteError.noRouteFound
                }
                
                // Extract polyline coordinates
                let polyline = route.polyline
                var coordinates: [CLLocationCoordinate2D] = []
                let pointCount = polyline.pointCount
                
                if pointCount > 0 {
                    // Use MKPolyline's points() method to get coordinates
                    let points = polyline.points()
                    for i in 0..<pointCount {
                        coordinates.append(points[i].coordinate)
                    }
                }
                
                return WalkingRoute(
                    distance: route.distance,
                    duration: route.expectedTravelTime,
                    polyline: coordinates
                )
            }
            
            group.addTask {
                try await Task.sleep(for: .seconds(self.requestTimeout))
                throw WalkingRouteError.timeout
            }
            
            // Get first result (either success or timeout)
            let result = try await group.next()!
            // Cancel remaining tasks
            group.cancelAll()
            
            // Cache the result
            self.cacheResult(key: cacheKey, route: result)
            
            return result
        }
    }
    
    /// Calculate fallback route using great-circle distance
    private func calculateFallbackRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        cacheKey: String
    ) -> WalkingRoute {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        
        // Calculate great-circle distance
        let distance = fromLocation.distance(from: toLocation)
        
        // Calculate walking time using walking speed from config
        let walkingSpeed = TripPlannerConfig.walkingSpeedMps
        let duration = distance / walkingSpeed
        
        // Create simple polyline with just start and end points
        let polyline = [from, to]
        
        let route = WalkingRoute(
            distance: distance,
            duration: duration,
            polyline: polyline
        )
        
        // Cache the result
        cacheResult(key: cacheKey, route: route)
        
        return route
    }
    
    /// Create cache key from coordinates (rounded to 100m precision)
    private func makeCacheKey(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String {
        // Round coordinates to 100m precision for cache key
        // This groups nearby coordinates together in cache
        let roundedFromLat = round(from.latitude * (cachePrecision / 0.0009)) / (cachePrecision / 0.0009)
        let roundedFromLon = round(from.longitude * (cachePrecision / 0.0009)) / (cachePrecision / 0.0009)
        let roundedToLat = round(to.latitude * (cachePrecision / 0.0009)) / (cachePrecision / 0.0009)
        let roundedToLon = round(to.longitude * (cachePrecision / 0.0009)) / (cachePrecision / 0.0009)
        
        // Ensure consistent ordering (smaller coordinate first)
        if roundedFromLat < roundedToLat || (roundedFromLat == roundedToLat && roundedFromLon < roundedToLon) {
            return "\(roundedFromLat),\(roundedFromLon)-\(roundedToLat),\(roundedToLon)"
        } else {
            return "\(roundedToLat),\(roundedToLon)-\(roundedFromLat),\(roundedFromLon)"
        }
    }
    
    /// Cache a walking route result
    private func cacheResult(key: String, route: WalkingRoute) {
        cache[key] = CachedWalkingRoute(
            route: route,
            timestamp: Date()
        )
    }
    
    /// Clear the walking route cache
    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Supporting Types

/// Represents a walking route with distance, duration, and polyline coordinates
struct WalkingRoute {
    /// Distance in meters
    let distance: Double
    
    /// Duration in seconds
    let duration: TimeInterval
    
    /// Polyline coordinates for map rendering
    let polyline: [CLLocationCoordinate2D]
    
    /// Formatted distance string (e.g., "2.3 km" or "800 m")
    var formattedDistance: String {
        if distance >= 1000 {
            let km = distance / 1000
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
    
    /// Formatted duration string (e.g., "5 min")
    var formattedDuration: String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

private struct CachedWalkingRoute {
    let route: WalkingRoute
    let timestamp: Date
}

enum WalkingRouteError: LocalizedError {
    case noRouteFound
    case timeout
    case networkError(Error)
    case mapKitUnavailable
    
    var errorDescription: String? {
        switch self {
        case .noRouteFound:
            return "No walking route found"
        case .timeout:
            return "Route calculation timed out. Please check your connection and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .mapKitUnavailable:
            return "MapKit is unavailable. Using estimated route."
        }
    }
}

