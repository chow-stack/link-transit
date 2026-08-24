import Foundation
import CoreLocation

/// View model for managing bus information and stop sequence
@MainActor
struct BusInfoViewModel {
    private let stopTimesService: StopTimesService
    private let realtimeETAService = RealtimeETAService.shared
    private let tripLookup: [String: Trip]
    private let stopLookup: [Int: Stop]
    private let firstTripByRouteId: [String: Trip]
    
    // Cached trip updates for performance
    private let tripUpdates: [String: TripUpdate]?
    
    init(
        stopTimesService: StopTimesService,
        tripLookup: [String: Trip],
        stopLookup: [Int: Stop],
        firstTripByRouteId: [String: Trip],
        tripUpdates: [String: TripUpdate]? = nil
    ) {
        self.stopTimesService = stopTimesService
        self.tripLookup = tripLookup
        self.stopLookup = stopLookup
        self.firstTripByRouteId = firstTripByRouteId
        self.tripUpdates = tripUpdates
    }
    
    /// Get bus info including current stop and upcoming stops
    func getBusInfo(for bus: EnrichedVehicle) async -> BusInfo? {
        // Get trip ID from vehicle
        guard let tripId = getTripId(for: bus) else {
            print("⚠️ BusInfoViewModel: No trip ID found for bus \(bus.vehicle.id), routeId: \(bus.vehicle.routeId), tripId: \(bus.vehicle.tripId)")
            return createUnknownBusInfo(for: bus)
        }
        
        // Get trip details
        guard let trip = tripLookup[tripId] else {
            print("⚠️ BusInfoViewModel: Trip \(tripId) not found in lookup for bus \(bus.vehicle.id)")
            return createUnknownBusInfo(for: bus)
        }
        
        print("✅ BusInfoViewModel: Found trip \(tripId) for bus \(bus.vehicle.id) on route \(trip.route_id)")
        
        // Get stop sequence for this trip
        let stopSequence = stopTimesService.getStopSequence(for: tripId)
        
        guard !stopSequence.isEmpty else {
            print("⚠️ BusInfoViewModel: No stop sequence found for trip \(tripId)")
            return createUnknownBusInfo(for: bus)
        }
        
        print("✅ BusInfoViewModel: Found \(stopSequence.count) stops in sequence for trip \(tripId)")
        
        // Find current/next stop based on bus position
        let (currentStopIndex, atStop) = findCurrentStop(
            busCoordinate: bus.coordinate,
            stopSequence: stopSequence
        )
        
        guard currentStopIndex < stopSequence.count else {
            return createUnknownBusInfo(for: bus)
        }
        
        let currentStopEntry = stopSequence[currentStopIndex]
        
        guard let currentStop = stopLookup[currentStopEntry.stopId] else {
            return createUnknownBusInfo(for: bus)
        }
        
        // Use cached trip updates if available
        let tripUpdates = self.tripUpdates
        
        // Calculate ETA to current/next stop
        let currentStopETA = atStop ? nil : await calculateETA(
            to: currentStop,
            from: bus,
            arrivalTime: currentStopEntry.arrivalTime,
            tripId: tripId,
            tripUpdates: tripUpdates
        )
        
        // Get upcoming stops (next 2-3 stops)
        var upcomingStops: [BusInfo.StopInfo] = []
        let upcomingRange = min(currentStopIndex + 1, stopSequence.count)..<min(currentStopIndex + 4, stopSequence.count)
        
        for index in upcomingRange {
            let stopEntry = stopSequence[index]
            guard let stop = stopLookup[stopEntry.stopId] else { continue }
            
            let eta = await calculateETA(
                to: stop,
                from: bus,
                arrivalTime: stopEntry.arrivalTime,
                tripId: tripId,
                tripUpdates: tripUpdates
            )
            
            upcomingStops.append(BusInfo.StopInfo(name: stop.name, eta: eta))
        }
        
        // Calculate delay status
        let delayStatus = calculateDelayStatus(
            tripId: tripId,
            stopId: currentStop.id,
            scheduledTime: currentStopEntry.arrivalTime,
            tripUpdates: tripUpdates
        )
        
        // Get bus number from trip block_id or vehicle ID
        let busNumber = trip.block_id ?? bus.vehicle.id
        
        return BusInfo(
            busNumber: busNumber,
            currentStopName: currentStop.name,
            currentStopETA: currentStopETA,
            atStop: atStop,
            delayStatus: delayStatus,
            upcomingStops: upcomingStops
        )
    }
    
