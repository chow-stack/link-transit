import Foundation
import CoreLocation
import Observation

/// Manages location services and permission requests
@Observable
@MainActor
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    var userLocation: CLLocationCoordinate2D?
    var heading: CLLocationDirection?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10 // meters, keeps continuous GPS updates infrequent
        manager.headingFilter = 3 // degrees, avoids flooding updates for tiny compass jitter
        authorizationStatus = manager.authorizationStatus
    }

    /// Request when-in-use location authorization
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Start continuous location updates, used to position the initial map camera
    /// and to keep the user's blue dot (and its heading cone) live on the map.
    func startUpdatingLocation() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    /// Stop updating user location and heading
    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    /// Start compass updates that drive the heading cone on the user's map marker.
    /// Cheap relative to GPS (magnetometer-based), so this can stay on independently
    /// of the one-shot location fix above.
    func startUpdatingHeading() {
        guard isAuthorized, CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stopUpdatingHeading() {
        manager.stopUpdatingHeading()
        heading = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if isAuthorized {
            startUpdatingLocation()
            startUpdatingHeading()
        } else {
            stopUpdatingLocation()
            stopUpdatingHeading()
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
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
}
