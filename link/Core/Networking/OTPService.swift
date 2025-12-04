import Foundation
import CoreLocation

/// Actor-based service for communicating with OpenTripPlanner API
actor OTPService {
    
    // MARK: - Singleton
    
    static let shared = OTPService()
    
    private init() {}
    
    // MARK: - Trip Planning
    
    func planTrip(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        departureTime: Date
    ) async throws -> [Itinerary] {
        
        // Format departure time as ISO 8601 with timezone
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let departureString = dateFormatter.string(from: departureTime)
        
        // Build GraphQL query
        let query = buildGraphQLQuery(
            origin: origin,
            destination: destination,
            departureTime: departureString
        )
        
        // Create request
        guard let url = URL(string: APIConfig.otpBaseURL) else {
            throw OTPError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = APIConfig.otpTimeout
        
        let requestBody = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("🗺️ OTP Request to: \(url.absoluteString)")
        print("🗺️ OTP Departure time: \(departureString)")
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OTPError.networkError(NSError(domain: "OTP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }
        
        print("🗺️ OTP Response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw OTPError.networkError(NSError(domain: "OTP", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
        }
        
        // Parse response
        let itineraries = try parseOTPResponse(data, departureTime: departureTime)
        
        print("🗺️ OTP returned \(itineraries.count) itineraries")
        
        return itineraries
    }
    
    // MARK: - GraphQL Query Building
    
    private func buildGraphQLQuery(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        departureTime: String
    ) -> String {
        return """
        { plan(from: {lat: \(origin.latitude), lon: \(origin.longitude)}, to: {lat: \(destination.latitude), lon: \(destination.longitude)}, transportModes: [{mode: WALK}, {mode: BUS}], numItineraries: 3) { itineraries { duration walkTime startTime endTime walkDistance legs { mode startTime endTime duration distance from { name lat lon stop { gtfsId } } to { name lat lon stop { gtfsId } } legGeometry { points } route { shortName longName color } trip { gtfsId } } } } }
        """
    }
    
    // MARK: - Response Parsing
    
    private func parseOTPResponse(_ data: Data, departureTime: Date) throws -> [Itinerary] {
        // Debug: Print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🗺️ OTP Response JSON (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let plan = dataDict["plan"] as? [String: Any],
              let itinerariesArray = plan["itineraries"] as? [[String: Any]] else {
            
            // Check for errors in response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]] {
                let errorMessages = errors.compactMap { $0["message"] as? String }.joined(separator: ", ")
                print("🗺️ OTP Error: \(errorMessages)")
                throw OTPError.noRoutesFound
            }
            
            throw OTPError.invalidResponse
        }
        
        guard !itinerariesArray.isEmpty else {
            throw OTPError.noRoutesFound
        }
        
        var itineraries: [Itinerary] = []
        
        for itinDict in itinerariesArray {
            do {
                let itinerary = try parseItinerary(itinDict, departureTime: departureTime)
                itineraries.append(itinerary)
            } catch {
                print("⚠️ Failed to parse itinerary: \(error)")
                // Continue parsing other itineraries
            }
        }
        
        if itineraries.isEmpty {
            throw OTPError.noRoutesFound
        }
        
        return itineraries
    }
    
    private func parseItinerary(_ dict: [String: Any], departureTime: Date) throws -> Itinerary {
        guard let legsArray = dict["legs"] as? [[String: Any]] else {
            throw OTPError.invalidResponse
        }
        
        var segments: [TripSegment] = []
        var totalDistance: Double = 0
        var transferCount = 0
        var hasBusSegment = false
        
        for legDict in legsArray {
            guard let mode = legDict["mode"] as? String else { continue }
            
            let segment: TripSegment
            
            if mode == "WALK" {
                segment = try parseWalkLeg(legDict)
                if case .walk(_, let distance, _, _, _) = segment {
                    totalDistance += distance
                }
            } else if mode == "BUS" {
                segment = try parseBusLeg(legDict)
                if hasBusSegment {
                    transferCount += 1
                }
                hasBusSegment = true
            } else {
                continue // Skip unsupported modes
            }
            
            segments.append(segment)
        }
        
        // Calculate times
        let durationSeconds = dict["duration"] as? Double ?? 0
        let startTimeMillis = dict["startTime"] as? Int64 ?? 0
        let endTimeMillis = dict["endTime"] as? Int64 ?? 0
        
        let calculatedDepartureTime = Date(timeIntervalSince1970: TimeInterval(startTimeMillis) / 1000.0)
        let arrivalTime = Date(timeIntervalSince1970: TimeInterval(endTimeMillis) / 1000.0)
        
        return Itinerary(
            segments: segments,
            totalTime: durationSeconds,
            totalDistance: totalDistance,
            transferCount: transferCount,
            departureTime: calculatedDepartureTime,
            arrivalTime: arrivalTime
        )
    }
    
    private func parseWalkLeg(_ dict: [String: Any]) throws -> TripSegment {
        guard let distance = dict["distance"] as? Double,
              let duration = dict["duration"] as? Double,
              let fromDict = dict["from"] as? [String: Any],
              let toDict = dict["to"] as? [String: Any],
              let fromLat = fromDict["lat"] as? Double,
              let fromLon = fromDict["lon"] as? Double,
              let toLat = toDict["lat"] as? Double,
              let toLon = toDict["lon"] as? Double else {
            throw OTPError.invalidResponse
        }
        
        let from = CLLocationCoordinate2D(latitude: fromLat, longitude: fromLon)
        let to = CLLocationCoordinate2D(latitude: toLat, longitude: toLon)
        
        return .walk(
            id: UUID(),
            distance: distance,
            duration: duration,
            from: from,
            to: to
        )
    }
    
    private func parseBusLeg(_ dict: [String: Any]) throws -> TripSegment {
        guard let fromDict = dict["from"] as? [String: Any],
              let toDict = dict["to"] as? [String: Any],
              let fromLat = fromDict["lat"] as? Double,
              let fromLon = fromDict["lon"] as? Double,
              let toLat = toDict["lat"] as? Double,
              let toLon = toDict["lon"] as? Double,
              let duration = dict["duration"] as? Double else {
            throw OTPError.invalidResponse
        }
        
        // Extract stop information
        let fromName = fromDict["name"] as? String ?? "Unknown Stop"
        let toName = toDict["name"] as? String ?? "Unknown Stop"
        
        // Extract stop IDs from GTFS if available
        var fromStopId = 0
        var toStopId = 0
        
        if let fromStopDict = fromDict["stop"] as? [String: Any],
           let fromGtfsId = fromStopDict["gtfsId"] as? String {
            // Parse GTFS ID (format: "agency:stopId")
            let components = fromGtfsId.split(separator: ":")
            if components.count > 1, let id = Int(components[1]) {
                fromStopId = id
            }
        }
        
        if let toStopDict = toDict["stop"] as? [String: Any],
           let toGtfsId = toStopDict["gtfsId"] as? String {
            let components = toGtfsId.split(separator: ":")
            if components.count > 1, let id = Int(components[1]) {
                toStopId = id
            }
        }
        
        // Create Stop objects
        let fromStop = Stop(
            id: fromStopId,
            name: fromName,
            lat: fromLat,
            lon: fromLon
        )
        
        let toStop = Stop(
            id: toStopId,
            name: toName,
            lat: toLat,
            lon: toLon
        )
        
        // Extract route information
        var routeShortName = "Bus"
        var routeColor: String?
        
        if let routeDict = dict["route"] as? [String: Any] {
            routeShortName = routeDict["shortName"] as? String ?? routeDict["longName"] as? String ?? "Bus"
            routeColor = routeDict["color"] as? String
        }
        
        // Extract trip ID
        var tripId: String?
        if let tripDict = dict["trip"] as? [String: Any],
           let gtfsId = tripDict["gtfsId"] as? String {
            tripId = gtfsId
        }
        
        // Calculate wait time (assume 0 for OTP, as it's already included in the plan)
        let waitTime: TimeInterval = 0
        
        return .ride(
            id: UUID(),
            routeId: routeShortName,
            routeName: routeShortName,
            routeColor: routeColor,
            fromStop: fromStop,
            toStop: toStop,
            duration: duration,
            waitTime: waitTime,
            tripId: tripId
        )
    }
}

// MARK: - Error Types

enum OTPError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case noRoutesFound
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Trip planner returned invalid data"
        case .noRoutesFound:
            return "No routes found"
        case .timeout:
            return "Request timed out"
        }
    }
}

