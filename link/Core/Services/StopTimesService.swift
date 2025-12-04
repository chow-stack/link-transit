import Foundation

/// Service for processing stop times and calculating upcoming arrivals
@MainActor
final class StopTimesService {
    // Stop times data: tripId -> [StopTimeEntry]
    private var stopTimesData: StopTimesData = [:]
    
    // Reverse lookup: stopId -> [(tripId, arrivalTime)]
    private var stopToTrips: [Int: [(tripId: String, arrivalTime: String)]] = [:]
    
    // Reference to routes and trips for enrichment
    private var routes: [Route] = []
    private var trips: [Trip] = []
    
    // Lookup dictionaries for performance
    private var routeLookup: [String: Route] = [:]
    private var tripLookup: [String: Trip] = [:]
    
    // Route to stops lookup: routeId -> Set<Int> (stop IDs)
    // Built during initialization for O(1) access in getStopsForRoutes
    private var routeToStops: [String: Set<Int>] = [:]
    
    // Real-time ETA service
    private let realtimeETAService = RealtimeETAService.shared
    
    // Cache for recent arrivals to avoid redundant fetching
    private var arrivalsCache: [Int: (arrivals: [Arrival], timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 10.0 // Cache arrivals for 10 seconds
    
    init() {}
    
    /// Initialize with stop times data and route/trip information
    func initialize(stopTimesData: StopTimesData, routes: [Route], trips: [Trip]) {
        self.stopTimesData = stopTimesData
        self.routes = routes
        self.trips = trips
        
        // Build lookup dictionaries
        self.routeLookup = Dictionary(uniqueKeysWithValues: routes.map { ($0.route_id, $0) })
        self.tripLookup = Dictionary(uniqueKeysWithValues: trips.map { ($0.trip_id, $0) })
        
        // Build reverse lookup: stopId -> [(tripId, arrivalTime)]
        buildStopToTripsLookup()
        
        // Build route to stops lookup for O(1) access
        buildRouteToStopsLookup()
        
        // Set reference in RealtimeETAService
        Task {
            await realtimeETAService.setStopTimesService(self)
        }
        
        print("✅ StopTimesService initialized with \(stopTimesData.count) trips")
    }
    
    /// Build reverse lookup from stop ID to trips serving that stop
    private func buildStopToTripsLookup() {
        var lookup: [Int: [(tripId: String, arrivalTime: String)]] = [:]
        
        for (tripId, stopTimes) in stopTimesData {
            for stopTime in stopTimes {
                if lookup[stopTime.s] == nil {
                    lookup[stopTime.s] = []
                }
                lookup[stopTime.s]?.append((tripId: tripId, arrivalTime: stopTime.a))
            }
        }
        
        self.stopToTrips = lookup
    }
    
    /// Build route to stops lookup: routeId -> Set<Int> (stop IDs)
    /// This allows O(1) access in getStopsForRoutes instead of iterating through all stopTimesData
    /// Optimized: Initialize sets upfront to avoid repeated nil checks
    private func buildRouteToStopsLookup() {
        var lookup: [String: Set<Int>] = [:]
        
        // Iterate through trips to get route -> stops mapping
        for trip in trips {
            let routeId = trip.route_id
            // Initialize set if needed
            if lookup[routeId] == nil {
                lookup[routeId] = Set<Int>()
            }
            
            // Get stop times for this trip and add all stop IDs
            if let stopTimes = stopTimesData[trip.trip_id] {
                for stopTime in stopTimes {
                    lookup[routeId]?.insert(stopTime.s)
                }
            }
        }
        
        self.routeToStops = lookup
    }
    
    /// Get upcoming arrivals for a specific stop with real-time ETAs
    /// Returns up to maxArrivals sorted by arrival time
    func getUpcomingArrivals(for stopId: Int, maxArrivals: Int = 5, tripUpdates: [String: TripUpdate]? = nil) async -> [Arrival] {
        // Check cache first
        if let cached = arrivalsCache[stopId],
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return Array(cached.arrivals.prefix(maxArrivals))
        }
        
        guard let tripsAtStop = stopToTrips[stopId] else {
            return []
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Get current date components for calculating arrival times
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        
        // Use pre-fetched trip updates if provided, otherwise fetch
        let finalTripUpdates: [String: TripUpdate]?
        if let tripUpdates = tripUpdates {
            finalTripUpdates = tripUpdates
        } else {
            finalTripUpdates = try? await realtimeETAService.fetchTripUpdates()
        }
        
        var arrivals: [Arrival] = []
        
        for (tripId, arrivalTimeString) in tripsAtStop {
            // Parse scheduled arrival time (format: "HH:mm:ss")
            guard let scheduledDate = parseArrivalTime(arrivalTimeString, baseComponents: todayComponents) else {
                continue
            }
            
            // Get trip and route information
            guard let trip = tripLookup[tripId],
                  let route = routeLookup[trip.route_id] else {
                continue
            }
            
            // Try to get real-time ETA from trip updates
            var actualArrivalTime = scheduledDate
            var isRealtime = false
            
            if let finalTripUpdates = finalTripUpdates,
               let realtimeETA = await realtimeETAService.getRealtimeETA(
                tripId: tripId,
                stopId: stopId,
                tripUpdates: finalTripUpdates
               ) {
                actualArrivalTime = realtimeETA
                isRealtime = true
            }
            
            // Create arrival object with vehicle information
            let arrival = Arrival(
                id: "\(tripId)-\(stopId)",
                stopId: stopId,
                tripId: tripId,
                routeId: route.route_id,
                routeShortName: route.route_short_name,
                routeColor: route.route_color,
                arrivalTime: actualArrivalTime,
                scheduledTime: arrivalTimeString,
                isRealtime: isRealtime,
                vehicleId: tripId, // Use tripId as vehicle identifier for now
                busNumber: trip.block_id // Use real block_id from GTFS data
            )
            
            arrivals.append(arrival)
        }
        
        // Filter to show only real-time arrivals (no scheduled)
        let filteredArrivals = arrivals
            .filter { $0.isRealtime && !$0.hasDeparted } // Only real-time buses that haven't departed
            .sorted { $0.arrivalTime < $1.arrivalTime }
        
        // Remove duplicates by grouping by route and bus number
        let deduplicatedArrivals = removeDuplicates(filteredArrivals)
        
        // Cache the results
        arrivalsCache[stopId] = (deduplicatedArrivals, Date())
        
        return Array(deduplicatedArrivals.prefix(maxArrivals))
    }

    /// Routing-specific arrivals: prefer realtime, fallback to scheduled if none
    func getUpcomingArrivalsForRouting(for stopId: Int, maxArrivals: Int = 10, tripUpdates: [String: TripUpdate]? = nil) async -> [Arrival] {
        // Reuse the computation but without enforcing realtime-only when none available
        // Check cache first but do not reuse realtime-only cache; compute fresh
        guard let tripsAtStop = stopToTrips[stopId] else {
            return []
        }
        let now = Date()
        let calendar = Calendar.current
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let finalTripUpdates: [String: TripUpdate]?
        if let tripUpdates = tripUpdates {
            finalTripUpdates = tripUpdates
        } else {
            finalTripUpdates = try? await realtimeETAService.fetchTripUpdates()
        }
        var arrivals: [Arrival] = []
        for (tripId, arrivalTimeString) in tripsAtStop {
            guard let scheduledDate = parseArrivalTime(arrivalTimeString, baseComponents: todayComponents) else { continue }
            guard let trip = tripLookup[tripId], let route = routeLookup[trip.route_id] else { continue }
            var actualArrivalTime = scheduledDate
            var isRealtime = false
            if let finalTripUpdates = finalTripUpdates,
               let realtimeETA = await realtimeETAService.getRealtimeETA(tripId: tripId, stopId: stopId, tripUpdates: finalTripUpdates) {
                actualArrivalTime = realtimeETA
                isRealtime = true
            }
            let arrival = Arrival(
                id: "\(tripId)-\(stopId)",
                stopId: stopId,
                tripId: tripId,
                routeId: route.route_id,
                routeShortName: route.route_short_name,
                routeColor: route.route_color,
                arrivalTime: actualArrivalTime,
                scheduledTime: arrivalTimeString,
                isRealtime: isRealtime,
                vehicleId: tripId,
                busNumber: trip.block_id
            )
            arrivals.append(arrival)
        }
        // Prefer realtime not departed; fallback to scheduled not departed if none
        let realtimeArrivals = arrivals.filter { $0.isRealtime && !$0.hasDeparted }.sorted { $0.arrivalTime < $1.arrivalTime }
        if !realtimeArrivals.isEmpty {
            return Array(realtimeArrivals.prefix(maxArrivals))
        }
        let scheduledFallback = arrivals.filter { !$0.hasDeparted }.sorted { $0.arrivalTime < $1.arrivalTime }
        return Array(scheduledFallback.prefix(maxArrivals))
    }
    
    /// Parse arrival time string ("HH:mm:ss") into Date
    /// GTFS times can exceed 24 hours (e.g., "25:30:00" for 1:30 AM next day)
    private func parseArrivalTime(_ timeString: String, baseComponents: DateComponents) -> Date? {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        
        var hour = components[0]
        let minute = components[1]
        let second = components[2]
        
        // Handle times >= 24:00:00 (next day service)
        var dayOffset = 0
        if hour >= 24 {
            dayOffset = hour / 24
            hour = hour % 24
        }
        
        // Create date from components
        let calendar = Calendar.current
        var dateComponents = baseComponents
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = second
        
        guard var date = calendar.date(from: dateComponents) else {
            return nil
        }
        
        // Add day offset if needed
        if dayOffset > 0 {
            date = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }
        
        return date
    }
    
    /// Get all stops that serve the given routes
    /// Optimized to use pre-built routeToStops lookup instead of iterating through all stopTimesData
    func getStopsForRoutes(_ routeIds: Set<String>) -> Set<Int> {
        var stopsForRoutes = Set<Int>()
        
        // Use pre-built lookup for O(1) access per route
        for routeId in routeIds {
            if let stopsForRoute = routeToStops[routeId] {
                stopsForRoutes.formUnion(stopsForRoute)
            }
        }
        
        return stopsForRoutes
    }
    
    /// Get all routes that serve a specific stop
    /// Optimized to use tripLookup dictionary instead of filtering all trips
    func getRoutesForStop(_ stopId: Int) -> [Route] {
        // Get all trips serving this stop
        guard let tripsAtStop = stopToTrips[stopId] else {
            return []
        }
        
        // Get unique route IDs from these trips using tripLookup for O(1) access
        var uniqueRouteIds = Set<String>()
        for tripInfo in tripsAtStop {
            if let trip = tripLookup[tripInfo.tripId] {
                uniqueRouteIds.insert(trip.route_id)
            }
        }
        
        // Get route objects for these route IDs
        return uniqueRouteIds.compactMap { routeLookup[$0] }
    }
    
    /// Get all stops that have arrivals in the next hour
    func getActiveStops() async -> Set<Int> {
        let now = Date()
        let oneHourFromNow = now.addingTimeInterval(3600)
        
        var activeStops = Set<Int>()
        
        for stopId in stopToTrips.keys {
            let arrivals = await getUpcomingArrivals(for: stopId, maxArrivals: 1)
            if let firstArrival = arrivals.first,
               firstArrival.arrivalTime <= oneHourFromNow {
                activeStops.insert(stopId)
            }
        }
        
        return activeStops
    }
    
    /// Get stop times for a specific trip (ordered by sequence)
    func getStopTimesForTrip(tripId: String) async -> [StopTimeEntry] {
        return stopTimesData[tripId] ?? []
    }
    
    /// Get stop sequence for a trip (stopId and arrivalTime pairs)
    func getStopSequence(for tripId: String) -> [(stopId: Int, arrivalTime: String)] {
        guard let stopTimes = stopTimesData[tripId] else {
            return []
        }
        
        return stopTimes.map { (stopId: $0.s, arrivalTime: $0.a) }
    }
    
    /// Get scheduled arrival time for a trip and stop
    func getScheduledArrivalTime(tripId: String, stopId: Int) async -> Date? {
        guard let stopTimes = stopTimesData[tripId] else {
            return nil
        }
        
        guard let stopTime = stopTimes.first(where: { $0.s == stopId }) else {
            return nil
        }
        
        return parseGTFSTime(stopTime.a)
    }
    
    /// Parse GTFS time format (HH:mm:ss) to Date
    /// Handles times that exceed 24 hours (e.g., "25:00:00")
    private func parseGTFSTime(_ timeString: String) -> Date? {
        let components = timeString.split(separator: ":")
        guard components.count == 3,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]) else {
            return nil
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Handle times that exceed 24 hours
        var adjustedHours = hours
        var dayOffset = 0
        
        if hours >= 24 {
            adjustedHours = hours % 24
            dayOffset = hours / 24
        }
        
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        dateComponents.hour = adjustedHours
        dateComponents.minute = minutes
        dateComponents.second = seconds
        
        guard var date = calendar.date(from: dateComponents) else {
            return nil
        }
        
        // Add day offset if needed
        if dayOffset > 0 {
            date = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }
        
        return date
    }
    
    /// Remove duplicate buses by grouping by route and bus number
    private func removeDuplicates(_ arrivals: [Arrival]) -> [Arrival] {
        // Group by route and bus number to handle multiple trips for same bus
        let groupedByRouteAndBus = Dictionary(grouping: arrivals) { "\($0.routeId)-\($0.busDisplayName)" }
        
        var deduplicated: [Arrival] = []
        
        for (_, groupArrivals) in groupedByRouteAndBus {
            // Take the earliest arrival for each bus
            if let earliestArrival = groupArrivals.min(by: { $0.arrivalTime < $1.arrivalTime }) {
                deduplicated.append(earliestArrival)
            }
        }
        
        // Sort final results by arrival time
        return deduplicated.sorted { $0.arrivalTime < $1.arrivalTime }
    }
    
    /// Clear arrivals cache (useful when trip updates are refreshed)
    func clearArrivalsCache() {
        arrivalsCache.removeAll()
    }

}
