import Foundation

/// How the ship talks: aggressive warship (Power) vs. serene cruiser (Eco).
enum EnginePersonality: String, CaseIterable, Identifiable {
    case power = "Power"
    case eco = "Eco"

    var id: String { rawValue }

    var confirmation: String {
        switch self {
        case .power:
            return "Power configuration confirmed. All reactors to full. Let's make some improbability."
        case .eco:
            return "Eco configuration confirmed. Reactors trimmed for efficiency. The universe thanks you, Captain."
        }
    }

    var speechRate: Float {
        switch self {
        case .power: return 0.52
        case .eco: return 0.45
        }
    }

    var pitch: Float {
        switch self {
        case .power: return 0.9
        case .eco: return 1.02
        }
    }

    func speedCallout(threshold: Int) -> String {
        switch (self, threshold) {
        case (.power, 30): return "Cruise velocity. Weapons cold, engines hot."
        case (.power, 55): return "Fifty-five and climbing. The engines approve."
        case (.power, _): return "Maximum recommended sublight. Now we're flying."
        case (.eco, 30): return "Entering cruise velocity. Efficiency curve optimal."
        case (.eco, 55): return "Fifty-five. A dignified and economical pace, Captain."
        case (.eco, _): return "Approaching maximum sublight. Fuel cells filing a formal complaint."
        }
    }
}
