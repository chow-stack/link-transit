import Foundation

/// Represents a bus arrival at a stop
struct Arrival: Identifiable, Hashable {
    let id: String
    let stopId: Int
    let tripId: String
    let routeId: String
    let routeShortName: String
    let routeColor: String?
    let tripHeadsign: String
    let arrivalTime: Date // Real-time predicted arrival or scheduled arrival
    let scheduledArrivalTime: Date
    let scheduledTime: String // "HH:mm:ss" format from GTFS
    let serviceDateKey: String
    let isRealtime: Bool // Whether this is a real-time prediction
    let vehicleId: String? // Individual bus/vehicle ID if available

    init(
        id: String,
        stopId: Int,
        tripId: String,
        routeId: String,
        routeShortName: String,
        routeColor: String?,
        tripHeadsign: String = "",
        arrivalTime: Date,
        scheduledArrivalTime: Date? = nil,
        scheduledTime: String,
        serviceDateKey: String = "",
        isRealtime: Bool,
        vehicleId: String?
    ) {
        self.id = id
        self.stopId = stopId
        self.tripId = tripId
        self.routeId = routeId
        self.routeShortName = routeShortName
        self.routeColor = routeColor
        self.tripHeadsign = tripHeadsign
        self.arrivalTime = arrivalTime
        self.scheduledArrivalTime = scheduledArrivalTime ?? arrivalTime
        self.scheduledTime = scheduledTime
        self.serviceDateKey = serviceDateKey
        self.isRealtime = isRealtime
        self.vehicleId = vehicleId
    }

    var destinationDisplayName: String {
        tripHeadsign.isEmpty ? "Route \(routeShortName)" : tripHeadsign
    }
}
