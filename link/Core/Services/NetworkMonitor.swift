import Foundation
import Network
import Observation

/// Network monitoring service using NWPathMonitor
/// Provides real-time network connectivity status
@Observable
@MainActor
class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    /// Current network connectivity status
    private(set) var isConnected: Bool = true
    
    /// Whether the connection is expensive (cellular on low data mode)
    private(set) var isExpensive: Bool = false
    
    /// Whether the connection is constrained (low data mode)
    private(set) var isConstrained: Bool = false
    
    /// Current connection type (WiFi, cellular, etc.)
    private(set) var connectionType: NWInterface.InterfaceType?
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.link.networkmonitor")
    
    private init() {
        monitor = NWPathMonitor()
        
        // Start monitoring immediately
        startMonitoring()
    }
    
    /// Start monitoring network path changes
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isExpensive = path.isExpensive
            let isConstrained = path.isConstrained
            let usesWifi = path.usesInterfaceType(.wifi)
            let usesCellular = path.usesInterfaceType(.cellular)
            let usesEthernet = path.usesInterfaceType(.wiredEthernet)
            
            // Update properties on MainActor
            // Use nonisolated unsafe to avoid Swift 6 concurrency warning
            // The handler runs on background queue, we bridge to MainActor safely
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                self.isExpensive = isExpensive
                self.isConstrained = isConstrained
                
                // Determine connection type
                if usesWifi {
                    self.connectionType = .wifi
                } else if usesCellular {
                    self.connectionType = .cellular
                } else if usesEthernet {
                    self.connectionType = .wiredEthernet
                } else {
                    self.connectionType = nil
                }
                
                if wasConnected && !self.isConnected {
                    print("❌ Network disconnected")
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    /// Stop monitoring (typically not needed, but available for cleanup)
    func stopMonitoring() {
        monitor.cancel()
    }
}

// MARK: - NWInterface.InterfaceType Extension

extension NWInterface.InterfaceType {
    var description: String {
        switch self {
        case .wifi:
            return "WiFi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        case .other:
            return "Other"
        @unknown default:
            return "Unknown"
        }
    }
}

