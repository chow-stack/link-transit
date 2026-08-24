import SwiftUI

/// View for managing user favorites (routes and stops)
struct FavoritesView: View {
    @Environment(FavoriteStore.self) private var favoriteStore
    @Environment(DataSyncService.self) private var dataSyncService
    @State private var showingClearAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !favoriteStore.isInitialized {
                    SimpleLoadingView()
                } else if favoriteStore.favorites.isEmpty {
                    emptyState
                } else {
                    favoritesList
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !favoriteStore.favorites.isEmpty {
                        Button("Delete All") {
                            showingClearAlert = true
                        }
                        .foregroundStyle(Color("AlertRed"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Spacer for bottom nav bar (handled by MainContainerView)
                // Bottom nav bar is 60px + safe area bottom inset
                GeometryReader { geometry in
                    Spacer()
                        .frame(height: 60 + geometry.safeAreaInsets.bottom)
                }
                .frame(height: 60)
            }
        }
        .background(Color("Background"))
        .alert("Delete All Favorites", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                Task {
                    await favoriteStore.clearAllFavorites()
                }
            }
        } message: {
            Text("This will remove all your favorite routes and stops. This action cannot be undone.")
        }
    }
    
    // MARK: - UI Components
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "heart")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    Text("No Favorites Yet")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Add routes and stops to your favorites for quick access")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, min(32, UIScreen.main.bounds.width * 0.08))
                }
            }
            
            Spacer()
        }
    }
    
    private var favoritesList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Route favorites section
                if !favoriteStore.routeFavorites.isEmpty {
                    FavoritesSection(
                        title: "Routes",
                        icon: "bus.fill",
                        favorites: favoriteStore.routeFavorites,
                        onRemove: { favorite in
                            Task {
                                await favoriteStore.removeRouteFavorite(routeId: favorite.itemId)
                            }
                        }
                    )
                }
                
                // Stop favorites section
                if !favoriteStore.stopFavorites.isEmpty {
                    FavoritesSection(
                        title: "Stops",
                        icon: "mappin.circle.fill",
                        favorites: favoriteStore.stopFavorites,
                        onRemove: { favorite in
                            Task {
                                await favoriteStore.removeStopFavorite(stopId: Int(favorite.itemId) ?? 0)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Supporting Components

/// Section displaying favorites of a specific type
struct FavoritesSection: View {
    let title: String
    let icon: String
    let favorites: [Favorite]
    let onRemove: (Favorite) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color("PrimaryAccent"))
                
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(favorites.count)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color("Background").opacity(0.6))
                    )
            }
            
            // Favorites list
            VStack(spacing: 12) {
                ForEach(favorites) { favorite in
                    FavoriteRow(favorite: favorite, onRemove: onRemove)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onRemove(favorite)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                            .tint(.red)
                        }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("Background").opacity(0.8))
        )
    }
}

/// Individual favorite row
struct FavoriteRow: View {
    let favorite: Favorite
    let onRemove: (Favorite) -> Void
    @Environment(DataSyncService.self) private var dataSyncService
    @Environment(MapNavigationService.self) private var mapNavigationService
    @State private var showingRemoveAlert = false
    @State private var showingStopDetails = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: favorite.type.iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(iconBackgroundColor)
                )
            
            // Content - button if it's a stop
            Group {
                if favorite.type == .stop {
                    Button {
                        // Navigate to stop on the map
                        if let stopId = Int(favorite.itemId),
                           let stop = dataSyncService.stops.first(where: { $0.id == stopId }) {
                            mapNavigationService.requestNavigation(to: stop)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(favorite.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            
                            Text(favorite.type.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(favorite.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        
                        Text(favorite.type.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Delete button
            Button { showingRemoveAlert = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Color("AlertRed"))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("Background").opacity(0.6))
        )
        .alert("Remove Favorite", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                onRemove(favorite)
            }
        } message: {
            Text("Remove \(favorite.name) from your favorites?")
        }
    }
    
    private var iconColor: Color {
        switch favorite.type {
        case .route:
            return favorite.routeColor != nil ? Color(hex: favorite.routeColor!) : Color("PrimaryAccent")
        case .stop:
            return .green // Semantic color for stops
        }
    }
    
    private var iconBackgroundColor: Color {
        switch favorite.type {
        case .route:
            return favorite.routeColor != nil ? Color(hex: favorite.routeColor!).opacity(0.15) : Color("PrimaryAccent").opacity(0.15)
        case .stop:
            return Color.green.opacity(0.15) // Semantic color for stops
        }
    }
}

#Preview {
    FavoritesView()
        .environment(FavoriteStore())
        .environment(DataSyncService())
}
