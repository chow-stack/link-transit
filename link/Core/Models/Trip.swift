import Foundation

struct Trip: Codable, Identifiable, Sendable {
    let route_id: String
    let service_id: String
    let trip_id: String
    let shape_id: String?
    let trip_headsign: String
    let direction_id: Int?
    /// GTFS operational block assignment. This is not a public vehicle/fleet number.
    let block_id: String?
    
    var id: String { trip_id }
    
    // Custom decoding to handle route_id, service_id, and trip_id as either String or Int
    enum CodingKeys: String, CodingKey {
        case route_id, service_id, trip_id, shape_id, trip_headsign, direction_id, block_id
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle route_id as either String or Int
        if let idString = try? container.decode(String.self, forKey: .route_id) {
            route_id = idString
        } else if let idInt = try? container.decode(Int.self, forKey: .route_id) {
            route_id = String(idInt)
        } else {
            route_id = ""
        }
        
        // Handle service_id as either String or Int
        if let serviceString = try? container.decode(String.self, forKey: .service_id) {
            service_id = serviceString
        } else if let serviceInt = try? container.decode(Int.self, forKey: .service_id) {
            service_id = String(serviceInt)
        } else {
            service_id = ""
        }
        
        // Handle trip_id as either String or Int
        if let tripString = try? container.decode(String.self, forKey: .trip_id) {
            trip_id = tripString
        } else if let tripInt = try? container.decode(Int.self, forKey: .trip_id) {
            trip_id = String(tripInt)
        } else {
            trip_id = ""
        }
        
        // shape_id is optional
        shape_id = try? container.decode(String.self, forKey: .shape_id)
        
        trip_headsign = try container.decode(String.self, forKey: .trip_headsign)
        direction_id = try? container.decode(Int.self, forKey: .direction_id)
        
        // Handle block_id as either String or Int
        if let blockString = try? container.decode(String.self, forKey: .block_id) {
            block_id = blockString
        } else if let blockInt = try? container.decode(Int.self, forKey: .block_id) {
            block_id = String(blockInt)
        } else {
            block_id = nil
        }
    }
}
