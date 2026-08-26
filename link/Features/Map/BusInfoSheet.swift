import SwiftUI

/// A live vehicle sheet organized around the rider's next decision: where the
/// bus is going, its next stop, and the remaining stop sequence.
struct BusInfoSheet: View {
    let bus: EnrichedVehicle
    let busInfo: BusInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(FavoriteStore.self) private var favoriteStore
    @State private var showsAllStops = false

    private var visibleStops: [BusInfo.StopInfo] {
        showsAllStops ? busInfo.upcomingStops : Array(busInfo.upcomingStops.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    nextStopCard

                    if !busInfo.upcomingStops.isEmpty {
                        upcomingStops
                    }

                    freshness
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color("Background"))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { favoriteButton }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Close bus details")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            RouteIdentityBadge(
                shortName: bus.routeShortName,
                colorHex: bus.route?.route_color
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("To \(busInfo.destination)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Bus \(busInfo.vehicleId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Vehicle \(busInfo.vehicleId)")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var nextStopCard: some View {
        if let stop = busInfo.currentStop {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            busInfo.atStop ? "At stop" : "Next stop",
                            systemImage: busInfo.atStop ? "bus.fill" : "mappin.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(bus.routeColor)

                        Spacer()

                        if let delay = delayText {
                            Text(delay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(stop.name)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if busInfo.atStop {
                        Text("Now")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(bus.routeColor)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(stop.effectiveArrival, format: .dateTime.hour().minute())
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                            Spacer()
                            Text(relativeETA(to: stop.effectiveArrival, now: context.date))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if busInfo.totalStopCount > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: completedProgress)
                                .tint(bus.routeColor)
                            Text(remainingStopsText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .appSheetCard()
                .accessibilityElement(children: .combine)
            }
        } else {
            ContentUnavailableView(
                "Stop progress unavailable",
                systemImage: "location.slash",
                description: Text("The vehicle is visible, but its trip progress is not in the current feed.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var upcomingStops: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming stops")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                ForEach(Array(visibleStops.enumerated()), id: \.element.id) { index, stop in
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        UpcomingBusStopRow(
                            stop: stop,
                            now: context.date,
                            tint: bus.routeColor,
                            isLast: index == visibleStops.count - 1
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .appSheetCard()

            if busInfo.upcomingStops.count > 5 {
                Button(showsAllStops ? "Show fewer stops" : "Show all \(busInfo.upcomingStops.count) stops") {
                    withAnimation(.easeInOut(duration: 0.2)) { showsAllStops.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("PrimaryAccent"))
            }
        }
    }

    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Vehicle updated")
                Text(busInfo.lastUpdated, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var favoriteButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await favoriteStore.toggleRouteFavorite(
                    routeId: bus.vehicle.routeId,
                    name: "Route \(bus.routeShortName)",
                    routeColor: bus.route?.route_color
                )
            }
        } label: {
            Image(systemName: favoriteStore.isRouteFavorited(bus.vehicle.routeId) ? "heart.fill" : "heart")
                .foregroundStyle(favoriteStore.isRouteFavorited(bus.vehicle.routeId) ? Color("AlertRed") : .secondary)
        }
        .accessibilityLabel(favoriteStore.isRouteFavorited(bus.vehicle.routeId) ? "Remove route from favorites" : "Add route to favorites")
    }

    private var delayText: String? {
        guard let delay = busInfo.delayMinutes else { return nil }
        if delay >= 1 { return "\(delay) min late" }
        if delay <= -1 { return "\(-delay) min early" }
        return "On time"
    }

    private var completedProgress: Double {
        guard busInfo.totalStopCount > 1 else { return 0 }
        let completed = busInfo.totalStopCount - busInfo.remainingStopCount
        return Double(completed) / Double(busInfo.totalStopCount - 1)
    }

    private var remainingStopsText: String {
        let count = busInfo.remainingStopCount
        return count == 1 ? "Final stop" : "\(count) stops remaining"
    }

    private func relativeETA(to date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < -60 { return "Timing unavailable" }
        if seconds < 60 { return "<1 min" }
        return "\(max(1, Int(ceil(seconds / 60)))) min"
    }
}

private struct UpcomingBusStopRow: View {
    let stop: BusInfo.StopInfo
    let now: Date
    let tint: Color
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle().fill(tint).frame(width: 8, height: 8)
                if !isLast {
                    Rectangle().fill(Color("PrimaryAccent").opacity(0.18)).frame(width: 2, height: 34)
                }
            }
            .padding(.top, 7)

            Text(stop.name)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(stop.effectiveArrival, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(relativeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 11)
        .accessibilityElement(children: .combine)
    }

    private var relativeText: String {
        let seconds = stop.effectiveArrival.timeIntervalSince(now)
        if seconds < -60, stop.predictedArrival == nil { return "Timing unavailable" }
        if seconds < 60 { return "<1 min" }
        return "\(max(1, Int(ceil(seconds / 60)))) min"
    }
}

struct BusInfo {
    let vehicleId: String
    let destination: String
    let currentStop: StopInfo?
    let atStop: Bool
    let delayMinutes: Int?
    let upcomingStops: [StopInfo]
    let remainingStopCount: Int
    let totalStopCount: Int
    let lastUpdated: Date
    let isRealtimeProgress: Bool

    struct StopInfo: Identifiable {
        let name: String
        let sequence: Int
        let scheduledArrival: Date
        let predictedArrival: Date?

        var id: Int { sequence }
        var effectiveArrival: Date { predictedArrival ?? scheduledArrival }
    }
}

#Preview {
    let now = Date()
    let vehicle = Vehicle(
        id: "2494",
        routeId: "6",
        tripId: "trip123",
        routeName: "6",
        latitude: 39.166595,
        longitude: -86.542137,
        heading: 45,
        speed: 8,
        currentStopSequence: 4,
        currentStatus: .inTransitTo,
        lastUpdated: now
    )
    let route = Route(route_id: "6", route_short_name: "6", route_long_name: "Campus Loop", route_color: "EC0E0E")
    let current = BusInfo.StopInfo(name: "Kirkwood Ave & Indiana Ave", sequence: 4, scheduledArrival: now.addingTimeInterval(240), predictedArrival: now.addingTimeInterval(300))
    let info = BusInfo(
        vehicleId: "2494",
        destination: "Downtown via Kirkwood",
        currentStop: current,
        atStop: false,
        delayMinutes: 1,
        upcomingStops: [
            .init(name: "Indiana Memorial Union", sequence: 5, scheduledArrival: now.addingTimeInterval(600), predictedArrival: nil),
            .init(name: "Sample Gates", sequence: 6, scheduledArrival: now.addingTimeInterval(900), predictedArrival: nil)
        ],
        remainingStopCount: 3,
        totalStopCount: 10,
        lastUpdated: now,
        isRealtimeProgress: true
    )
    BusInfoSheet(bus: EnrichedVehicle(vehicle: vehicle, route: route), busInfo: info)
}
