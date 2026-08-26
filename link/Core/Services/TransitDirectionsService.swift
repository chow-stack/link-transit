import MapKit
import Observation
import SwiftUI

enum PreferredMapApp: String, CaseIterable, Identifiable {
    case ask
    case appleMaps
    case googleMaps

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ask: "Ask Every Time"
        case .appleMaps: "Apple Maps"
        case .googleMaps: "Google Maps"
        }
    }
}

@Observable
@MainActor
final class MapAppPreference {
    private static let defaultsKey = "preferredTransitMapApp"

    var selectedApp: PreferredMapApp {
        didSet { UserDefaults.standard.set(selectedApp.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        selectedApp = defaults.string(forKey: Self.defaultsKey)
            .flatMap(PreferredMapApp.init(rawValue:)) ?? .ask
    }
}

@MainActor
enum TransitDirectionsService {
    static func open(stop: Stop, in app: PreferredMapApp) {
        switch app {
        case .ask:
            return
        case .appleMaps:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
            item.name = stop.name
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit
            ])
        case .googleMaps:
            var components = URLComponents(string: "https://www.google.com/maps/dir/")
            components?.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: "\(stop.lat),\(stop.lon)"),
                URLQueryItem(name: "travelmode", value: "transit")
            ]
            if let url = components?.url {
                UIApplication.shared.open(url)
            }
        }
    }
}
