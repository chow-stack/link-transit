import Foundation
import SwiftProtobuf

/// Service for fetching and parsing GTFS-realtime Protocol Buffer feeds
actor GTFSRealtimeService {
    static let shared = GTFSRealtimeService()
    
    private let session: URLSession
    private var cachedVehicles: (data: [Vehicle], timestamp: Date)?
    private let cacheTimeout: TimeInterval = 3.0 // Shorter than 5s refresh to ensure fresh data
    
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
    
    /// Fetch real-time vehicle positions from GTFS-realtime .pb feed
    /// Returns cached data on timeout/error if available, otherwise empty array
    func fetchVehicles(forceRefresh: Bool = false) async throws -> [Vehicle] {
        // Check cache first
        if !forceRefresh,
           let cached = cachedVehicles,
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.data
        }
        
        // Fetch and parse the .pb file with retry logic
        do {
            let vehicles = try await fetchAndParseVehiclePositions()
            
            // Update cache only if we got data
            if !vehicles.isEmpty {
                cachedVehicles = (vehicles, Date())
            } else {
                // If we got empty array but have cached data, use cache as fallback
                if let cached = cachedVehicles {
                    print("⚠️ Received empty vehicle list, using cached data")
                    return cached.data
                }
            }
            
            return vehicles
        } catch {
            // Check if error is cancellation (expected when tasks are cancelled)
            let isCancellation = (error as NSError).code == NSURLErrorCancelled
            
            // On error, return cached data if available as fallback
            if let cached = cachedVehicles {
                // Only log non-cancellation errors to reduce console noise
                if !isCancellation {
                    print("⚠️ Vehicle fetch failed: \(error.localizedDescription). Using cached data.")
                }
                return cached.data
            }
            
            // No cache available - return empty array gracefully instead of throwing
            // This prevents app crashes on slow networks during launch
            print("⚠️ Vehicle fetch failed with no cache: \(error.localizedDescription). Returning empty array.")
            return []
        }
    }
    
    /// Fetch and parse vehicle positions from the Protocol Buffer feed
    /// Includes retry logic with exponential backoff and graceful timeout handling
    private func fetchAndParseVehiclePositions() async throws -> [Vehicle] {
        let urlString = APIConfig.vehiclePositionsFeedURL
        
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
                
                let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
                
                let vehicles = feedMessage.entity.compactMap { entity -> Vehicle? in
                    guard entity.hasVehicle else { return nil }
                    
                    let vehiclePos = entity.vehicle
                    guard vehiclePos.hasPosition else { return nil }
                    
                    let position = vehiclePos.position
                    
                    // Get route and trip information from trip descriptor
                    var routeId = ""
                    var tripId = ""
                    
                    if vehiclePos.hasTrip {
                        let trip = vehiclePos.trip
                        
                        // Get routeID if available
                        if trip.hasRouteID && !trip.routeID.isEmpty {
                            routeId = trip.routeID
                        }
                        
                        // Get tripID - we'll use this to look up route if routeID is missing
                        if trip.hasTripID && !trip.tripID.isEmpty {
                            tripId = trip.tripID
                        }
                    }
                    
                    // Get vehicle ID
                    let vehicleId = vehiclePos.hasVehicle && vehiclePos.vehicle.hasID
                        ? vehiclePos.vehicle.id
                        : entity.id
                    
                    return Vehicle(
                        id: vehicleId,
                        routeId: routeId,
                        tripId: tripId,
                        routeName: routeId.isEmpty ? tripId : routeId, // Store tripId in name if no routeId
                        latitude: Double(position.latitude),
                        longitude: Double(position.longitude),
                        heading: position.hasBearing ? Double(position.bearing) : nil,
                        speed: position.hasSpeed ? Double(position.speed) : nil,
                        lastUpdated: Date() // Set current timestamp when vehicle is parsed
                    )
                }
                
                // Success - return vehicles
                return vehicles
                
            } catch let error as URLError {
                lastError = error
                
                // Check if it's a timeout error
                let isTimeout = error.code == .timedOut || error.code == .networkConnectionLost
                
                // If it's the last attempt or not a timeout, throw the error
                if attempt == APIConfig.maxRetries - 1 || !isTimeout {
                    // For timeout on last attempt, return empty array gracefully
                    if isTimeout && attempt == APIConfig.maxRetries - 1 {
                        print("⚠️ Vehicle positions fetch timed out after \(APIConfig.maxRetries) attempts. Using empty array.")
                        return []
                    }
                    throw NetworkError.networkError(error)
                }
                
                // Wait before retrying (exponential backoff)
                let delay = APIConfig.retryDelay * Double(attempt + 1)
                print("⚠️ Vehicle positions fetch failed (attempt \(attempt + 1)/\(APIConfig.maxRetries)): \(error.localizedDescription). Retrying in \(delay)s...")
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
                print("⚠️ Vehicle positions fetch failed (attempt \(attempt + 1)/\(APIConfig.maxRetries)): \(error.localizedDescription). Retrying in \(delay)s...")
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        
        // Should never reach here, but handle gracefully
        if let lastError = lastError {
            throw NetworkError.networkError(lastError)
        }
        return []
    }
    
    /// Clear cache
    func clearCache() {
        cachedVehicles = nil
    }
}

