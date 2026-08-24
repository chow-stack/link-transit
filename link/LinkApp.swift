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
    @State private var onboardingStore = OnboardingStore()
    
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
            AppRootView()
                .environment(locationManager)
                .environment(dataSyncService)
                .environment(filterStore)
                .environment(favoriteStore)
                .environment(notificationService)
                .environment(alertsService)
                .environment(themePreference)
                .environment(networkMonitor)
                .environment(onboardingStore)
                .modelContainer(modelContainer)
                .preferredColorScheme(themePreference.colorScheme)
                .onAppear {
                    // Start alerts service fetching on app launch
                    alertsService.startFetching()
                    Task {
                        await notificationService.clearBadge()
                    }
                }
                .background(
                    ScenePhaseObserver(
                        notificationService: notificationService,
                        dataSyncService: dataSyncService,
                        alertsService: alertsService
                    )
                )
        }
    }
}

private struct AppRootView: View {
    @Environment(OnboardingStore.self) private var onboardingStore

    var body: some View {
        Group {
            if onboardingStore.needsOnboarding {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            } else {
                MainContainerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: onboardingStore.needsOnboarding)
    }
}

/// Helper view to observe scene phase changes and refresh notification authorization status
private struct ScenePhaseObserver: View {
    @Environment(\.scenePhase) private var scenePhase
    let notificationService: NotificationService
    let dataSyncService: DataSyncService
    let alertsService: AlertsService
    
    var body: some View {
        Color.clear
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Refresh notification authorization status when app becomes active
                // This handles the case where user grants permission in Settings and returns
                if newPhase == .active && oldPhase != .active {
                    dataSyncService.resumeAutoRefreshIfNeeded()
                    alertsService.startFetching()
                    Task {
                        await notificationService.checkAuthorizationStatus()
                        await notificationService.clearBadge()
                        if notificationService.isInitialized {
                            await notificationService.refreshNotifications()
                        }
                    }
                } else if newPhase != .active {
                    dataSyncService.stopAutoRefresh()
                    alertsService.stopFetching()
                }
            }
    }
}
