import SwiftUI

/// Sheet for configuring notifications on a specific stop
struct StopNotificationConfigSheet: View {
    let stop: Stop
    let servingRoutes: [Route]
    
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationService.self) private var notificationService
    @Environment(DataSyncService.self) private var dataSyncService
    
    @State private var selectedRoutes: Set<String> = []
    @State private var advanceMinutes: Int = 5
    @State private var arrivals: [Arrival] = []
    @State private var isLoadingArrivals = false
    @State private var isSaving = false
    @State private var showingPermissionAlert = false
    
    private var existingPreference: StopNotification? {
        notificationService.getNotificationPreference(for: stop.id)
    }
    
    private var hasPermission: Bool {
        notificationService.canScheduleNotifications
    }
    
    private var canSave: Bool {
        !selectedRoutes.isEmpty && !isSaving
    }
    
    // Discrete timing options
    private let timingOptions = [1, 2, 3, 5, 10, 15, 20, 25, 30]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stop header
                    stopHeader
                    
                    // Permission banner (if needed)
                    if !hasPermission {
                        permissionBanner
                    }
                    
                    // Live arrivals section
                    liveArrivalsSection
                    
                    // Route selection
                    routeSelectionSection
                    
                    // Timing selection
                    timingSection
                    
                    // Save button
                    saveButton
                    
                    // Delete button (if preference exists)
                    if existingPreference != nil {
                        deleteButton
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Close notification settings")
                }
            }
        }
        .background(Color("Background"))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadExistingPreference()
            loadArrivals()
        }
        .alert("Notifications Are Off", isPresented: $showingPermissionAlert) {
            Button("Not Now", role: .cancel) { }
            Button("Open Settings") {
                openAppSettings()
            }
        } message: {
            Text("Allow notifications in Settings, then return to Link to save this arrival alert.")
        }
    }
    
    // MARK: - UI Components
    
    private var stopHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.largeTitle)
                .foregroundStyle(Color("PrimaryAccent"))

            Text(stop.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("Get notified before your bus arrives")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: notificationService.authorizationStatus == .notDetermined ? "bell.badge.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(notificationService.authorizationStatus == .notDetermined ? Color("PrimaryAccent") : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(notificationService.authorizationStatus == .notDetermined ? "Ready when you are" : "Permission required")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(notificationService.authorizationStatus == .notDetermined
                     ? "Link will ask for permission when you save this alert."
                     : "Enable notifications in Settings to receive alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if notificationService.authorizationStatus == .denied {
                Button("Settings") {
                    openAppSettings()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("PrimaryAccent"))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(notificationService.authorizationStatus == .notDetermined
                      ? Color("PrimaryAccent").opacity(0.08)
                      : Color.orange.opacity(0.1))
        )
    }

    private var liveArrivalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("PrimaryAccent"))

                Text("Live Arrivals")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            if isLoadingArrivals {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading arrivals…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            } else if arrivals.isEmpty {
                Text("No active buses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(arrivals.prefix(5)) { arrival in
                        ArrivalRow(arrival: arrival)
                    }
                }
            }
        }
        .padding(20)
        .appSheetCard(cornerRadius: 16)
    }

    private var routeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "bus.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("PrimaryAccent"))

                Text("Select Routes")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            if servingRoutes.isEmpty {
                Text("No routes available for this stop")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(servingRoutes) { route in
                        RouteSelectionRow(
                            route: route,
                            isSelected: selectedRoutes.contains(route.route_id),
                            onToggle: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    if selectedRoutes.contains(route.route_id) {
                                        selectedRoutes.remove(route.route_id)
                                    } else {
                                        selectedRoutes.insert(route.route_id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("PrimaryAccent"))

                Text("Notification Timing")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 20) {
                // Large display of selected time
                VStack(spacing: 4) {
                    Text("\(advanceMinutes)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryAccent"))
                        .monospacedDigit()

                    Text(advanceMinutes == 1 ? "minute before" : "minutes before")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                // Discrete slider with snap-to steps
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(timingOptions.firstIndex(of: advanceMinutes) ?? 0) },
                            set: { newValue in
                                let index = Int(newValue.rounded())
                                if index >= 0 && index < timingOptions.count {
                                    advanceMinutes = timingOptions[index]
                                }
                            }
                        ),
                        in: 0...Double(timingOptions.count - 1),
                        step: 1
                    )
                    .tint(Color("PrimaryAccent"))

                    // Labels showing min and max
                    HStack {
                        Text("1m")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("30m")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .appSheetCard(cornerRadius: 16)
    }

    private var saveButton: some View {
        Button {
            Task {
                await saveAlert()
            }
        } label: {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isSaving ? "Saving…" : "Save Arrival Alert")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("PrimaryAccent"))
        .controlSize(.large)
        .disabled(!canSave)
    }

    private var deleteButton: some View {
        Button {
            Task {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                await notificationService.removeNotificationPreference(for: stop.id)
                dismiss()
            }
        } label: {
            HStack {
                Image(systemName: "trash.fill")
                Text("Delete Notification")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color("AlertRed"))
        .controlSize(.large)
    }
    
    // MARK: - Helper Methods
    
    private func loadExistingPreference() {
        if let preference = existingPreference {
            selectedRoutes = preference.enabledRouteIds
            advanceMinutes = preference.advanceMinutes
        } else {
            // Default to all routes selected
            selectedRoutes = Set(servingRoutes.map { $0.route_id })
            advanceMinutes = notificationService.defaultAdvanceMinutes
        }
    }
    
    private func loadArrivals() {
        Task {
            isLoadingArrivals = true
            arrivals = await dataSyncService.stopTimesService.getUpcomingArrivals(
                for: stop.id,
                maxArrivals: 5
            )
            isLoadingArrivals = false
        }
    }

    private func saveAlert() async {
        isSaving = true
        defer { isSaving = false }

        if !notificationService.canScheduleNotifications {
            let granted = await notificationService.requestPermission()
            guard granted else {
                showingPermissionAlert = true
                return
            }
        }

        // Saving an alert is an explicit opt-in, including after the in-app
        // global switch was previously turned off.
        notificationService.notificationsEnabled = true
        await notificationService.saveNotificationPreference(
            stopId: stop.id,
            stopName: stop.name,
            enabledRouteIds: selectedRoutes,
            advanceMinutes: advanceMinutes
        )

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Supporting Components

/// Individual arrival row in the live arrivals section
struct ArrivalRow: View {
    let arrival: Arrival
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 12) {
                RouteIdentityBadge(
                    shortName: arrival.routeShortName,
                    colorHex: arrival.routeColor,
                    compact: true
                )
            
                VStack(alignment: .leading, spacing: 2) {
                    Text(arrival.destinationDisplayName)
                        .font(.subheadline.weight(.medium))

                    if let vehicleId = arrival.vehicleId {
                        Text("Bus \(vehicleId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            
                Spacer()
            
                VStack(alignment: .trailing, spacing: 2) {
                    Text(arrival.arrivalTime, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    Text(relativeETA(now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .appSheetCard(cornerRadius: 10)
            .accessibilityElement(children: .combine)
        }
    }

    private func relativeETA(now: Date) -> String {
        let seconds = arrival.arrivalTime.timeIntervalSince(now)
        if seconds < 60 { return "<1 min" }
        return "\(max(1, Int(ceil(seconds / 60)))) min"
    }
}

/// Clean, Apple-style route selection row
struct RouteSelectionRow: View {
    let route: Route
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button { onToggle() } label: {
            HStack(spacing: 14) {
                RouteIdentityBadge(shortName: route.route_short_name, colorHex: route.route_color)

                // Route information
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route \(route.route_short_name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(route.route_long_name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color("PrimaryAccent") : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appSheetCard(cornerRadius: 12)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(routeColor.opacity(0.4), lineWidth: 1.5)
            }
        }
        .accessibilityLabel("Route \(route.route_short_name), \(route.route_long_name)")
        .accessibilityHint(isSelected ? "Double tap to stop notifying for this route" : "Double tap to notify for this route")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var routeColor: Color {
        if let hex = route.route_color, !hex.isEmpty {
            return Color(hex: hex)
        }
        return Color("PrimaryAccent")
    }
}

#Preview {
    // Sample stop
    let stop = Stop(
        id: 45121,
        name: "Kirkwood Ave & Maple St",
        lat: 39.166595,
        lon: -86.542137
    )
    
    // Sample serving routes
    let servingRoutes = [
        Route(route_id: "1", route_short_name: "6", route_long_name: "Campus Shuttle", route_color: "80471C"),
        Route(route_id: "2", route_short_name: "3E", route_long_name: "3 East College Mall", route_color: "0066CC"),
        Route(route_id: "3", route_short_name: "9", route_long_name: "IU Campus Express", route_color: "FF9900")
    ]
    
    return StopNotificationConfigSheet(stop: stop, servingRoutes: servingRoutes)
        .environment(NotificationService())
        .environment(DataSyncService())
}
