import Foundation

/// Service hours for a route by day of week
struct RouteServiceHours: Codable, Identifiable, Sendable {
    let route_id: String
    let service_hours: ServiceHours
    
    var id: String { route_id }
}

/// Service hours for each day of the week
struct ServiceHours: Codable, Sendable {
    let monday: DayHours?
    let tuesday: DayHours?
    let wednesday: DayHours?
    let thursday: DayHours?
    let friday: DayHours?
    let saturday: DayHours?
    let sunday: DayHours?
}

/// Service hours for a single day
struct DayHours: Codable, Sendable {
    let start: String  // "HH:mm" format (24-hour)
    let end: String    // "HH:mm" format (24-hour)
    
    /// Format time for display (e.g., "6:30 AM")
    func formattedStart() -> String {
        formatTime(start)
    }
    
    /// Format time for display (e.g., "9:35 PM")
    func formattedEnd() -> String {
        formatTime(end)
    }
    
    /// Format time string from "HH:mm" to "H:MM AM/PM"
    private func formatTime(_ time: String) -> String {
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return time
        }
        
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}
