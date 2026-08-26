import Foundation

/// Regular GTFS service availability from calendar.txt.
struct GTFSServiceCalendar: Codable, Sendable {
    let service_id: String
    let monday: Bool
    let tuesday: Bool
    let wednesday: Bool
    let thursday: Bool
    let friday: Bool
    let saturday: Bool
    let sunday: Bool
    let start_date: String
    let end_date: String
}

/// A date-specific GTFS service addition (1) or removal (2) from calendar_dates.txt.
struct GTFSServiceException: Codable, Sendable {
    let service_id: String
    let date: String
    let exception_type: Int
}

struct GTFSServiceCalendarData: Codable, Sendable {
    let calendars: [GTFSServiceCalendar]
    let exceptions: [GTFSServiceException]

    static let empty = GTFSServiceCalendarData(calendars: [], exceptions: [])
}
