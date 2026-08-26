import Foundation

struct StopTimesPreparedData: Sendable {
    let routeToStops: [String: Set<Int>]
    let routeIdsByStop: [Int: Set<String>]
    let scheduledTimesByStop: [Int: [ScheduledStopTime]]
}

struct ScheduledStopTime: Sendable {
    let tripId: String
    let arrivalTime: String
}

/// Service for processing stop times and calculating upcoming arrivals
@MainActor
final class StopTimesService {
    private static let transitCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

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
    private var scheduledTimesByStop: [Int: [ScheduledStopTime]] = [:]

    private var serviceCalendarsById: [String: GTFSServiceCalendar] = [:]
    private var serviceExceptionsByDate: [String: [String: Int]] = [:]

    /// Memoized, sorted `getRoutesForStop` results. `routeIdsByStop`/`routeLookup`
    /// never change after `initialize()`, so once a stop's route list is sorted
    /// it's valid for the rest of the session. Without this, `MapViewModel.
    /// rebuildMapSnapshot()` re-sorts every stop's routes on every realtime
    /// refresh (~every 15s), which is cheap in a Release build but can run into
    /// seconds in an unoptimized Debug build across hundreds of stops — enough
    /// to visibly stall an in-flight tap-to-sheet interaction on the main actor.
    private var routesForStopCache: [Int: [Route]] = [:]

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
        serviceCalendar: GTFSServiceCalendarData,
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
        scheduledTimesByStop = preparedData.scheduledTimesByStop
        serviceCalendarsById = Dictionary(
            uniqueKeysWithValues: serviceCalendar.calendars.map { ($0.service_id, $0) }
        )
        serviceExceptionsByDate = Dictionary(
            grouping: serviceCalendar.exceptions,
            by: \.date
        ).mapValues { exceptions in
            Dictionary(uniqueKeysWithValues: exceptions.map { ($0.service_id, $0.exception_type) })
        }
        routesForStopCache.removeAll()
    }
    
    /// Prepare the large reverse indexes away from the main actor.
    nonisolated static func prepare(
        stopTimesData: StopTimesData,
        trips: [Trip]
    ) -> StopTimesPreparedData {
        let tripRouteLookup = Dictionary(uniqueKeysWithValues: trips.map { ($0.trip_id, $0.route_id) })
        var routeToStops: [String: Set<Int>] = [:]
        var routeIdsByStop: [Int: Set<String>] = [:]
        var scheduledTimesByStop: [Int: [ScheduledStopTime]] = [:]

        for (tripId, stopTimes) in stopTimesData {
            guard let routeId = tripRouteLookup[tripId] else { continue }
            for stopTime in stopTimes {
                routeToStops[routeId, default: []].insert(stopTime.s)
                routeIdsByStop[stopTime.s, default: []].insert(routeId)
                scheduledTimesByStop[stopTime.s, default: []].append(
                    ScheduledStopTime(tripId: tripId, arrivalTime: stopTime.a)
                )
            }
        }

        return StopTimesPreparedData(
            routeToStops: routeToStops,
            routeIdsByStop: routeIdsByStop,
            scheduledTimesByStop: scheduledTimesByStop
        )
    }
    
    /// Get upcoming arrivals for a specific stop with real-time ETAs
    /// Returns up to maxArrivals sorted by arrival time
    func getUpcomingArrivals(
        for stopId: Int,
        maxArrivals: Int = 5,
        tripUpdates: [String: TripUpdate]? = nil,
        now: Date = Date()
    ) async -> [Arrival] {
        let usesLiveClock = abs(now.timeIntervalSinceNow) < 1
        // Check cache first
        if usesLiveClock,
           let cached = arrivalsCache[stopId],
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return Array(cached.arrivals.prefix(maxArrivals))
        }
        
        let finalTripUpdates = tripUpdates ?? latestTripUpdates ?? [:]
        var arrivalsByInstance = scheduledArrivals(for: stopId, now: now)
        let allowedServiceDates = currentServiceDateKeys(at: now)

        // Realtime augments the schedule: it replaces a scheduled prediction,
        // removes canceled/skipped service, or adds an active trip that is not
        // part of today's regular schedule.
        for (tripId, tripUpdate) in finalTripUpdates {
            if tripUpdate.isCanceled {
                if let key = matchingInstanceKey(
                    tripId: tripId,
                    serviceDate: tripUpdate.serviceDate,
                    realtimeArrival: nil,
                    arrivals: arrivalsByInstance
                ) {
                    arrivalsByInstance.removeValue(forKey: key)
                }
                continue
            }

            guard let stopUpdate = tripUpdate.stopTimeUpdates.first(where: { $0.stopId == stopId }) else {
                continue
            }
            if stopUpdate.isSkipped {
                if let key = matchingInstanceKey(
                    tripId: tripId,
                    serviceDate: tripUpdate.serviceDate,
                    realtimeArrival: stopUpdate.arrivalTime,
                    arrivals: arrivalsByInstance
                ) {
                    arrivalsByInstance.removeValue(forKey: key)
                }
                continue
            }
            guard let realtimeArrival = stopUpdate.arrivalTime,
                  realtimeArrival.timeIntervalSince(now) >= -300,
                  let trip = tripLookup[tripId],
                  let route = routeLookup[trip.route_id],
                  let scheduledEntry = stopTimesData[tripId]?.first(where: { $0.s == stopId }) else {
                continue
            }

            let matchedKey = matchingInstanceKey(
                tripId: tripId,
                serviceDate: tripUpdate.serviceDate,
                realtimeArrival: realtimeArrival,
                arrivals: arrivalsByInstance
            )
            guard matchedKey != nil || realtimeBelongsToCurrentServiceDay(
                tripUpdate,
                arrival: realtimeArrival,
                allowedServiceDates: allowedServiceDates,
                now: now
            ) else { continue }

            let instanceKey = matchedKey
                ?? "\(tripId)-\(tripUpdate.serviceDate ?? Self.dateKey(for: realtimeArrival))"
            let scheduledArrival = arrivalsByInstance[instanceKey]?.scheduledArrivalTime
                ?? scheduledDate(
                    for: scheduledEntry.a,
                    serviceDateKey: tripUpdate.serviceDate,
                    fallback: realtimeArrival
                )
            arrivalsByInstance[instanceKey] = Arrival(
                id: "\(instanceKey)-\(stopId)",
                stopId: stopId,
                tripId: tripId,
                routeId: route.route_id,
                routeShortName: route.route_short_name,
                routeColor: route.route_color,
                tripHeadsign: trip.trip_headsign,
                arrivalTime: realtimeArrival,
                scheduledArrivalTime: scheduledArrival,
                scheduledTime: scheduledEntry.a,
                serviceDateKey: tripUpdate.serviceDate ?? Self.dateKey(for: scheduledArrival),
                isRealtime: true,
                vehicleId: tripUpdate.vehicleId
            )
        }

        let arrivals = arrivalsByInstance.values
            .filter { $0.arrivalTime.timeIntervalSince(now) >= -300 }
            .sorted { $0.arrivalTime < $1.arrivalTime }
        if usesLiveClock {
            arrivalsCache[stopId] = (arrivals, Date())
        }
        return Array(arrivals.prefix(maxArrivals))
    }

    private func matchingInstanceKey(
        tripId: String,
        serviceDate: String?,
        realtimeArrival: Date?,
        arrivals: [String: Arrival]
    ) -> String? {
        if let serviceDate {
            let exactKey = "\(tripId)-\(serviceDate)"
            if arrivals[exactKey] != nil { return exactKey }
        }
        let candidates = arrivals.filter { $0.value.tripId == tripId }
        guard !candidates.isEmpty else { return nil }
        if let realtimeArrival {
            return candidates.min {
                abs($0.value.arrivalTime.timeIntervalSince(realtimeArrival))
                    < abs($1.value.arrivalTime.timeIntervalSince(realtimeArrival))
            }?.key
        }
        return candidates.min { $0.value.arrivalTime < $1.value.arrivalTime }?.key
    }

    private func scheduledArrivals(for stopId: Int, now: Date) -> [String: Arrival] {
        guard let candidates = scheduledTimesByStop[stopId], !candidates.isEmpty else { return [:] }

        var result: [String: Arrival] = [:]
        let calendar = Self.transitCalendar
        let today = calendar.startOfDay(for: now)
        // A service day can legally extend after midnight with GTFS times above
        // 24:00. Include only that spillover from yesterday plus today's full
        // service; never mix tomorrow's regular schedule into this list.
        for dayOffset in -1...0 {
            guard let serviceDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let activeServices = activeServiceIds(on: serviceDate)
            guard !activeServices.isEmpty else { continue }
            let serviceDateKey = Self.dateKey(for: serviceDate)

            for candidate in candidates {
                if dayOffset == -1, !Self.isAfterMidnightGTFSTime(candidate.arrivalTime) {
                    continue
                }
                guard let trip = tripLookup[candidate.tripId],
                      activeServices.contains(trip.service_id),
                      let route = routeLookup[trip.route_id],
                      let arrivalDate = Self.parseGTFSTime(candidate.arrivalTime, serviceDate: serviceDate),
                      arrivalDate.timeIntervalSince(now) >= -300 else {
                    continue
                }

                let instanceKey = "\(candidate.tripId)-\(serviceDateKey)"
                if let existing = result[instanceKey], arrivalDate >= existing.arrivalTime {
                    continue
                } else {
                    result[instanceKey] = Arrival(
                        id: "\(instanceKey)-\(stopId)",
                        stopId: stopId,
                        tripId: candidate.tripId,
                        routeId: route.route_id,
                        routeShortName: route.route_short_name,
                        routeColor: route.route_color,
                        tripHeadsign: trip.trip_headsign,
                        arrivalTime: arrivalDate,
                        scheduledArrivalTime: arrivalDate,
                        scheduledTime: candidate.arrivalTime,
                        serviceDateKey: serviceDateKey,
                        isRealtime: false,
                        vehicleId: nil
                    )
                }
            }
        }
        return result
    }

    /// The complete published schedule at a stop for today's GTFS service day.
    /// Calendar exceptions are already applied, so holidays automatically use
    /// the correct service without hard-coded weekday/weekend assumptions.
    func getTodaySchedule(for stopId: Int, now: Date = Date()) -> [StopScheduleRoute] {
        guard let candidates = scheduledTimesByStop[stopId], !candidates.isEmpty else { return [] }
        let serviceDate = Self.transitCalendar.startOfDay(for: now)
        let serviceDateKey = Self.dateKey(for: serviceDate)
        let activeServices = activeServiceIds(on: serviceDate)
        var grouped: [String: [String: [StopScheduleTime]]] = [:]

        for candidate in candidates {
            guard let trip = tripLookup[candidate.tripId],
                  activeServices.contains(trip.service_id),
                  let route = routeLookup[trip.route_id],
                  let date = Self.parseGTFSTime(candidate.arrivalTime, serviceDate: serviceDate) else {
                continue
            }
            let destination = trip.trip_headsign.isEmpty ? route.route_long_name : trip.trip_headsign
            grouped[route.route_id, default: [:]][destination, default: []].append(
                StopScheduleTime(
                    id: "\(candidate.tripId)-\(serviceDateKey)-\(stopId)",
                    tripId: candidate.tripId,
                    date: date,
                    rawTime: candidate.arrivalTime,
                    isNextCalendarDay: Self.isAfterMidnightGTFSTime(candidate.arrivalTime)
                )
            )
        }

        return grouped.compactMap { routeId, destinations in
            guard let route = routeLookup[routeId] else { return nil }
            return StopScheduleRoute(
                id: routeId,
                shortName: route.route_short_name,
                longName: route.route_long_name,
                colorHex: route.route_color,
                destinations: destinations.map { name, times in
                    StopScheduleDestination(
                        id: "\(routeId)-\(name)",
                        name: name,
                        times: times.sorted { $0.date < $1.date }
                    )
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }.sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }
    }

    private func activeServiceIds(on serviceDate: Date) -> Set<String> {
        let dateKey = Self.dateKey(for: serviceDate)
        let exceptions = serviceExceptionsByDate[dateKey] ?? [:]
        var active = Set<String>()

        for (serviceId, calendarEntry) in serviceCalendarsById {
            guard calendarEntry.start_date <= dateKey, dateKey <= calendarEntry.end_date else { continue }
            if isRegularlyActive(calendarEntry, on: serviceDate) {
                active.insert(serviceId)
            }
        }
        for (serviceId, exceptionType) in exceptions {
            if exceptionType == 1 {
                active.insert(serviceId)
            } else if exceptionType == 2 {
                active.remove(serviceId)
            }
        }
        return active
    }

    private func isRegularlyActive(_ service: GTFSServiceCalendar, on date: Date) -> Bool {
        switch Self.transitCalendar.component(.weekday, from: date) {
        case 1: service.sunday
        case 2: service.monday
        case 3: service.tuesday
        case 4: service.wednesday
        case 5: service.thursday
        case 6: service.friday
        case 7: service.saturday
        default: false
        }
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
    /// Optimized to use tripLookup dictionary instead of filtering all trips,
    /// and memoized since the underlying route/stop mapping is fixed after init.
    func getRoutesForStop(_ stopId: Int) -> [Route] {
        if let cached = routesForStopCache[stopId] {
            return cached
        }
        let result = routeIdsByStop[stopId, default: []]
            .compactMap { routeLookup[$0] }
            .sorted { $0.route_short_name < $1.route_short_name }
        routesForStopCache[stopId] = result
        return result
    }
    
    /// Get stop sequence for a trip (stopId and arrivalTime pairs).
    func getStopSequence(for tripId: String) -> [(stopId: Int, arrivalTime: String)] {
        guard let stopTimes = stopTimesData[tripId] else {
            return []
        }
        
        return stopTimes.map { (stopId: $0.s, arrivalTime: $0.a) }
    }

    func getTripStopSchedule(
        for tripId: String,
        serviceDateKey: String? = nil,
        now: Date = Date()
    ) -> [TripStopSchedule] {
        guard let entries = stopTimesData[tripId], let trip = tripLookup[tripId] else { return [] }
        let serviceDate = serviceDateKey.flatMap(Self.parseServiceDate)
            ?? preferredServiceDate(for: trip, entries: entries, now: now)
        return entries.enumerated().compactMap { index, entry in
            guard let date = Self.parseGTFSTime(entry.a, serviceDate: serviceDate) else { return nil }
            return TripStopSchedule(
                stopId: entry.s,
                sequence: entry.q ?? index + 1,
                rawArrivalTime: entry.a,
                scheduledArrival: date
            )
        }
    }
    
    private static func dateKey(for date: Date) -> String {
        let components = transitCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d%02d%02d", year, month, day)
    }

    private func currentServiceDateKeys(at now: Date) -> Set<String> {
        let today = Self.transitCalendar.startOfDay(for: now)
        let yesterday = Self.transitCalendar.date(byAdding: .day, value: -1, to: today) ?? today
        return [Self.dateKey(for: today), Self.dateKey(for: yesterday)]
    }

    private func realtimeBelongsToCurrentServiceDay(
        _ update: TripUpdate,
        arrival: Date,
        allowedServiceDates: Set<String>,
        now: Date
    ) -> Bool {
        if let serviceDate = update.serviceDate {
            return allowedServiceDates.contains(serviceDate)
        }
        let today = Self.transitCalendar.startOfDay(for: now)
        let endOfTodayService = Self.transitCalendar.date(byAdding: .hour, value: 30, to: today)
            ?? today.addingTimeInterval(108_000)
        return arrival < endOfTodayService
    }

    private func scheduledDate(for rawTime: String, serviceDateKey: String?, fallback: Date) -> Date {
        if let serviceDateKey,
           let serviceDate = Self.parseServiceDate(serviceDateKey),
           let parsed = Self.parseGTFSTime(rawTime, serviceDate: serviceDate) {
            return parsed
        }
        let serviceDate = Self.transitCalendar.startOfDay(for: fallback)
        return Self.parseGTFSTime(rawTime, serviceDate: serviceDate) ?? fallback
    }

    private func preferredServiceDate(for trip: Trip, entries: [StopTimeEntry], now: Date) -> Date {
        let today = Self.transitCalendar.startOfDay(for: now)
        let yesterday = Self.transitCalendar.date(byAdding: .day, value: -1, to: today) ?? today
        if entries.contains(where: { Self.isAfterMidnightGTFSTime($0.a) }),
           activeServiceIds(on: yesterday).contains(trip.service_id),
           Self.transitCalendar.component(.hour, from: now) < 6 {
            return yesterday
        }
        return today
    }

    private static func parseServiceDate(_ key: String) -> Date? {
        guard key.count == 8,
              let year = Int(key.prefix(4)),
              let month = Int(key.dropFirst(4).prefix(2)),
              let day = Int(key.suffix(2)) else { return nil }
        return transitCalendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func isAfterMidnightGTFSTime(_ value: String) -> Bool {
        guard let hour = Int(value.split(separator: ":").first ?? "") else { return false }
        return hour >= 24
    }

    /// Parse GTFS time relative to its service date, including hours above 24.
    private static func parseGTFSTime(_ timeString: String, serviceDate: Date) -> Date? {
        let components = timeString.split(separator: ":")
        guard components.count == 3,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]) else {
            return nil
        }

        var dateComponents = transitCalendar.dateComponents([.year, .month, .day], from: serviceDate)
        dateComponents.hour = hours % 24
        dateComponents.minute = minutes
        dateComponents.second = seconds
        guard let base = transitCalendar.date(from: dateComponents) else { return nil }
        return transitCalendar.date(byAdding: .day, value: hours / 24, to: base)
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
