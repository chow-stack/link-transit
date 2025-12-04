import Foundation
import SwiftData

/// Persists user's route filter preferences
@Model
final class RouteFilter {
    @Attribute(.unique) var routeId: String
    var isEnabled: Bool
    var timestamp: Date
    
    init(routeId: String, isEnabled: Bool = true) {
        self.routeId = routeId
        self.isEnabled = isEnabled
        self.timestamp = Date()
    }
}

