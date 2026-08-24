import Foundation

struct Shape: Codable, Identifiable, Sendable {
    let shape_id: String
    let shape_pt_lat: Double
    let shape_pt_lon: Double
    let shape_pt_sequence: Int
    
    var id: String { "\(shape_id)-\(shape_pt_sequence)" }
    
    // Custom decoding to handle lat/lon as strings
    enum CodingKeys: String, CodingKey {
        case shape_id, shape_pt_lat, shape_pt_lon, shape_pt_sequence
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        shape_id = try container.decode(String.self, forKey: .shape_id)
        
        // Handle latitude as either Double or String
        if let lat = try? container.decode(Double.self, forKey: .shape_pt_lat) {
            shape_pt_lat = lat
        } else if let latString = try? container.decode(String.self, forKey: .shape_pt_lat),
                  let lat = Double(latString) {
            shape_pt_lat = lat
        } else {
            shape_pt_lat = 0.0
        }
        
        // Handle longitude as either Double or String
        if let lon = try? container.decode(Double.self, forKey: .shape_pt_lon) {
            shape_pt_lon = lon
        } else if let lonString = try? container.decode(String.self, forKey: .shape_pt_lon),
                  let lon = Double(lonString) {
            shape_pt_lon = lon
        } else {
            shape_pt_lon = 0.0
        }
        
        shape_pt_sequence = try container.decode(Int.self, forKey: .shape_pt_sequence)
    }
}
