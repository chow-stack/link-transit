import Foundation
import CoreLocation
import SwiftUI

/// Service for formatting itineraries into user-readable format and map annotations
final class ItineraryFormatter {
    // MARK: - Format Itinerary
    
    /// Format an itinerary into user-readable steps and map annotations
    /// - Parameter itinerary: Itinerary to format
    /// - Returns: FormattedItinerary with steps, map annotations, and summary
    func formatItinerary(_ itinerary: Itinerary) -> FormattedItinerary {
        let steps = generateSteps(from: itinerary)
        let mapAnnotations = generateMapAnnotations(from: itinerary)
        let summary = generateSummary(from: itinerary)
        
        return FormattedItinerary(
            steps: steps,
            mapAnnotations: mapAnnotations,
            summary: summary
        )
    }
    
    // MARK: - Step Generation
    
    private func generateSteps(from itinerary: Itinerary) -> [InstructionStep] {
        var steps: [InstructionStep] = []
        var currentTime = itinerary.departureTime
        
        for (index, segment) in itinerary.segments.enumerated() {
            switch segment {
            case .walk(_, let distance, let duration, let from, let to):
                let step = InstructionStep(
                    type: .walk,
                    instruction: generateWalkInstruction(distance: distance, duration: duration, to: to),
                    time: currentTime,
                    duration: duration,
                    location: from,
                    routeColor: nil
                )
                steps.append(step)
                currentTime = currentTime.addingTimeInterval(duration)
                
            case .ride(_, _, let routeName, let routeColor, let fromStop, let toStop, let duration, let waitTime, _):
                // Board step
                let boardStep = InstructionStep(
                    type: .board,
                    instruction: generateBoardInstruction(routeName: routeName, stopName: fromStop.name, waitTime: waitTime),
                    time: currentTime.addingTimeInterval(waitTime),
                    duration: waitTime,
                    location: fromStop.coordinate,
                    routeColor: routeColor
                )
                steps.append(boardStep)
                currentTime = currentTime.addingTimeInterval(waitTime)
                
                // Ride step
                let rideStep = InstructionStep(
                    type: .ride,
                    instruction: generateRideInstruction(routeName: routeName, stopName: toStop.name, duration: duration),
                    time: currentTime,
                    duration: duration,
                    location: fromStop.coordinate,
                    routeColor: routeColor
                )
                steps.append(rideStep)
                currentTime = currentTime.addingTimeInterval(duration)
                
                // Alight step
                let alightStep = InstructionStep(
                    type: .alight,
                    instruction: generateAlightInstruction(stopName: toStop.name),
                    time: currentTime,
                    duration: 0,
                    location: toStop.coordinate,
                    routeColor: nil
                )
                steps.append(alightStep)
                
                // Check if next segment is a transfer (walk between stops before next ride)
                if index < itinerary.segments.count - 1 {
                    let nextSegment = itinerary.segments[index + 1]
                    if case .walk(_, _, _, _, _) = nextSegment {
                        // Check if this walk connects two different stops (transfer)
                        // Transfer detection: walk from current alight stop to next boarding stop
                        // Check if there's another ride segment after the walk
                        if index + 2 < itinerary.segments.count {
                            let segmentAfterWalk = itinerary.segments[index + 2]
                            switch segmentAfterWalk {
                            case .ride(_, _, _, _, let nextFromStop, _, _, _, _):
                                // This is a transfer - walk between two different stops
                                // Compare stop IDs explicitly to avoid SwiftUI id() conflict  
                                let currentStopId: Int = toStop.id
                                let nextStopId: Int = nextFromStop.id
                                if currentStopId != nextStopId {
                                    let transferStep = InstructionStep(
                                        type: .transfer,
                                        instruction: generateTransferInstruction(fromStop: toStop.name, toStopName: nextFromStop.name),
                                        time: currentTime,
                                        duration: 0,
                                        location: toStop.coordinate,
                                        routeColor: nil
                                    )
                                    steps.append(transferStep)
                                }
                            default:
                                break
                            }
                        }
                    }
                }
            }
        }
        
        return steps
    }
    
