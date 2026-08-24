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
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
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
        VStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color("PrimaryAccent"))
            
            Text(stop.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            
            Text("Get notified before your bus arrives")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: notificationService.authorizationStatus == .notDetermined ? "bell.badge.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(notificationService.authorizationStatus == .notDetermined ? Color("PrimaryAccent") : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(notificationService.authorizationStatus == .notDetermined ? "Ready When You Are" : "Permission Required")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(notificationService.authorizationStatus == .notDetermined
                     ? "Link will ask for permission when you save this alert."
                     : "Enable notifications in Settings to receive alerts.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if notificationService.authorizationStatus == .denied {
                Button("Settings") {
                    openAppSettings()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color("PrimaryAccent"))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(notificationService.authorizationStatus == .notDetermined
                      ? Color("PrimaryAccent").opacity(0.08)
                      : Color.orange.opacity(0.1))
        )
    }
    
    private var liveArrivalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                
                Text("Live Arrivals")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            if isLoadingArrivals {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading arrivals...")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            } else if arrivals.isEmpty {
                Text("No active buses")
                    .font(.system(size: 14))
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.3))
        )
    }
    
    private var routeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color("PrimaryAccent"))
                
                Text("Select Routes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            if servingRoutes.isEmpty {
                Text("No routes available for this stop")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(servingRoutes.enumerated()), id: \.element.id) { index, route in
                        RouteSelectionRow(
                            route: route,
                            isSelected: selectedRoutes.contains(route.route_id),
                            isFirst: index == 0,
                            isLast: index == servingRoutes.count - 1,
                            onToggle: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
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
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "timer.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color("PrimaryAccent"))
                
                Text("Notification Timing")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            VStack(spacing: 20) {
                // Large display of selected time
                VStack(spacing: 4) {
                    Text("\(advanceMinutes)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(advanceMinutes == 1 ? "minute before" : "minutes before")
                        .font(.system(size: 15))
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
                    .tint(.blue)
                    
                    // Labels showing min and max
                    HStack {
                        Text("1m")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("30m")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.3))
        )
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
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(isSaving ? "Saving…" : "Save Arrival Alert")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(canSave ? Color("PrimaryAccent") : Color.gray.opacity(0.3))
            )
        }
        .disabled(!canSave)
        .buttonStyle(.plain)
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
                    .font(.system(size: 16, weight: .semibold))
                Text("Delete Notification")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color("AlertRed"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("AlertRed").opacity(0.1))
            )
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 12) {
            // Route color circle
            Circle()
                .fill(arrival.routeColor != nil ? Color(hex: arrival.routeColor!) : Color("PrimaryAccent"))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(arrival.routeShortName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Route \(arrival.routeShortName)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text(arrival.isRealtime ? "Live" : "Scheduled")
                    .font(.system(size: 12))
                    .foregroundStyle(arrival.isRealtime ? .green : .secondary)
            }
            
            Spacer()
            
            // ETA
            VStack(alignment: .trailing, spacing: 2) {
                Text(arrival.formattedTime)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(timeColor)
                
                if let badge = arrival.statusBadge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(badgeColor.opacity(0.15))
                        )
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground).opacity(0.5))
        )
    }
    
    private var timeColor: Color {
        if arrival.isArriving {
            return .green
        } else {
            return .primary
        }
    }
    
    private var badgeColor: Color {
        switch arrival.statusColor {
        case "green": return .green
        case "blue": return .blue
        case "gray": return .secondary
        default: return .secondary
        }
    }
}

/// Clean, Apple-style route selection row
struct RouteSelectionRow: View {
    let route: Route
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button { onToggle() } label: {
            HStack(spacing: 14) {
                // Route color circle
                Circle()
                    .fill(routeColor)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(route.route_short_name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    )
                
                // Route information
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route \(route.route_short_name)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Text(route.route_long_name)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color("PrimaryAccent"))
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(backgroundShape)
        .overlay(
            // Divider (hide for last item)
            Group {
                if !isLast {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                        .offset(y: 24)
                }
            }
        )
    }
    
    @ViewBuilder
    private var backgroundShape: some View {
        if isFirst && isLast {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("Background").opacity(0.8))
        } else if isFirst {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 12, bottomLeading: 0, bottomTrailing: 0, topTrailing: 12))
                .fill(Color("Background").opacity(0.8))
        } else if isLast {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 12, bottomTrailing: 12, topTrailing: 0))
                .fill(Color("Background").opacity(0.8))
        } else {
            Rectangle()
                .fill(Color("Background").opacity(0.8))
        }
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
