import Foundation
import CoreLocation

/// Routing engine for finding multimodal trip itineraries using OpenTripPlanner API
final class TripRoutingEngine {
    // MARK: - Dependencies
    
    private let walkingRouteService: WalkingRouteService
    private let dataSyncService: DataSyncService
    
    // MARK: - Initialization
    
    init(
        walkingRouteService: WalkingRouteService,
        dataSyncService: DataSyncService
    ) {
        self.walkingRouteService = walkingRouteService
        self.dataSyncService = dataSyncService
    }
    
    // MARK: - Route Finding
    
    /// Find routes from origin to destination using OpenTripPlanner API
    /// - Parameters:
    ///   - from: Origin location
    ///   - to: Destination location
    ///   - departureTime: Optional departure time (nil = now)
    /// - Returns: Array of itineraries sorted by arrival time (earliest first), then by transfer count, then by total time
    func findRoutes(from: PlannedLocation, to: PlannedLocation, departureTime: Date? = nil) async -> [Itinerary] {
        let now = departureTime ?? Date()
        
        // Try OTP API first
        do {
            let otpService = OTPService.shared
            var itineraries = try await otpService.planTrip(
                origin: from.coordinate,
                destination: to.coordinate,
                departureTime: now
            )
            
            if !itineraries.isEmpty {
                // Sort by arrival time (earliest first), then by transfer count, then by total time
                itineraries.sort {
                    if $0.arrivalTime != $1.arrivalTime {
                        return $0.arrivalTime < $1.arrivalTime
                    }
                    if $0.transferCount != $1.transferCount {
                        return $0.transferCount < $1.transferCount
                    }
                    return $0.totalTime < $1.totalTime
                }
                return itineraries
            }
        } catch {
            print("⚠️ OTP request failed: \(error.localizedDescription)")
            // Fall through to walk-only fallback
        }
        
        // Fallback: Walk-only route if within reasonable distance
        return await findWalkOnlyRoute(from: from, to: to, departureTime: now)
    }
    
    // MARK: - Walk-Only Fallback
    
    /// Find walk-only route when no bus routes are available
    /// Only returns a route if distance is reasonable (< maxWalkingDistanceM)
    private func findWalkOnlyRoute(from: PlannedLocation, to: PlannedLocation, departureTime: Date) async -> [Itinerary] {
        // Calculate direct walking route
        guard let walkRoute = try? await walkingRouteService.calculateWalkingRoute(
            from: from.coordinate,
            to: to.coordinate
        ) else {
            return []
        }
        
        // Only suggest walk-only if distance is reasonable
        guard walkRoute.distance <= TripPlannerConfig.maxWalkingDistanceM else {
            return []
        }
        
        let segments: [TripSegment] = [
            .walk(
                id: UUID(),
                distance: walkRoute.distance,
                duration: walkRoute.duration,
                from: from.coordinate,
                to: to.coordinate
            )
        ]
        
        let arrivalTime = departureTime.addingTimeInterval(walkRoute.duration)
        
        let itinerary = Itinerary(
            segments: segments,
            totalTime: walkRoute.duration,
            totalDistance: walkRoute.distance,
            transferCount: 0,
            departureTime: departureTime,
            arrivalTime: arrivalTime
        )
        
        return [itinerary]
    }
    
}