import Foundation
import CoreLocation

enum VehicleProgressStatus: String, Codable, Sendable {
    case incomingAt
    case stoppedAt
    case inTransitTo
    case unknown
}

/// Represents a bus vehicle with real-time position
struct Vehicle: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let routeId: String
    let tripId: String  // Add tripId field
    let routeName: String
    let latitude: Double
    let longitude: Double
    let heading: Double?
    let speed: Double?
    let vehicleLabel: String?
    let currentStopSequence: Int?
    let currentStopId: Int?
    let currentStatus: VehicleProgressStatus
    let serviceDateKey: String?
    let lastUpdated: Date

    init(
        id: String,
        routeId: String,
        tripId: String,
        routeName: String,
        latitude: Double,
        longitude: Double,
        heading: Double?,
        speed: Double?,
        vehicleLabel: String? = nil,
        currentStopSequence: Int? = nil,
        currentStopId: Int? = nil,
        currentStatus: VehicleProgressStatus = .unknown,
        serviceDateKey: String? = nil,
        lastUpdated: Date
    ) {
        self.id = id
        self.routeId = routeId
        self.tripId = tripId
        self.routeName = routeName
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.speed = speed
        self.vehicleLabel = vehicleLabel
        self.currentStopSequence = currentStopSequence
        self.currentStopId = currentStopId
        self.currentStatus = currentStatus
        self.serviceDateKey = serviceDateKey
        self.lastUpdated = lastUpdated
    }
    
    /// Computed property for MapKit coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// Check if vehicle data has actually changed (position, heading, speed)
    func hasChanged(from other: Vehicle) -> Bool {
        return latitude != other.latitude ||
               longitude != other.longitude ||
               heading != other.heading ||
               speed != other.speed ||
               tripId != other.tripId ||
               currentStopSequence != other.currentStopSequence ||
               currentStopId != other.currentStopId ||
               currentStatus != other.currentStatus
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case routeId = "route_id"
        case tripId = "trip_id"
        case routeName = "route_name"
        case latitude
        case longitude
        case heading
        case speed
        case vehicleLabel = "vehicle_label"
        case currentStopSequence = "current_stop_sequence"
        case currentStopId = "current_stop_id"
        case currentStatus = "current_status"
        case serviceDateKey = "service_date"
        case lastUpdated = "last_updated"
    }
}

/// Response structure for real-time vehicle data
struct VehicleResponse: Codable {
    let vehicles: [Vehicle]
    let timestamp: Date
}
