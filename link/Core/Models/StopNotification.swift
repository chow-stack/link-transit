import Foundation
import SwiftData

/// Represents a user's notification preference for a specific stop
@Model
class StopNotification {
    /// Unique identifier for the notification preference
    @Attribute(.unique) var id: String
    
    /// Stop ID this notification is for
    var stopId: Int
    
    /// Stop name for display
    var stopName: String
    
    /// Set of route IDs to receive notifications for
    var enabledRouteIds: Set<String>
    
    /// How many minutes before arrival to notify (1-30)
    var advanceMinutes: Int
    
    /// Whether this notification is currently active
    var isEnabled: Bool
    
    /// Timestamp when notification was created
    var createdAt: Date
    
    /// Last time a notification was triggered for this stop
    var lastTriggered: Date?
    
    init(stopId: Int, stopName: String, enabledRouteIds: Set<String>, advanceMinutes: Int = 5) {
        self.id = "stop_\(stopId)"
        self.stopId = stopId
        self.stopName = stopName
        self.enabledRouteIds = enabledRouteIds
        self.advanceMinutes = advanceMinutes
        self.isEnabled = true
        self.createdAt = Date()
        self.lastTriggered = nil
    }
    
    /// Update last triggered timestamp
    func updateLastTriggered() {
        lastTriggered = Date()
    }
    
    /// Check if a specific route is enabled for notifications
    func isRouteEnabled(_ routeId: String) -> Bool {
        enabledRouteIds.contains(routeId)
    }
    
    /// Toggle a route on/off
    func toggleRoute(_ routeId: String) {
        if enabledRouteIds.contains(routeId) {
            enabledRouteIds.remove(routeId)
        } else {
            enabledRouteIds.insert(routeId)
        }
    }
}

