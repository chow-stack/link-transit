import Foundation
import UserNotifications
import SwiftData
import Observation

/// Service managing local notifications for bus arrivals
@Observable
@MainActor
class NotificationService {
    private let notificationCenter = UNUserNotificationCenter.current()
    private let responseDelegate = NotificationCenterDelegate()
    private var modelContext: ModelContext?
    private var dataSyncService: DataSyncService?
    private var isScheduling = false
    
    /// Current authorization status
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Both full and provisional permission can receive scheduled notifications.
    var canScheduleNotifications: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// Set when a delivered notification is tapped. MainContainerView consumes
    /// this after static stop data and map navigation are available.
    private(set) var pendingNavigationStopId: Int?
    
    /// Whether notifications are globally enabled
    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }
    
    /// Default advance minutes for new notifications
    var defaultAdvanceMinutes: Int {
        didSet {
            UserDefaults.standard.set(defaultAdvanceMinutes, forKey: "defaultAdvanceMinutes")
        }
    }
    
    /// All active notification preferences
    private var notificationPreferences: [StopNotification] = []
    private(set) var isInitialized = false
    
    init() {
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        let savedAdvanceMinutes = UserDefaults.standard.integer(forKey: "defaultAdvanceMinutes")
        defaultAdvanceMinutes = savedAdvanceMinutes > 0 ? savedAdvanceMinutes : 5

        notificationCenter.delegate = responseDelegate
        responseDelegate.onOpenStop = { [weak self] stopId in
            self?.pendingNavigationStopId = stopId
        }

        Task {
            await checkAuthorizationStatus()
        }
    }
    
    /// Initialize with model context and data sync service
    /// Idempotent: skips if already initialized to prevent unnecessary SwiftData fetches
    func initialize(modelContext: ModelContext, dataSyncService: DataSyncService? = nil) async {
        // Skip if already initialized (modelContext already set)
        guard self.modelContext == nil else { return }
        
        self.modelContext = modelContext
        self.dataSyncService = dataSyncService
        await loadNotificationPreferences()
        await checkAuthorizationStatus()
        isInitialized = true

        if notificationsEnabled && canScheduleNotifications {
            await scheduleAllNotifications()
        }
    }
    
    /// Load notification preferences from SwiftData
    private func loadNotificationPreferences() async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<StopNotification>()
            notificationPreferences = try modelContext.fetch(descriptor)
        } catch {
            print("⚠️ Failed to load notification preferences: \(error)")
            notificationPreferences = []
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    /// Request notification permission from an explicit, contextual UI action.
    func requestPermission() async -> Bool {
        await checkAuthorizationStatus()

        if canScheduleNotifications {
            notificationsEnabled = true
            return true
        }

        guard authorizationStatus == .notDetermined else {
            return false
        }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            
            if granted {
                notificationsEnabled = true
            } else {
                print("⚠️ Notification permission denied")
            }
            
            return granted
        } catch {
            print("❌ Failed to request notification permission: \(error)")
            return false
        }
    }
    
    /// Get all notification preferences
    func getNotificationPreferences() -> [StopNotification] {
        return notificationPreferences.filter { $0.isEnabled }
    }
    
    /// Get notification preference for a specific stop
    func getNotificationPreference(for stopId: Int) -> StopNotification? {
        return notificationPreferences.first { $0.stopId == stopId }
    }
    
    /// Check if notifications are enabled for a specific stop
    func hasNotification(for stopId: Int) -> Bool {
        return notificationPreferences.contains { $0.stopId == stopId && $0.isEnabled }
    }

    func consumePendingNavigationStopId() -> Int? {
        defer { pendingNavigationStopId = nil }
        return pendingNavigationStopId
    }
    
    /// Save or update notification preference
    func saveNotificationPreference(
        stopId: Int,
        stopName: String,
        enabledRouteIds: Set<String>,
        advanceMinutes: Int
    ) async {
        guard let modelContext = modelContext else { return }
        
        // Check if preference already exists
        if let existing = notificationPreferences.first(where: { $0.stopId == stopId }) {
            // Update existing
            existing.enabledRouteIds = enabledRouteIds
            existing.advanceMinutes = advanceMinutes
            existing.isEnabled = !enabledRouteIds.isEmpty
            
            do {
                try modelContext.save()
                await loadNotificationPreferences()
            } catch {
                print("⚠️ Failed to update notification preference: \(error)")
            }
        } else {
            // Create new
            let preference = StopNotification(
                stopId: stopId,
                stopName: stopName,
                enabledRouteIds: enabledRouteIds,
                advanceMinutes: advanceMinutes
            )
            
            do {
                modelContext.insert(preference)
                try modelContext.save()
                await loadNotificationPreferences()
            } catch {
                print("⚠️ Failed to create notification preference: \(error)")
            }
        }
        
        // Schedule notifications if enabled
        if notificationsEnabled && canScheduleNotifications {
            // Rebuild the shared queue so the app stays below the system-wide
            // pending-notification limit as users add more stops.
            await scheduleAllNotifications()
        }
    }
    
    /// Remove notification preference for a stop
    func removeNotificationPreference(for stopId: Int) async {
        guard let modelContext = modelContext else { return }
        
        if let preference = notificationPreferences.first(where: { $0.stopId == stopId }) {
            modelContext.delete(preference)
            
            do {
                try modelContext.save()
                await loadNotificationPreferences()
                
                // Cancel pending notifications for this stop
                await cancelNotificationsForStop(stopId)
            } catch {
                print("⚠️ Failed to remove notification preference: \(error)")
            }
        }
    }
    
    /// Toggle global notifications on/off
    func toggleNotifications() {
        notificationsEnabled.toggle()
        
        if !notificationsEnabled {
            // Cancel all pending notifications
            notificationCenter.removeAllPendingNotificationRequests()
        } else if canScheduleNotifications {
            // Reschedule all notifications
            Task {
                await scheduleAllNotifications()
            }
        }
    }
    
    /// Schedule notifications for a specific stop
    private func scheduleNotificationsForStop(_ stopId: Int, limit: Int) async -> Int {
        guard let preference = notificationPreferences.first(where: { $0.stopId == stopId && $0.isEnabled }),
              let dataSyncService = dataSyncService else {
            return 0
        }
        
        // Cancel existing notifications for this stop
        await cancelNotificationsForStop(stopId)
        
        // Get upcoming arrivals for this stop
        let arrivals = await dataSyncService.stopTimesService.getUpcomingArrivals(for: stopId, maxArrivals: 10)
        
        // Filter arrivals for enabled routes
        let relevantArrivals = arrivals.filter { arrival in
            preference.isRouteEnabled(arrival.routeId)
        }
        
        // Schedule notification for each arrival
        var scheduledCount = 0
        for arrival in relevantArrivals.prefix(limit) {
            if await scheduleNotification(for: arrival, preference: preference) {
                scheduledCount += 1
            }
        }
        return scheduledCount
    }
    
    /// Schedule a notification for a specific arrival
    private func scheduleNotification(for arrival: Arrival, preference: StopNotification) async -> Bool {
        // Calculate notification time
        let notificationTime = arrival.arrivalTime.addingTimeInterval(-Double(preference.advanceMinutes * 60))
        
        // Don't schedule if notification time is in the past
        guard notificationTime > Date() else {
            return false
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "🚌 Bus Arriving Soon"
        content.body = "Route \(arrival.routeShortName) will arrive at \(preference.stopName) in \(preference.advanceMinutes) min"
        content.sound = .default
        content.badge = 1
        
        // Add user info for deep linking
        content.userInfo = [
            "stopId": preference.stopId,
            "routeId": arrival.routeId,
            "tripId": arrival.tripId
        ]
        
        // Create trigger
        let timeInterval = notificationTime.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        
        // Create request with unique identifier
        let identifier = "stop_\(preference.stopId)_trip_\(arrival.tripId)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Schedule notification
        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            print("⚠️ Failed to schedule notification: \(error)")
            return false
        }
    }
    
    /// Cancel notifications for a specific stop
    private func cancelNotificationsForStop(_ stopId: Int) async {
        let identifiers = await notificationCenter.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("stop_\(stopId)_") }
            .map { $0.identifier }
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    /// Schedule all notifications based on current preferences
    func scheduleAllNotifications() async {
        guard notificationsEnabled && canScheduleNotifications && !isScheduling else {
            return
        }

        isScheduling = true
        defer { isScheduling = false }

        // Only remove arrival notifications owned by this service.
        let identifiers = await notificationCenter.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("stop_") }
            .map(\.identifier)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        
        // iOS keeps a finite pending queue. Reserve a few slots for any future
        // non-arrival notifications and divide the remaining 60 fairly.
        let activePreferences = notificationPreferences
            .filter(\.isEnabled)
            .sorted { $0.createdAt < $1.createdAt }
        let includedPreferences = Array(activePreferences.prefix(60))
        let perStopLimit = min(10, max(1, 60 / max(includedPreferences.count, 1)))

        for preference in includedPreferences {
            _ = await scheduleNotificationsForStop(
                preference.stopId,
                limit: perStopLimit
            )
        }
    }
    
    /// Refresh all notifications (call this periodically or when data updates)
    func refreshNotifications() async {
        guard notificationsEnabled && canScheduleNotifications else {
            return
        }
        
        await scheduleAllNotifications()
    }
    
    /// Clear all notifications
    func clearAllNotifications() async {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(0)
            } catch {
                print("⚠️ Failed to set badge count: \(error)")
            }
        }
    }

    func clearBadge() async {
        do {
            try await notificationCenter.setBadgeCount(0)
        } catch {
            print("⚠️ Failed to clear badge: \(error)")
        }
    }
}

private final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor var onOpenStop: ((Int) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let stopId = response.notification.request.content.userInfo["stopId"] as? Int else {
            return
        }

        await MainActor.run {
            onOpenStop?(stopId)
        }
    }
}
