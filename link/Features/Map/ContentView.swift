import SwiftUI
import MapKit

struct ContentView: View {
    @Binding var selectedTab: MainContainerView.MainTab
    @Binding var showingFilterSheet: Bool
    @Binding var tripPlannerViewModel: TripPlannerViewModel?
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
    @State private var loadingPhase: AppLoadingPhase = .loadingRoutes
    
    // Trip planner state
    @State private var tripOrigin: PlannedLocation?
    @State private var tripDestination: PlannedLocation?
    @State private var isSearchingRoutes = false
    @State private var showingTripResults = false
    @State private var guidanceBoardStop: Stop?
    @State private var guidanceAlightStop: Stop?
    @State private var highlightedTripId: String?
    
    var body: some View {
        ZStack {
            if isLoading {
                // Check network status and static data availability
                if !networkMonitor.isConnected && dataSyncService.routes.isEmpty {
                    // No connection and no cached data - show connection message
                    noConnectionView
                } else {
                    // Use dynamic loading for first-time app launches
                    AppLaunchLoadingView(phase: loadingPhase)
                        .transition(.opacity)
                }
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
            
            // Initialize trip planner view model
            initializeTripPlannerViewModel()
            
            requestLocationIfNeeded()
            
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
        .onChange(of: selectedTab) { oldValue, newValue in
            // When switching to map tab, check for pending navigation
            if newValue == .map {
                checkPendingNavigation()
                
                // When returning to map tab, ensure guidance state is preserved
                if let vm = tripPlannerViewModel, vm.isGuidanceMode {
                    // Restart guidance refresh task
                    vm.startGuidanceRefresh()
                    
                    // Update overlays to reflect current state
                    Task {
                        if let itinerary = vm.selectedItinerary ?? vm.itineraries.first {
                            await prepareGuidance(for: itinerary)
                        }
                    }
                }
            }
        }
        .onChange(of: isLoading) { oldValue, newValue in
            // When map finishes loading, check for pending navigation
            if !newValue {
                checkPendingNavigation()
            }
        }
        .task {
            // Only run initialization once
            guard !hasInitialized else { return }
            await loadDataWithPhases()
            hasInitialized = true
            
            // Initialize trip planner after data is loaded
            initializeTripPlannerViewModel()
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            // When connection is restored, automatically retry if we were stuck
            if newValue && !oldValue {
                // Connection just restored
                if isLoading && dataSyncService.routes.isEmpty && !hasInitialized {
                    // Only retry if we haven't initialized yet
                    Task {
                        await loadDataWithPhases()
                    }
                } else if !isLoading {
                    // App is running - refresh realtime data only
                    Task {
                        await viewModel?.refresh()
                    }
                }
            }
        }
        .onChange(of: tripPlannerViewModel?.isGuidanceMode) { oldValue, newValue in
            // When guidance mode becomes active, update overlays
            if newValue == true, let vm = tripPlannerViewModel {
                Task {
                    if let itinerary = vm.selectedItinerary ?? vm.itineraries.first {
                        await prepareGuidance(for: itinerary)
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
        .sheet(isPresented: $showingTripResults) {
            if let tripViewModel = tripPlannerViewModel {
                NavigationStack {
                    TripPlannerResultsView(
                        viewModel: tripViewModel,
                        onSelectItinerary: { itinerary in
                            tripViewModel.selectItinerary(itinerary)
                        },
                        onGo: { itinerary in
                            tripViewModel.selectItinerary(itinerary)
                            showingTripResults = false
                            // Format overlay only when entering guidance
                            let formatted = ItineraryFormatter().formatItinerary(itinerary)
                            tripViewModel.startGuidanceMode(with: formatted)
                            zoomToFormattedItinerary(formatted)
                            Task { 
                                await computeTripOverlay(for: itinerary)
                                await prepareGuidance(for: itinerary)
                            }
                            // Start guidance refresh task (updates overlays every 15s)
                            tripViewModel.startGuidanceRefresh()
                        }
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
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

                // Show network based on guidance mode
                Group {
                if tripPlannerViewModel?.isGuidanceMode != true {
                    // Normal mode: show full network
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
                } else if let itinerary = tripPlannerViewModel?.selectedItinerary ?? tripPlannerViewModel?.itineraries.first {
                    // Guidance mode: show only itinerary-related buses/routes/stops
                    // Route polylines for itinerary routes only
                    ForEach(itineraryRoutePolylines(for: itinerary)) { polyline in
                        MapPolyline(coordinates: polyline.coordinates)
                            .stroke(polyline.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    // Stop annotations for itinerary stops only
                    ForEach(itineraryStops(for: itinerary)) { stopWithColor in
                        Annotation("", coordinate: stopWithColor.coordinate) {
                            StopAnnotationView(stop: stopWithColor.stop, routeColor: stopWithColor.routeColor) {
                                self.navigateToStop(stopWithColor.stop)
                            }
                        }
                    }
                    // Bus annotations for itinerary trips only
                    ForEach(activeVehicles(for: itinerary)) { vehicle in
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
                }
                // Trip planner overlay (walk dashed, bus solid) only in guidance mode
                Group {
                if let vm = tripPlannerViewModel, vm.isGuidanceMode, let formatted = vm.formattedSelectedItinerary {
                    // Walking polylines (modern, clean dashed style)
                    ForEach(Array(0..<walkPolys(for: formatted).count), id: \.self) { idx in
                        MapPolyline(coordinates: walkPolys(for: formatted)[idx])
                            .stroke(
                                Color.primary.opacity(0.8),
                                style: StrokeStyle(
                                    lineWidth: 3,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: [12, 8],
                                    dashPhase: 0
                                )
                            )
                    }
                    // Bus polylines (solid with route color)
                    ForEach(Array(0..<rideCount(formatted: formatted)), id: \.self) { idx in
                        let (coords, color) = ridePolyAt(idx, formatted: formatted)
                        MapPolyline(coordinates: coords)
                            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    // Show all buses for routes used in the itinerary
                    // In guidance mode, we show ALL buses for the itinerary's routes for better visibility
                    if let activeItinerary = (tripPlannerViewModel?.selectedItinerary ?? tripPlannerViewModel?.itineraries.first) {
                        ForEach(activeVehicles(for: activeItinerary)) { vehicle in
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
                    // Stop markers
                    ForEach(formatted.mapAnnotations.stopMarkers) { marker in
                        Annotation(marker.stopName, coordinate: marker.coordinate) {
                            Button {
                                if let stop = nearestStop(to: marker.coordinate) {
                                    self.navigateToStop(stop)
                                }
                            } label: {
                                StopMarkerView(marker: marker)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    // Direction arrows along ride polylines
                    ForEach(directionArrows()) { arrow in
                        Annotation("", coordinate: arrow.coordinate) {
                            Image(systemName: "triangle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(arrow.headingDegrees))
                                .foregroundStyle(arrow.color)
                        }
                    }
                    // Origin marker
                    if let origin = tripPlannerViewModel?.origin {
                        Annotation("Origin", coordinate: origin.coordinate) {
                            OriginDestinationMarker(isOrigin: true)
                        }
                    }
                    // Destination marker
                    if let destination = tripPlannerViewModel?.destination {
                        Annotation("Destination", coordinate: destination.coordinate) {
                            OriginDestinationMarker(isOrigin: false)
                        }
                    }
                }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            // Keep itinerary overlay in sync and auto-zoom handled by search/selection flows
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
            .overlay(alignment: .top) {
                if let vm = tripPlannerViewModel, vm.isGuidanceMode, let formatted = vm.formattedSelectedItinerary {
                    GuidanceDirectionsBanner(
                        formatted: formatted,
                        isExpanded: Binding(
                            get: { vm.isDirectionsBannerExpanded },
                            set: { vm.isDirectionsBannerExpanded = $0 }
                        )
                    )
                    .padding(.top, 56) // Beneath status badges
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(900)
                }
            }
            .overlay(alignment: .bottom) {
                if tripPlannerViewModel?.isGuidanceMode != true {
                    // Trip planner search bar button - oval above navbar
                    VStack(spacing: 0) {
                        TripPlannerSearchBar(
                            origin: $tripOrigin,
                            destination: $tripDestination,
                            isSearching: $isSearchingRoutes,
                            onSearch: {
                                Task {
                                    await searchRoutes()
                                }
                            },
                            onLongPress: nil
                        )
                        .padding(.bottom, 72) // Space above bottom nav bar
                        .onChange(of: tripOrigin) { oldValue, newValue in
                            tripPlannerViewModel?.setOrigin(newValue)
                        }
                        .onChange(of: tripDestination) { oldValue, newValue in
                            tripPlannerViewModel?.setDestination(newValue)
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let vm = tripPlannerViewModel, vm.isGuidanceMode && vm.formattedSelectedItinerary != nil {
                    guidanceBottomBar
                        .padding(.bottom, 72)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(950)
                }
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
        .task {
            await monitorLocationUpdates()
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
        // Add timeout to ensure loading always dismisses (safety mechanism)
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if isLoading {
                print("⚠️ Force dismissing loading screen after timeout")
                isLoading = false
            }
        }
        
        // Check network status and static data availability immediately
        let hasConnection = networkMonitor.isConnected
        let hasStaticData = !dataSyncService.routes.isEmpty
        
        // If no connection and no static data, show connection message instead of loading
        // Static data loads from bundle (works offline), so we only need connection for first-time setup
        // If we have static data, we can proceed even without connection
        if !hasConnection && !hasStaticData {
            // Don't proceed - user sees noConnectionView
            // The view will automatically retry when connection is restored
            timeoutTask.cancel()
            return
        }
        
        // Check if data is already loaded (DataSyncService tracks initialization)
        // If routes are already loaded, skip loading screen
        let dataAlreadyLoaded = !dataSyncService.routes.isEmpty
        
        // Phase 1: Loading routes
        loadingPhase = .loadingRoutes
        
        // Initialize data sync FIRST (loads static data only - realtime runs in background)
        // DataSyncService will skip if already initialized
        guard let vm = viewModel else {
            // If no viewModel, ensure loading screen dismisses
            isLoading = false
            timeoutTask.cancel()
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
        
        // Phase 2: Fetching buses (non-blocking, just visual feedback)
        // GTFS-RT data is already fetching in background, this is just for user feedback
        loadingPhase = .fetchingBuses
        try? await Task.sleep(for: .milliseconds(300))
        
        // Phase 3: Complete
        loadingPhase = .complete
        
        // Show completion briefly before dismissing
        if !dataAlreadyLoaded {
            try? await Task.sleep(for: .milliseconds(400))
        }
        
        // Always dismiss loading screen - static data is ready, realtime will update when available
        withAnimation(.easeInOut(duration: 0.25)) {
            isLoading = false
        }
        
        // Cancel timeout since we dismissed normally
        timeoutTask.cancel()
        
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
    
    /// No internet connection view shown during loading when offline and no static data exists
    private var noConnectionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No Internet Connection")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("The app needs internet to load route data for the first time. Please check your connection and try again.")
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
    
    /// Request location permission if not determined
    private func requestLocationIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        } else if locationManager.isAuthorized {
            locationManager.startUpdatingLocation()
        }
    }
    
    /// Monitor location updates and center camera on first location
    @MainActor
    private func monitorLocationUpdates() async {
        // Poll for location updates
        while !Task.isCancelled {
            if !hasInitiallyPositioned, let location = locationManager.userLocation {
                // Center on user location with appropriate zoom for Bloomington, IN
                let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                let region = MKCoordinateRegion(center: location, span: span)
                cameraPosition = .region(region)
                hasInitiallyPositioned = true
            }
            
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
    
    /// Format time ago string
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
    
    /// Navigate to a specific stop on the map with smooth animation
    private func navigateToStop(_ stop: Stop) {
        // Animate camera to stop location with a zoom level appropriate for viewing the stop
        let span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        let region = MKCoordinateRegion(center: stop.coordinate, span: span)
        
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
        
        // Show stop details after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            selectedStop = stop
            showingStopDetails = true
        }
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
        
        // Wait a brief moment for UI to settle, then navigate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.navigateToStop(pendingStop)
        }
    }
    
    /// Navigate to a specific bus on the map with smooth animation
    private func navigateToBus(_ bus: EnrichedVehicle) {
        // Animate camera to bus location with a zoom level appropriate for viewing the bus
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let region = MKCoordinateRegion(center: bus.coordinate, span: span)
        
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
        
        // Show bus info after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            selectedBus = bus
            showingBusInfo = true
        }
    }
    
    // MARK: - Trip Planner Methods
    
    /// Initialize trip planner view model with required dependencies
    private func initializeTripPlannerViewModel() {
        // Only initialize once (check binding value)
        guard tripPlannerViewModel == nil else { return }
        
        // Wait for data sync service to be initialized (stops loaded)
        guard !dataSyncService.stops.isEmpty else { return }
        
        // Create TripRoutingEngine (simplified for OTP API integration)
        let routingEngine = TripRoutingEngine(
            walkingRouteService: WalkingRouteService.shared,
            dataSyncService: dataSyncService
        )
        
        // Create StopIndex (still needed for TripPlannerViewModel)
        let stopIndex = StopIndex(stops: dataSyncService.stops)
        
        // Create TripPlannerViewModel and assign to binding
        tripPlannerViewModel = TripPlannerViewModel(
            routingEngine: routingEngine,
            dataSyncService: dataSyncService,
            stopIndex: stopIndex
        )
        
        // Sync origin/destination with view model
        tripPlannerViewModel?.setOrigin(tripOrigin)
        tripPlannerViewModel?.setDestination(tripDestination)
    }
    
    /// Search for routes between origin and destination
    private func searchRoutes() async {
        guard tripOrigin != nil || locationManager.userLocation != nil,
              tripDestination != nil else {
            return
        }
        
        // Ensure trip planner view model is initialized
        if tripPlannerViewModel == nil {
            initializeTripPlannerViewModel()
        }
        
        guard let tripViewModel = tripPlannerViewModel else {
            return
        }
        
        // Set origin (use user location if not set)
        if tripOrigin == nil, let userLocation = locationManager.userLocation {
            tripOrigin = PlannedLocation(
                coordinate: userLocation,
                address: nil
            )
        }
        
        // Update view model with current locations
        tripViewModel.setOrigin(tripOrigin)
        tripViewModel.setDestination(tripDestination)
        
        isSearchingRoutes = true
        
        // Search for routes
        await tripViewModel.searchRoutes()
        
        isSearchingRoutes = false
        
        // Show results if we have any
        if !tripViewModel.itineraries.isEmpty || tripViewModel.errorMessage != nil {
            showingTripResults = true
        }
        
        // Start auto-refresh if we have results
        if !tripViewModel.itineraries.isEmpty {
            tripViewModel.startAutoRefresh()
        }

        // Do not format or show overlay here; overlays are shown only after tapping Go
    }

    /// Update formatted itinerary overlay and zoom map to fit
    private func updateItineraryOverlayAndZoom() {
        guard let vm = tripPlannerViewModel else { return }
        // Prefer selected itinerary; fallback to first result
        if let selected = vm.selectedItinerary ?? vm.itineraries.first {
            let formatted = ItineraryFormatter().formatItinerary(selected)
            vm.formattedSelectedItinerary = formatted
            Task { await computeTripOverlay(for: selected) }
            zoomToFormattedItinerary(formatted)
        } else {
            vm.formattedSelectedItinerary = nil
            vm.computedWalkPolylines = []
            vm.computedRidePolylines = []
        }
    }

    /// Build high-fidelity polylines for walking (MKDirections) and rides (GTFS shapes)
    private func computeTripOverlay(for itinerary: Itinerary) async {
        var walkPolys: [[CLLocationCoordinate2D]] = []
        var ridePolys: [([CLLocationCoordinate2D], Color)] = []
        
        for segment in itinerary.segments {
            switch segment {
            case .walk(_, _, _, let from, let to):
                // Use MKDirections walking route polyline
                if let route = try? await WalkingRouteService.shared.calculateWalkingRoute(from: from, to: to) {
                    walkPolys.append(route.polyline)
                } else {
                    walkPolys.append([from, to])
                }
            case .ride(_, _, _, let routeColorHex, let fromStop, let toStop, _, _, let tripId):
                // Use trip's shape polyline; fallback to straight line between stops if missing
                var foundShape = false
                
                if let tripId = tripId {
                    // OTP may return trip IDs in "agency:tripId" format, try both formats
                    let normalizedTripId = normalizeTripId(tripId)
                    
                    // Try to find trip in local GTFS data
                    if let trip = dataSyncService.trips.first(where: { 
                        normalizeTripId($0.trip_id) == normalizedTripId 
                    }), let shapeId = trip.shape_id {
                        let shapePoints = dataSyncService.shapes
                            .filter { $0.shape_id == shapeId }
                            .sorted { $0.shape_pt_sequence < $1.shape_pt_sequence }
                        
                        if !shapePoints.isEmpty {
                            // Filter shape points to the segment between fromStop and toStop
                            // by finding the closest shape points to the stops
                            let coords = filterShapeBetweenStops(
                                shapePoints: shapePoints,
                                fromStop: fromStop,
                                toStop: toStop
                            )
                            let color = (routeColorHex != nil && !(routeColorHex!).isEmpty) ? Color(hex: routeColorHex!) : Color("PrimaryAccent")
                            ridePolys.append((coords, color))
                            foundShape = true
                        }
                    }
                }
                
                // Fallback: draw straight line between boarding and alighting stops
                if !foundShape {
                    let coords = [fromStop.coordinate, toStop.coordinate]
                    let color = (routeColorHex != nil && !(routeColorHex!).isEmpty) ? Color(hex: routeColorHex!) : Color("PrimaryAccent")
                    ridePolys.append((coords, color))
                }
            }
        }
        // Update on main actor
        await MainActor.run {
            tripPlannerViewModel?.computedWalkPolylines = walkPolys
            tripPlannerViewModel?.computedRidePolylines = ridePolys
        }
    }
    
    /// Normalize trip ID to handle both "agency:tripId" and "tripId" formats
    private func normalizeTripId(_ tripId: String) -> String {
        // If it contains a colon, extract the part after the colon (OTP format: "agency:tripId")
        if let colonIndex = tripId.firstIndex(of: ":") {
            return String(tripId[tripId.index(after: colonIndex)...])
        }
        return tripId
    }
    
    /// Filter shape points to the segment between two stops
    private func filterShapeBetweenStops(
        shapePoints: [Shape],
        fromStop: Stop,
        toStop: Stop
    ) -> [CLLocationCoordinate2D] {
        guard !shapePoints.isEmpty else { return [fromStop.coordinate, toStop.coordinate] }
        
        // Find closest shape points to each stop
        var fromIndex = 0
        var toIndex = shapePoints.count - 1
        var minFromDist = Double.greatestFiniteMagnitude
        var minToDist = Double.greatestFiniteMagnitude
        
        for (index, shapePoint) in shapePoints.enumerated() {
            let fromDist = CLLocation(
                latitude: fromStop.lat,
                longitude: fromStop.lon
            ).distance(from: CLLocation(
                latitude: shapePoint.shape_pt_lat,
                longitude: shapePoint.shape_pt_lon
            ))
            
            let toDist = CLLocation(
                latitude: toStop.lat,
                longitude: toStop.lon
            ).distance(from: CLLocation(
                latitude: shapePoint.shape_pt_lat,
                longitude: shapePoint.shape_pt_lon
            ))
            
            if fromDist < minFromDist {
                minFromDist = fromDist
                fromIndex = index
            }
            
            if toDist < minToDist {
                minToDist = toDist
                toIndex = index
            }
        }
        
        // Ensure fromIndex < toIndex
        let startIndex = min(fromIndex, toIndex)
        let endIndex = max(fromIndex, toIndex)
        
        // Extract segment between stops, including the stops themselves
        var coords = shapePoints[startIndex...endIndex].map { 
            CLLocationCoordinate2D(latitude: $0.shape_pt_lat, longitude: $0.shape_pt_lon) 
        }
        
        // Add actual stop coordinates at the beginning and end for accuracy
        coords.insert(fromStop.coordinate, at: 0)
        coords.append(toStop.coordinate)
        
        return coords
    }

    /// Zoom camera to fit a formatted itinerary's coordinates
    private func zoomToFormattedItinerary(_ formatted: FormattedItinerary) {
        var coords: [CLLocationCoordinate2D] = []
        // Collect all polyline points
        for poly in formatted.mapAnnotations.walkPolylines { coords.append(contentsOf: poly.coordinates) }
        for poly in formatted.mapAnnotations.ridePolylines { coords.append(contentsOf: poly.coordinates) }
        // Include origin/destination if present
        if let origin = tripPlannerViewModel?.origin { coords.append(origin.coordinate) }
        if let destination = tripPlannerViewModel?.destination { coords.append(destination.coordinate) }
        guard !coords.isEmpty else { return }
        let minLat = coords.map { $0.latitude }.min()!
        let maxLat = coords.map { $0.latitude }.max()!
        let minLon = coords.map { $0.longitude }.min()!
        let maxLon = coords.map { $0.longitude }.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        // Add padding factor for comfortable viewing
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.005) * 1.4,
            longitudeDelta: max(maxLon - minLon, 0.005) * 1.4
        )
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    // MARK: - Overlay Helpers
    private func walkPolys(for formatted: FormattedItinerary) -> [[CLLocationCoordinate2D]] {
        if let vm = tripPlannerViewModel, !vm.computedWalkPolylines.isEmpty { return vm.computedWalkPolylines }
        return formatted.mapAnnotations.walkPolylines.map { $0.coordinates }
    }
    private func rideCount(formatted: FormattedItinerary) -> Int {
        if let vm = tripPlannerViewModel, !vm.computedRidePolylines.isEmpty { return vm.computedRidePolylines.count }
        return formatted.mapAnnotations.ridePolylines.count
    }
    private func ridePolyAt(_ index: Int, formatted: FormattedItinerary) -> ([CLLocationCoordinate2D], Color) {
        if let vm = tripPlannerViewModel, !vm.computedRidePolylines.isEmpty {
            return vm.computedRidePolylines[index]
        } else {
            let poly = formatted.mapAnnotations.ridePolylines[index]
            return (poly.coordinates, poly.color)
        }
    }
    /// Get all buses for routes used in the itinerary
    /// In guidance mode, we show ALL buses for the routes in the itinerary, not just specific trips
    /// This provides better visibility and is more reliable than matching exact trip IDs
    private func activeVehicles(for itinerary: Itinerary) -> [EnrichedVehicle] {
        let routeIds = itineraryRouteIds(for: itinerary)
        let vehicles = viewModel?.enrichedVehicles ?? []
        
        // Filter vehicles by route IDs - show all buses for itinerary routes
        return vehicles.filter { vehicle in
            routeIds.contains(vehicle.vehicle.routeId)
        }
    }
    
    /// Get route IDs used in the itinerary
    private func itineraryRouteIds(for itinerary: Itinerary) -> Set<String> {
        var routeIds = Set<String>()
        for segment in itinerary.segments {
            if case let .ride(_, routeId, _, _, _, _, _, _, _) = segment {
                routeIds.insert(routeId)
            }
        }
        return routeIds
    }
    
    /// Get stop IDs used in the itinerary (boarding, alighting, and stops along routes)
    private func itineraryStopIds(for itinerary: Itinerary) -> Set<Int> {
        var stopIds = Set<Int>()
        let routeIds = itineraryRouteIds(for: itinerary)
        
        // Get all stops served by routes in the itinerary using StopTimesService
        let routeStops = dataSyncService.stopTimesService.getStopsForRoutes(routeIds)
        stopIds.formUnion(routeStops)
        
        // Always include boarding and alighting stops explicitly
        for segment in itinerary.segments {
            if case let .ride(_, _, _, _, fromStop, toStop, _, _, _) = segment {
                stopIds.insert(fromStop.id)
                stopIds.insert(toStop.id)
            }
        }
        
        return stopIds
    }
    
    /// Get route polylines for itinerary routes only
    /// Ensures polylines use the correct colors from GTFS route data to match itinerary routes
    private func itineraryRoutePolylines(for itinerary: Itinerary) -> [RoutePolyline] {
        let routeIds = itineraryRouteIds(for: itinerary)
        guard let routePolylines = viewModel?.routePolylines else { return [] }
        
        // Match polylines by finding routes where route_short_name matches polyline.routeName
        // Then check if the route_id is in the itinerary routeIds
        // Also ensure colors match the GTFS route colors from the itinerary
        return routePolylines.compactMap { polyline -> RoutePolyline? in
            // Find route by short name (routeName in polyline)
            guard let route = dataSyncService.routes.first(where: { $0.route_short_name == polyline.routeName }),
                  routeIds.contains(route.route_id) else {
                return nil
            }
            
            // Ensure color matches GTFS route color (not the polyline's cached color which might be outdated)
            let routeColor: Color
            if let hex = route.route_color, !hex.isEmpty {
                routeColor = Color(hex: hex)
            } else {
                routeColor = Color("PrimaryAccent")
            }
            
            // Return polyline with corrected color from GTFS route data
            return RoutePolyline(
                id: polyline.id,
                coordinates: polyline.coordinates,
                color: routeColor,
                routeName: polyline.routeName
            )
        }
    }
    
    /// Get stops for itinerary routes only
    /// Only includes stops that are actually on the itinerary segments, not all stops for those routes
    /// Colors are determined by the itinerary route that uses each stop, not by the first route serving it
    private func itineraryStops(for itinerary: Itinerary) -> [StopWithColor] {
        var stopIds = Set<Int>()
        var stopToRouteMap: [Int: String] = [:] // Map stop ID to route ID from itinerary
        
        // Collect only stops from the actual itinerary segments (boarding, alighting, and stops between)
        for segment in itinerary.segments {
            switch segment {
            case .ride(_, let routeId, _, _, let fromStop, let toStop, _, _, let tripId):
                // Always include boarding and alighting stops, mapped to their route
                stopIds.insert(fromStop.id)
                stopToRouteMap[fromStop.id] = routeId
                stopIds.insert(toStop.id)
                stopToRouteMap[toStop.id] = routeId
                
                // If we have a trip ID, get all stops along that specific trip
                if let tripId = tripId {
                    let normalizedTripId = normalizeTripId(tripId)
                    if let trip = dataSyncService.trips.first(where: { 
                        normalizeTripId($0.trip_id) == normalizedTripId 
                    }) {
                        // Get stop sequence for this specific trip
                        let stopSequence = dataSyncService.stopTimesService.getStopSequence(for: trip.trip_id)
                        let tripStopIds = stopSequence.map { $0.stopId }
                        stopIds.formUnion(tripStopIds)
                        
                        // Map all stops in this trip to the route ID
                        for tripStopId in tripStopIds {
                            stopToRouteMap[tripStopId] = routeId
                        }
                    }
                }
            case .walk:
                // Walking segments don't add stops
                break
            }
        }
        
        guard let allStops = viewModel?.stops else { return [] }
        
        // Filter and recolor stops based on itinerary route colors
        return allStops
            .filter { stopIds.contains($0.stop.id) }
            .compactMap { stopWithColor -> StopWithColor? in
                // Get the route ID from the itinerary that uses this stop
                guard let routeId = stopToRouteMap[stopWithColor.stop.id],
                      let route = dataSyncService.routes.first(where: { $0.route_id == routeId }) else {
                    // Fallback to original color if route not found
                    return stopWithColor
                }
                
                // Determine route color from itinerary route
                let routeColor: Color
                if let hex = route.route_color, !hex.isEmpty {
                    routeColor = Color(hex: hex)
                } else {
                    routeColor = Color("PrimaryAccent")
                }
                
                // Return stop with itinerary route color
                return StopWithColor(stop: stopWithColor.stop, routeColor: routeColor)
            }
    }

    // MARK: - Guidance UI
    private var guidanceBottomBar: some View {
        Button {
            // No-op in guidance mode; details open removed
        } label: {
            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ETA")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(arrivalText())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Duration")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(durationText())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color("PrimaryAccent"))
                    }
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Distance")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(distanceText())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        // Cancel guidance mode and reset trip planner state
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tripPlannerViewModel?.exitGuidanceMode()
                        }
                        // Reset search fields
                        tripOrigin = nil
                        tripDestination = nil
                        // Hide any results
                        showingTripResults = false
                        // Reset view model
                        if let tpvm = tripPlannerViewModel {
                            tpvm.clearResults()
                            tpvm.setOrigin(nil)
                            tpvm.setDestination(nil)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Cancel")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color("AlertRed")))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color("Background").opacity(0.95))
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    private func durationText() -> String {
        tripPlannerViewModel?.formattedSelectedItinerary?.summary.formattedTotalTime ?? "--"
    }
    private func arrivalText() -> String {
        tripPlannerViewModel?.formattedSelectedItinerary?.summary.formattedArrivalTime ?? "Arrive --"
    }
    private func distanceText() -> String {
        if let itin = tripPlannerViewModel?.selectedItinerary ?? tripPlannerViewModel?.itineraries.first {
            let miles = itin.totalDistance / 1609.344
            return String(format: "%.1f mi", miles)
        }
        return "-- mi"
    }

    // MARK: - Guidance Prep & Utilities
    private func nearestStop(to coordinate: CLLocationCoordinate2D) -> Stop? {
        let stops = dataSyncService.stops
        return stops.min(by: { a, b in
            CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <
            CLLocation(latitude: b.lat, longitude: b.lon).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        })
    }
    /// Prepare guidance mode by identifying boarding/alighting stops
    /// Note: We no longer try to highlight a specific bus - instead we show ALL buses
    /// for the routes used in the itinerary, which is more reliable and provides better visibility
    private func prepareGuidance(for itinerary: Itinerary) async {
        // Identify first ride segment (boarding) and last ride segment (alighting)
        var boardStop: Stop?
        var alightStop: Stop?
        
        for segment in itinerary.segments {
            switch segment {
            case .ride(_, _, _, _, let fromStop, let toStop, _, _, _):
                if boardStop == nil { boardStop = fromStop }
                alightStop = toStop
            case .walk:
                // Walking segments don't affect boarding/alighting stops
                break
            }
        }
        
        await MainActor.run {
            self.guidanceBoardStop = boardStop
            self.guidanceAlightStop = alightStop
            // Clear highlighted trip ID since we're showing all buses for routes
            self.highlightedTripId = nil
        }
    }
    private struct DirectionArrow: Identifiable { let id = UUID(); let coordinate: CLLocationCoordinate2D; let headingDegrees: Double; let color: Color }
    private func directionArrows() -> [DirectionArrow] {
        guard let vm = tripPlannerViewModel, vm.isGuidanceMode else { return [] }
        var arrows: [DirectionArrow] = []
        let strideStep = 20 // sample every 20th point
        for (coords, color) in vm.computedRidePolylines {
            guard coords.count > 2 else { continue }
            var i = 0
            while i + 1 < coords.count {
                let a = coords[i]
                let b = coords[i + 1]
                let heading = headingDegrees(from: a, to: b)
                arrows.append(DirectionArrow(coordinate: b, headingDegrees: heading, color: color))
                i += strideStep
            }
        }
        return arrows
    }
    private func headingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
    /// Get highlighted vehicle (deprecated - we now show all buses for itinerary routes)
    /// Kept for backwards compatibility but no longer used in guidance mode
    private func currentHighlightedVehicle() -> EnrichedVehicle? {
        // This method is no longer used since we show all buses for routes
        // in guidance mode instead of highlighting a specific bus
        return nil
    }
}

// MARK: - Helper Views

/// Loader view for stop details sheet that fetches arrivals asynchronously
struct StopDetailsSheetLoader: View {
    let viewModel: MapViewModel
    let stop: Stop
    @State private var arrivals: [Arrival] = []
    @State private var servingRoutes: [Route] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                StopLoadingView(stopName: stop.name)
                    .transition(.opacity)
            } else {
                StopDetailsSheet(stop: stop, arrivals: arrivals, servingRoutes: servingRoutes)
                    .transition(.opacity)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            // Fetch data immediately - no initial delay
            arrivals = await viewModel.getArrivals(for: stop.id)
            servingRoutes = viewModel.dataSyncService.stopTimesService.getRoutesForStop(stop.id)
            
            // Ensure loading was visible for minimum time
            try? await Task.sleep(for: .milliseconds(300))
            
            // Smooth transition to content
            withAnimation(.easeInOut(duration: 0.25)) {
                isLoading = false
            }
        }
    }
}

/// Loader view for bus info sheet that fetches bus data asynchronously
struct BusInfoSheetLoader: View {
    let viewModel: MapViewModel
    let bus: EnrichedVehicle
    @State private var busInfo: BusInfo?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                BusLoadingView(
                    routeShortName: bus.routeShortName,
                    routeLongName: bus.routeLongName,
                    routeColor: bus.routeColor
                )
                .transition(.opacity)
            } else if let busInfo = busInfo {
                BusInfoSheet(bus: bus, busInfo: busInfo)
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
        .task {
            // Fetch data immediately - no initial delay
            busInfo = await viewModel.getBusInfo(for: bus)
            
            // Ensure loading was visible for minimum time
            try? await Task.sleep(for: .milliseconds(300))
            
            // Smooth transition to content
            withAnimation(.easeInOut(duration: 0.25)) {
                isLoading = false
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: MainContainerView.MainTab = .map
        @State private var showingFilterSheet = false
        @State private var tripPlannerViewModel: TripPlannerViewModel?
        @State private var mapNavigationService = MapNavigationService()
        
        var body: some View {
            ContentView(
                selectedTab: $selectedTab,
                showingFilterSheet: $showingFilterSheet,
                tripPlannerViewModel: $tripPlannerViewModel
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

