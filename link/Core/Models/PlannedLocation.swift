import Foundation
import CoreLocation

/// Represents a location used for trip planning (origin or destination)
struct PlannedLocation: Identifiable, Hashable, Codable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let address: String?
    
    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, address: String? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.address = address
    }
    
    /// Display name for UI (address if available, otherwise coordinate)
    var displayName: String {
        address ?? "\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude))"
    }
    
    /// Latitude for Codable compatibility
    private var latitude: Double {
        coordinate.latitude
    }
    
    /// Longitude for Codable compatibility
    private var longitude: Double {
        coordinate.longitude
    }
    
    /// Custom Codable implementation for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, address
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        address = try container.decodeIfPresent(String.self, forKey: .address)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(address, forKey: .address)
    }
    
    // MARK: - Hashable Conformance
    
    static func == (lhs: PlannedLocation, rhs: PlannedLocation) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.address == rhs.address
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(address)
    }
}

