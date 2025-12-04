import SwiftUI

/// Main container view managing tab-based navigation
struct MainContainerView: View {
    @State private var selectedTab: MainTab = .map
    @State private var showingFilterSheet = false
    @State private var mapNavigationService = MapNavigationService()
    @State private var tripPlannerViewModel: TripPlannerViewModel?
    
    enum MainTab {
        case map
        case favorites
        case notifications
        case settings
    }
    
    var body: some View {
        ZStack {
            // Show the current page based on selected tab
            Group {
                switch selectedTab {
                case .map:
                    ContentView(
                        selectedTab: $selectedTab,
                        showingFilterSheet: $showingFilterSheet,
                        tripPlannerViewModel: $tripPlannerViewModel
                    )
                    .environment(mapNavigationService)
                    
                case .favorites:
                    FavoritesView()
                        .environment(mapNavigationService)
                        .transition(.opacity)
                    
                case .notifications:
                    NotificationsManagementView()
                        .environment(mapNavigationService)
                        .transition(.opacity)
                    
                case .settings:
                    SettingsView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            
            // Bottom nav bar always visible
            VStack {
                Spacer()
                BottomNavBar(
                    selectedTab: $selectedTab
                )
            }
        }
        .onAppear {
            // Set up tab switching callback for navigation service
            mapNavigationService.switchToMapTab = {
                selectedTab = .map
            }
        }
    }
}

/// Bottom navigation bar component
struct BottomNavBar: View {
    @Binding var selectedTab: MainContainerView.MainTab
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

