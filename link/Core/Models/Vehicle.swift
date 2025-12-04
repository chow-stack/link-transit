import Foundation
import CoreLocation

/// Represents a bus vehicle with real-time position
struct Vehicle: Identifiable, Codable, Equatable {
    let id: String
    let routeId: String
    let tripId: String  // Add tripId field
    let routeName: String
    let latitude: Double
    let longitude: Double
    let heading: Double?
    let speed: Double?
    let lastUpdated: Date
    
    /// Computed property for MapKit coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// Check if vehicle data has actually changed (position, heading, speed)
    func hasChanged(from other: Vehicle) -> Bool {
        return latitude != other.latitude ||
               longitude != other.longitude ||
               heading != other.heading ||
               speed != other.speed
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
        case lastUpdated = "last_updated"
    }
}

/// Response structure for real-time vehicle data
struct VehicleResponse: Codable {
    let vehicles: [Vehicle]
    let timestamp: Date
}

