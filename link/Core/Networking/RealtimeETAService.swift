import Foundation
import SwiftProtobuf
import CoreLocation

/// Vehicle position data from GTFS-realtime
struct VehiclePosition {
    let vehicleId: String
    let tripId: String?
    let routeId: String?
    let latitude: Double
    let longitude: Double
    let bearing: Double?
    let speed: Double?
    let timestamp: Date
}

/// Service for fetching and processing real-time ETAs from GTFS-realtime feeds
actor RealtimeETAService {
    static let shared = RealtimeETAService()
    
    private let session: URLSession
    private var cachedTripUpdates: (data: [String: TripUpdate], timestamp: Date)?
    private let cacheTimeout: TimeInterval = 15.0 // Cache for 15 seconds
    
    // Reference to static data for mapping
    private weak var stopTimesService: StopTimesService?
    
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
    
    /// Set reference to StopTimesService for mapping stop sequences to stop IDs
    func setStopTimesService(_ service: StopTimesService) {
        self.stopTimesService = service
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
        
        // Fetch and parse the trip updates with retry logic
        do {
            let tripUpdates = try await fetchAndParseTripUpdates()
            
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
            
            // No cache available - return empty dictionary gracefully instead of throwing
            // This prevents app crashes on slow networks during launch
            print("⚠️ Trip updates fetch failed with no cache: \(error.localizedDescription). Returning empty dictionary.")
            return [:]
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
    
    /// Estimate ETA using vehicle position and route shape
    /// Fallback when trip updates are not available
    func estimateETA(
        vehicleCoordinate: CLLocationCoordinate2D,
        vehicleSpeed: Double?, // meters per second
        stopCoordinate: CLLocationCoordinate2D,
        shapePoints: [CLLocationCoordinate2D]
    ) -> Date? {
        // If no speed data, can't estimate
        guard let speed = vehicleSpeed, speed > 0 else {
            return nil
        }
        
        // Find vehicle's position on the shape
        guard let vehicleIndex = findClosestPointOnShape(
            coordinate: vehicleCoordinate,
            shape: shapePoints
        ) else {
            return nil
        }
        
        // Find stop's position on the shape
        guard let stopIndex = findClosestPointOnShape(
            coordinate: stopCoordinate,
            shape: shapePoints
        ) else {
            return nil
        }
        
        // If stop is behind the vehicle, it's likely already passed
        if stopIndex <= vehicleIndex {
            return nil
        }
        
        // Calculate distance along shape from vehicle to stop
        let distance = calculateDistanceAlongShape(
            from: vehicleIndex,
            to: stopIndex,
            shape: shapePoints
        )
        
        // Estimate travel time: distance / speed
        let travelTimeSeconds = distance / speed
        
        // Add a buffer for stops (average 30 seconds per stop between vehicle and target)
        let stopsInBetween = stopIndex - vehicleIndex
        let stopDelayBuffer = Double(stopsInBetween) * 30.0
        
        return Date().addingTimeInterval(travelTimeSeconds + stopDelayBuffer)
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
                
                // Count different entity types for basic validation
                var tripUpdateCount = 0
                var vehicleCount = 0
                var alertCount = 0
                
                for entity in feedMessage.entity {
                    if entity.hasTripUpdate {
                        tripUpdateCount += 1
                    } else if entity.hasVehicle {
                        vehicleCount += 1
                    } else if entity.hasAlert {
                        alertCount += 1
                    }
                }
                
                // Convert to our TripUpdate model
                var tripUpdates: [String: TripUpdate] = [:]
                var route1TripUpdates: [String: TripUpdate] = [:]
                
                // Now let's try to parse the actual trip updates with more robust logic
                for entity in feedMessage.entity {
                    guard entity.hasTripUpdate else { continue }
                    
                    let tripUpdate = entity.tripUpdate
                    guard tripUpdate.hasTrip, tripUpdate.trip.hasTripID else { continue }
                    
                    let tripId = tripUpdate.trip.tripID
                    let routeId = tripUpdate.trip.hasRouteID ? tripUpdate.trip.routeID : "unknown"
                    
                    // Parse stop time updates with more flexible logic
                    var stopTimeUpdates: [StopTimeUpdate] = []
                    
                    for stopTimeUpdate in tripUpdate.stopTimeUpdate {
                        // Map stop sequence to actual stop ID using static data
                        let stopSequence = stopTimeUpdate.stopSequence
                        guard let stopId = await mapStopSequenceToStopId(tripId: tripId, stopSequence: Int(stopSequence)) else {
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
                                if let scheduledTime = await getScheduledArrivalTime(tripId: tripId, stopId: stopId) {
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
                                if let scheduledTime = await getScheduledDepartureTime(tripId: tripId, stopId: stopId) {
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
                        
                        // Track Route 1 specifically
                        if routeId == "1" {
                            route1TripUpdates[tripId] = TripUpdate(
                                tripId: tripId,
                                stopTimeUpdates: stopTimeUpdates,
                                timestamp: Date()
                            )
                        }
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
                        return [:]
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
    
    /// Fetch vehicle positions from GTFS-realtime feed
    func fetchVehiclePositions() async throws -> [String: VehiclePosition] {
        let urlString = APIConfig.vehiclePositionsFeedURL
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
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
            
            // Convert to our VehiclePosition model
            var vehiclePositions: [String: VehiclePosition] = [:]
            
            for entity in feedMessage.entity {
                guard entity.hasVehicle else { continue }
                
                let vehiclePos = entity.vehicle
                guard vehiclePos.hasPosition else { continue }
                
                let position = vehiclePos.position
                let vehicleId = vehiclePos.hasVehicle && vehiclePos.vehicle.hasID ? vehiclePos.vehicle.id : "unknown"
                
                let vehiclePosition = VehiclePosition(
                    vehicleId: vehicleId,
                    tripId: vehiclePos.hasTrip && vehiclePos.trip.hasTripID ? vehiclePos.trip.tripID : nil,
                    routeId: vehiclePos.hasTrip && vehiclePos.trip.hasRouteID ? vehiclePos.trip.routeID : nil,
                    latitude: Double(position.latitude),
                    longitude: Double(position.longitude),
                    bearing: position.hasBearing ? Double(position.bearing) : nil,
                    speed: position.hasSpeed ? Double(position.speed) : nil,
                    timestamp: Date()
                )
                
                vehiclePositions[vehicleId] = vehiclePosition
            }
            
            print("✅ Fetched \(vehiclePositions.count) vehicle positions")
            return vehiclePositions
            
        } catch let error as NetworkError {
            throw error
        } catch let error as SwiftProtobuf.BinaryDecodingError {
            throw NetworkError.decodingError(error)
        } catch {
            throw NetworkError.networkError(error)
        }
    }
    
    /// Find the closest point on a shape polyline to a given coordinate
    private func findClosestPointOnShape(
        coordinate: CLLocationCoordinate2D,
        shape: [CLLocationCoordinate2D]
    ) -> Int? {
        guard !shape.isEmpty else { return nil }
        
        var closestIndex = 0
        var minDistance = Double.greatestFiniteMagnitude
        
        for (index, point) in shape.enumerated() {
            let distance = coordinate.distance(to: point)
            if distance < minDistance {
                minDistance = distance
                closestIndex = index
            }
        }
        
        return closestIndex
    }
    
    /// Calculate distance along a shape from one index to another
    private func calculateDistanceAlongShape(
        from startIndex: Int,
        to endIndex: Int,
        shape: [CLLocationCoordinate2D]
    ) -> Double {
        guard startIndex < endIndex, endIndex < shape.count else {
            return 0
        }
        
        var totalDistance: Double = 0
        
        for i in startIndex..<endIndex {
            let distance = shape[i].distance(to: shape[i + 1])
            totalDistance += distance
        }
        
        return totalDistance
    }
    
    /// Map stop sequence to stop ID using static data
    private func mapStopSequenceToStopId(tripId: String, stopSequence: Int) async -> Int? {
        guard let stopTimesService = stopTimesService else {
            print("⚠️ StopTimesService not available for mapping")
            return nil
        }
        
        // Get the stop times for this trip from static data
        let stopTimes = await stopTimesService.getStopTimesForTrip(tripId: tripId)
        
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
    private func getScheduledArrivalTime(tripId: String, stopId: Int) async -> Date? {
        guard let stopTimesService = stopTimesService else {
            return nil
        }
        
        return await stopTimesService.getScheduledArrivalTime(tripId: tripId, stopId: stopId)
    }
    
    /// Get scheduled departure time for a trip and stop
    private func getScheduledDepartureTime(tripId: String, stopId: Int) async -> Date? {
        // For now, use arrival time as departure time
        return await getScheduledArrivalTime(tripId: tripId, stopId: stopId)
    }
    
    /// Clear cache
    func clearCache() {
        cachedTripUpdates = nil
    }
}

// MARK: - Models

/// Represents a GTFS-RT trip update
struct TripUpdate {
    let tripId: String
    let stopTimeUpdates: [StopTimeUpdate]
    let timestamp: Date
}

/// Represents a stop time update with predicted arrival
struct StopTimeUpdate {
    let stopId: Int
    let arrivalTime: Date?
    let departureTime: Date?
}

// MARK: - Helper Extensions

extension CLLocationCoordinate2D {
    /// Calculate distance between two coordinates in meters
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2)
    }
}

