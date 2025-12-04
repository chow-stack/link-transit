import Foundation

/// Represents a bus arrival at a stop
struct Arrival: Identifiable, Hashable {
    let id: String
    let stopId: Int
    let tripId: String
    let routeId: String
    let routeShortName: String
    let routeColor: String?
    let arrivalTime: Date // Real-time predicted arrival or scheduled arrival
    let scheduledTime: String // "HH:mm:ss" format from GTFS
    let isRealtime: Bool // Whether this is a real-time prediction
    let vehicleId: String? // Individual bus/vehicle ID if available
    let busNumber: String? // Display-friendly bus number
    
    /// Time until arrival in seconds
    var timeUntilArrival: TimeInterval {
        arrivalTime.timeIntervalSinceNow
    }
    
    /// Formatted time string ("5 min", "under 2 mins", "12:30 PM")
    var formattedTime: String {
        let seconds = Int(timeUntilArrival)
        
        if seconds < 60 { // Less than 1 minute - more conservative threshold
            return "under 2 mins"
        } else if seconds < 3600 {
            // Less than 1 hour - show minutes
            let minutes = seconds / 60
            return "\(minutes) min"
        } else {
            // More than 1 hour - show clock time
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: arrivalTime)
        }
    }
    
    /// Whether this arrival is in the past
    var hasDeparted: Bool {
        // Only consider departed if it's more than 5 minutes ago
        return timeUntilArrival < -300 // 5 minutes ago
    }
    
    /// Whether this arrival is happening soon (within 1 minute)
    var isArriving: Bool {
        let seconds = Int(timeUntilArrival)
        // Show "arriving" for arrivals within 1 minute (matching "under 2 mins" threshold)
        return seconds < 60
    }
    
    /// Status badge text
    var statusBadge: String? {
        let seconds = Int(timeUntilArrival)
        
        if seconds < 60 {
            return "Arriving" // Green badge for "under 2 mins" arrivals
        } else if isRealtime {
            return "Live" // Blue badge for real-time arrivals 1+ minutes away
        } else {
            return nil // No badge for scheduled (we're not showing scheduled anymore)
        }
    }
    
    /// Badge color
    var statusColor: String {
        let seconds = Int(timeUntilArrival)
        
        if seconds < 60 {
            return "green" // Green for "under 2 mins" arrivals
        } else if isRealtime {
            return "blue" // Blue for real-time arrivals 1+ minutes away
        } else {
            return "gray"
        }
    }
    
    /// Display name for the bus (vehicle ID or bus number)
    var busDisplayName: String {
        if let busNumber = busNumber {
            return busNumber
        } else if let vehicleId = vehicleId {
            return vehicleId
        } else {
            return "Bus"
        }
    }
}

