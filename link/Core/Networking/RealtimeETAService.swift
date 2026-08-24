import Foundation
import SwiftProtobuf

/// Service for fetching and processing real-time ETAs from GTFS-realtime feeds
actor RealtimeETAService {
    static let shared = RealtimeETAService()
    
    private let session: URLSession
    private var cachedTripUpdates: (data: [String: TripUpdate], timestamp: Date)?
    private var inFlightFetch: Task<[String: TripUpdate], Error>?
    private let cacheTimeout: TimeInterval = 15.0 // Cache for 15 seconds
    
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
    /// Includes retry logic with exponential backoff and graceful timeout handling
    private func fetchAndParseTripUpdates() async throws -> [String: TripUpdate] {
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
                
                // Convert to our TripUpdate model
                var tripUpdates: [String: TripUpdate] = [:]
                
                // Now let's try to parse the actual trip updates with more robust logic
                for entity in feedMessage.entity {
                    guard entity.hasTripUpdate else { continue }
                    
                    let tripUpdate = entity.tripUpdate
                    guard tripUpdate.hasTrip, tripUpdate.trip.hasTripID else { continue }
                    
                    let tripId = tripUpdate.trip.tripID
                    // Parse stop time updates with more flexible logic
                    var stopTimeUpdates: [StopTimeUpdate] = []
                    
                    for stopTimeUpdate in tripUpdate.stopTimeUpdate {
                        // Map stop sequence to actual stop ID using static data
                        let stopSequence = stopTimeUpdate.stopSequence
                        guard let stopId = mapStopSequenceToStopId(tripId: tripId, stopSequence: Int(stopSequence)) else {
                            continue
                        }
                        
                        // Calculate arrival time using delay-based approach
                        var arrivalTime: Date?
                        if stopTimeUpdate.hasArrival {
                            if stopTimeUpdate.arrival.hasTime && stopTimeUpdate.arrival.time > 0 {
                                // Use absolute timestamp if available
                                arrivalTime = Date(timeIntervalSince1970: TimeInterval(stopTimeUpdate.arrival.time))
                            } else if stopTimeUpdate.arrival.hasDelay {
                                // Use delay-based calculation
                                let delaySeconds = stopTimeUpdate.arrival.delay
                                if let scheduledTime = getScheduledArrivalTime(tripId: tripId, stopId: stopId) {
                                    arrivalTime = scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
                                }
                            }
                        }
                        
                        // Calculate departure time using delay-based approach
                        var departureTime: Date?
                        if stopTimeUpdate.hasDeparture {
                            if stopTimeUpdate.departure.hasTime && stopTimeUpdate.departure.time > 0 {
                                departureTime = Date(timeIntervalSince1970: TimeInterval(stopTimeUpdate.departure.time))
                            } else if stopTimeUpdate.departure.hasDelay {
                                let delaySeconds = stopTimeUpdate.departure.delay
                                if let scheduledTime = getScheduledDepartureTime(tripId: tripId, stopId: stopId) {
                                    departureTime = scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
                                }
                            }
                        }
                        
                        // Only add if we have at least one time
                        if let arrival = arrivalTime {
                            stopTimeUpdates.append(StopTimeUpdate(
                                stopId: stopId,
                                arrivalTime: arrival,
                                departureTime: departureTime
                            ))
                        }
                    }
                    
                    // Only add trip if it has stop updates
                    if !stopTimeUpdates.isEmpty {
                        tripUpdates[tripId] = TripUpdate(
                            tripId: tripId,
                            stopTimeUpdates: stopTimeUpdates,
                            timestamp: Date()
                        )
                        
                    }
                }
            
                // Log basic success info only
                print("✅ Fetched \(tripUpdates.count) trip updates")
                
                // Success - return trip updates
                return tripUpdates
                
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
                let delay = APIConfig.retryDelay * Double(attempt + 1)
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
                let delay = APIConfig.retryDelay * Double(attempt + 1)
                print("⚠️ Trip updates fetch failed (attempt \(attempt + 1)/\(APIConfig.maxRetries)): \(error.localizedDescription). Retrying in \(delay)s...")
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        
        // Should never reach here, but handle gracefully
        if let lastError = lastError {
            throw NetworkError.networkError(lastError)
        }
        return [:]
    }
    
    /// Map stop sequence to stop ID using static data
    private func mapStopSequenceToStopId(tripId: String, stopSequence: Int) -> Int? {
        let stopTimes = stopTimesData[tripId] ?? []
        
        // Stop sequences are 1-based, array indices are 0-based
        let arrayIndex = stopSequence - 1
        
        guard arrayIndex >= 0 && arrayIndex < stopTimes.count else {
            // Suppress warning for known data quality issues in GTFS-RT feed
            // Some trips report stop sequences that don't match static data
            // This is a feed issue, not an app bug, so we silently skip invalid sequences
            return nil
        }
        
        let stopTime = stopTimes[arrayIndex]
        return stopTime.s
    }
    
    /// Get scheduled arrival time for a trip and stop
    private func getScheduledArrivalTime(tripId: String, stopId: Int) -> Date? {
        guard let stopTime = stopTimesData[tripId]?.first(where: { $0.s == stopId }) else { return nil }
        return parseGTFSTime(stopTime.a)
    }
    
    /// Get scheduled departure time for a trip and stop
    private func getScheduledDepartureTime(tripId: String, stopId: Int) -> Date? {
        // For now, use arrival time as departure time
        return getScheduledArrivalTime(tripId: tripId, stopId: stopId)
    }

    private func parseGTFSTime(_ timeString: String) -> Date? {
        let components = timeString.split(separator: ":")
        guard components.count == 3,
              let rawHour = Int(components[0]),
              let minute = Int(components[1]),
              let second = Int(components[2]) else { return nil }
        var day = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        day.hour = rawHour % 24
        day.minute = minute
        day.second = second
        guard let date = Calendar.current.date(from: day) else { return nil }
        return Calendar.current.date(byAdding: .day, value: rawHour / 24, to: date)
    }
    
    /// Clear cache
    func clearCache() {
        cachedTripUpdates = nil
    }
}

// MARK: - Models

/// Represents a GTFS-RT trip update
struct TripUpdate: Sendable {
    let tripId: String
    let stopTimeUpdates: [StopTimeUpdate]
    let timestamp: Date
}

/// Represents a stop time update with predicted arrival
struct StopTimeUpdate: Sendable {
    let stopId: Int
    let arrivalTime: Date?
    let departureTime: Date?
}
