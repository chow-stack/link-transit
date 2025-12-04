import SwiftUI

/// Global view for managing all notification preferences
struct NotificationsManagementView: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(DataSyncService.self) private var dataSyncService
    @State private var showingClearAlert = false
    @State private var preferenceToEdit: StopNotification?
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    SimpleLoadingView()
                } else if notificationService.getNotificationPreferences().isEmpty {
                    emptyState
                } else {
                    notificationsList
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
            .task {
                // Wait for data to be ready
                if !dataSyncService.routes.isEmpty {
                    // Data already loaded
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation {
                        isLoading = false
                    }
                } else {
                    // Wait for data to load
                    while dataSyncService.routes.isEmpty && !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation {
                        isLoading = false
                    }
                }
            }
        }
        .background(Color("Background"))
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
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            
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
            
            Spacer()
        }
    }
    
    private var notificationsList: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Active notifications section
                activeNotificationsSection
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
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

