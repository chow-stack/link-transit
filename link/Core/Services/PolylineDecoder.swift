import Foundation
import CoreLocation

/// Utility for decoding Google/OTP encoded polylines into coordinate arrays
struct PolylineDecoder {
    
    /// Decode an encoded polyline string into an array of coordinates
    /// Uses precision level 5 (standard for OTP and Google Maps)
    /// - Parameter encodedPolyline: The encoded polyline string
    /// - Returns: Array of CLLocationCoordinate2D representing the path
    /// - Throws: DecodingError if polyline is malformed
    static func decode(_ encodedPolyline: String) throws -> [CLLocationCoordinate2D] {
        guard !encodedPolyline.isEmpty else {
            throw DecodingError.emptyPolyline
        }
        
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encodedPolyline.startIndex
        var lat: Int = 0
        var lon: Int = 0
        
        while index < encodedPolyline.endIndex {
            // Decode latitude
            var result = 0
            var shift = 0
            var byte: Int
            
            repeat {
                guard index < encodedPolyline.endIndex else {
                    throw DecodingError.malformedPolyline
                }
                
                byte = Int(encodedPolyline[index].asciiValue ?? 0) - 63
                index = encodedPolyline.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            
            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat
            
            // Decode longitude
            result = 0
            shift = 0
            
            repeat {
                guard index < encodedPolyline.endIndex else {
                    throw DecodingError.malformedPolyline
                }
                
                byte = Int(encodedPolyline[index].asciiValue ?? 0) - 63
                index = encodedPolyline.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            
            let deltaLon = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lon += deltaLon
            
            // Convert to coordinates (precision 5 = divide by 1e5)
            let latitude = Double(lat) / 1e5
            let longitude = Double(lon) / 1e5
            
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            coordinates.append(coordinate)
        }
        
        return coordinates
    }
    
    /// Errors that can occur during polyline decoding
    enum DecodingError: LocalizedError {
        case emptyPolyline
        case malformedPolyline
        
        var errorDescription: String? {
            switch self {
            case .emptyPolyline:
                return "Polyline string is empty"
            case .malformedPolyline:
                return "Polyline string is malformed or incomplete"
            }
        }
    }
}

