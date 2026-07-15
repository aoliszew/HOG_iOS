import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    // Errands first: it's the default and most common mission profile.
    case errands = "Errands"
    case roadtrip = "Roadtrip"

    var id: String { rawValue }

    /// Seconds between random encounters (min...max).
    var encounterInterval: ClosedRange<TimeInterval> {
        switch self {
        case .roadtrip: return 240...540
        case .errands: return 150...330
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
