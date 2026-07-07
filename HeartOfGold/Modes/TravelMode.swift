import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    case roadtrip = "Roadtrip"
    case errands = "Errands"

    var id: String { rawValue }

    /// Seconds between random encounters (min...max).
    var encounterInterval: ClosedRange<TimeInterval> {
        switch self {
        case .roadtrip: return 120...300
        case .errands: return 60...150
        }
    }

    var startupGreeting: String {
        switch self {
        case .roadtrip:
            return "Long-range cruise configuration engaged. Plotting course through the outer systems. Snack reserves are your responsibility, Captain."
        case .errands:
            return "Local patrol configuration engaged. Short-hop thrusters online. Estimated probability of forgetting one item on the list: ninety-two percent."
        }
    }
}
