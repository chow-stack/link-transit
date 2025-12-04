import Foundation
import UserNotifications
import SwiftData
import Observation

/// Service managing local notifications for bus arrivals
@Observable
@MainActor
class NotificationService {
    private let notificationCenter = UNUserNotificationCenter.current()
    private var modelContext: ModelContext?
    private var dataSyncService: DataSyncService?
    
    /// Current authorization status
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    /// Whether notifications are globally enabled
    var notificationsEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "notificationsEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "notificationsEnabled")
        }
    }
    
    /// Default advance minutes for new notifications
    var defaultAdvanceMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "defaultAdvanceMinutes")
            return value > 0 ? value : 5 // Default to 5 minutes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "defaultAdvanceMinutes")
        }
    }
    
    /// All active notification preferences
    private var notificationPreferences: [StopNotification] = []
    
    init() {
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
    }
    
    /// Load notification preferences from SwiftData
    private func loadNotificationPreferences() async {
        guard let modelContext = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<StopNotification>()
            notificationPreferences = try modelContext.fetch(descriptor)
            print("✅ Loaded \(notificationPreferences.count) notification preferences")
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
    
    /// Request notification permission if not determined (first launch)
    /// This should be called on app launch to request permission on first use
    func requestPermissionIfNeeded() async {
        // Check current status first
        await checkAuthorizationStatus()
        
        // Only request if status is not determined (first launch)
        guard authorizationStatus == .notDetermined else {
            print("ℹ️ Notification permission already determined: \(authorizationStatus.rawValue)")
            return
        }
        
        // Request permission
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            
            if granted {
                notificationsEnabled = true
                print("✅ Notification permission granted on first launch")
            } else {
                print("⚠️ Notification permission denied on first launch")
            }
        } catch {
            print("❌ Failed to request notification permission: \(error)")
        }
    }
    
    /// Request notification permission (can be called from UI)
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            
            if granted {
                notificationsEnabled = true
                print("✅ Notification permission granted")
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
                print("✅ Updated notification preference for stop \(stopId)")
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
                print("✅ Created notification preference for stop \(stopId)")
            } catch {
                print("⚠️ Failed to create notification preference: \(error)")
            }
        }
        
        // Schedule notifications if enabled
        if notificationsEnabled && authorizationStatus == .authorized {
            await scheduleNotificationsForStop(stopId)
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
                
                print("✅ Removed notification preference for stop \(stopId)")
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
            print("🔕 Disabled all notifications")
        } else if authorizationStatus == .authorized {
            // Reschedule all notifications
            Task {
                await scheduleAllNotifications()
            }
        }
    }
    
    /// Schedule notifications for a specific stop
    private func scheduleNotificationsForStop(_ stopId: Int) async {
        guard let preference = notificationPreferences.first(where: { $0.stopId == stopId && $0.isEnabled }),
              let dataSyncService = dataSyncService else {
            return
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
        for arrival in relevantArrivals {
            await scheduleNotification(for: arrival, preference: preference)
        }
    }
    
    /// Schedule a notification for a specific arrival
    private func scheduleNotification(for arrival: Arrival, preference: StopNotification) async {
        // Calculate notification time
        let notificationTime = arrival.arrivalTime.addingTimeInterval(-Double(preference.advanceMinutes * 60))
        
        // Don't schedule if notification time is in the past
        guard notificationTime > Date() else {
            return
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
            print("✅ Scheduled notification for stop \(preference.stopId), route \(arrival.routeShortName) at \(notificationTime)")
        } catch {
            print("⚠️ Failed to schedule notification: \(error)")
        }
    }
    
    /// Cancel notifications for a specific stop
    private func cancelNotificationsForStop(_ stopId: Int) async {
        let identifiers = await notificationCenter.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("stop_\(stopId)_") }
            .map { $0.identifier }
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        print("🔕 Cancelled \(identifiers.count) notifications for stop \(stopId)")
    }
    
    /// Schedule all notifications based on current preferences
    func scheduleAllNotifications() async {
        guard notificationsEnabled && authorizationStatus == .authorized else {
            return
        }
        
        // Cancel all existing notifications
        notificationCenter.removeAllPendingNotificationRequests()
        
        // Schedule notifications for each preference
        for preference in notificationPreferences where preference.isEnabled {
            await scheduleNotificationsForStop(preference.stopId)
        }
        
        print("✅ Scheduled notifications for \(notificationPreferences.count) stops")
    }
    
    /// Refresh all notifications (call this periodically or when data updates)
    func refreshNotifications() async {
        guard notificationsEnabled && authorizationStatus == .authorized else {
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
        print("🔕 Cleared all notifications")
    }
}