    // MARK: - Instruction Generation
    
    private func generateWalkInstruction(distance: Double, duration: TimeInterval, to: CLLocationCoordinate2D) -> String {
        let minutes = Int(duration / 60)
        let miles = distance / 1609.344
        let feet = distance * 3.28084
        
        if miles >= 0.1 {
            // Show in miles with 1 decimal place if >= 0.1 miles
            return String(format: "Walk %.1f mi (%d min)", miles, minutes)
        } else {
            // Show in feet for shorter distances
            let roundedFeet = Int(feet.rounded())
            return String(format: "Walk %d ft (%d min)", roundedFeet, minutes)
        }
    }
    
    private func generateBoardInstruction(routeName: String, stopName: String, waitTime: TimeInterval) -> String {
        if waitTime < 60 {
            return "Board \(routeName) at \(stopName) (Leave now)"
        } else {
            let minutes = Int(waitTime / 60)
            return "Board \(routeName) at \(stopName) (in \(minutes) min)"
        }
    }
    
    private func generateRideInstruction(routeName: String, stopName: String, duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "Ride \(routeName) for \(minutes) min to \(stopName)"
    }
    
    private func generateAlightInstruction(stopName: String) -> String {
        return "Get off at \(stopName)"
    }
    
    private func generateTransferInstruction(fromStop: String, toStopName: String) -> String {
        return "Transfer from \(fromStop) to \(toStopName)"
    }
    
    // MARK: - Map Annotations Generation
    
    private func generateMapAnnotations(from itinerary: Itinerary) -> MapAnnotations {
        var walkPolylines: [(coordinates: [CLLocationCoordinate2D], style: PolylineStyle)] = []
        var ridePolylines: [(coordinates: [CLLocationCoordinate2D], color: Color, routeName: String)] = []
        var stopMarkers: [StopMarker] = []
        
        for segment in itinerary.segments {
            switch segment {
            case .walk(_, _, _, let from, let to):
                // For walk segments, we need to get the polyline from WalkingRouteService
                // But since we don't have access to it here, we'll create a simple two-point polyline
                // The actual polyline should come from the WalkingRoute if available
                walkPolylines.append((
                    coordinates: [from, to],
                    style: .dashed
                ))
                
            case .ride(_, _, let routeName, let routeColor, let fromStop, let toStop, _, _, _):
                // For ride segments, we need route shape coordinates
                // For now, create a simple polyline between stops
                // In a full implementation, this would use route shapes from DataSyncService
                let routeColorObj = routeColor != nil ? Color(hex: routeColor!) : .blue
                ridePolylines.append((
                    coordinates: [fromStop.coordinate, toStop.coordinate],
                    color: routeColorObj,
                    routeName: routeName
                ))
                
                // Add stop markers
                stopMarkers.append(StopMarker(
                    stopId: fromStop.id,
                    stopName: fromStop.name,
                    coordinate: fromStop.coordinate,
                    type: .boarding
                ))
                stopMarkers.append(StopMarker(
                    stopId: toStop.id,
                    stopName: toStop.name,
                    coordinate: toStop.coordinate,
                    type: .alighting
                ))
            }
        }
        
        return MapAnnotations(
            walkPolylines: walkPolylines,
            ridePolylines: ridePolylines,
            stopMarkers: stopMarkers
        )
    }
    
    // MARK: - Summary Generation
    
    private func generateSummary(from itinerary: Itinerary) -> ItinerarySummary {
        return ItinerarySummary(
            totalTime: itinerary.totalTime,
            totalDistance: itinerary.totalDistance,
            transferCount: itinerary.transferCount,
            departureTime: itinerary.departureTime,
            arrivalTime: itinerary.arrivalTime
        )
    }
}

// MARK: - Supporting Types

/// Formatted itinerary with steps, map annotations, and summary
struct FormattedItinerary {
    let steps: [InstructionStep]
    let mapAnnotations: MapAnnotations
    let summary: ItinerarySummary
}

