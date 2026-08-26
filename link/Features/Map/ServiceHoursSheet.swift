import SwiftUI
import Foundation

/// Sheet displaying service hours for all routes
struct ServiceHoursSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataSyncService.self) private var dataSyncService
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "clock.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color("PrimaryAccent"))

                        Text("Service Hours")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("Regular operating hours for each route")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
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
                    .padding(.bottom, 20)
                }
            }
            .background(Color("Background"))
            .navigationTitle("Service Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
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

