import Foundation
import CoreLocation

/// Represents a segment of a trip itinerary (walking or riding)
enum TripSegment: Identifiable, Hashable, Codable {
    case walk(
        id: UUID,
        distance: Double,
        duration: TimeInterval,
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    )
    case ride(
        id: UUID,
        routeId: String,
        routeName: String,
        routeColor: String?,
        fromStop: Stop,
        toStop: Stop,
        duration: TimeInterval,
        waitTime: TimeInterval,
        tripId: String?
    )
    
    /// Unique identifier for this segment
    var id: UUID {
        switch self {
        case .walk(let id, _, _, _, _):
            return id
        case .ride(let id, _, _, _, _, _, _, _, _):
            return id
        }
    }
    
    /// Duration of this segment in seconds
    var duration: TimeInterval {
        switch self {
        case .walk(_, _, let duration, _, _):
            return duration
        case .ride(_, _, _, _, _, _, let duration, _, _):
            return duration
        }
    }
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .walk(_, _, let duration, _, _):
            let minutes = Int(duration / 60)
            return "Walk \(minutes) min"
        case .ride(_, _, let routeName, _, _, _, _, _, _):
            return routeName
        }
    }
    
    /// Type of segment
    var segmentType: SegmentType {
        switch self {
        case .walk:
            return .walk
        case .ride:
            return .ride
        }
    }
    
    /// Custom Codable implementation
    enum CodingKeys: String, CodingKey {
        case type, id, distance, duration, fromLat, fromLon, toLat, toLon
        case routeId, routeName, routeColor, fromStop, toStop, waitTime, tripId
    }
    
    enum SegmentType: String, Codable {
        case walk, ride
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SegmentType.self, forKey: .type)
        let id = try container.decode(UUID.self, forKey: .id)
        
        switch type {
        case .walk:
            let distance = try container.decode(Double.self, forKey: .distance)
            let duration = try container.decode(TimeInterval.self, forKey: .duration)
            let fromLat = try container.decode(Double.self, forKey: .fromLat)
            let fromLon = try container.decode(Double.self, forKey: .fromLon)
            let toLat = try container.decode(Double.self, forKey: .toLat)
            let toLon = try container.decode(Double.self, forKey: .toLon)
            let from = CLLocationCoordinate2D(latitude: fromLat, longitude: fromLon)
            let to = CLLocationCoordinate2D(latitude: toLat, longitude: toLon)
            self = .walk(id: id, distance: distance, duration: duration, from: from, to: to)
            
        case .ride:
            let routeId = try container.decode(String.self, forKey: .routeId)
            let routeName = try container.decode(String.self, forKey: .routeName)
            let routeColor = try container.decodeIfPresent(String.self, forKey: .routeColor)
            let fromStop = try container.decode(Stop.self, forKey: .fromStop)
            let toStop = try container.decode(Stop.self, forKey: .toStop)
            let duration = try container.decode(TimeInterval.self, forKey: .duration)
            let waitTime = try container.decode(TimeInterval.self, forKey: .waitTime)
            let tripId = try container.decodeIfPresent(String.self, forKey: .tripId)
            self = .ride(
                id: id,
                routeId: routeId,
                routeName: routeName,
                routeColor: routeColor,
                fromStop: fromStop,
                toStop: toStop,
                duration: duration,
                waitTime: waitTime,
                tripId: tripId
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        
        switch self {
        case .walk(_, let distance, let duration, let from, let to):
            try container.encode(SegmentType.walk, forKey: .type)
            try container.encode(distance, forKey: .distance)
            try container.encode(duration, forKey: .duration)
            try container.encode(from.latitude, forKey: .fromLat)
            try container.encode(from.longitude, forKey: .fromLon)
            try container.encode(to.latitude, forKey: .toLat)
            try container.encode(to.longitude, forKey: .toLon)
            
        case .ride(_, let routeId, let routeName, let routeColor, let fromStop, let toStop, let duration, let waitTime, let tripId):
            try container.encode(SegmentType.ride, forKey: .type)
            try container.encode(routeId, forKey: .routeId)
            try container.encode(routeName, forKey: .routeName)
            try container.encodeIfPresent(routeColor, forKey: .routeColor)
            try container.encode(fromStop, forKey: .fromStop)
            try container.encode(toStop, forKey: .toStop)
            try container.encode(duration, forKey: .duration)
            try container.encode(waitTime, forKey: .waitTime)
            try container.encodeIfPresent(tripId, forKey: .tripId)
        }
    }
    
    // MARK: - Hashable Conformance
    
    static func == (lhs: TripSegment, rhs: TripSegment) -> Bool {
        switch (lhs, rhs) {
        case (.walk(let lhsId, let lhsDistance, let lhsDuration, let lhsFrom, let lhsTo),
              .walk(let rhsId, let rhsDistance, let rhsDuration, let rhsFrom, let rhsTo)):
            return lhsId == rhsId &&
                   lhsDistance == rhsDistance &&
                   lhsDuration == rhsDuration &&
                   lhsFrom.latitude == rhsFrom.latitude &&
                   lhsFrom.longitude == rhsFrom.longitude &&
                   lhsTo.latitude == rhsTo.latitude &&
                   lhsTo.longitude == rhsTo.longitude
            
        case (.ride(let lhsId, let lhsRouteId, let lhsRouteName, let lhsRouteColor, let lhsFromStop, let lhsToStop, let lhsDuration, let lhsWaitTime, let lhsTripId),
              .ride(let rhsId, let rhsRouteId, let rhsRouteName, let rhsRouteColor, let rhsFromStop, let rhsToStop, let rhsDuration, let rhsWaitTime, let rhsTripId)):
            return lhsId == rhsId &&
                   lhsRouteId == rhsRouteId &&
                   lhsRouteName == rhsRouteName &&
                   lhsRouteColor == rhsRouteColor &&
                   lhsFromStop == rhsFromStop &&
                   lhsToStop == rhsToStop &&
                   lhsDuration == rhsDuration &&
                   lhsWaitTime == rhsWaitTime &&
                   lhsTripId == rhsTripId
            
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .walk(let id, let distance, let duration, let from, let to):
            hasher.combine(0) // Case discriminator for .walk
            hasher.combine(id)
            hasher.combine(distance)
            hasher.combine(duration)
            hasher.combine(from.latitude)
            hasher.combine(from.longitude)
            hasher.combine(to.latitude)
            hasher.combine(to.longitude)
            
        case .ride(let id, let routeId, let routeName, let routeColor, let fromStop, let toStop, let duration, let waitTime, let tripId):
            hasher.combine(1) // Case discriminator for .ride
            hasher.combine(id)
            hasher.combine(routeId)
            hasher.combine(routeName)
            hasher.combine(routeColor)
            hasher.combine(fromStop)
            hasher.combine(toStop)
            hasher.combine(duration)
            hasher.combine(waitTime)
            hasher.combine(tripId)
        }
    }
}

