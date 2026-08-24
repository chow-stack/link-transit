import Foundation

struct StopTimesPreparedData: Sendable {
    let routeToStops: [String: Set<Int>]
    let routeIdsByStop: [Int: Set<String>]
}

/// Service for processing stop times and calculating upcoming arrivals
@MainActor
final class StopTimesService {
    // Stop times data: tripId -> [StopTimeEntry]
    private var stopTimesData: StopTimesData = [:]
    
    // Reference to routes and trips for enrichment
    private var routes: [Route] = []
    private var trips: [Trip] = []
    
    // Lookup dictionaries for performance
    private var routeLookup: [String: Route] = [:]
    private var tripLookup: [String: Trip] = [:]
    
    // Route to stops lookup: routeId -> Set<Int> (stop IDs)
    // Built during initialization for O(1) access in getStopsForRoutes
    private var routeToStops: [String: Set<Int>] = [:]

    /// Direct stop-to-route lookup used by map rendering and stop sheets.
    private var routeIdsByStop: [Int: Set<String>] = [:]
    
    // Real-time ETA service
    private let realtimeETAService = RealtimeETAService.shared
    
    // Cache for recent arrivals to avoid redundant fetching
    private var arrivalsCache: [Int: (arrivals: [Arrival], timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 10.0 // Cache arrivals for 10 seconds
    private var latestTripUpdates: [String: TripUpdate]?
    private var latestTripUpdateGeneration: Date?
    
    init() {}
    
    /// Initialize with stop times data and route/trip information
    func initialize(
        stopTimesData: StopTimesData,
        routes: [Route],
        trips: [Trip],
        preparedData: StopTimesPreparedData
    ) {
        self.stopTimesData = stopTimesData
        self.routes = routes
        self.trips = trips
        
        // Build lookup dictionaries
        self.routeLookup = Dictionary(uniqueKeysWithValues: routes.map { ($0.route_id, $0) })
        self.tripLookup = Dictionary(uniqueKeysWithValues: trips.map { ($0.trip_id, $0) })
        
        routeToStops = preparedData.routeToStops
        routeIdsByStop = preparedData.routeIdsByStop
        
        print("✅ StopTimesService initialized with \(stopTimesData.count) trips")
    }
    
    /// Prepare the large reverse indexes away from the main actor.
    nonisolated static func prepare(
        stopTimesData: StopTimesData,
        trips: [Trip]
    ) -> StopTimesPreparedData {
        let tripRouteLookup = Dictionary(uniqueKeysWithValues: trips.map { ($0.trip_id, $0.route_id) })
        var routeToStops: [String: Set<Int>] = [:]
        var routeIdsByStop: [Int: Set<String>] = [:]

        for (tripId, stopTimes) in stopTimesData {
            guard let routeId = tripRouteLookup[tripId] else { continue }
            for stopTime in stopTimes {
                routeToStops[routeId, default: []].insert(stopTime.s)
                routeIdsByStop[stopTime.s, default: []].insert(routeId)
            }
        }

        return StopTimesPreparedData(
            routeToStops: routeToStops,
            routeIdsByStop: routeIdsByStop
        )
    }
    
    /// Get upcoming arrivals for a specific stop with real-time ETAs
    /// Returns up to maxArrivals sorted by arrival time
    func getUpcomingArrivals(for stopId: Int, maxArrivals: Int = 5, tripUpdates: [String: TripUpdate]? = nil) async -> [Arrival] {
        // Check cache first
        if let cached = arrivalsCache[stopId],
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return Array(cached.arrivals.prefix(maxArrivals))
        }
        
        // Use pre-fetched trip updates if provided, then the last published
        // generation, and finally the shared coalesced network request.
        let finalTripUpdates: [String: TripUpdate]
        if let tripUpdates = tripUpdates {
            finalTripUpdates = tripUpdates
        } else if let latestTripUpdates {
            finalTripUpdates = latestTripUpdates
        } else {
            finalTripUpdates = (try? await realtimeETAService.fetchTripUpdates()) ?? [:]
            updateTripUpdates(finalTripUpdates)
        }

        // An unavailable initial feed must not poison the arrival cache with a
        // ten-second empty result while the background refresh is still running.
        guard !finalTripUpdates.isEmpty else { return [] }

        var arrivals: [Arrival] = []

        // Iterate only active realtime trips. The previous implementation walked
        // every scheduled trip serving the stop and discarded nearly all of them.
        for (tripId, tripUpdate) in finalTripUpdates {
            guard let stopUpdate = tripUpdate.stopTimeUpdates.first(where: { $0.stopId == stopId }),
                  let realtimeArrival = stopUpdate.arrivalTime,
                  realtimeArrival.timeIntervalSinceNow >= -300,
                  let scheduledEntry = stopTimesData[tripId]?.first(where: { $0.s == stopId }) else {
                continue
            }

            guard let trip = tripLookup[tripId],
                  let route = routeLookup[trip.route_id] else {
                continue
            }

            // Create arrival object with vehicle information
            let arrival = Arrival(
                id: "\(tripId)-\(stopId)",
                stopId: stopId,
                tripId: tripId,
                routeId: route.route_id,
                routeShortName: route.route_short_name,
                routeColor: route.route_color,
                arrivalTime: realtimeArrival,
                scheduledTime: scheduledEntry.a,
                isRealtime: true,
                vehicleId: tripId, // Use tripId as vehicle identifier for now
                busNumber: trip.block_id // Use real block_id from GTFS data
            )
            
            arrivals.append(arrival)
        }
        
        // Remove duplicates by grouping by route and bus number
        let deduplicatedArrivals = removeDuplicates(arrivals)
        
        // Cache the results
        arrivalsCache[stopId] = (deduplicatedArrivals, Date())
        
        return Array(deduplicatedArrivals.prefix(maxArrivals))
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
        routeIdsByStop[stopId, default: []]
            .compactMap { routeLookup[$0] }
            .sorted { $0.route_short_name < $1.route_short_name }
    }
    
    /// Get stop sequence for a trip (stopId and arrivalTime pairs)
    func getStopSequence(for tripId: String) -> [(stopId: Int, arrivalTime: String)] {
        guard let stopTimes = stopTimesData[tripId] else {
            return []
        }
        
        return stopTimes.map { (stopId: $0.s, arrivalTime: $0.a) }
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

    /// Publish a new realtime generation and invalidate derived stop results only
    /// when the feed itself changed, not on every polling tick.
    func updateTripUpdates(_ updates: [String: TripUpdate]) {
        guard !updates.isEmpty else { return }
        let generation = updates.values.map(\.timestamp).max()
        guard generation != latestTripUpdateGeneration else { return }
        latestTripUpdates = updates
        latestTripUpdateGeneration = generation
        clearArrivalsCache()
    }

}
