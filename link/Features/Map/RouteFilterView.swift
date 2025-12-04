import SwiftUI

/// Modern bottom sheet for filtering routes on the map
struct RouteFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataSyncService.self) private var dataSyncService
    @Environment(FavoriteStore.self) private var favoriteStore
    let filterStore: RouteFilterStore
    @State private var showingFavoritesView = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background - use theme color
                Color("Background")
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with Select All/Deselect All buttons
                    headerView
                    
                    // Route list
                    if dataSyncService.routes.isEmpty {
                        emptyState
                    } else {
                        routeList
                    }
                }
            }
            .navigationTitle("Filter Routes")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Stats with proper filtering
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("PrimaryAccent"))
                
                Text(routeCountText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            // Action buttons section
            VStack(spacing: 12) {
                // Side-by-side buttons for favorites toggle and select/deselect
                HStack(spacing: 12) {
                    // Favorites-only toggle (always visible, cleaner text)
                    Button { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            favoriteStore.toggleFavoritesOnly()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: favoriteStore.showFavoritesOnly ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                            Text(favoriteStore.showFavoritesOnly ? "All Routes" : "Favorites Only")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(favoriteStore.showFavoritesOnly ? Color.red.gradient : Color.orange.gradient)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                    }
                    
                    // Select/Deselect toggle button
                    Button { 
                        toggleAllFilteredRoutes()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: allFilteredRoutesSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                            Text(allFilteredRoutesSelected ? "Deselect All" : "Select All")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(allFilteredRoutesSelected ? Color.red.gradient : Color.green.gradient)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                    }
                    .disabled(currentFilteredRoutes.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color("Background").opacity(0.9))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Computed Properties
    
    /// Current filtered routes
    private var currentFilteredRoutes: [Route] {
        filteredRoutes
    }
    
    /// Route count text with proper filtering
    private var routeCountText: String {
        let activeCount = filterStore.getFilteredActiveRouteCount(filteredRoutes: currentFilteredRoutes)
        let totalCount = filterStore.getFilteredTotalRouteCount(filteredRoutes: currentFilteredRoutes)
        return "\(activeCount) of \(totalCount) routes selected"
    }
    
    /// Whether all filtered routes are selected
    private var allFilteredRoutesSelected: Bool {
        filterStore.areAllFilteredRoutesSelected(filteredRoutes: currentFilteredRoutes)
    }
    
    /// Toggle all filtered routes
    private func toggleAllFilteredRoutes() {
        if allFilteredRoutesSelected {
            filterStore.deselectAllFiltered(filteredRoutes: currentFilteredRoutes)
        } else {
            filterStore.selectAllFiltered(filteredRoutes: currentFilteredRoutes)
        }
    }
    
    // MARK: - Route List
    
    private var routeList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredRoutes.sorted(by: { $0.route_short_name < $1.route_short_name })) { route in
                    RouteFilterRow(
                        route: route,
                        isEnabled: filterStore.isRouteEnabled(route.route_id),
                        isFavorited: favoriteStore.isRouteFavorited(route.route_id),
                        onToggle: {
                            filterStore.toggleRoute(route.route_id)
                        },
                        onToggleFavorite: {
                            Task {
                                await favoriteStore.toggleRouteFavorite(
                                    routeId: route.route_id,
                                    name: "Route \(route.route_short_name)",
                                    routeColor: route.route_color
                                )
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    /// Routes filtered by favorites-only toggle
    private var filteredRoutes: [Route] {
        if favoriteStore.showFavoritesOnly {
            return dataSyncService.routes.filter { favoriteStore.isRouteFavorited($0.route_id) }
        } else {
            return dataSyncService.routes
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 4) {
                Text("No Routes Available")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Routes will appear here once loaded")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Route Filter Row

struct RouteFilterRow: View {
    let route: Route
    let isEnabled: Bool
    let isFavorited: Bool
    let onToggle: () -> Void
    let onToggleFavorite: () -> Void
    
    var routeColor: Color {
        if let hex = route.route_color, !hex.isEmpty {
            return Color(hex: hex)
        }
        return .blue
    }
    
    var body: some View {
        Button { onToggle() } label: {
            HStack(spacing: 12) {
                // Route color indicator
                Circle()
                    .fill(routeColor.gradient)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(route.route_short_name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: routeColor.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Route info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Route \(route.route_short_name)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(route.route_long_name)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Favorite button
                Button { 
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onToggleFavorite()
                } label: {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isFavorited ? Color.red : Color.gray.opacity(0.5))
                        .scaleEffect(isFavorited ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFavorited)
                }
                .buttonStyle(.plain)
                
                // Toggle indicator
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.green : Color.gray.opacity(0.3))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isEnabled)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("Background").opacity(0.9))
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isEnabled ? routeColor.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var dataSyncService = DataSyncService()
    @Previewable @State var filterStore = RouteFilterStore()
    @Previewable @State var favoriteStore = FavoriteStore()
    
    RouteFilterView(filterStore: filterStore)
        .environment(dataSyncService)
        .environment(favoriteStore)
        .onAppear {
            // Mock data for preview
            dataSyncService.routes = [
                try! JSONDecoder().decode(Route.self, from: """
                    {"route_id":"1","route_short_name":"1","route_long_name":"Campus Loop","route_color":"EC0E0E"}
                    """.data(using: .utf8)!),
                try! JSONDecoder().decode(Route.self, from: """
                    {"route_id":"6","route_short_name":"6","route_long_name":"East Campus Express","route_color":"0066CC"}
                    """.data(using: .utf8)!),
                try! JSONDecoder().decode(Route.self, from: """
                    {"route_id":"9","route_short_name":"9","route_long_name":"Downtown Shuttle","route_color":"00AA44"}
                    """.data(using: .utf8)!)
            ]
        }
}

