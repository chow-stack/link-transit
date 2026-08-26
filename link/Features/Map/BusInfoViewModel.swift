import CoreLocation
import Foundation

/// Builds presentation-ready vehicle progress from GTFS-RT first, using
/// geometry only when the feed does not identify a current stop.
@MainActor
struct BusInfoViewModel {
    private let stopTimesService: StopTimesService
    private let tripLookup: [String: Trip]
    private let stopLookup: [Int: Stop]
    private let tripUpdates: [String: TripUpdate]

    init(
        stopTimesService: StopTimesService,
        tripLookup: [String: Trip],
        stopLookup: [Int: Stop],
        firstTripByRouteId: [String: Trip],
        tripUpdates: [String: TripUpdate]? = nil
    ) {
        self.stopTimesService = stopTimesService
        self.tripLookup = tripLookup
        self.stopLookup = stopLookup
        self.tripUpdates = tripUpdates ?? [:]
        _ = firstTripByRouteId // Kept for source compatibility with MapViewModel.
    }

    func getBusInfo(for bus: EnrichedVehicle, now: Date = Date()) async -> BusInfo? {
        let vehicle = bus.vehicle
        guard !vehicle.tripId.isEmpty,
              let trip = tripLookup[vehicle.tripId] else {
            return unavailableInfo(for: bus)
        }

        let update = tripUpdates[vehicle.tripId]
        let sequence = stopTimesService.getTripStopSchedule(
            for: vehicle.tripId,
            serviceDateKey: update?.serviceDate ?? vehicle.serviceDateKey,
            now: now
        )
        guard !sequence.isEmpty else { return unavailableInfo(for: bus) }

        let progress = resolveProgress(
            vehicle: vehicle,
            sequence: sequence,
            tripUpdate: update,
            now: now
        )
        guard sequence.indices.contains(progress.index) else { return unavailableInfo(for: bus) }

        let stopInfos = sequence.enumerated().compactMap { index, entry -> BusInfo.StopInfo? in
            guard index >= progress.index, let stop = stopLookup[entry.stopId] else { return nil }
            let realtime = update?.stopTimeUpdates.first(where: {
                $0.stopId == entry.stopId && !$0.isSkipped
            })?.arrivalTime
            return BusInfo.StopInfo(
                name: stop.name,
                sequence: entry.sequence,
                scheduledArrival: entry.scheduledArrival,
                predictedArrival: realtime
            )
        }

        guard let current = stopInfos.first else { return unavailableInfo(for: bus) }
        let delayMinutes = current.predictedArrival.map {
            Int(($0.timeIntervalSince(current.scheduledArrival) / 60).rounded())
        }

        return BusInfo(
            vehicleId: vehicle.id,
            destination: trip.trip_headsign.isEmpty ? bus.routeLongName : trip.trip_headsign,
            currentStop: current,
            atStop: progress.atStop,
            delayMinutes: delayMinutes,
            upcomingStops: Array(stopInfos.dropFirst()),
            remainingStopCount: stopInfos.count,
            totalStopCount: sequence.count,
            lastUpdated: vehicle.lastUpdated,
            isRealtimeProgress: progress.isRealtime
        )
    }

    private func resolveProgress(
        vehicle: Vehicle,
        sequence: [TripStopSchedule],
        tripUpdate: TripUpdate?,
        now: Date
    ) -> (index: Int, atStop: Bool, isRealtime: Bool) {
        if let feedSequence = vehicle.currentStopSequence,
           let index = sequence.firstIndex(where: { $0.sequence == feedSequence }) {
            return (index, vehicle.currentStatus == .stoppedAt, true)
        }

        if let currentStopId = vehicle.currentStopId,
           let index = sequence.firstIndex(where: { $0.stopId == currentStopId }) {
            return (index, vehicle.currentStatus == .stoppedAt, true)
        }

        if let nextUpdate = tripUpdate?.stopTimeUpdates.first(where: {
            !$0.isSkipped && ($0.arrivalTime ?? .distantPast) >= now.addingTimeInterval(-300)
        }), let index = sequence.firstIndex(where: { $0.stopId == nextUpdate.stopId }) {
            return (index, false, true)
        }

        return geometryFallback(vehicle: vehicle, sequence: sequence)
    }

    private func geometryFallback(
        vehicle: Vehicle,
        sequence: [TripStopSchedule]
    ) -> (index: Int, atStop: Bool, isRealtime: Bool) {
        let vehicleLocation = CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude)
        let nearest = sequence.enumerated().compactMap { index, entry -> (Int, CLLocationDistance)? in
            guard let stop = stopLookup[entry.stopId] else { return nil }
            let location = CLLocation(latitude: stop.lat, longitude: stop.lon)
            return (index, vehicleLocation.distance(from: location))
        }.min { $0.1 < $1.1 }
        guard let nearest else { return (0, false, false) }
        return (nearest.0, nearest.1 <= 30, false)
    }

    private func unavailableInfo(for bus: EnrichedVehicle) -> BusInfo {
        BusInfo(
            vehicleId: bus.vehicle.id,
            destination: bus.routeLongName,
            currentStop: nil,
            atStop: false,
            delayMinutes: nil,
            upcomingStops: [],
            remainingStopCount: 0,
            totalStopCount: 0,
            lastUpdated: bus.vehicle.lastUpdated,
            isRealtimeProgress: false
        )
    }
}