    // MARK: - Helper Methods
    
    /// Get trip ID from vehicle
    private func getTripId(for bus: EnrichedVehicle) -> String? {
        // Use the tripId field directly from the vehicle
        if !bus.vehicle.tripId.isEmpty {
            return bus.vehicle.tripId
        }
        
        // Fallback: if no tripId, try to find a trip for this route
        if !bus.vehicle.routeId.isEmpty {
            if let trip = firstTripByRouteId[bus.vehicle.routeId] {
                return trip.trip_id
            }
        }
        
        return nil
    }
    
    /// Find current/next stop based on bus position
    private func findCurrentStop(
        busCoordinate: CLLocationCoordinate2D,
        stopSequence: [(stopId: Int, arrivalTime: String)]
    ) -> (index: Int, atStop: Bool) {
        let busLocation = CLLocation(latitude: busCoordinate.latitude, longitude: busCoordinate.longitude)
        
        var closestStopIndex = 0
        var minimumDistance = Double.infinity
        
        // Find closest stop to bus
        for (index, stopEntry) in stopSequence.enumerated() {
            guard let stop = stopLookup[stopEntry.stopId] else { continue }
            
            let stopLocation = CLLocation(latitude: stop.lat, longitude: stop.lon)
            let distance = busLocation.distance(from: stopLocation)
            
            if distance < minimumDistance {
                minimumDistance = distance
                closestStopIndex = index
            }
        }
        
        // Consider "at stop" if within 30 meters (reduced from 50m for better accuracy)
        let atStop = minimumDistance < 30.0
        
        // If not at stop, determine if we should advance to next stop
        if !atStop && closestStopIndex < stopSequence.count - 1 {
            // Check if bus has passed this stop by looking at the direction
            // We'll use a simple heuristic: if the bus is closer to the next stop than current,
            // and the next stop is further along the route, advance to next stop
            
            let currentStop = stopLookup[stopSequence[closestStopIndex].stopId]!
            let nextStop = stopLookup[stopSequence[closestStopIndex + 1].stopId]!
            
            let currentStopLocation = CLLocation(latitude: currentStop.lat, longitude: currentStop.lon)
            let nextStopLocation = CLLocation(latitude: nextStop.lat, longitude: nextStop.lon)
            
            let distanceToCurrent = busLocation.distance(from: currentStopLocation)
            let distanceToNext = busLocation.distance(from: nextStopLocation)
            
            // If bus is significantly closer to next stop, advance
            if distanceToNext < distanceToCurrent - 20.0 { // 20m threshold
                return (closestStopIndex + 1, false)
            }
        }
        
        return (closestStopIndex, atStop)
    }
    
    /// Calculate ETA to a stop
    private func calculateETA(
        to stop: Stop,
        from bus: EnrichedVehicle,
        arrivalTime: String,
        tripId: String,
        tripUpdates: [String: TripUpdate]?
    ) async -> String? {
        // Try to get real-time ETA first
        if tripUpdates?[tripId] != nil,
           let realtimeETA = await realtimeETAService.getRealtimeETA(
               tripId: tripId,
               stopId: stop.id,
               tripUpdates: tripUpdates ?? [:]
           ) {
            print("✅ BusInfoViewModel: Using real-time ETA for stop \(stop.id)")
            return formatETA(to: realtimeETA)
        }
        
        // Fallback: estimate based on distance and speed
        if let speed = bus.vehicle.speed, speed > 0 {
            let busLocation = CLLocation(
                latitude: bus.vehicle.latitude,
                longitude: bus.vehicle.longitude
            )
            let stopLocation = CLLocation(latitude: stop.lat, longitude: stop.lon)
            let distance = busLocation.distance(from: stopLocation) // meters
            
            // Convert speed from m/s to km/h for more accurate estimation
            let speedKmh = speed * 3.6
            let timeInHours = (distance / 1000.0) / speedKmh
            let timeInMinutes = Int(timeInHours * 60)
            
            // Add buffer for stops (30 seconds per intermediate stop estimate)
            let adjustedMinutes = timeInMinutes + 1
            
            print("✅ BusInfoViewModel: Using speed-based ETA for stop \(stop.id): \(max(1, adjustedMinutes)) min")
            return "\(max(1, adjustedMinutes)) min"
        }
        
        // Fallback: use scheduled time if available
        if let scheduledETA = parseScheduledETA(arrivalTime) {
            print("✅ BusInfoViewModel: Using scheduled ETA for stop \(stop.id): \(scheduledETA)")
            return scheduledETA
        }
        
        print("⚠️ BusInfoViewModel: No ETA available for stop \(stop.id)")
        return nil
    }
    
