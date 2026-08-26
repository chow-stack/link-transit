import Foundation

/// A scheduled departure for the selected GTFS service day.
struct StopScheduleTime: Identifiable, Hashable, Sendable {
    let id: String
    let tripId: String
    let date: Date
    let rawTime: String
    let isNextCalendarDay: Bool
}

struct StopScheduleDestination: Identifiable, Sendable {
    let id: String
    let name: String
    let times: [StopScheduleTime]
}

struct StopScheduleRoute: Identifiable, Sendable {
    let id: String
    let shortName: String
    let longName: String
    let colorHex: String?
    let destinations: [StopScheduleDestination]
}

/// A stop in a trip, preserving the source GTFS sequence and schedule.
struct TripStopSchedule: Sendable {
    let stopId: Int
    let sequence: Int
    let rawArrivalTime: String
    let scheduledArrival: Date
}