/// User-readable instruction step
struct InstructionStep: Identifiable {
    let id: UUID
    let type: StepType
    let instruction: String
    let time: Date
    let duration: TimeInterval
    let location: CLLocationCoordinate2D
    let routeColor: String? // Route color hex for board/ride steps
    
    init(id: UUID = UUID(), type: StepType, instruction: String, time: Date, duration: TimeInterval, location: CLLocationCoordinate2D, routeColor: String? = nil) {
        self.id = id
        self.type = type
        self.instruction = instruction
        self.time = time
        self.duration = duration
        self.location = location
        self.routeColor = routeColor
    }
    
    /// Formatted time string
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }
}

/// Type of instruction step
enum StepType: String, Codable {
    case walk
    case board
    case ride
    case alight
    case transfer
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .walk:
            return "Walk"
        case .board:
            return "Board"
        case .ride:
            return "Ride"
        case .alight:
            return "Get Off"
        case .transfer:
            return "Transfer"
        }
    }
    
    /// Icon name for UI
    var iconName: String {
        switch self {
        case .walk:
            return "figure.walk"
        case .board:
            return "arrow.up.circle.fill"
        case .ride:
            return "bus.fill"
        case .alight:
            return "arrow.down.circle.fill"
        case .transfer:
            return "arrow.2.squarepath"
        }
    }
}

/// Map annotations for rendering itinerary on map
struct MapAnnotations {
    let walkPolylines: [(coordinates: [CLLocationCoordinate2D], style: PolylineStyle)]
    let ridePolylines: [(coordinates: [CLLocationCoordinate2D], color: Color, routeName: String)]
    let stopMarkers: [StopMarker]
}

/// Polyline style for walking routes
enum PolylineStyle: String, Codable {
    case dashed
    case solid
}

/// Stop marker for map display
struct StopMarker: Identifiable {
    let id: Int
    let stopName: String
    let coordinate: CLLocationCoordinate2D
    let type: StopMarkerType
    
    init(stopId: Int, stopName: String, coordinate: CLLocationCoordinate2D, type: StopMarkerType) {
        self.id = stopId
        self.stopName = stopName
        self.coordinate = coordinate
        self.type = type
    }
}

/// Type of stop marker
enum StopMarkerType: String, Codable {
    case boarding
    case alighting
    case transfer
    
    /// Display label for UI
    var label: String {
        switch self {
        case .boarding:
            return "Board"
        case .alighting:
            return "Get Off"
        case .transfer:
            return "Transfer"
        }
    }
}

/// Summary information for itinerary
struct ItinerarySummary {
    let totalTime: TimeInterval
    let totalDistance: Double
    let transferCount: Int
    let departureTime: Date
    let arrivalTime: Date
    
    /// Formatted total time string showing time until arrival (e.g., "25 min" or "1 hr 15 min")
    /// This shows the time from now until arrival, not the trip duration
    var formattedTotalTime: String {
        let seconds = Int(arrivalTime.timeIntervalSinceNow)
        if seconds < 0 {
            // Already arrived or past
            return "0 min"
        } else if seconds < 60 {
            return "< 1 min"
        } else {
            let totalMinutes = seconds / 60
            if totalMinutes < 60 {
                return "\(totalMinutes) min"
            } else {
                let hours = totalMinutes / 60
                let minutes = totalMinutes % 60
                if minutes == 0 {
                    return "\(hours) hr"
                } else {
                    return "\(hours) hr \(minutes) min"
                }
            }
        }
    }
    
    /// Formatted total distance string
    var formattedTotalDistance: String {
        if totalDistance >= 1000 {
            let km = totalDistance / 1000
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f m", totalDistance)
        }
    }
    
    /// Formatted departure guidance
    var departureGuidance: String {
        let seconds = Int(departureTime.timeIntervalSinceNow)
        if seconds < 60 {
            return "Leave now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "Depart in \(minutes) min"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Depart at \(formatter.string(from: departureTime))"
        }
    }
    
    /// Formatted arrival time
    var formattedArrivalTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalTime)
    }
}

