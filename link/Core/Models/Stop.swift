import Foundation
import CoreLocation

/// Represents a bus stop location
struct Stop: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let lat: Double
    let lon: Double
    
    /// Computed property for MapKit coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Computed property for latitude (for consistency)
    var latitude: Double { lat }
    
    /// Computed property for longitude (for consistency)
    var longitude: Double { lon }
}

