import Foundation
import CoreLocation

/// Spatial index for efficient nearest-stop queries and transfer detection
final class StopIndex {
    // MARK: - Properties
    
    private let stops: [Stop]
    private let transferAdjacencyMap: [Int: [Int: Double]] // stopId -> [nearbyStopId: distance]
    private let transferRadiusM: Double
    
    // MARK: - Initialization
    
    /// Initialize stop index with stops array
    /// - Parameter stops: Array of stops to index
    /// - Parameter transferRadiusM: Radius for transfer detection (default from TripPlannerConfig)
    init(stops: [Stop], transferRadiusM: Double = TripPlannerConfig.transferRadiusM) {
        self.stops = stops
        self.transferRadiusM = transferRadiusM
        
        // Pre-compute transfer adjacency map for stops within transfer matrix radius
        // This is expensive but done once at initialization
        let transferMatrixRadius = TripPlannerConfig.transferMatrixRadiusM
        self.transferAdjacencyMap = Self.buildTransferAdjacencyMap(
            stops: stops,
            transferRadius: transferRadiusM,
            matrixRadius: transferMatrixRadius
        )
        
        print("✅ StopIndex initialized with \(stops.count) stops")
        print("✅ Transfer adjacency map: \(transferAdjacencyMap.count) stops with nearby transfers")
    }
    
    // MARK: - Nearest Stop Queries
    
    /// Find nearest stops to a coordinate
    /// - Parameters:
    ///   - coordinate: Target coordinate
    ///   - count: Maximum number of stops to return (K)
    ///   - radius: Maximum radius in meters to search
    /// - Returns: Array of nearest stops sorted by distance (closest first)
    func nearestStops(to coordinate: CLLocationCoordinate2D, count: Int, radius: Double) -> [Stop] {
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Calculate distances for all stops
        var stopDistances: [(stop: Stop, distance: Double)] = stops.map { stop in
            let stopLocation = CLLocation(latitude: stop.lat, longitude: stop.lon)
            let distance = targetLocation.distance(from: stopLocation)
            return (stop, distance)
        }
        
        // Filter by radius and sort by distance
        stopDistances = stopDistances
            .filter { $0.distance <= radius }
            .sorted { $0.distance < $1.distance }
        
        // Return top K stops
        return Array(stopDistances.prefix(count).map { $0.stop })
    }
    
    // MARK: - Transfer Detection
    
    /// Check if two stops are within transfer radius
    /// - Parameters:
    ///   - stopId1: First stop ID
    ///   - stopId2: Second stop ID
    /// - Returns: Distance between stops if within transfer radius, nil otherwise
    func transferDistance(from stopId1: Int, to stopId2: Int) -> Double? {
        guard let nearbyStops = transferAdjacencyMap[stopId1],
              let distance = nearbyStops[stopId2] else {
            return nil
        }
        return distance
    }
    
    /// Get all stops within transfer radius of a given stop
    /// - Parameter stopId: Stop ID to check
    /// - Returns: Dictionary mapping nearby stop IDs to their distances
    func nearbyTransferStops(for stopId: Int) -> [Int: Double] {
        transferAdjacencyMap[stopId] ?? [:]
    }
    
    /// Check if a transfer is possible between two stops
    /// - Parameters:
    ///   - stopId1: First stop ID
    ///   - stopId2: Second stop ID
    /// - Returns: True if stops are within transfer radius
    func canTransfer(from stopId1: Int, to stopId2: Int) -> Bool {
        transferDistance(from: stopId1, to: stopId2) != nil
    }
    
    // MARK: - Private Methods
    
    /// Build transfer adjacency map for stops within matrix radius
    /// This pre-computes distances between stops to enable fast transfer detection
    private static func buildTransferAdjacencyMap(
        stops: [Stop],
        transferRadius: Double,
        matrixRadius: Double
    ) -> [Int: [Int: Double]] {
        var adjacencyMap: [Int: [Int: Double]] = [:]
        
        // Convert stops to CLLocation for efficient distance calculations
        let stopLocations = stops.reduce(into: [Int: CLLocation]()) { dict, stop in
            dict[stop.id] = CLLocation(latitude: stop.lat, longitude: stop.lon)
        }
        
        // For each stop, find nearby stops within matrix radius
        for stop in stops {
            let stopLocation = stopLocations[stop.id]!
            var nearbyStops: [Int: Double] = [:]
            
            for otherStop in stops {
                // Skip self
                guard otherStop.id != stop.id else { continue }
                
                let otherLocation = stopLocations[otherStop.id]!
                let distance = stopLocation.distance(from: otherLocation)
                
                // Only include stops within matrix radius (pre-computation radius)
                // Actual transfer check uses transferRadius
                if distance <= matrixRadius {
                    // Only add to map if within actual transfer radius
                    if distance <= transferRadius {
                        nearbyStops[otherStop.id] = distance
                    }
                }
            }
            
            if !nearbyStops.isEmpty {
                adjacencyMap[stop.id] = nearbyStops
            }
        }
        
        return adjacencyMap
    }
}

// MARK: - Convenience Extensions

extension StopIndex {
    /// Get stop by ID
    func stop(id: Int) -> Stop? {
        stops.first { $0.id == id }
    }
    
    /// Get all stops
    var allStops: [Stop] {
        stops
    }
    
    /// Number of stops in index
    var count: Int {
        stops.count
    }
}

