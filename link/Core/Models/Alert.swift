import Foundation

/// Simplified alert model for UI display
struct Alert: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let headerText: String
    let descriptionText: String
    let cause: String
    let effect: String
    let severityLevel: SeverityLevel
    let activePeriods: [ActivePeriod]
    let url: String?
    
    /// Whether the alert is currently active based on active periods
    var isActive: Bool {
        let now = Date()
        
        // If no active periods specified, alert is always active
        if activePeriods.isEmpty {
            return true
        }
        
        // Check if current time falls within any active period
        return activePeriods.contains { period in
            let isAfterStart = period.start.map { now >= $0 } ?? true
            let isBeforeEnd = period.end.map { now <= $0 } ?? true
            return isAfterStart && isBeforeEnd
        }
    }
    
    enum SeverityLevel: String, Codable {
        case unknown = "UNKNOWN"
        case info = "INFO"
        case warning = "WARNING"
        case severe = "SEVERE"
        
        var displayName: String {
            switch self {
            case .unknown: return "Alert"
            case .info: return "Info"
            case .warning: return "Warning"
            case .severe: return "Severe"
            }
        }
        
        var icon: String {
            switch self {
            case .unknown: return "info.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .severe: return "exclamationmark.octagon.fill"
            }
        }
    }
    
    struct ActivePeriod: Codable, Equatable, Hashable {
        let start: Date?
        let end: Date?
    }
}

/// Extension to parse from GTFS-realtime protobuf
extension Alert {
    /// Initialize from TransitRealtime_Alert protobuf message
    init?(from gtfsAlert: TransitRealtime_Alert, id: String) {
        // Extract header text
        guard gtfsAlert.hasHeaderText,
              !gtfsAlert.headerText.translation.isEmpty,
              let firstTranslation = gtfsAlert.headerText.translation.first else {
            return nil
        }
        
        self.id = id
        self.headerText = firstTranslation.text
        
        // Extract description text
        self.descriptionText = gtfsAlert.hasDescriptionText && !gtfsAlert.descriptionText.translation.isEmpty
            ? gtfsAlert.descriptionText.translation.first?.text ?? ""
            : ""
        
        // Extract cause
        self.cause = gtfsAlert.hasCause ? String(describing: gtfsAlert.cause) : "UNKNOWN_CAUSE"
        
        // Extract effect
        self.effect = gtfsAlert.hasEffect ? String(describing: gtfsAlert.effect) : "UNKNOWN_EFFECT"
        
        // Extract severity level
        if gtfsAlert.hasSeverityLevel {
            switch gtfsAlert.severityLevel {
            case .info:
                self.severityLevel = .info
            case .warning:
                self.severityLevel = .warning
            case .severe:
                self.severityLevel = .severe
            default:
                self.severityLevel = .unknown
            }
        } else {
            self.severityLevel = .unknown
        }
        
        // Extract active periods
        self.activePeriods = gtfsAlert.activePeriod.map { period in
            let start = period.hasStart ? Date(timeIntervalSince1970: TimeInterval(period.start)) : nil
            let end = period.hasEnd ? Date(timeIntervalSince1970: TimeInterval(period.end)) : nil
            return ActivePeriod(start: start, end: end)
        }
        
        // Extract URL
        self.url = gtfsAlert.hasURL && !gtfsAlert.url.translation.isEmpty
            ? gtfsAlert.url.translation.first?.text
            : nil
    }
}

