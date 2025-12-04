import SwiftUI

/// Modern bottom sheet for filtering routes on the map
struct RouteFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataSyncService.self) private var dataSyncService
    @Environment(FavoriteStore.self) private var favoriteStore
    let filterStore: RouteFilterStore
    @State private var showingFavoritesView = false
    @State private var showingServiceHours = false
    
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingServiceHours = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(Color("PrimaryAccent"))
                    }
                }
                
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
        .sheet(isPresented: $showingServiceHours) {
            ServiceHoursSheet()
        }
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
            
            // Action buttons section - modern, clean design
            VStack(spacing: 10) {
                // Top row: Favorites toggle and Select All
                HStack(spacing: 10) {
                    // Favorites-only toggle
                    Button { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            favoriteStore.toggleFavoritesOnly()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: favoriteStore.showFavoritesOnly ? "heart.fill" : "heart")
                                .font(.system(size: 15, weight: .medium))
                            Text(favoriteStore.showFavoritesOnly ? "All Routes" : "Favorites")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(favoriteStore.showFavoritesOnly ? .primary : Color("PrimaryAccent"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Select/Deselect All button
                    Button { 
                        toggleAllFilteredRoutes()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: allFilteredRoutesSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15, weight: .medium))
                            Text(allFilteredRoutesSelected ? "Deselect All" : "Select All")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(allFilteredRoutesSelected ? .primary : Color("PrimaryAccent"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(filteredRoutes.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color("Background").opacity(0.9))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Computed Properties
    
    /// Route IDs that currently have active buses
    private var activeRouteIds: Set<String> {
        Set(dataSyncService.vehicles.map { $0.routeId })
    }
    
    /// Routes filtered by favorites-only toggle, separated into active and inactive
    private var separatedRoutes: (active: [Route], inactive: [Route]) {
        let allFiltered = filteredRoutes
        let activeIds = activeRouteIds
        
        let active = allFiltered.filter { activeIds.contains($0.route_id) }
        let inactive = allFiltered.filter { !activeIds.contains($0.route_id) }
        
        return (active: active, inactive: inactive)
    }
    
    /// Route count text showing all selected routes
    private var routeCountText: String {
        let selectedCount = filterStore.getFilteredActiveRouteCount(filteredRoutes: filteredRoutes)
        let totalCount = filteredRoutes.count
        return "\(selectedCount) of \(totalCount) routes selected"
    }
    
    /// Whether all filtered routes are selected
    private var allFilteredRoutesSelected: Bool {
        filterStore.areAllFilteredRoutesSelected(filteredRoutes: filteredRoutes)
    }
    
    /// Toggle all filtered routes (both active and inactive)
    private func toggleAllFilteredRoutes() {
        if allFilteredRoutesSelected {
            filterStore.deselectAllFiltered(filteredRoutes: filteredRoutes)
        } else {
            filterStore.selectAllFiltered(filteredRoutes: filteredRoutes)
        }
    }
    
    // MARK: - Route List
    
    private var routeList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Active Routes Section
                if !separatedRoutes.active.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Active Routes", count: separatedRoutes.active.count)
                        
                        ForEach(separatedRoutes.active.sorted(by: { $0.route_short_name < $1.route_short_name })) { route in
                            RouteFilterRow(
                                route: route,
                                isEnabled: filterStore.isRouteEnabled(route.route_id),
                                isFavorited: favoriteStore.isRouteFavorited(route.route_id),
                                isSelectable: true,
                                isInactive: false,
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
                }
                
                // Inactive Routes Section
                if !separatedRoutes.inactive.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Inactive Routes", count: separatedRoutes.inactive.count)
                        
                        ForEach(separatedRoutes.inactive.sorted(by: { $0.route_short_name < $1.route_short_name })) { route in
                            RouteFilterRow(
                                route: route,
                                isEnabled: filterStore.isRouteEnabled(route.route_id),
                                isFavorited: favoriteStore.isRouteFavorited(route.route_id),
                                isSelectable: true,
                                isInactive: true,
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
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    /// Section header for active/inactive routes
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            
            Text("(\(count))")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 4)
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
    let isSelectable: Bool
    let isInactive: Bool
    let onToggle: () -> Void
    let onToggleFavorite: () -> Void
    
    init(
        route: Route,
        isEnabled: Bool,
        isFavorited: Bool,
        isSelectable: Bool,
        isInactive: Bool = false,
        onToggle: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.route = route
        self.isEnabled = isEnabled
        self.isFavorited = isFavorited
        self.isSelectable = isSelectable
        self.isInactive = isInactive
        self.onToggle = onToggle
        self.onToggleFavorite = onToggleFavorite
    }
    
    var routeColor: Color {
        if let hex = route.route_color, !hex.isEmpty {
            return Color(hex: hex)
        }
        return .blue
    }
    
    var body: some View {
        Button { 
            if isSelectable {
                onToggle()
            }
        } label: {
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
                    .opacity(isInactive ? 0.6 : 1.0)
                
                // Route info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Route \(route.route_short_name)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isInactive ? .secondary : .primary)
                        
                        if isInactive {
                            Text("(No buses)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
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
                    .foregroundStyle(isEnabled ? Color.green : Color.gray.opacity(isInactive ? 0.2 : 0.3))
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
                    .stroke(isEnabled ? routeColor.opacity(isInactive ? 0.2 : 0.3) : Color.clear, lineWidth: 2)
            )
            .opacity(isInactive ? 0.7 : 1.0)
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