    /// Format ETA from date
    private func formatETA(to date: Date) -> String {
        let seconds = date.timeIntervalSince(Date())
        
        if seconds < 0 {
            return "Arriving"
        } else if seconds < 60 {
            return "under 1 min"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    /// Calculate delay status
    private func calculateDelayStatus(
        tripId: String,
        stopId: Int,
        scheduledTime: String,
        tripUpdates: [String: TripUpdate]?
    ) -> DelayStatus {
        // Try to get real-time delay status first
        if let tripUpdate = tripUpdates?[tripId],
           let stopUpdate = tripUpdate.stopTimeUpdates.first(where: { $0.stopId == stopId }),
           let arrivalTime = stopUpdate.arrivalTime {
            
            // Parse scheduled time and calculate delay
            let calendar = Calendar.current
            let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
            
            guard let scheduledDate = parseArrivalTime(scheduledTime, baseComponents: todayComponents) else {
                return .unknown
            }
            
            // Calculate delay in seconds
            let delaySeconds = arrivalTime.timeIntervalSince(scheduledDate)
            
            if abs(delaySeconds) < 60 {
                return .onTime
            } else if delaySeconds < 0 {
                return .early
            } else {
                let delayMinutes = Int(delaySeconds / 60)
                return .delayed(minutes: delayMinutes)
            }
        }
        
        // Fallback: assume on-time if we have scheduled data but no real-time updates
        print("⚠️ BusInfoViewModel: No real-time delay data for stop \(stopId), assuming on-time")
        return .onTime
    }
    
    /// Create unknown bus info when data is unavailable
    private func createUnknownBusInfo(for bus: EnrichedVehicle) -> BusInfo {
        return BusInfo(
            busNumber: bus.vehicle.id,
            currentStopName: "Location unavailable",
            currentStopETA: nil,
            atStop: false,
            delayStatus: .unknown,
            upcomingStops: []
        )
    }
    
    /// Parse GTFS time format (HH:mm:ss) to Date
    private func parseArrivalTime(_ timeString: String, baseComponents: DateComponents) -> Date? {
        let timeComponents = timeString.split(separator: ":")
        guard timeComponents.count == 3,
              let hours = Int(timeComponents[0]),
              let minutes = Int(timeComponents[1]),
              let seconds = Int(timeComponents[2]) else {
            return nil
        }
        
        var dateComponents = baseComponents
        dateComponents.hour = hours
        dateComponents.minute = minutes
        dateComponents.second = seconds
        
        // Handle times that exceed 24 hours (e.g., "25:00:00")
        if hours >= 24 {
            dateComponents.hour = hours - 24
            let calendar = Calendar.current
            if let baseDate = calendar.date(from: baseComponents) {
                return calendar.date(byAdding: .day, value: 1, to: calendar.date(from: dateComponents) ?? baseDate)
            }
        }
        
        return Calendar.current.date(from: dateComponents)
    }
    
    /// Parse scheduled arrival time and return formatted ETA
    private func parseScheduledETA(_ arrivalTime: String) -> String? {
        let calendar = Calendar.current
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        
        guard let scheduledDate = parseArrivalTime(arrivalTime, baseComponents: todayComponents) else {
            return nil
        }
        
        let seconds = scheduledDate.timeIntervalSince(Date())
        
        if seconds < 0 {
            return "Departed"
        } else if seconds < 60 {
            return "under 1 min"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: scheduledDate)
        }
    }
}
