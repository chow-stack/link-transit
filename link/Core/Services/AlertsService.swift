import Foundation
import SwiftProtobuf

/// Service for fetching and managing transit alerts
@Observable
@MainActor
class AlertsService {
    // MARK: - Published Properties
    
    /// Current list of active alerts
    private(set) var alerts: [Alert] = []
    
    /// Whether alerts are currently being fetched
    private(set) var isLoading: Bool = false
    
    /// Last time alerts were fetched
    private(set) var lastFetchTime: Date?
    
    /// Whether there was an error fetching alerts
    private(set) var hasError: Bool = false
    
    // MARK: - Private Properties
    
    private let session: URLSession
    private var fetchTask: Task<Void, Never>?
    private let fetchInterval: TimeInterval = 600 // 10 minutes
    private let cacheKey = "cached_alerts"
    private let cacheTimestampKey = "alerts_cache_timestamp"
    private let dismissedAlertsKey = "dismissed_alerts"
    private let lastDismissalDateKey = "last_dismissal_date"
    private let bannerShownThisSessionKey = "banner_shown_this_session"
    private let appLaunchTimestampKey = "app_launch_timestamp"
    
    // MARK: - Initialization
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 20.0
        // Don't wait for connectivity - fail fast and retry instead
        // This prevents indefinite waiting when app launches with no internet
        config.waitsForConnectivity = false
        
        self.session = URLSession(configuration: config)
        
        // Load cached alerts on init
        loadCachedAlerts()
        
