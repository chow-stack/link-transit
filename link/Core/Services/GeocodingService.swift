import Foundation
import CoreLocation

/// Service for geocoding addresses to coordinates and reverse geocoding coordinates to addresses
/// Uses actor for thread-safe access to CLGeocoder
actor GeocodingService {
    // MARK: - Singleton
    
    static let shared = GeocodingService()
    
    // MARK: - Private Properties
    
    private let geocoder = CLGeocoder()
    private var cache: [String: CachedGeocodeResult] = [:]
    private let maxCacheSize = 50
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    private let requestTimeout: TimeInterval = 10.0 // 10 seconds
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Geocoding (Address → Coordinate)
    
    /// Geocode an address string to a coordinate
    /// - Parameter address: Address string to geocode
    /// - Returns: Coordinate for the address
    /// - Throws: GeocodingError if geocoding fails
    func geocodeAddress(_ address: String) async throws -> CLLocationCoordinate2D {
        // Check cache first
        let cacheKey = address.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.coordinate
        }
        
        // Perform geocoding with timeout
        return try await withThrowingTaskGroup(of: CLLocationCoordinate2D.self) { group in
            group.addTask {
                let placemarks = try await self.geocoder.geocodeAddressString(address)
                guard let location = placemarks.first?.location else {
                    throw GeocodingError.noResults
                }
                return location.coordinate
            }
            
            group.addTask {
                try await Task.sleep(for: .seconds(self.requestTimeout))
                throw GeocodingError.timeout
            }
            
            // Get first result (either success or timeout)
            let result = try await group.next()!
            // Cancel remaining tasks
            group.cancelAll()
            
            // Cache the result
            self.cacheResult(key: cacheKey, coordinate: result, address: address)
            
            return result
        }
    }
    
    // MARK: - Reverse Geocoding (Coordinate → Address)
    
    /// Reverse geocode a coordinate to an address string
    /// - Parameter coordinate: Coordinate to reverse geocode
    /// - Returns: Address string for the coordinate
    /// - Throws: GeocodingError if reverse geocoding fails
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        // Check cache first
        let cacheKey = "\(coordinate.latitude),\(coordinate.longitude)"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout,
           let address = cached.address {
            return address
        }
        
        // Perform reverse geocoding with timeout
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let placemarks = try await self.geocoder.reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else {
                    throw GeocodingError.noResults
                }
                
                // Build address string from placemark components
                var addressComponents: [String] = []
                
                if let streetNumber = placemark.subThoroughfare {
                    addressComponents.append(streetNumber)
                }
                if let streetName = placemark.thoroughfare {
                    addressComponents.append(streetName)
                }
                if let city = placemark.locality {
                    addressComponents.append(city)
                }
                if let state = placemark.administrativeArea {
                    addressComponents.append(state)
                }
                if let zipCode = placemark.postalCode {
                    addressComponents.append(zipCode)
                }
                
                let address = addressComponents.isEmpty
                    ? "\(coordinate.latitude), \(coordinate.longitude)"
                    : addressComponents.joined(separator: " ")
                
                return address
            }
            
            group.addTask {
                try await Task.sleep(for: .seconds(self.requestTimeout))
                throw GeocodingError.timeout
            }
            
            // Get first result (either success or timeout)
            let result = try await group.next()!
            // Cancel remaining tasks
            group.cancelAll()
            
            // Cache the result
            self.cacheResult(key: cacheKey, coordinate: coordinate, address: result)
            
            return result
        }
    }
    
    // MARK: - Cache Management
    
    private func cacheResult(key: String, coordinate: CLLocationCoordinate2D, address: String?) {
        // Remove oldest entries if cache is full
        if cache.count >= maxCacheSize {
            // Sort by timestamp and remove oldest 25%
            let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = sorted.prefix(maxCacheSize / 4)
            for (key, _) in toRemove {
                cache.removeValue(forKey: key)
            }
        }
        
        cache[key] = CachedGeocodeResult(
            coordinate: coordinate,
            address: address,
            timestamp: Date()
        )
    }
    
    /// Clear the geocoding cache
    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Supporting Types

private struct CachedGeocodeResult {
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let timestamp: Date
}

enum GeocodingError: LocalizedError {
    case noResults
    case timeout
    case networkError(Error)
    case invalidAddress
    
    var errorDescription: String? {
        switch self {
        case .noResults:
            return "No results found for this location"
        case .timeout:
            return "Request timed out. Please check your connection and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidAddress:
            return "Invalid address format"
        }
    }
}

