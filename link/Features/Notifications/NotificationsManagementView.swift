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
                            .font(.system(size: 16))
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
                    .foregroundStyle(Color("PrimaryAccent"))
                Text("Alert Settings")
                    .font(.system(size: 20, weight: .bold))
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
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("PrimaryAccent"))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("Background").opacity(0.8))
        )
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color("PrimaryAccent"))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background(Color("Background").opacity(0.65))
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    Text("No Notifications Set")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Tap the bell icon on any stop to set up arrival notifications")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, min(32, UIScreen.main.bounds.width * 0.08))
                }
            }
            
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("Background").opacity(0.8))
        )
    }
    
    private var activeNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color("PrimaryAccent"))
                
                Text("Active Notifications")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(notificationService.getNotificationPreferences().count)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color("Background").opacity(0.6))
                    )
            }
            
            VStack(spacing: 12) {
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
                        .tint(.red)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("Background").opacity(0.8))
        )
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
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.green.opacity(0.15))
                )
            
            // Content - button to navigate to stop on map
            Button {
                // Navigate to stop on the map
                if let stop = dataSyncService.stops.first(where: { $0.id == preference.stopId }) {
                    mapNavigationService.requestNavigation(to: stop)
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preference.stopName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                
                // Route badges with colors
                if !preference.enabledRouteIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(preference.enabledRouteIds), id: \.self) { routeId in
                                if let route = dataSyncService.routes.first(where: { $0.route_id == routeId }) {
                                    Text(route.route_short_name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(route.route_color != nil ? Color(hex: route.route_color!) : Color("PrimaryAccent"))
                                        )
                                }
                            }
                        }
                    }
                }
                
                Text("\(preference.advanceMinutes) min before arrival")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Edit and delete buttons
            HStack(spacing: 8) {
                // Edit button (pencil icon)
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                        .foregroundStyle(Color("PrimaryAccent"))
                }
                .buttonStyle(.plain)
                
                // Delete button
                Button {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color("AlertRed"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("Background").opacity(0.6))
        )
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
