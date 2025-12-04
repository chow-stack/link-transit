import SwiftUI
import Foundation

/// Full-screen view shown when no buses are active
/// Replaces map view entirely, allows navbar navigation
struct NoBusesView: View {
    @Environment(DataSyncService.self) private var dataSyncService
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No Buses Active")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Service Hours")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 8)
                
                // Route list with service hours
                VStack(spacing: 16) {
                    ForEach(0..<routesWithHours.count, id: \.self) { index in
                        let routeWithHours = routesWithHours[index]
                        RouteServiceHoursCard(
                            route: routeWithHours.route,
                            serviceHours: routeWithHours.hours
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100) // Space for navbar
            }
        }
        .background(Color("Background"))
    }
    
    /// Match routes with their service hours
    private var routesWithHours: [(route: Route, hours: ServiceHours)] {
        dataSyncService.routes.compactMap { route in
            if let serviceHours = dataSyncService.routeServiceHours.first(where: { $0.route_id == route.route_id }) {
                return (route, serviceHours.service_hours)
            }
            return nil
        }
        .sorted { route1, route2 in
            // Sort by route short name (handle numeric vs string sorting)
            let name1 = route1.route.route_short_name
            let name2 = route2.route.route_short_name
            
            // Try to compare as numbers first
            if let num1 = Int(name1), let num2 = Int(name2) {
                return num1 < num2
            }
            // Otherwise string comparison
            return name1 < name2
        }
    }
}

/// Card displaying service hours for a single route
struct RouteServiceHoursCard: View {
    let route: Route
    let serviceHours: ServiceHours
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Route header
            HStack(spacing: 8) {
                Text("Route \(route.route_short_name)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                if let color = route.route_color, !color.isEmpty {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 12, height: 12)
                }
            }
            
            // Service hours grouped by day pattern
            VStack(alignment: .leading, spacing: 6) {
                // Weekdays (Mon-Fri) if all have same hours
                if let weekdays = groupedWeekdays {
                    ServiceHoursRow(days: weekdays.label, hours: weekdays.hours)
                } else {
                    // Show individual weekdays if different
                    if let monday = serviceHours.monday {
                        ServiceHoursRow(days: "Monday", hours: monday)
                    }
                    if let tuesday = serviceHours.tuesday {
                        ServiceHoursRow(days: "Tuesday", hours: tuesday)
                    }
                    if let wednesday = serviceHours.wednesday {
                        ServiceHoursRow(days: "Wednesday", hours: wednesday)
                    }
                    if let thursday = serviceHours.thursday {
                        ServiceHoursRow(days: "Thursday", hours: thursday)
                    }
                    if let friday = serviceHours.friday {
                        ServiceHoursRow(days: "Friday", hours: friday)
                    }
                }
                
                // Saturday
                if let saturday = serviceHours.saturday {
                    ServiceHoursRow(days: "Saturday", hours: saturday)
                } else if hasAnyService {
                    ServiceHoursRow(days: "Saturday", hours: nil)
                }
                
                // Sunday
                if let sunday = serviceHours.sunday {
                    ServiceHoursRow(days: "Sunday", hours: sunday)
                } else if hasAnyService {
                    ServiceHoursRow(days: "Sunday", hours: nil)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    /// Check if route has any service at all
    private var hasAnyService: Bool {
        serviceHours.monday != nil || serviceHours.tuesday != nil ||
        serviceHours.wednesday != nil || serviceHours.thursday != nil ||
        serviceHours.friday != nil || serviceHours.saturday != nil ||
        serviceHours.sunday != nil
    }
    
    /// Group weekdays if they all have the same hours
    private var groupedWeekdays: (label: String, hours: DayHours)? {
        let weekdays = [
            serviceHours.monday,
            serviceHours.tuesday,
            serviceHours.wednesday,
            serviceHours.thursday,
            serviceHours.friday
        ]
        
        // Check if all weekdays have the same hours
        if let first = weekdays.first,
           let firstHours = first,
           weekdays.allSatisfy({ $0?.start == firstHours.start && $0?.end == firstHours.end }) {
            return ("Mon-Fri", firstHours)
        }
        return nil
    }
}

/// Row displaying service hours for a day or day range
struct ServiceHoursRow: View {
    let days: String
    let hours: DayHours?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(days)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            
            if let hours = hours {
                Text("\(hours.formattedStart()) - \(hours.formattedEnd())")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            } else {
                Text("No service")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

