import Foundation
import StoreKit
import SwiftUI

/// Service for handling app review prompts and App Store navigation
/// Follows Apple's best practices for in-app reviews and App Store links
enum AppReviewService {
    /// Placeholder App Store ID - replace with your actual App Store ID when available
    /// Format: https://apps.apple.com/app/idYOUR_APP_STORE_ID
    static let appStoreID = "6755202112"
    
    /// App Store review URL with write-review action
    static var appStoreReviewURL: URL? {
        guard appStoreID != "6755202112" else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
    
    /// App Store page URL (without write-review action)
    static var appStorePageURL: URL? {
        guard appStoreID != "6755202112" else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }
    
    /// Requests an in-app review prompt using SKStoreReviewController
    /// This follows Apple's guidelines:
    /// - Only shows when appropriate (Apple controls timing)
    /// - Works in development builds (shows prompt in Xcode)
    /// - Respects user's review history and system limits
    @MainActor
    static func requestInAppReview() {
        // Check if we're in a valid window scene context
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            // Fallback to App Store URL if no window scene available
            openAppStoreReviewPage()
            return
        }
        
        // Request review - Apple controls when/if the prompt actually appears
        // In development, this will show the prompt in Xcode
        // In production, Apple's algorithm determines if/when to show it
        SKStoreReviewController.requestReview(in: windowScene)
    }
    
    /// Opens the App Store review page directly
    /// This bypasses Apple's review prompt system and takes users directly to write a review
    /// Useful as a fallback or when in-app review isn't available
    @MainActor
    static func openAppStoreReviewPage() {
        guard let url = appStoreReviewURL else {
            // If App Store ID not configured, try opening the app's page
            if let pageURL = appStorePageURL {
                UIApplication.shared.open(pageURL)
            }
            return
        }
        
        UIApplication.shared.open(url)
    }
    
    /// Opens the App Store page (without write-review action)
    /// Useful for viewing the app page or as a fallback
    @MainActor
    static func openAppStorePage() {
        guard let url = appStorePageURL else { return }
        UIApplication.shared.open(url)
    }
}

