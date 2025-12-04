import SwiftUI
import Observation

/// Service managing app-wide theme preference (light/dark mode)
@Observable
@MainActor
class ThemePreference {
    /// Current color scheme preference
    var colorScheme: ColorScheme? {
        didSet {
            if let scheme = colorScheme {
                UserDefaults.standard.set(scheme == .dark ? "dark" : "light", forKey: "preferredColorScheme")
            } else {
                UserDefaults.standard.removeObject(forKey: "preferredColorScheme")
            }
        }
    }
    
    init() {
        // Load saved preference on initialization
        if let saved = UserDefaults.standard.string(forKey: "preferredColorScheme") {
            colorScheme = saved == "dark" ? .dark : .light
        } else {
            // Default to nil (system default) if not set
            colorScheme = nil
        }
    }
    
    /// Toggle between light and dark mode
    func toggleColorScheme() {
        switch colorScheme {
        case .dark:
            colorScheme = .light
        case .light:
            colorScheme = .dark
        case .none:
            // If using system, switch to dark
            colorScheme = .dark
        @unknown default:
            // Handle future cases
            colorScheme = .dark
        }
    }
    
    /// Reset to system default
    func resetToSystem() {
        colorScheme = nil
    }
    
    /// Display name for current preference
    var displayName: String {
        switch colorScheme {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        case .none:
            return "System"
        @unknown default:
            return "System"
        }
    }
}

