import Foundation

struct Route: Codable, Identifiable {
    let route_id: String
    let route_short_name: String
    let route_long_name: String
    let route_color: String?
    
    var id: String { route_id }
    
    // Memberwise initializer
    init(route_id: String, route_short_name: String, route_long_name: String, route_color: String?) {
        self.route_id = route_id
        self.route_short_name = route_short_name
        self.route_long_name = route_long_name
        self.route_color = route_color
    }
    
    // Custom decoding to handle numbers as strings
    enum CodingKeys: String, CodingKey {
        case route_id, route_short_name, route_long_name, route_color
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
        
        // Handle route_short_name as either String or Int
        if let nameString = try? container.decode(String.self, forKey: .route_short_name) {
            route_short_name = nameString
        } else if let nameInt = try? container.decode(Int.self, forKey: .route_short_name) {
            route_short_name = String(nameInt)
        } else {
            route_short_name = ""
        }
        
        route_long_name = try container.decode(String.self, forKey: .route_long_name)
        route_color = try? container.decode(String.self, forKey: .route_color)
    }
}
