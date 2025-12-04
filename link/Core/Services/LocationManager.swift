import Foundation
import CoreLocation
import Observation

/// Manages location services and permission requests
@Observable
@MainActor
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }
    
    /// Request when-in-use location authorization
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    /// Start updating user location and heading
    func startUpdatingLocation() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        // Enable heading updates to show direction cone on map
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }
    
    /// Stop updating user location and heading
    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        if isAuthorized {
            startUpdatingLocation()
        } else {
            stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Validate heading accuracy - only process headings with valid accuracy
        // SwiftUI Map's UserAnnotation will automatically use this heading data for the cone
        guard newHeading.headingAccuracy >= 0 else { return }
        // Heading data is valid - MapKit will automatically display the cone
    }
}

