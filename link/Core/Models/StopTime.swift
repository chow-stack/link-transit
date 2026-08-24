import Foundation

/// Represents a stop time entry from stop_times_optimized.json
/// The JSON structure is: {"tripId": [{"s": stopId, "a": "HH:mm:ss"}, ...]}
struct StopTimeEntry: Codable, Sendable {
    let s: Int  // stop_id
    let a: String  // arrival_time in "HH:mm:ss" format
}

/// Container for all stop times, organized by trip ID
/// This matches the JSON structure: { "tripId": [StopTimeEntry, ...], ... }
typealias StopTimesData = [String: [StopTimeEntry]]
