import Foundation
import MapKit
import Observation

/// Service for coordinating map navigation across the app
@Observable
@MainActor
class MapNavigationService {
    /// Callback to navigate to a specific stop on the map
    var navigateToStop: ((Stop) -> Void)?
    
    /// Callback to switch to the map tab
    var switchToMapTab: (() -> Void)?
    
    /// Pending stop to navigate to (used when switching tabs)
    /// This ensures navigation works even when ContentView isn't immediately visible
    var pendingStop: Stop?
    
    /// Trigger navigation to a stop
    /// Always stores as pending and switches to map tab, then ContentView will handle it when ready
    func requestNavigation(to stop: Stop) {
        // Store as pending - ContentView will handle it when ready
        pendingStop = stop
        
        // Switch to map tab if callback is set
        switchToMapTab?()
    }
}

