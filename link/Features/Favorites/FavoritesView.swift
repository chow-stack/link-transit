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
        ContentUnavailableView(
            "No Favorites Yet",
            systemImage: "heart",
            description: Text("Add routes and stops to your favorites for quick access.")
        )
        .frame(maxHeight: .infinity)
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("PrimaryAccent"))

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(favorites.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }

            // Favorites list
            VStack(spacing: 10) {
                ForEach(favorites) { favorite in
                    FavoriteRow(favorite: favorite, onRemove: onRemove)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onRemove(favorite)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                            .tint(Color("AlertRed"))
                        }
                }
            }
        }
        .padding(20)
        .appSheetCard(cornerRadius: 16)
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
        HStack(spacing: 14) {
            // Icon
            Image(systemName: favorite.type.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(iconColor.opacity(0.15)))

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
                        favoriteLabel
                    }
                    .buttonStyle(.plain)
                } else {
                    favoriteLabel
                }
            }

            Spacer()

            // Delete button
            Button { showingRemoveAlert = true } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(Color("AlertRed"))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(favorite.name) from favorites")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .appSheetCard(cornerRadius: 12)
        .alert("Remove Favorite", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                onRemove(favorite)
            }
        } message: {
            Text("Remove \(favorite.name) from your favorites?")
        }
    }

    private var favoriteLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(favorite.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(favorite.type.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var iconColor: Color {
        switch favorite.type {
        case .route:
            return favorite.routeColor != nil ? Color(hex: favorite.routeColor!) : Color("PrimaryAccent")
        case .stop:
            return Color("PrimaryAccent")
        }
    }
}

#Preview {
    FavoritesView()
        .environment(FavoriteStore())
        .environment(DataSyncService())
}
