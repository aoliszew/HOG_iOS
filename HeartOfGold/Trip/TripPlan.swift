import Foundation

/// The captain's pre-flight mission briefing: rough length and planned stops.
/// Gives the story engine an arc (beginning / middle / final leg) and lets
/// errand objectives tick down as stops are detected.
struct TripPlan: Codable, Equatable {
    enum Length: String, Codable, CaseIterable {
        case quickHop      // ~10 minutes around town
        case underAnHour
        case longHaul

        var estimatedMiles: Double {
            switch self {
            case .quickHop: return 6
            case .underAnHour: return 25
            case .longHaul: return 90
            }
        }

        var spoken: String {
            switch self {
            case .quickHop: return "a quick hop"
            case .underAnHour: return "under an hour"
            case .longHaul: return "a long haul"
            }
        }
    }

    var length: Length?
    /// Planned stops before returning to base (0–3+; 3 means "3 or more").
    var plannedStops: Int?
    var stopsCompleted: Int = 0

    var stopsRemaining: Int? {
        guard let plannedStops else { return nil }
        return max(0, plannedStops - stopsCompleted)
    }

    var isComplete: Bool { length != nil && plannedStops != nil }

    /// Where we are in the drive's arc, if the length is known.
    func phase(distanceMiles: Double) -> String? {
        guard let length else { return nil }
        let fraction = distanceMiles / length.estimatedMiles
        if fraction < 0.3 { return "beginning" }
        if fraction < 0.75 { return "middle" }
        return "final"
    }
}
