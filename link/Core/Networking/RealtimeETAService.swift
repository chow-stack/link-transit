import Foundation
import SwiftProtobuf

/// Service for fetching and processing real-time ETAs from GTFS-realtime feeds
actor RealtimeETAService {
    static let shared = RealtimeETAService()
    
    private let session: URLSession
    private var cachedTripUpdates: (data: [String: TripUpdate], timestamp: Date)?
    private var inFlightFetch: Task<[String: TripUpdate], Error>?
    private let cacheTimeout: TimeInterval = 15.0 // Cache for 15 seconds

    /// A feed download started before static stop-time data is available (e.g. at
    /// launch, in parallel with static GTFS decoding). Consumed by the next
    /// `fetchTripUpdates` call so the network round trip overlaps with static
    /// decoding instead of starting only once a stop/bus sheet is tapped.
    private var prefetchedFeed: Task<TransitRealtime_FeedMessage, Error>?

    private var stopTimesData: StopTimesData = [:]
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.requestTimeout
        config.timeoutIntervalForResource = APIConfig.resourceTimeout
        config.waitsForConnectivity = false // Don't wait - fail fast and retry instead
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        
        self.session = URLSession(configuration: config)
    }
    
    /// Copy-on-write snapshot used for sequence mapping without a main-actor hop
    /// for every realtime stop update.
    func setStopTimesData(_ data: StopTimesData) {
        stopTimesData = data
    }
    
    // MARK: - Public API

    /// Start downloading and decoding the trip-updates protobuf feed without
    /// waiting for static stop-time data. Call this as early as possible
    /// (e.g. before static GTFS decoding begins) so the network round trip
    /// overlaps with static data preparation. The result is consumed by the
    /// next `fetchTripUpdates` call once `stopTimesData` is available.
    func prefetchTripUpdates() {
        guard prefetchedFeed == nil, cachedTripUpdates == nil else { return }
        prefetchedFeed = Task { try await self.fetchFeedMessage() }
    }

    /// Fetch trip updates from GTFS-realtime feed
    /// Returns cached data on timeout/error if available, otherwise empty dictionary
    func fetchTripUpdates(forceRefresh: Bool = false) async throws -> [String: TripUpdate] {
        // Check cache first
        if !forceRefresh,
           let cached = cachedTripUpdates,
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.data
        }

        let fetchTask: Task<[String: TripUpdate], Error>
        if let inFlightFetch {
            fetchTask = inFlightFetch
        } else if !forceRefresh, let prefetchedFeed {
            // Reuse the feed download that was already started in parallel
            // with static decoding instead of issuing a brand-new request.
            self.prefetchedFeed = nil
            let newTask = Task { self.convert(try await prefetchedFeed.value) }
            inFlightFetch = newTask
            fetchTask = newTask
        } else {
            let newTask = Task { try await self.fetchAndParseTripUpdates() }
            inFlightFetch = newTask
            fetchTask = newTask
        }

        do {
            let tripUpdates = try await fetchTask.value
            inFlightFetch = nil

            // Update cache only if we got data
            if !tripUpdates.isEmpty {
                cachedTripUpdates = (tripUpdates, Date())
            } else {
                // If we got empty dict but have cached data, use cache as fallback
                if let cached = cachedTripUpdates {
                    print("⚠️ Received empty trip updates, using cached data")
                    return cached.data
                }
            }

            return tripUpdates
        } catch {
            inFlightFetch = nil
            // Check if error is cancellation (expected when tasks are cancelled)
            let isCancellation = (error as NSError).code == NSURLErrorCancelled

            // On error, return cached data if available as fallback
            if let cached = cachedTripUpdates {
                // Only log non-cancellation errors to reduce console noise
                if !isCancellation {
                    print("⚠️ Trip updates fetch failed: \(error.localizedDescription). Using cached data.")
                }
                return cached.data
            }

            throw error
        }
    }
    
    /// Get real-time ETA for a specific stop from trip updates
    /// Returns the predicted arrival time if available, nil otherwise
    func getRealtimeETA(tripId: String, stopId: Int, tripUpdates: [String: TripUpdate]) -> Date? {
        guard let tripUpdate = tripUpdates[tripId] else {
            return nil
        }
        
        // Find stop time update for this stop
        guard let stopUpdate = tripUpdate.stopTimeUpdates.first(where: { $0.stopId == stopId }) else {
            return nil
        }
        
        // Return the arrival time if available
        return stopUpdate.arrivalTime
    }
    
    // MARK: - Private Methods
    
    /// Fetch and parse trip updates from Protocol Buffer feed
    private func fetchAndParseTripUpdates() async throws -> [String: TripUpdate] {
        let feedMessage = try await fetchFeedMessage()
        return convert(feedMessage)
    }

    /// Download and decode the trip-updates protobuf feed. This has no
    /// dependency on static stop-time data, so it can run before static GTFS
    /// decoding finishes.
    /// Includes retry logic with exponential backoff and graceful timeout handling
    private func fetchFeedMessage() async throws -> TransitRealtime_FeedMessage {
        let urlString = APIConfig.tripUpdatesFeedURL

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var lastError: Error?

        // Retry up to maxRetries times
        for attempt in 0..<APIConfig.maxRetries {
            do {
                let (data, response) = try await session.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.noData
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkError.serverError(statusCode: httpResponse.statusCode)
                }

                // Parse protobuf
                let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
                return feedMessage

            } catch let error as URLError {
                lastError = error
                
                // Check if it's a timeout error
                let isTimeout = error.code == .timedOut || error.code == .networkConnectionLost
                
                // If it's the last attempt or not a timeout, throw the error
                if attempt == APIConfig.maxRetries - 1 || !isTimeout {
                    // For timeout on last attempt, return empty dict gracefully
                    if isTimeout && attempt == APIConfig.maxRetries - 1 {
                        print("⚠️ Trip updates fetch timed out after \(APIConfig.maxRetries) attempts. Using empty dictionary.")
                        throw NetworkError.timeout
                    }
                    throw NetworkError.networkError(error)
                }
                
                // Wait before retrying (exponential backoff)
                let delay = APIConfig.retryDelay * pow(2, Double(attempt))
                print("⚠️ Trip updates fetch failed (attempt \(attempt + 1)/\(APIConfig.maxRetries)): \(error.localizedDescription). Retrying in \(delay)s...")
                try? await Task.sleep(for: .seconds(delay))
                
            } catch let error as NetworkError {
                // Don't retry on non-network errors
                throw error
            } catch let error as SwiftProtobuf.BinaryDecodingError {
                // Don't retry on decoding errors
                throw NetworkError.decodingError(error)
            } catch {
                lastError = error
                // If it's the last attempt, throw the error
                if attempt == APIConfig.maxRetries - 1 {
                    throw NetworkError.networkError(error)
                }
                
                // Wait before retrying
                let delay = APIConfig.retryDelay * pow(2, Double(attempt))
                print("⚠️ Trip updates fetch failed (attempt \(attempt + 1)/\(APIConfig.maxRetries)): \(error.localizedDescription). Retrying in \(delay)s...")
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        
        // Should never reach here, but handle gracefully
        if let lastError = lastError {
            throw NetworkError.networkError(lastError)
        }
        throw NetworkError.noData
    }

    /// Convert a decoded feed message into trip updates using static stop-time
    /// data. Pure/synchronous: no network involved, safe to run once
    /// `stopTimesData` has been set.
    private func convert(_ feedMessage: TransitRealtime_FeedMessage) -> [String: TripUpdate] {
        var tripUpdates: [String: TripUpdate] = [:]
        let feedTimestamp = feedMessage.header.hasTimestamp
            ? Date(timeIntervalSince1970: TimeInterval(feedMessage.header.timestamp))
            : Date()

        for entity in feedMessage.entity {
            guard entity.hasTripUpdate else { continue }

            let tripUpdate = entity.tripUpdate
            guard tripUpdate.hasTrip, tripUpdate.trip.hasTripID else { continue }

            let tripId = tripUpdate.trip.tripID
            let relationship = tripUpdate.trip.scheduleRelationship
            let isCanceled = relationship == .canceled || relationship == .deleted
            let serviceDate = tripUpdate.trip.hasStartDate
                ? parseServiceDate(tripUpdate.trip.startDate)
                : nil
            let updateTimestamp = tripUpdate.hasTimestamp
                ? Date(timeIntervalSince1970: TimeInterval(tripUpdate.timestamp))
                : feedTimestamp
            let vehicleId: String? = {
                guard tripUpdate.hasVehicle else { return nil }
                if tripUpdate.vehicle.hasID, !tripUpdate.vehicle.id.isEmpty {
                    return tripUpdate.vehicle.id
                }
                if tripUpdate.vehicle.hasLabel, !tripUpdate.vehicle.label.isEmpty {
                    return tripUpdate.vehicle.label
                }
                return nil
            }()
            var stopTimeUpdates: [StopTimeUpdate] = []

            for stopTimeUpdate in tripUpdate.stopTimeUpdate {
                guard let stopId = resolveStopId(stopTimeUpdate, tripId: tripId) else {
                    continue
                }

                if stopTimeUpdate.scheduleRelationship == .skipped {
                    stopTimeUpdates.append(StopTimeUpdate(
                        stopId: stopId,
                        arrivalTime: nil,
                        departureTime: nil,
                        isSkipped: true
                    ))
                    continue
                }
                // NO_DATA means the schedule remains the best available value.
                guard stopTimeUpdate.scheduleRelationship != .noData else { continue }

                var arrivalTime: Date?
                if stopTimeUpdate.hasArrival {
                    if stopTimeUpdate.arrival.hasTime && stopTimeUpdate.arrival.time > 0 {
                        arrivalTime = Date(timeIntervalSince1970: TimeInterval(stopTimeUpdate.arrival.time))
                    } else if stopTimeUpdate.arrival.hasDelay {
                        let delaySeconds = stopTimeUpdate.arrival.delay
                        if let scheduledTime = getScheduledArrivalTime(
                            tripId: tripId,
                            stopId: stopId,
                            serviceDate: serviceDate
                        ) {
                            arrivalTime = scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
                        }
                    }
                }

                var departureTime: Date?
                if stopTimeUpdate.hasDeparture {
                    if stopTimeUpdate.departure.hasTime && stopTimeUpdate.departure.time > 0 {
                        departureTime = Date(timeIntervalSince1970: TimeInterval(stopTimeUpdate.departure.time))
                    } else if stopTimeUpdate.departure.hasDelay {
                        let delaySeconds = stopTimeUpdate.departure.delay
                        if let scheduledTime = getScheduledDepartureTime(
                            tripId: tripId,
                            stopId: stopId,
                            serviceDate: serviceDate
                        ) {
                            departureTime = scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
                        }
                    }
                }

                if let arrival = arrivalTime {
                    stopTimeUpdates.append(StopTimeUpdate(
                        stopId: stopId,
                        arrivalTime: arrival,
                        departureTime: departureTime,
                        isSkipped: false
                    ))
                }
            }

            if !stopTimeUpdates.isEmpty || isCanceled {
                tripUpdates[tripId] = TripUpdate(
                    tripId: tripId,
                    stopTimeUpdates: stopTimeUpdates,
                    timestamp: updateTimestamp,
                    vehicleId: vehicleId,
                    isCanceled: isCanceled,
                    serviceDate: tripUpdate.trip.hasStartDate ? tripUpdate.trip.startDate : nil
                )
            }
        }

        return tripUpdates
    }

    private func resolveStopId(
        _ update: TransitRealtime_TripUpdate.StopTimeUpdate,
        tripId: String
    ) -> Int? {
        if update.hasStopID, let stopId = Int(update.stopID) {
            return stopId
        }
        guard update.hasStopSequence else { return nil }
        return mapStopSequenceToStopId(tripId: tripId, stopSequence: Int(update.stopSequence))
    }

    /// Map the actual GTFS stop_sequence, falling back to array position only
    /// for an older app bundle generated before sequences were preserved.
    private func mapStopSequenceToStopId(tripId: String, stopSequence: Int) -> Int? {
        let stopTimes = stopTimesData[tripId] ?? []
        if let exactMatch = stopTimes.first(where: { $0.q == stopSequence }) {
            return exactMatch.s
        }
        let arrayIndex = stopSequence - 1
        guard arrayIndex >= 0, arrayIndex < stopTimes.count else { return nil }
        return stopTimes[arrayIndex].s
    }
    
    /// Get scheduled arrival time for a trip and stop
    private func getScheduledArrivalTime(tripId: String, stopId: Int, serviceDate: Date?) -> Date? {
        guard let stopTime = stopTimesData[tripId]?.first(where: { $0.s == stopId }) else { return nil }
        return parseGTFSTime(stopTime.a, serviceDate: serviceDate)
    }
    
    /// Get scheduled departure time for a trip and stop
    private func getScheduledDepartureTime(tripId: String, stopId: Int, serviceDate: Date?) -> Date? {
        // For now, use arrival time as departure time
        return getScheduledArrivalTime(tripId: tripId, stopId: stopId, serviceDate: serviceDate)
    }

    private func parseGTFSTime(_ timeString: String, serviceDate: Date?) -> Date? {
        let components = timeString.split(separator: ":")
        guard components.count == 3,
              let rawHour = Int(components[0]),
              let minute = Int(components[1]),
              let second = Int(components[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let baseDate = serviceDate ?? Date()
        var day = calendar.dateComponents([.year, .month, .day], from: baseDate)
        day.hour = rawHour % 24
        day.minute = minute
        day.second = second
        guard let date = calendar.date(from: day) else { return nil }
        return calendar.date(byAdding: .day, value: rawHour / 24, to: date)
    }

    private func parseServiceDate(_ value: String) -> Date? {
        guard value.count == 8,
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.suffix(2)) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
    
    /// Clear cache
    func clearCache() {
        cachedTripUpdates = nil
        prefetchedFeed = nil
    }
}

// MARK: - Models

/// Represents a GTFS-RT trip update
struct TripUpdate: Sendable {
    let tripId: String
    let stopTimeUpdates: [StopTimeUpdate]
    let timestamp: Date
    let vehicleId: String?
    let isCanceled: Bool
    let serviceDate: String?
}

/// Represents a stop time update with predicted arrival
struct StopTimeUpdate: Sendable {
    let stopId: Int
    let arrivalTime: Date?
    let departureTime: Date?
    let isSkipped: Bool
}
