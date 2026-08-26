import SwiftUI
import CoreLocation

/// Settings view for app preferences and info
struct SettingsView: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(ThemePreference.self) private var themePreference
    @Environment(MapAppPreference.self) private var mapAppPreference
    @Environment(LocationManager.self) private var locationManager
    @Environment(OnboardingStore.self) private var onboardingStore
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Settings sections
                    preferencesSection
                    
                    // App info section
                    appInfoSection
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
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
        .onAppear {
            // Refresh notification authorization status when view appears
            // This handles the case where user grants permission in Settings and returns
            Task {
                await notificationService.checkAuthorizationStatus()
            }
        }
    }
    
    // MARK: - Sections
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Preferences", icon: "gearshape.fill")
            
            VStack(spacing: 12) {
                // Appearance/Theme toggle
                settingsRow(
                    icon: themePreference.colorScheme == .dark ? "moon.fill" : themePreference.colorScheme == .light ? "sun.max.fill" : "circle.lefthalf.filled",
                    iconColor: Color("PrimaryAccent"),
                    title: "Appearance",
                    subtitle: themePreference.displayName
                ) {
                    Menu {
                        Button {
                            themePreference.colorScheme = .light
                        } label: {
                            HStack {
                                Text("Light")
                                if themePreference.colorScheme == .light {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Button {
                            themePreference.colorScheme = .dark
                        } label: {
                            HStack {
                                Text("Dark")
                                if themePreference.colorScheme == .dark {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Button {
                            themePreference.resetToSystem()
                        } label: {
                            HStack {
                                Text("System")
                                if themePreference.colorScheme == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(themePreference.displayName)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color("PrimaryAccent"))
                    }
                }

                Button {
                    configureLocation()
                } label: {
                    settingsRow(
                        icon: locationManager.isAuthorized ? "location.fill" : "location.slash.fill",
                        iconColor: locationManager.isAuthorized ? Color("PrimaryAccent") : .secondary,
                        title: "Location",
                        subtitle: locationStatusText
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                settingsRow(
                    icon: "map.fill",
                    iconColor: Color("PrimaryAccent"),
                    title: "Transit Directions",
                    subtitle: "Preferred map app"
                ) {
                    Menu {
                        ForEach(PreferredMapApp.allCases) { app in
                            Button {
                                mapAppPreference.selectedApp = app
                            } label: {
                                HStack {
                                    Text(app.displayName)
                                    if mapAppPreference.selectedApp == app {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(mapAppPreference.selectedApp.displayName)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color("PrimaryAccent"))
                    }
                }

                // Request in context when undetermined; otherwise open the
                // system settings where an existing decision can be changed.
                Button {
                    configureNotifications()
                } label: {
                    settingsRow(
                        icon: notificationService.authorizationStatus == .authorized ? "bell.fill" : "bell.slash.fill",
                        iconColor: notificationService.authorizationStatus == .authorized ? Color("PrimaryAccent") : .secondary,
                        title: "Notifications",
                        subtitle: notificationStatusText
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .appSheetCard(cornerRadius: 16)
        .padding(.horizontal, 20)
    }
    
    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "About", icon: "info.circle.fill")
            
            VStack(spacing: 12) {
                // App version
                settingsRow(
                    icon: "app.badge.fill",
                    iconColor: Color("PrimaryAccent"),
                    title: "Version",
                    subtitle: appVersion
                )

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    settingsRow(
                        icon: "hand.raised.fill",
                        iconColor: Color("PrimaryAccent"),
                        title: "Privacy Policy",
                        subtitle: "How Link handles your data"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Rate App
                Button {
                    requestAppReview()
                } label: {
                    settingsRow(
                        icon: "star.fill",
                        iconColor: Color("PrimaryAccent"),
                        title: "Rate App",
                        subtitle: "Share your feedback"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    onboardingStore.reset()
                } label: {
                    settingsRow(
                        icon: "sparkles.rectangle.stack.fill",
                        iconColor: Color("PrimaryAccent"),
                        title: "View App Guide",
                        subtitle: "Replay the introduction"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .appSheetCard(cornerRadius: 16)
        .padding(.horizontal, 20)
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("PrimaryAccent"))

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    private func settingsRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    // MARK: - Computed Properties
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
    
    private var notificationStatusText: String {
        switch notificationService.authorizationStatus {
        case .authorized:
            return "Enabled"
        case .denied:
            return "Disabled - Tap to open Settings"
        case .notDetermined:
            return "Not configured"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Enabled"
        case .denied: return "Disabled - Tap to open Settings"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not configured"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - Actions
    
    private func requestAppReview() {
        AppReviewService.requestInAppReview()
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func configureLocation() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        } else if locationManager.isAuthorized {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        } else {
            openSettings()
        }
    }

    private func configureNotifications() {
        if notificationService.authorizationStatus == .notDetermined {
            Task {
                _ = await notificationService.requestPermission()
            }
        } else {
            openSettings()
        }
    }
}

#Preview {
    SettingsView()
        .environment(NotificationService())
        .environment(ThemePreference())
        .environment(MapAppPreference(defaults: UserDefaults(suiteName: "SettingsMapPreview")!))
        .environment(LocationManager())
        .environment(OnboardingStore(defaults: UserDefaults(suiteName: "SettingsPreview")!))
}
