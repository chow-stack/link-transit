import SwiftUI
import CoreLocation
import MapKit
import Combine

/// Search bar button component for trip planning - oval button that opens full sheet
struct TripPlannerSearchBar: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(FavoriteStore.self) private var favoriteStore
    
    @Binding var origin: PlannedLocation?
    @Binding var destination: PlannedLocation?
    @Binding var isSearching: Bool
    
    @State private var searchText: String = ""
    @State private var showingSearchSheet = false
    @State private var lastObservedLatitude: Double?
    @State private var lastObservedLongitude: Double?
    
    // MKLocalSearchCompleter for address suggestions
    @StateObject private var searchCompleter = SearchCompleterManager()
    
    var onSearch: () -> Void
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    
    // Computed properties to extract Equatable values for onChange
    private var userLatitude: Double? {
        locationManager.userLocation?.latitude
    }
    
    private var userLongitude: Double? {
        locationManager.userLocation?.longitude
    }
    
    var body: some View {
        Button(action: {
            showingSearchSheet = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                
                Text(collapsedText)
                    .font(.system(size: 16, weight: .regular))
                
                if destination != nil || !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        destination = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear destination")
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color("Background"))
            )
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search for destination")
        .accessibilityHint("Double tap to open search sheet")
        .onChange(of: destination) { oldValue, newValue in
            if let newValue = newValue {
                searchText = newValue.address ?? newValue.displayName
            } else if searchText.isEmpty {
                searchText = ""
            }
        }
        .onAppear {
            // Set origin to user location if not set
            if origin == nil, let userLocation = locationManager.userLocation {
                origin = PlannedLocation(coordinate: userLocation, address: "My Location")
                // Update search completer region to user location
                searchCompleter.updateRegion(center: userLocation)
                lastObservedLatitude = userLocation.latitude
                lastObservedLongitude = userLocation.longitude
            }
        }
        .onChange(of: userLatitude) {
            // Update search completer region when location changes
            guard let newLocation = locationManager.userLocation else { return }
            let newLat = newLocation.latitude
            
            // Only update if moved significantly (more than ~0.001 degrees, roughly 100m)
            if let oldLat = lastObservedLatitude, abs(newLat - oldLat) > 0.001 {
                searchCompleter.updateRegion(center: newLocation)
                lastObservedLatitude = newLat
            } else if lastObservedLatitude == nil {
                // First location update
                searchCompleter.updateRegion(center: newLocation)
                lastObservedLatitude = newLat
            }
        }
        .onChange(of: userLongitude) {
            // Update search completer region when location changes
            guard let newLocation = locationManager.userLocation else { return }
            let newLon = newLocation.longitude
            
            // Only update if moved significantly (more than ~0.001 degrees, roughly 100m)
            if let oldLon = lastObservedLongitude, abs(newLon - oldLon) > 0.001 {
                searchCompleter.updateRegion(center: newLocation)
                lastObservedLongitude = newLon
            } else if lastObservedLongitude == nil {
                // First location update
                searchCompleter.updateRegion(center: newLocation)
                lastObservedLongitude = newLon
            }
        }
        .sheet(isPresented: $showingSearchSheet) {
            TripPlannerSearchSheet(
                origin: $origin,
                destination: $destination,
                isSearching: $isSearching,
                searchText: $searchText,
                searchCompleter: searchCompleter,
                onSearch: {
                    showingSearchSheet = false
                    onSearch()
                },
                onDismiss: {
                    showingSearchSheet = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
        }
    }
    
    private var collapsedText: String {
        if let destination = destination {
            return destination.address ?? destination.displayName
        } else if !searchText.isEmpty {
            return searchText
        } else {
            return "Where to?"
        }
    }
}

// MARK: - Full Sheet View

struct TripPlannerSearchSheet: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(FavoriteStore.self) private var favoriteStore
    
    @Binding var origin: PlannedLocation?
    @Binding var destination: PlannedLocation?
    @Binding var isSearching: Bool
    @Binding var searchText: String
    
    @ObservedObject var searchCompleter: SearchCompleterManager
    
    // Local focus state for the search field
    @FocusState private var searchFieldFocus: Bool
    
    // Recent places state for immediate view updates
    @State private var recentPlaces: [String] = []
    
    var onSearch: () -> Void
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Search field with dismiss button
                    HStack(spacing: 12) {
                        // Search field
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 18))
                            
                            TextField("Enter destination", text: $searchText)
                                .font(.body)
                                .foregroundColor(.primary)
                                .textFieldStyle(.plain)
                                .focused($searchFieldFocus)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .accessibilityLabel("Destination search field")
                                .accessibilityHint("Enter an address or place name")
                                .onChange(of: searchText) { oldValue, newValue in
                                    handleSearchTextChange(newValue)
                                }
                            
                            Button(action: {
                                searchText = ""
                                destination = nil
                                searchCompleter.completions = []
                            }) {
                                Image(systemName: "xmark")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .opacity(searchText.isEmpty ? 0 : 1)
                            .accessibilityLabel("Clear search")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                        
                        // Dismiss sheet button
                        Button(action: {
                            onDismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 28))
                        }
                        .accessibilityLabel("Close search sheet")
                    }
                    
                    // Address suggestions from MKLocalSearchCompleter
                    if !searchCompleter.completions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(searchCompleter.completions.enumerated()), id: \.offset) { index, completion in
                                Button(action: {
                                    selectCompletion(completion)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundColor(Color("AlertRed"))
                                            .font(.system(size: 16))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(completion.title)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            
                                            if !completion.subtitle.isEmpty {
                                                Text(completion.subtitle)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(completion.title), \(completion.subtitle)")
                                .accessibilityHint("Double tap to select this location")
                                
                                if index < searchCompleter.completions.count - 1 {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }
                    
                    // Recent places (only show when no search text and no suggestions)
                    if searchText.isEmpty && searchCompleter.completions.isEmpty && !recentPlaces.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("Recent")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button(action: clearRecentPlaces) {
                                    Text("Clear")
                                        .font(.caption)
                                        .foregroundColor(Color("PrimaryAccent"))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            
                            ForEach(recentPlaces.prefix(5), id: \.self) { place in
                                Button(action: {
                                    selectRecentPlace(place)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 16))
                                        
                                        Text(place)
                                            .foregroundColor(.primary)
                                            .font(.body)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                }
                                .buttonStyle(.plain)
                                
                                if place != recentPlaces.prefix(5).last {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }
                    
                    // Search button
                    Button(action: {
                        onSearch()
                    }) {
                        HStack {
                            if isSearching {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Search Routes")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44, idealHeight: 50)
                        .background(
                            destination != nil && !isSearching
                            ? Color("PrimaryAccent")
                            : Color.secondary.opacity(0.3)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isSearching || destination == nil)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.never)
        }
        .onAppear {
            // Focus search field immediately so keyboard appears with sheet
            searchFieldFocus = true
            // Load recent places from UserDefaults
            loadRecentPlaces()
        }
        .onDisappear {
            // Reset focus state when sheet disappears
            searchFieldFocus = false
        }
    }
    
    // MARK: - Recent Places
    
    private func loadRecentPlaces() {
        recentPlaces = UserDefaults.standard.stringArray(forKey: "tripPlannerRecentPlaces") ?? []
    }
    
    private func saveRecentPlaces() {
        UserDefaults.standard.set(recentPlaces, forKey: "tripPlannerRecentPlaces")
    }
    
    private func addRecentPlace(_ place: String) {
        guard !place.isEmpty else { return }
        
        recentPlaces.removeAll { $0 == place }
        recentPlaces.insert(place, at: 0)
        recentPlaces = Array(recentPlaces.prefix(5))
        
        saveRecentPlaces()
    }
    
    private func clearRecentPlaces() {
        recentPlaces = []
        saveRecentPlaces()
    }
    
    private func selectRecentPlace(_ place: String) {
        searchText = place
        Task {
            await geocodeAddress(place)
        }
    }
    
    // MARK: - Search Text Handling
    
    private func handleSearchTextChange(_ newValue: String) {
        if newValue.isEmpty {
            destination = nil
            searchCompleter.completions = []
        } else {
            // Update search completer query
            searchCompleter.updateQuery(newValue)
        }
    }
    
    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        let fullAddress = "\(completion.title)\(completion.subtitle.isEmpty ? "" : ", \(completion.subtitle)")"
        searchText = fullAddress
        
        // Get coordinate for the completion
        Task {
            await geocodeCompletion(completion)
        }
        
        // Don't close sheet - let user continue editing or search
    }
    
    private func geocodeCompletion(_ completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            if let mapItem = response.mapItems.first {
                let coordinate = mapItem.placemark.coordinate
                let address = "\(completion.title)\(completion.subtitle.isEmpty ? "" : ", \(completion.subtitle)")"
                
                destination = PlannedLocation(coordinate: coordinate, address: address)
                addRecentPlace(address)
            }
        } catch {
            // Fallback to regular geocoding
            await geocodeAddress(searchText)
        }
    }
    
    // MARK: - Geocoding
    
    private func geocodeAddress(_ address: String) async {
        do {
            let coordinate = try await GeocodingService.shared.geocodeAddress(address)
            let location = PlannedLocation(coordinate: coordinate, address: address)
            destination = location
            addRecentPlace(address)
        } catch {
            print("Geocoding error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Search Completer Manager

class SearchCompleterManager: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    
    private let completer = MKLocalSearchCompleter()
    private var currentQuery: String = ""
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        
        // Default to Bloomington, IN region
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.1653, longitude: -86.5264),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    
    func updateRegion(center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    
    func updateQuery(_ query: String) {
        guard !query.isEmpty else {
            completions = []
            return
        }
        
        currentQuery = query
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Filter and limit results on main thread
        Task { @MainActor in
            let filtered = completer.results.prefix(5)
            completions = Array(filtered)
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
        Task { @MainActor in
            completions = []
        }
    }
}


#Preview {
    TripPlannerSearchBar(
        origin: .constant(nil),
        destination: .constant(nil),
        isSearching: .constant(false),
        onSearch: {},
        onLongPress: nil
    )
    .environment(LocationManager())
    .environment(FavoriteStore())
}
