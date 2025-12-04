import Foundation

final class StaticDataService {
    static let shared = StaticDataService()
    
    private init() {}
    
    private func loadJSON<T: Decodable>(_ filename: String) -> [T] {
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
    private func loadStopTimesData(_ filename: String) -> StopTimesData {
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
    
    // MARK: - Public Accessors
    
    func loadRoutes() -> [Route] {
        loadJSON("routes")
    }
    
    func loadShapes() -> [Shape] {
        loadJSON("shapes")
    }
    
    func loadTrips() -> [Trip] {
        loadJSON("trips")
    }
    
    func loadStops() -> [Stop] {
        loadJSON("stops_optimized")
    }
    
    func loadStopTimes() -> StopTimesData {
        loadStopTimesData("stop_times_optimized")
    }
    
    func loadRouteServiceHours() -> [RouteServiceHours] {
        loadJSON("route_service_hours")
    }
}