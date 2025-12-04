import Foundation
import SwiftData

/// Represents a user's favorite route or stop
@Model
class Favorite {
    /// Unique identifier for the favorite
    @Attribute(.unique) var id: String
    
    /// Type of favorite (route or stop)
    var type: FavoriteType
    
    /// ID of the route or stop
    var itemId: String
    
    /// Display name for the favorite
    var name: String
    
    /// Optional route color (for route favorites)
    var routeColor: String?
    
    /// Timestamp when favorite was created
    var createdAt: Date
    
    /// Timestamp when favorite was last accessed
    var lastAccessedAt: Date
    
    init(type: FavoriteType, itemId: String, name: String, routeColor: String? = nil) {
        self.id = "\(type.rawValue)_\(itemId)"
        self.type = type
        self.itemId = itemId
        self.name = name
        self.routeColor = routeColor
        self.createdAt = Date()
        self.lastAccessedAt = Date()
    }
    
    /// Update last accessed timestamp
    func updateLastAccessed() {
        lastAccessedAt = Date()
    }
}

/// Types of favorites
enum FavoriteType: String, CaseIterable, Codable {
    case route = "route"
    case stop = "stop"
    
    var displayName: String {
        switch self {
        case .route:
            return "Route"
        case .stop:
            return "Stop"
        }
    }
    
    var iconName: String {
        switch self {
        case .route:
            return "bus.fill"
        case .stop:
            return "mappin.circle.fill"
        }
    }
}
