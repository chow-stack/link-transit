import SwiftUI

/// Settings view for app preferences and info
struct SettingsView: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(ThemePreference.self) private var themePreference
    
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
                Spacer()
                    .frame(height: 60)
            }
        }
        .background(Color("Background"))
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
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color("PrimaryAccent"))
                    }
                }
                
                // Notifications toggle
                settingsRow(
                    icon: notificationService.notificationsEnabled ? "bell.fill" : "bell.slash.fill",
                    iconColor: notificationService.notificationsEnabled ? Color("PrimaryAccent") : .secondary,
                    title: "Notifications",
                    subtitle: notificationService.notificationsEnabled ? "Enabled" : "Disabled"
                ) {
                    Toggle("", isOn: Binding(
                        get: { notificationService.notificationsEnabled },
                        set: { _ in notificationService.toggleNotifications() }
                    ))
                    .labelsHidden()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("Background").opacity(0.8))
        )
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
                
                // Feedback
                Button {
                    sendFeedback()
                } label: {
                    settingsRow(
                        icon: "envelope.fill",
                        iconColor: Color("PrimaryAccent"),
                        title: "Send Feedback",
                        subtitle: "Share your thoughts"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("Background").opacity(0.8))
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color("PrimaryAccent"))
            
            Text(title)
                .font(.system(size: 20, weight: .bold))
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
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            trailing()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("Background").opacity(0.8))
        )
    }
    
    // MARK: - Computed Properties
    
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0"
    }
    
    // MARK: - Actions
    
    private func sendFeedback() {
        let subject = "Bloom Bus Feedback"
        let body = ""
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:support@bloombus.app?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .environment(NotificationService())
        .environment(ThemePreference())
}

