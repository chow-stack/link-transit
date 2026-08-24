import SwiftUI
import MapKit
import SwiftData

struct ContentView: View {
    @Binding var selectedTab: MainContainerView.MainTab
    @Binding var showingFilterSheet: Bool
    @Environment(LocationManager.self) private var locationManager
    @Environment(DataSyncService.self) private var dataSyncService
    @Environment(RouteFilterStore.self) private var filterStore
    @Environment(FavoriteStore.self) private var favoriteStore
    @Environment(NotificationService.self) private var notificationService
    @Environment(AlertsService.self) private var alertsService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MapViewModel?
    @Environment(MapNavigationService.self) private var mapNavigationService
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasInitiallyPositioned = false
    @State private var showingAlertsSheet = false
    @State private var selectedStop: Stop?
    @State private var showingStopDetails = false
    @State private var selectedBus: EnrichedVehicle?
    @State private var showingBusInfo = false
    @State private var isLoading = true
    @State private var hasInitialized = false
    @State private var staticDataLoadFailed = false
    @State private var loadingPhase: AppLoadingPhase = .loadingRoutes
    
    var body: some View {
        ZStack {
            if isLoading {
                AppLaunchLoadingView(phase: loadingPhase)
                    .transition(.opacity)
            } else if staticDataLoadFailed {
                dataLoadFailureView
            } else {
                // Show no buses view or map content
                // Always show mapContent when buses exist (even if filtered),
                // so users can access the filter button to reselect routes
                if viewModel?.hasNoBuses == true {
                    NoBusesView()
                        .transition(.opacity)
                } else {
                    mapContent
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
        .onAppear {
            // Initialize view model with data sync service, filter store, and favorite store
            if viewModel == nil {
                viewModel = MapViewModel(dataSyncService: dataSyncService, filterStore: filterStore, favoriteStore: favoriteStore)
            }
            
            startLocationIfAuthorized()
            positionMapAtCurrentLocationIfNeeded()
            
            // Set up map navigation callback
            mapNavigationService.navigateToStop = { stop in
                self.navigateToStop(stop)
            }
            
            // If already initialized, skip loading screen
            if hasInitialized {
                isLoading = false
            }
            
            // Check for pending navigation when view appears and map is ready
            checkPendingNavigation()
        }
        .onChange(of: isLoading) { oldValue, newValue in
            // When map finishes loading, check for pending navigation
            if !newValue {
                checkPendingNavigation()
            }
        }
        .task(id: MapSnapshotRefreshToken(
            dataVersion: dataSyncService.dataVersion,
            enabledRouteIds: filterStore.enabledRouteIds,
            favoritesOnly: favoriteStore.showFavoritesOnly,
            favoritesRevision: favoriteStore.revision
        )) {
            viewModel?.rebuildMapSnapshot()
        }
        .task(id: LocationCoordinateToken(locationManager.userLocation)) {
            positionMapAtCurrentLocationIfNeeded()
        }
        .task(id: dataSyncService.tripUpdatesGeneration) {
            guard notificationService.isInitialized,
                  dataSyncService.tripUpdatesGeneration != nil else { return }
            await notificationService.refreshNotifications()
        }
        .task {
            // Only run initialization once
            guard !hasInitialized else { return }
            await loadDataWithPhases()
            // Only mark launch complete after bundled static data actually loaded.
            // This keeps reconnection/retry paths available if resource loading fails.
            hasInitialized = !dataSyncService.routes.isEmpty
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            // When connection is restored, automatically retry if we were stuck
            if newValue && !oldValue {
                if !isLoading && !staticDataLoadFailed {
                    // App is running - refresh realtime data only
                    Task {
                        await viewModel?.refresh()
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            RouteFilterView(filterStore: filterStore)
        }
        .sheet(isPresented: $showingStopDetails) {
            if let stop = selectedStop, let vm = viewModel {
                StopDetailsSheetLoader(viewModel: vm, stop: stop)
            }
        }
        .sheet(isPresented: $showingBusInfo) {
            if let bus = selectedBus, let vm = viewModel {
                BusInfoSheetLoader(viewModel: vm, bus: bus)
            }
        }
        .sheet(isPresented: $showingAlertsSheet) {
            AlertsDetailSheet(alertsService: alertsService)
        }
    }
    
    // MARK: - Map Content
    
    private var mapContent: some View {
        ZStack {
            // Main map view
            GeometryReader { geometry in
                Map(position: $cameraPosition) {
                // User location always shown
                UserAnnotation()

                // Route polylines (colored lines for each route)
                ForEach(viewModel?.routePolylines ?? []) { polyline in
                    MapPolyline(coordinates: polyline.coordinates)
                        .stroke(polyline.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                // Stop annotations (color-coded by route)
                ForEach(viewModel?.stops ?? []) { stopWithColor in
                    Annotation("", coordinate: stopWithColor.coordinate) {
                        StopAnnotationView(stop: stopWithColor.stop, routeColor: stopWithColor.routeColor) {
                            self.navigateToStop(stopWithColor.stop)
                        }
                    }
                }

                // Bus vehicle annotations with route colors
                ForEach(viewModel?.enrichedVehicles ?? []) { vehicle in
                    Annotation("", coordinate: vehicle.coordinate) {
                        BusAnnotationView(
                            routeShortName: vehicle.routeShortName,
                            routeColor: vehicle.routeColor,
                            heading: vehicle.vehicle.heading,
                            onTap: {
                                self.navigateToBus(vehicle)
                            }
                        )
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .top) {
                // Status bar with refresh and last updated time
                statusBar
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
            .overlay(alignment: .top) {
                // Network status banner (above alerts banner)
                NetworkStatusBanner()
                    .zIndex(1001) // Above alerts banner (1000)
            }
            .overlay(alignment: .top) {
                // Alerts banner as overlay - slides in/out as notification
                AlertsBannerView(
                    alertsService: alertsService,
                    onTap: {
                        showingAlertsSheet = true
                    },
                    onDismiss: {
                        alertsService.dismissAlerts()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .zIndex(1000) // Ensure it's on top
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            }
            
            // Offline indicator
            if viewModel?.isOffline == true {
                offlineIndicator
            }
            
            // All routes filtered message
            // Show when buses exist but all routes are filtered out
            if shouldShowFilteredRoutesMessage {
                allRoutesFilteredMessage
            }
        }
    }
    
    /// Check if we should show the "all routes filtered" message
    private var shouldShowFilteredRoutesMessage: Bool {
        guard let viewModel = viewModel else { return false }
        // Show message when:
        // 1. There are actual buses running (unfiltered)
        // 2. But no filtered vehicles are shown (all routes deselected)
        // 3. And not all routes are selected (filters are active)
        return !dataSyncService.vehicles.isEmpty &&
               viewModel.enrichedVehicles.isEmpty &&
               !viewModel.allFilteredRoutesSelected
    }
    
    /// Message shown when all routes are filtered out
    private var allRoutesFilteredMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 6) {
                Text("All Routes Filtered")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Select routes to view buses")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Button {
                showingFilterSheet = true
            } label: {
                Text("Filter Routes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color("PrimaryAccent"))
                    )
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 40)
    }
    
    // MARK: - Data Loading
    
    /// Load data optimized for speed with progress feedback
    /// Idempotent: services check their own initialization state, so this runs quickly if already initialized
    /// Dismisses loading screen immediately after static data loads, allowing UI to proceed while realtime data and other services initialize in background
    private func loadDataWithPhases() async {
        // Phase 1: Loading routes
        loadingPhase = .loadingRoutes
        staticDataLoadFailed = false
        
        // Initialize data sync FIRST (loads static data only - realtime runs in background)
        // DataSyncService will skip if already initialized
        guard let vm = viewModel else {
            // If no viewModel, ensure loading screen dismisses
            isLoading = false
            return
        }
        await vm.initialize()
        
        // Initialize stores with loaded routes
        // Initialize critical services in parallel (needed for map to display)
        // Services will skip if already initialized
        // Capture modelContext to avoid Sendable warnings
        let context = modelContext
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await favoriteStore.initialize(modelContext: context)
            }
            group.addTask { @MainActor in
                await filterStore.initialize(modelContext: context, routes: dataSyncService.routes)
            }
        }
        
        guard dataSyncService.isStaticDataReady else {
            staticDataLoadFailed = true
            isLoading = false
            return
        }

        loadingPhase = .complete
        hasInitialized = true

        withAnimation(.easeInOut(duration: 0.25)) {
            isLoading = false
        }
        
        // Initialize non-critical services in background after loading screen dismisses
        // These don't block the UI and can complete asynchronously
        Task { @MainActor in
            await notificationService.initialize(modelContext: context, dataSyncService: dataSyncService)
        }
    }
    
    // MARK: - UI Components
    
    /// Status bar showing route filter button, alerts button, and universal timer
    /// Uses theme colors for consistent appearance in light/dark mode
    private var statusBar: some View {
        HStack {
            // Route filter button - replaces active bus count badge
            filterButton
            
            // Alerts button - positioned next to filter button
            alertsButton
            
            Spacer()
            
            // Universal timer showing time since last position change
            if let lastPositionUpdate = viewModel?.lastPositionUpdate {
                UniversalTimer(lastPositionUpdate: lastPositionUpdate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Computed Properties
    
    /// Whether filters are active (not all routes selected)
    private var hasActiveFilters: Bool {
        guard let viewModel = viewModel else { return false }
        return !viewModel.allFilteredRoutesSelected
    }
    
    /// Route count text with proper filtering
    private var routeCountText: String {
        guard let viewModel = viewModel else {
            return "0/0"
        }
        let counts = viewModel.filteredRouteCounts
        return "\(counts.active)/\(counts.total)"
    }
    
    /// Filter button for accessing route filter sheet
    /// Uses theme colors for consistent appearance in light/dark mode
    /// Shows filter icon with visual indicator when filters are active
    /// Always displays route count (e.g., "16/16" when all selected)
    private var filterButton: some View {
        Button {
            showingFilterSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hasActiveFilters ? Color("PrimaryAccent") : .secondary)
                
                Text(routeCountText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color("Background").opacity(0.9))
                    .overlay(
                        Capsule()
                            .stroke(hasActiveFilters ? Color("PrimaryAccent").opacity(0.3) : Color.clear, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// Alerts button for accessing alerts modal - same size as filter button
    /// Uses theme colors for consistent appearance in light/dark mode
    private var alertsButton: some View {
        Button {
            showingAlertsSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: alertsService.activeAlertCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(alertsService.activeAlertCount > 0 ? Color("AlertRed") : Color.green)
                
                Text("\(alertsService.activeAlertCount)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color("Background").opacity(0.9))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// Offline mode indicator
    private var offlineIndicator: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .semibold))
                
                Text("Connection Error")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.red.gradient)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
            .padding(.top, 80)
            
            Spacer()
        }
    }
    
    /// Bundled GTFS failure state. Network connectivity cannot repair a missing
    /// or malformed app resource, so this is intentionally not an offline view.
    private var dataLoadFailureView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Unable to Load Transit Data")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("The bundled transit data could not be read. Please restart the app or install the latest version.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, min(40, UIScreen.main.bounds.width * 0.1))
            }
            
            // Retry button
            Button {
                // Retry initialization when user taps
                Task {
                    await loadDataWithPhases()
                }
            } label: {
                Text("Retry")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color("PrimaryAccent"))
                    )
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background"))
        .transition(.opacity)
    }
    
    // MARK: - Helper Methods
    
    /// Location permission is requested in onboarding or from Settings. The map
    /// only starts the one-shot lookup after the user has opted in.
    private func startLocationIfAuthorized() {
        if locationManager.isAuthorized {
            locationManager.startUpdatingLocation()
        }
    }
    
    /// React to the observable location value instead of polling it.
    private func positionMapAtCurrentLocationIfNeeded() {
        guard !hasInitiallyPositioned, let location = locationManager.userLocation else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        cameraPosition = .region(MKCoordinateRegion(center: location, span: span))
        hasInitiallyPositioned = true
        locationManager.stopUpdatingLocation()
    }
    
    /// Navigate to a specific stop on the map with smooth animation
    private func navigateToStop(_ stop: Stop) {
        // Animate camera to stop location with a zoom level appropriate for viewing the stop
        let span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        let region = MKCoordinateRegion(center: stop.coordinate, span: span)
        
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
        
        selectedStop = stop
        showingStopDetails = true
    }
    
    /// Check for pending navigation and execute it if conditions are met
    private func checkPendingNavigation() {
        // Only proceed if:
        // 1. Map is loaded (not in loading state)
        // 2. We're on the map tab
        // 3. There's a pending stop
        guard !isLoading,
              selectedTab == .map,
              let pendingStop = mapNavigationService.pendingStop else {
            return
        }
        
        // Clear pending stop immediately to prevent duplicate navigation
        mapNavigationService.pendingStop = nil
        
        navigateToStop(pendingStop)
    }
    
    /// Navigate to a specific bus on the map with smooth animation
    private func navigateToBus(_ bus: EnrichedVehicle) {
        // Animate camera to bus location with a zoom level appropriate for viewing the bus
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let region = MKCoordinateRegion(center: bus.coordinate, span: span)
        
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
        
        selectedBus = bus
        showingBusInfo = true
    }
    
}

// MARK: - Helper Views

/// Loader view for stop details sheet that fetches arrivals asynchronously
struct StopDetailsSheetLoader: View {
    let viewModel: MapViewModel
    let stop: Stop
    @State private var arrivals: [Arrival] = []
    @State private var servingRoutes: [Route] = []
    @State private var hasLoaded = false
    
    var body: some View {
        Group {
            if !hasLoaded {
                StopLoadingView(stopName: stop.name)
                    .transition(.opacity)
            } else {
                StopDetailsSheet(stop: stop, arrivals: arrivals, servingRoutes: servingRoutes)
                    .transition(.opacity)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: viewModel.dataSyncService.tripUpdatesGeneration) {
            arrivals = await viewModel.getArrivals(for: stop.id)
            if servingRoutes.isEmpty {
                servingRoutes = viewModel.dataSyncService.stopTimesService.getRoutesForStop(stop.id)
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                hasLoaded = true
            }
        }
    }
}

/// Loader view for bus info sheet that fetches bus data asynchronously
struct BusInfoSheetLoader: View {
    let viewModel: MapViewModel
    let bus: EnrichedVehicle
    @State private var busInfo: BusInfo?
    @State private var displayedBus: EnrichedVehicle?
    @State private var hasLoaded = false
    
    var body: some View {
        Group {
            if !hasLoaded {
                BusLoadingView(
                    routeShortName: bus.routeShortName,
                    routeLongName: bus.routeLongName,
                    routeColor: bus.routeColor
                )
                .transition(.opacity)
            } else if let busInfo = busInfo {
                BusInfoSheet(bus: displayedBus ?? bus, busInfo: busInfo)
                    .transition(.opacity)
            } else {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("Unable to load bus information")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: BusInfoRefreshToken(
            dataVersion: viewModel.dataSyncService.dataVersion,
            tripGeneration: viewModel.dataSyncService.tripUpdatesGeneration
        )) {
            let currentBus = viewModel.enrichedVehicles.first(where: { $0.id == bus.id }) ?? bus
            displayedBus = currentBus
            busInfo = await viewModel.getBusInfo(for: currentBus)
            withAnimation(.easeInOut(duration: 0.25)) {
                hasLoaded = true
            }
        }
    }
}

private struct BusInfoRefreshToken: Hashable {
    let dataVersion: Int
    let tripGeneration: Date?
}

private struct MapSnapshotRefreshToken: Hashable {
    let dataVersion: Int
    let enabledRouteIds: Set<String>
    let favoritesOnly: Bool
    let favoritesRevision: Int
}

private struct LocationCoordinateToken: Hashable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?

    init(_ coordinate: CLLocationCoordinate2D?) {
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: MainContainerView.MainTab = .map
        @State private var showingFilterSheet = false
        @State private var mapNavigationService = MapNavigationService()
        
        var body: some View {
            ContentView(
                selectedTab: $selectedTab,
                showingFilterSheet: $showingFilterSheet
            )
            .environment(LocationManager())
            .environment(DataSyncService())
            .environment(RouteFilterStore())
            .environment(FavoriteStore())
            .environment(NotificationService())
            .environment(AlertsService())
            .environment(mapNavigationService)
        }
    }
    
    return PreviewWrapper()
}
