import Foundation

struct StaticDataSnapshot: Sendable {
    let routes: [Route]
    let shapes: [Shape]
    let trips: [Trip]
    let stops: [Stop]
    let stopTimes: StopTimesData
    let serviceCalendar: GTFSServiceCalendarData
    let routeServiceHours: [RouteServiceHours]
}

final class StaticDataService {
    static let shared = StaticDataService()
    
    private init() {}
    
    private static func loadJSON<T: Decodable>(_ filename: String) -> [T] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("❌ Missing \(filename).json in bundle.")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([T].self, from: data)
            return decoded
        } catch {
            print("❌ Failed to decode \(filename).json: \(error)")
            return []
        }
    }
    
    /// Load stop times from stop_times_optimized.json
    /// Returns dictionary mapping trip ID to array of stop time entries
    private static func loadStopTimesData(_ filename: String) -> StopTimesData {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("❌ Missing \(filename).json in bundle.")
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(StopTimesData.self, from: data)
            return decoded
        } catch {
            print("❌ Failed to decode \(filename).json: \(error)")
            return [:]
        }
    }

    private static func loadServiceCalendar(_ filename: String) -> GTFSServiceCalendarData {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("❌ Missing \(filename).json in bundle.")
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(GTFSServiceCalendarData.self, from: data)
        } catch {
            print("❌ Failed to decode \(filename).json: \(error)")
            return .empty
        }
    }
    
    /// Decode all bundled GTFS resources away from the main actor, then publish
    /// the completed value snapshot in one operation.
    func loadAll() async -> StaticDataSnapshot {
        await Task.detached(priority: .userInitiated) {
            StaticDataSnapshot(
                routes: Self.loadJSON("routes"),
                shapes: Self.loadJSON("shapes"),
                trips: Self.loadJSON("trips"),
                stops: Self.loadJSON("stops_optimized"),
                stopTimes: Self.loadStopTimesData("stop_times_optimized"),
                serviceCalendar: Self.loadServiceCalendar("service_calendar"),
                routeServiceHours: Self.loadJSON("route_service_hours")
            )
        }.value
    }
}
