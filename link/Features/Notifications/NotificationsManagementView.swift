import SwiftUI

/// Global view for managing all notification preferences
struct NotificationsManagementView: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(DataSyncService.self) private var dataSyncService
    @State private var showingClearAlert = false
    @State private var preferenceToEdit: StopNotification?
    private let timingOptions = [1, 2, 3, 5, 10, 15, 20, 25, 30]
    
    var body: some View {
        NavigationStack {
            Group {
                if !notificationService.isInitialized {
                    SimpleLoadingView()
                } else {
                    notificationsContent
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !notificationService.getNotificationPreferences().isEmpty {
                        Button("Delete All") {
                            showingClearAlert = true
                        }
                        .foregroundStyle(Color("AlertRed"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Spacer for bottom nav bar (handled by MainContainerView)
                // Bottom nav bar is 60px + safe area bottom inset
                GeometryReader { geometry in
                    Spacer()
                        .frame(height: 60 + geometry.safeAreaInsets.bottom)
                }
                .frame(height: 60)
            }
        }
        .background(Color("Background"))
        .task {
            await notificationService.checkAuthorizationStatus()
        }
        .alert("Delete All Notifications", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                Task {
                    for preference in notificationService.getNotificationPreferences() {
                        await notificationService.removeNotificationPreference(for: preference.stopId)
                    }
                }
            }
        } message: {
            Text("This will remove all your notification preferences. This action cannot be undone.")
        }
        .sheet(item: $preferenceToEdit) { preference in
            if let stop = dataSyncService.stops.first(where: { $0.id == preference.stopId }) {
                StopNotificationConfigSheet(
                    stop: stop,
                    servingRoutes: dataSyncService.stopTimesService.getRoutesForStop(preference.stopId)
                )
                .environment(notificationService)
                .environment(dataSyncService)
            } else {
                // Fallback if stop not found
                NavigationStack {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading stop details...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Loading")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") {
                                preferenceToEdit = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - UI Components

    private var notificationsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                notificationSettingsSection

                if notificationService.getNotificationPreferences().isEmpty {
                    emptyState
                } else {
                    activeNotificationsSection
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
    }

    private var notificationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("PrimaryAccent"))
                Text("Alert Settings")
                    .font(.headline.weight(.bold))
            }

            VStack(spacing: 0) {
                settingsRow(
                    icon: notificationService.canScheduleNotifications ? "bell.fill" : "bell.slash.fill",
                    title: "Arrival Alerts",
                    subtitle: permissionStatusText
                ) {
                    Toggle("", isOn: Binding(
                        get: { notificationService.notificationsEnabled && notificationService.canScheduleNotifications },
                        set: { shouldEnable in
                            Task { await setNotificationsEnabled(shouldEnable) }
                        }
                    ))
                    .labelsHidden()
                    .tint(Color("PrimaryAccent"))
                }

                Divider().padding(.leading, 48)

                settingsRow(
                    icon: "timer",
                    title: "Default Notice",
                    subtitle: "For new stop alerts"
                ) {
                    Menu {
                        ForEach(timingOptions, id: \.self) { minutes in
                            Button {
                                notificationService.defaultAdvanceMinutes = minutes
                            } label: {
                                if minutes == notificationService.defaultAdvanceMinutes {
                                    Label("\(minutes) min", systemImage: "checkmark")
                                } else {
                                    Text("\(minutes) min")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(notificationService.defaultAdvanceMinutes) min")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color("PrimaryAccent"))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(20)
        .appSheetCard(cornerRadius: 16)
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("PrimaryAccent"))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background(Color.secondary.opacity(0.06))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Notifications Set",
            systemImage: "bell.slash",
            description: Text("Tap the bell icon on any stop to set up arrival notifications.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .appSheetCard(cornerRadius: 16)
    }

    private var activeNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("PrimaryAccent"))

                Text("Active Notifications")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(notificationService.getNotificationPreferences().count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }

            VStack(spacing: 10) {
                ForEach(notificationService.getNotificationPreferences()) { preference in
                    NotificationPreferenceRow(
                        preference: preference,
                        onDelete: {
                            Task {
                                await notificationService.removeNotificationPreference(for: preference.stopId)
                            }
                        },
                        onEdit: {
                            preferenceToEdit = preference
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await notificationService.removeNotificationPreference(for: preference.stopId)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                        .tint(Color("AlertRed"))
                    }
                }
            }
        }
        .padding(20)
        .appSheetCard(cornerRadius: 16)
    }

    private var permissionStatusText: String {
        switch notificationService.authorizationStatus {
        case .authorized: return notificationService.notificationsEnabled ? "Enabled" : "Paused in Link"
        case .provisional: return notificationService.notificationsEnabled ? "Delivering quietly" : "Paused in Link"
        case .denied: return "Off in iOS Settings"
        case .notDetermined: return "Tap to allow notifications"
        case .ephemeral: return "Temporarily enabled"
        @unknown default: return "Unavailable"
        }
    }

    private func setNotificationsEnabled(_ shouldEnable: Bool) async {
        if !shouldEnable {
            if notificationService.notificationsEnabled {
                notificationService.toggleNotifications()
            }
            return
        }

        if !notificationService.canScheduleNotifications {
            let granted = await notificationService.requestPermission()
            if !granted {
                openAppSettings()
                return
            }
        }

        if !notificationService.notificationsEnabled {
            notificationService.toggleNotifications()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Supporting Components

/// Row displaying a single notification preference
struct NotificationPreferenceRow: View {
    let preference: StopNotification
    let onDelete: () -> Void
    let onEdit: () -> Void
    @Environment(DataSyncService.self) private var dataSyncService
    @Environment(MapNavigationService.self) private var mapNavigationService
    @State private var showingDeleteAlert = false
    @State private var showingStopDetails = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            Image(systemName: "mappin.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("PrimaryAccent"))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color("PrimaryAccent").opacity(0.15)))

            // Content - button to navigate to stop on map
            Button {
                // Navigate to stop on the map
                if let stop = dataSyncService.stops.first(where: { $0.id == preference.stopId }) {
                    mapNavigationService.requestNavigation(to: stop)
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preference.stopName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    // Route badges with colors
                    if !preference.enabledRouteIds.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(preference.enabledRouteIds), id: \.self) { routeId in
                                    if let route = dataSyncService.routes.first(where: { $0.route_id == routeId }) {
                                        RouteIdentityBadge(shortName: route.route_short_name, colorHex: route.route_color, compact: true)
                                    }
                                }
                            }
                        }
                    }

                    Text("\(preference.advanceMinutes) min before arrival")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Edit and delete buttons
            HStack(spacing: 14) {
                // Edit button (pencil icon)
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(Color("PrimaryAccent"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit notification for \(preference.stopName)")

                // Delete button
                Button {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color("AlertRed"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete notification for \(preference.stopName)")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .appSheetCard(cornerRadius: 12)
        .alert("Delete Notification", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Remove notifications for \(preference.stopName)?")
        }
    }
}

#Preview {
    NotificationsManagementView()
        .environment(NotificationService())
}
