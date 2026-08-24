import SwiftUI

/// Main container view managing tab-based navigation
struct MainContainerView: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(DataSyncService.self) private var dataSyncService
    @State private var selectedTab: MainTab = .map
    @State private var showingFilterSheet = false
    @State private var showingBookingSheet = false
    @State private var mapNavigationService = MapNavigationService()
    
    enum MainTab {
        case map
        case favorites
        case notifications
        case settings
    }
    
    var body: some View {
        ZStack {
            // Keep each tab mounted so the map camera, prepared annotations, and
            // navigation state survive tab changes.
            ZStack {
                ContentView(
                    selectedTab: $selectedTab,
                    showingFilterSheet: $showingFilterSheet
                )
                .environment(mapNavigationService)
                .tabLayer(isActive: selectedTab == .map)

                FavoritesView()
                    .environment(mapNavigationService)
                    .tabLayer(isActive: selectedTab == .favorites)

                NotificationsManagementView()
                    .environment(mapNavigationService)
                    .tabLayer(isActive: selectedTab == .notifications)

                SettingsView()
                    .tabLayer(isActive: selectedTab == .settings)
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            
            // Bottom nav bar always visible
            VStack {
                Spacer()
                BottomNavBar(
                    selectedTab: $selectedTab,
                    showingBookingSheet: $showingBookingSheet
                )
            }
        }
        .onAppear {
            // Set up tab switching callback for navigation service
            mapNavigationService.switchToMapTab = {
                selectedTab = .map
            }
            openPendingNotificationIfPossible()
        }
        .onChange(of: notificationService.pendingNavigationStopId) { _, _ in
            openPendingNotificationIfPossible()
        }
        .onChange(of: dataSyncService.isStaticDataReady) { _, _ in
            openPendingNotificationIfPossible()
        }
        .sheet(isPresented: $showingBookingSheet) {
            if let url = URL(string: "https://book.blink.rideco.com/home/booking/search") {
                SafariView(url: url)
            }
        }
    }

    private func openPendingNotificationIfPossible() {
        guard let stopId = notificationService.pendingNavigationStopId,
              let stop = dataSyncService.stops.first(where: { $0.id == stopId }) else {
            return
        }

        _ = notificationService.consumePendingNavigationStopId()
        mapNavigationService.requestNavigation(to: stop)
    }
}

private extension View {
    func tabLayer(isActive: Bool) -> some View {
        opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

/// Bottom navigation bar component
struct BottomNavBar: View {
    @Binding var selectedTab: MainContainerView.MainTab
    @Binding var showingBookingSheet: Bool
    @Environment(NotificationService.self) private var notificationService
    
    var body: some View {
        VStack(spacing: 0) {
            // Top border separator
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.primary.opacity(0.15))
            
            // Button content area - respects safe area for content
            HStack(spacing: 0) {
                // Map icon
                bottomBarButton(
                    icon: "map.fill",
                    label: "Map",
                    color: Color("PrimaryAccent"),
                    isSelected: selectedTab == .map,
                    action: { selectedTab = .map }
                )
                
                // Heart icon (Favorites)
                bottomBarButton(
                    icon: "heart.fill",
                    label: "Favorites",
                    color: Color("PrimaryAccent"),
                    isSelected: selectedTab == .favorites,
                    action: { selectedTab = .favorites }
                )
                
                // Bell icon (Notifications)
                bottomBarButton(
                    icon: "bell.fill",
                    label: "Notifications",
                    color: Color("PrimaryAccent"),
                    isSelected: selectedTab == .notifications,
                    action: { selectedTab = .notifications },
                    badgeCount: notificationService.getNotificationPreferences().isEmpty ? nil : notificationService.getNotificationPreferences().count
                )
                
                // Car icon (Micro-Transit)
                bottomBarButton(
                    icon: "car.fill",
                    label: "MicroTransit",
                    color: Color("PrimaryAccent"),
                    isSelected: false,
                    action: { showingBookingSheet = true }
                )
                
                // Settings icon
                bottomBarButton(
                    icon: "gearshape.fill",
                    label: "Settings",
                    color: Color("PrimaryAccent"),
                    isSelected: selectedTab == .settings,
                    action: { selectedTab = .settings }
                )
            }
            .frame(height: 60)
            .padding(.bottom, 0)
        }
        .background(
            // Theme background color extends to screen edge
            Color("Background")
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -4)
    }
    
    /// Individual button in the bottom bar with proper touch targets
    /// Uses color assets from Assets.xcassets for consistent theming
    private func bottomBarButton(
        icon: String,
        label: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void,
        badgeCount: Int? = nil
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? color : color.opacity(0.6))
                        .frame(height: 28)
                    
                    // Badge overlay for notifications using AlertRed
                    if let count = badgeCount {
                        Circle()
                            .fill(Color("AlertRed"))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 8, y: -4)
                    }
                }
                
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44) // Minimum touch target per Apple HIG
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainContainerView()
        .environment(LocationManager())
        .environment(DataSyncService())
        .environment(RouteFilterStore())
        .environment(FavoriteStore())
        .environment(NotificationService())
        .environment(AlertsService())
        .environment(ThemePreference())
}
