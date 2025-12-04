import Foundation

/// Represents a complete trip itinerary with multiple segments
struct Itinerary: Identifiable, Hashable, Codable {
    let id: UUID
    let segments: [TripSegment]
    let totalTime: TimeInterval
    let totalDistance: Double
    let transferCount: Int
    let departureTime: Date
    let arrivalTime: Date
    
    init(
        id: UUID = UUID(),
        segments: [TripSegment],
        totalTime: TimeInterval,
        totalDistance: Double,
        transferCount: Int,
        departureTime: Date,
        arrivalTime: Date
    ) {
        self.id = id
        self.segments = segments
        self.totalTime = totalTime
        self.totalDistance = totalDistance
        self.transferCount = transferCount
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
    }
    
    /// Time until arrival (from current time)
    var timeUntilArrival: TimeInterval {
        arrivalTime.timeIntervalSinceNow
    }
    
    /// Formatted total time string showing time until arrival (e.g., "25 min" or "1 hr 15 min")
    /// This shows the time from now until arrival, not the trip duration
    var formattedTotalTime: String {
        let seconds = Int(timeUntilArrival)
        if seconds < 0 {
            // Already arrived or past
            return "0 min"
        } else if seconds < 60 {
            return "< 1 min"
        } else {
            let totalMinutes = seconds / 60
            if totalMinutes < 60 {
                return "\(totalMinutes) min"
            } else {
                let hours = totalMinutes / 60
                let minutes = totalMinutes % 60
                if minutes == 0 {
                    return "\(hours) hr"
                } else {
                    return "\(hours) hr \(minutes) min"
                }
            }
        }
    }
    
    /// Formatted total distance string (e.g., "2.3 km" or "800 m")
    var formattedTotalDistance: String {
        if totalDistance >= 1000 {
            let km = totalDistance / 1000
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f m", totalDistance)
        }
    }
    
    /// Time until departure (negative if already departed)
    var timeUntilDeparture: TimeInterval {
        departureTime.timeIntervalSinceNow
    }
    
    /// Formatted departure guidance (e.g., "Leave now" or "Depart in 5 min")
    var departureGuidance: String {
        let seconds = Int(timeUntilDeparture)
        
        if seconds < 60 {
            return "Leave now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "Depart in \(minutes) min"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Depart at \(formatter.string(from: departureTime))"
        }
    }
    
    /// Formatted arrival time string
    var formattedArrivalTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalTime)
    }
    
    /// Whether this itinerary has transfers
    var hasTransfers: Bool {
        transferCount > 0
    }
    
    /// Display description for route chips (e.g., "WALK 5 min → 6 Bus • 14 min → WALK 3 min")
    var routeChipsDescription: String {
        segments.map { segment in
            switch segment {
            case .walk(_, _, let duration, _, _):
                let minutes = Int(duration / 60)
                return "WALK \(minutes) min"
            case .ride(_, _, let routeName, _, _, _, let duration, _, _):
                let minutes = Int(duration / 60)
                return "\(routeName) • \(minutes) min"
            }
        }.joined(separator: " → ")
    }
}

