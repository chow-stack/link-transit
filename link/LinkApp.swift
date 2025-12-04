import SwiftUI
import SwiftData

@main
struct LinkApp: App {
    @State private var locationManager = LocationManager()
    @State private var dataSyncService = DataSyncService()
    @State private var filterStore = RouteFilterStore()
    @State private var favoriteStore = FavoriteStore()
    @State private var notificationService: NotificationService
    @State private var alertsService = AlertsService()
    @State private var themePreference = ThemePreference()
    @State private var networkMonitor = NetworkMonitor.shared
    
    // SwiftData model container for route filters, favorites, and notifications
    let modelContainer: ModelContainer
    
    init() {
        do {
            // Create SwiftData container with RouteFilter, Favorite, and StopNotification models
            modelContainer = try ModelContainer(for: RouteFilter.self, Favorite.self, StopNotification.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        
        // Initialize notification service
        // Will receive StopTimesService reference after DataSyncService initializes
        _notificationService = State(initialValue: NotificationService())
    }
    
    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environment(locationManager)
                .environment(dataSyncService)
                .environment(filterStore)
                .environment(favoriteStore)
                .environment(notificationService)
                .environment(alertsService)
                .environment(themePreference)
                .environment(networkMonitor)
                .modelContainer(modelContainer)
                .preferredColorScheme(themePreference.colorScheme)
                .onAppear {
                    // Start alerts service fetching on app launch
                    alertsService.startFetching()
                    
                    // Request notification permission on first launch
                    Task {
                        await notificationService.requestPermissionIfNeeded()
                    }
                }
                .background(
                    ScenePhaseObserver(notificationService: notificationService)
                )
        }
    }
}

/// Helper view to observe scene phase changes and refresh notification authorization status
private struct ScenePhaseObserver: View {
    @Environment(\.scenePhase) private var scenePhase
    let notificationService: NotificationService
    
    var body: some View {
        Color.clear
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Refresh notification authorization status when app becomes active
                // This handles the case where user grants permission in Settings and returns
                if newPhase == .active && oldPhase != .active {
                    Task {
                        await notificationService.checkAuthorizationStatus()
                    }
                }
            }
    }
}

