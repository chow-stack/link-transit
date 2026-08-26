import SwiftUI

struct StopDetailsSheet: View {
    let stop: Stop
    let arrivals: [Arrival]
    let servingRoutes: [Route]
    let schedule: [StopScheduleRoute]
    let hasRealtimeFeed: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(FavoriteStore.self) private var favoriteStore
    @Environment(NotificationService.self) private var notificationService
    @Environment(MapAppPreference.self) private var mapAppPreference
    @State private var showingNotificationConfig = false
    @State private var choosingMapApp = false

    init(
        stop: Stop,
        arrivals: [Arrival],
        servingRoutes: [Route],
        schedule: [StopScheduleRoute] = [],
        hasRealtimeFeed: Bool = false
    ) {
        self.stop = stop
        self.arrivals = arrivals.sorted { $0.arrivalTime < $1.arrivalTime }
        self.servingRoutes = servingRoutes
        self.schedule = schedule
        self.hasRealtimeFeed = hasRealtimeFeed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    stopHeader
                    actionButtons
                    arrivalsHeader

                    if arrivals.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(arrivals) { arrival in
                                StopArrivalRow(arrival: arrival)
                                if arrival.id != arrivals.last?.id {
                                    Divider()
                                        .overlay(Color("PrimaryAccent").opacity(0.08))
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .appSheetCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color("Background"))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        favoriteButton
                        Button {
                            showingNotificationConfig = true
                        } label: {
                            Image(systemName: notificationService.hasNotification(for: stop.id) ? "bell.fill" : "bell")
                                .foregroundStyle(notificationService.hasNotification(for: stop.id) ? Color("PrimaryAccent") : .secondary)
                        }
                        .accessibilityLabel(notificationService.hasNotification(for: stop.id) ? "Edit arrival alert" : "Create arrival alert")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Close stop details")
                }
            }
            .navigationDestination(for: StopScheduleDestinationLink.self) { _ in
                TodayStopScheduleView(stopName: stop.name, routes: schedule)
            }
            .sheet(isPresented: $showingNotificationConfig) {
                StopNotificationConfigSheet(stop: stop, servingRoutes: servingRoutes)
            }
            .confirmationDialog("Choose a map app", isPresented: $choosingMapApp, titleVisibility: .visible) {
                Button("Apple Maps") { openDirections(in: .appleMaps) }
                Button("Google Maps") { openDirections(in: .googleMaps) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your choice becomes the preferred app. You can change it in Settings.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var stopHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stop.name)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            if !servingRoutes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(servingRoutes) { route in
                            RouteIdentityBadge(shortName: route.route_short_name, colorHex: route.route_color, compact: true)
                        }
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                if mapAppPreference.selectedApp == .ask {
                    choosingMapApp = true
                } else {
                    TransitDirectionsService.open(stop: stop, in: mapAppPreference.selectedApp)
                }
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("PrimaryAccent"))

            NavigationLink(value: StopScheduleDestinationLink()) {
                Label("Full schedule", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color("PrimaryAccent"))
        }
        .font(.subheadline.weight(.semibold))
        .controlSize(.regular)
    }

    private var arrivalsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Arrivals today")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Label(
                hasRealtimeFeed ? "Live + schedule" : "Published schedule",
                systemImage: hasRealtimeFeed ? "dot.radiowaves.left.and.right" : "calendar"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No more arrivals today",
            systemImage: "moon.stars",
            description: Text("Open the full schedule to see all published times for today's service.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var favoriteButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await favoriteStore.toggleStopFavorite(stopId: stop.id, name: stop.name) }
        } label: {
            Image(systemName: favoriteStore.isStopFavorited(stop.id) ? "heart.fill" : "heart")
                .foregroundStyle(favoriteStore.isStopFavorited(stop.id) ? Color("AlertRed") : .secondary)
        }
        .accessibilityLabel(favoriteStore.isStopFavorited(stop.id) ? "Remove stop from favorites" : "Add stop to favorites")
    }

    private func openDirections(in app: PreferredMapApp) {
        mapAppPreference.selectedApp = app
        TransitDirectionsService.open(stop: stop, in: app)
    }
}

private struct StopScheduleDestinationLink: Hashable {}