        // Track app launch - reset banner shown flag if new app session
        checkAndResetSessionFlagIfNeeded()
    }
    
    /// Check if this is a new app session and reset banner shown flag
    /// Uses app launch detection based on process info to reliably detect true app launches
    private func checkAndResetSessionFlagIfNeeded() {
        let lastLaunchTimestamp = UserDefaults.standard.object(forKey: appLaunchTimestampKey) as? Date
        let now = Date()
        
        // Check if this is truly a new app launch by checking if:
        // 1. No timestamp exists (first launch ever)
        // 2. Last timestamp was from a different day (new day = new session)
        // 3. More than 5 minutes have passed (indicates app was backgrounded/killed)
        // Note: We use 5 minutes instead of 30 seconds to avoid false resets during tab navigation
        let shouldReset: Bool
        if let lastTimestamp = lastLaunchTimestamp {
            let calendar = Calendar.current
            // If different day, definitely reset
            if !calendar.isDate(lastTimestamp, inSameDayAs: now) {
                shouldReset = true
            } else {
                // Same day - only reset if > 5 minutes (app was likely killed/backgrounded)
                shouldReset = now.timeIntervalSince(lastTimestamp) > 300
            }
        } else {
            // No timestamp - first launch
            shouldReset = true
        }
        
        if shouldReset {
            UserDefaults.standard.removeObject(forKey: bannerShownThisSessionKey)
            UserDefaults.standard.set(now, forKey: appLaunchTimestampKey)
        }
    }
    
    // MARK: - Public Methods
    
    /// Start periodic alert fetching
    func startFetching() {
        // Cancel any existing task
        fetchTask?.cancel()
        
        // Start new fetch task
        fetchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Initial fetch
            await self.fetchAlerts()
            
            // Periodic fetch every 10 minutes
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(fetchInterval))
                if !Task.isCancelled {
                    await self.fetchAlerts()
                }
            }
        }
    }
    
    /// Stop periodic alert fetching
    func stopFetching() {
        fetchTask?.cancel()
        fetchTask = nil
    }
    
    /// Manually refresh alerts
    func refresh() async {
        await fetchAlerts(forceRefresh: true)
    }
    
    /// Mark alerts as dismissed
    func dismissAlerts() {
        guard !alerts.isEmpty else { return }
        
        // Store dismissed alert IDs
        let alertIds = alerts.map { $0.id }
        UserDefaults.standard.set(alertIds, forKey: dismissedAlertsKey)
        UserDefaults.standard.set(Date(), forKey: lastDismissalDateKey)
    }
    
    /// Check if alerts should be shown (only on app launch, not on every navigation)
    /// Returns true only on first app launch, new alerts, or new day
    func shouldShowBanner() -> Bool {
        // Check if banner has been shown this app session
        let hasShownThisSession = UserDefaults.standard.bool(forKey: bannerShownThisSessionKey)
        
        // On first call in this session (app launch), mark as shown and return true
        if !hasShownThisSession {
            UserDefaults.standard.set(true, forKey: bannerShownThisSessionKey)
            return true
        }
        
        // After initial show, only show if there are new alerts not dismissed
        // Don't show "No active alerts" banner on subsequent navigations
        
        // Check if it's a new day since last dismissal
        if let lastDismissalDate = UserDefaults.standard.object(forKey: lastDismissalDateKey) as? Date {
            let calendar = Calendar.current
            if !calendar.isDateInToday(lastDismissalDate) {
                // New day - clear dismissed alerts and show again
                UserDefaults.standard.removeObject(forKey: dismissedAlertsKey)
                // Reset session flag so banner shows on new day
                UserDefaults.standard.removeObject(forKey: bannerShownThisSessionKey)
                UserDefaults.standard.set(true, forKey: bannerShownThisSessionKey)
                return true
            }
        }
        
        // Check if there are new alerts not in dismissed list
        if !alerts.isEmpty {
            if let dismissedAlertIds = UserDefaults.standard.stringArray(forKey: dismissedAlertsKey) {
                let currentAlertIds = Set(alerts.map { $0.id })
                let dismissedSet = Set(dismissedAlertIds)
                
                // Only show if there are new alerts that weren't dismissed
                let hasNewAlerts = !currentAlertIds.isSubset(of: dismissedSet)
                if hasNewAlerts {
                    // Reset session flag to show banner for new alerts
                    UserDefaults.standard.removeObject(forKey: bannerShownThisSessionKey)
                    UserDefaults.standard.set(true, forKey: bannerShownThisSessionKey)
                    return true
                }
            } else {
                // No dismissed alerts recorded, but alerts exist - show if first time seeing them
                if !hasShownThisSession {
                    return true
                }
            }
        }
        
        // Already shown this session with no new alerts - don't show
        return false
    }
    
    /// Get count of active alerts
    var activeAlertCount: Int {
        alerts.filter { $0.isActive }.count
    }
    
    // MARK: - Private Methods
    
    /// Fetch alerts from the GTFS-realtime feed
    private func fetchAlerts(forceRefresh: Bool = false) async {
        // Check if we should skip fetch based on cache
        if !forceRefresh, let lastFetch = lastFetchTime {
            let timeSinceLastFetch = Date().timeIntervalSince(lastFetch)
            if timeSinceLastFetch < fetchInterval {
                return
            }
        }
        
        isLoading = true
        hasError = false
        
        defer {
            isLoading = false
        }
        
        do {
            let fetchedAlerts = try await fetchAndParseAlerts()
            
            // Update alerts and cache
            self.alerts = fetchedAlerts
            self.lastFetchTime = Date()
            self.hasError = false
            
            // Cache alerts
            cacheAlerts(fetchedAlerts)
            
        } catch {
            print("Error fetching alerts: \(error)")
            self.hasError = true
            
            // Keep existing alerts on error
        }
    }
    
    /// Fetch and parse alerts from Protocol Buffer feed
    private func fetchAndParseAlerts() async throws -> [Alert] {
        guard let url = URL(string: APIConfig.alertsFeedURL) else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // Parse protobuf
        let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
        
        // Extract alerts from feed entities
        let alerts = feedMessage.entity.compactMap { entity -> Alert? in
            guard entity.hasAlert else { return nil }
            return Alert(from: entity.alert, id: entity.id)
        }
        
        return alerts
    }
    
    /// Cache alerts to UserDefaults
    private func cacheAlerts(_ alerts: [Alert]) {
        if let encoded = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
        }
    }
    
    /// Load cached alerts from UserDefaults
    private func loadCachedAlerts() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([Alert].self, from: data),
              let cacheDate = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return
        }
        
        // Only use cache if it's less than 10 minutes old
        let cacheAge = Date().timeIntervalSince(cacheDate)
        if cacheAge < fetchInterval {
            self.alerts = cached
            self.lastFetchTime = cacheDate
        }
    }
}

