import SwiftUI
import SwiftData

@main
struct BloomBusApp: App {
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
                }
        }
    }
}