private struct StopArrivalRow: View {
    let arrival: Arrival

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                RouteIdentityBadge(
                    shortName: arrival.routeShortName,
                    colorHex: arrival.routeColor,
                    compact: true
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(arrival.destinationDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if let vehicleId = arrival.vehicleId, !vehicleId.isEmpty {
                        Text("Bus \(vehicleId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(arrival.arrivalTime, format: .dateTime.hour().minute())
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                    Text(relativeETA(now: context.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(now: context.date))
        }
    }

    private func relativeETA(now: Date) -> String {
        let seconds = arrival.arrivalTime.timeIntervalSince(now)
        if seconds < 60 { return "<1 min" }
        return "\(max(1, Int(ceil(seconds / 60)))) min"
    }

    private func accessibilityText(now: Date) -> String {
        let bus = arrival.vehicleId.map { ", bus \($0)" } ?? ""
        return "Route \(arrival.routeShortName) to \(arrival.destinationDisplayName)\(bus), arriving at \(arrival.arrivalTime.formatted(date: .omitted, time: .shortened)), \(relativeETA(now: now))"
    }
}

private struct TodayStopScheduleView: View {
    let stopName: String
    let routes: [StopScheduleRoute]
    @State private var selectedRouteId: String

    init(stopName: String, routes: [StopScheduleRoute]) {
        self.stopName = stopName
        self.routes = routes
        _selectedRouteId = State(initialValue: routes.first?.id ?? "")
    }

    private var selectedRoute: StopScheduleRoute? {
        routes.first(where: { $0.id == selectedRouteId }) ?? routes.first
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "No service today",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("There are no published trips at this stop for today's service calendar.")
                    )
                    .padding(.top, 48)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        routeSelector
                        if let route = selectedRoute {
                            ForEach(route.destinations) { destination in
                                destinationSection(destination, route: route, now: context.date)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color("Background"))
        .navigationTitle("Today's schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var routeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if routes.count > 1 {
                Text("Select a route")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(routes) { route in
                        routeSelectorChip(for: route)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, -4)
        }
    }

    private func routeSelectorChip(for route: StopScheduleRoute) -> some View {
        let isSelected = selectedRouteId == route.id
        let tint = route.colorHex.map(Color.init(hex:)) ?? Color("PrimaryAccent")

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedRouteId = route.id
            }
        } label: {
            VStack(spacing: 6) {
                RouteIdentityBadge(shortName: route.shortName, colorHex: route.colorHex, compact: true)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? tint : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
                    }
                    .opacity(isSelected ? 1 : 0.5)
                    .scaleEffect(isSelected ? 1.08 : 1.0)

                Capsule()
                    .fill(isSelected ? tint : Color.clear)
                    .frame(width: 16, height: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route \(route.shortName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "" : "Double tap to show this route's schedule")
    }

    private func destinationSection(
        _ destination: StopScheduleDestination,
        route: StopScheduleRoute,
        now: Date
    ) -> some View {
        let nextId = destination.times.first(where: { $0.date >= now })?.id
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("To \(destination.name)")
                    .font(.headline)
                Text("\(destination.times.count) published times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(destination.times) { time in
                    ScheduleTimeCell(
                        time: time,
                        isNext: time.id == nextId,
                        tint: route.colorHex.map(Color.init(hex:)) ?? Color("PrimaryAccent"),
                        now: now
                    )
                }
            }
        }
        .padding(14)
        .appSheetCard()
    }
}

private struct ScheduleTimeCell: View {
    let time: StopScheduleTime
    let isNext: Bool
    let tint: Color
    let now: Date

    var body: some View {
        VStack(spacing: 2) {
            Text(time.date, format: .dateTime.hour().minute())
                .font(.subheadline.weight(isNext ? .bold : .medium))
                .monospacedDigit()
            if time.isNextCalendarDay {
                Text("Next day")
                    .font(.caption2)
            }
        }
        .foregroundStyle(time.date < now ? .secondary : .primary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isNext ? tint.opacity(0.18) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isNext {
                RoundedRectangle(cornerRadius: 10).stroke(tint, lineWidth: 1.5)
            }
        }
        .accessibilityLabel("\(time.date.formatted(date: .omitted, time: .shortened))\(time.isNextCalendarDay ? ", next day" : "")\(isNext ? ", next departure" : "")")
    }
}

/// Loader used by favorite/notification entry points outside the map.
struct StopDetailsSheetLoaderSimple: View {
    let stop: Stop
    let servingRoutes: [Route]
    @Environment(DataSyncService.self) private var dataSyncService
    @State private var arrivals: [Arrival] = []
    @State private var schedule: [StopScheduleRoute] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if !hasLoaded {
                StopLoadingView(stopName: stop.name)
            } else {
                StopDetailsSheet(
                    stop: stop,
                    arrivals: arrivals,
                    servingRoutes: servingRoutes,
                    schedule: schedule,
                    hasRealtimeFeed: dataSyncService.tripUpdatesGeneration != nil
                )
            }
        }
        .task(id: dataSyncService.tripUpdatesGeneration) {
            arrivals = await dataSyncService.stopTimesService.getUpcomingArrivals(for: stop.id, maxArrivals: 10)
            schedule = dataSyncService.stopTimesService.getTodaySchedule(for: stop.id)
            withAnimation(.easeInOut(duration: 0.2)) { hasLoaded = true }
        }
    }
}

#Preview {
    let stop = Stop(id: 45121, name: "Kirkwood Ave & Indiana Ave", lat: 39.166595, lon: -86.542137)
    let route = Route(route_id: "6", route_short_name: "6", route_long_name: "Campus Loop", route_color: "EC0E0E")
    let now = Date()
    return StopDetailsSheet(
        stop: stop,
        arrivals: [Arrival(
            id: "1",
            stopId: stop.id,
            tripId: "trip1",
            routeId: route.id,
            routeShortName: route.route_short_name,
            routeColor: route.route_color,
            tripHeadsign: "Downtown via Kirkwood",
            arrivalTime: now.addingTimeInterval(420),
            scheduledTime: "20:43:00",
            isRealtime: true,
            vehicleId: "2494"
        )],
        servingRoutes: [route],
        hasRealtimeFeed: true
    )
}
