import Foundation
import Observation

/// Persists completion by version so a future, materially different guide can
/// be shown without tying onboarding to a fragile one-time Boolean.
@Observable
@MainActor
final class OnboardingStore {
    static let currentVersion = 1

    private let defaults: UserDefaults
    private let completionKey = "completedOnboardingVersion"

    private(set) var completedVersion: Int

    var needsOnboarding: Bool {
        completedVersion < Self.currentVersion
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedVersion = defaults.integer(forKey: completionKey)
    }

    func complete() {
        completedVersion = Self.currentVersion
        defaults.set(Self.currentVersion, forKey: completionKey)
    }

    func reset() {
        completedVersion = 0
        defaults.removeObject(forKey: completionKey)
    }
}
