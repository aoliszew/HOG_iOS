import Foundation

/// Codable model of an event JSON file — schema v1, see docs/EVENT_SYSTEM.md.
struct EventDefinition: Decodable, Identifiable {
    enum EventType: String, Decodable {
        case single, sequence, branching
    }

    enum MessageClass: String, Decodable {
        case ambient   // observational color; skipped when the queue backs up
        case plot      // story content; always delivered
    }

    let schema: Int
    let id: String
    let title: String
    let author: String
    let type: EventType
    let tags: [String]?
    /// Defaults by type: single → ambient, sequence/branching → plot.
    let `class`: MessageClass?
    let trigger: Trigger?
    let content: Content
    let effects: Effects?

    var messageClass: MessageClass {
        `class` ?? (type == .single ? .ambient : .plot)
    }

    struct Trigger: Decodable {
        let contexts: Contexts?
        let weight: Double?
        let cooldownMinutes: Double?
        let maxPerTrip: Int?
    }

    struct Contexts: Decodable {
        let tripModes: [String]?
        let personalities: [String]?
        let speedMPH: RangeCondition?
        let tripDistanceMiles: RangeCondition?
        let stopped: Bool?
        let hardAccelRecently: Bool?
        let timeOfDay: [String]?
        let daysOfWeek: [String]?
        let weather: [String]?
        let requiresFlags: [String]?
        let forbidsFlags: [String]?
        /// Arc position within the drive: beginning | middle | final.
        let tripPhase: [String]?
        /// Errand objectives left before home (from the mission briefing).
        let stopsRemaining: RangeCondition?
        /// US state/province codes the ship must be operating in (e.g. ["OH"]).
        let states: [String]?
        /// Multi-day voyage chapter: outbound | returning.
        let voyagePhase: [String]?
        /// Straight-line miles to the active destination (needs a set destination).
        let milesToDestination: RangeCondition?
    }

    struct RangeCondition: Decodable {
        let min: Double?
        let max: Double?

        func contains(_ value: Double) -> Bool {
            if let min, value < min { return false }
            if let max, value > max { return false }
            return true
        }
    }

    /// Union of the three content shapes; which fields are set depends on `type`.
    struct Content: Decodable {
        // single
        let source: String?
        let text: String?
        /// Optional quick replies (max 2) on a single: tap → spoken reaction.
        /// No long-term effects — ambient banter, not plot.
        let responses: [QuickResponse]?
        // sequence
        let steps: [Step]?
        // branching
        let entry: String?
        let nodes: [String: Node]?
    }

    struct QuickResponse: Decodable {
        let label: String
        let phrases: [String]?
        let reaction: Line
    }

    struct Line: Decodable {
        let source: String
        let text: String
    }

    struct Step: Decodable {
        let source: String?
        let text: String?
        let wait: Wait?
    }

    struct Wait: Decodable {
        let seconds: Double?
        let miles: Double?
    }

    struct Node: Decodable {
        let source: String
        let text: String
        let choices: [Choice]?
        let next: String?
        let timeoutSeconds: Double?
        let timeoutNext: String?
        let setFlags: [String]?
    }

    struct Choice: Decodable {
        let label: String
        let phrases: [String]
        /// Deterministic destination…
        let next: String?
        /// …or a dice roll: one of these is picked at random. Exactly one of
        /// next/nextOneOf must be set (validator-enforced).
        let nextOneOf: [String]?
        let setFlags: [String]?

        var resolvedNext: String {
            next ?? nextOneOf?.randomElement() ?? "end"
        }
    }

    struct Effects: Decodable {
        let setFlags: [String]?
    }
}

/// Snapshot of everything the trigger system can currently observe.
/// Fields the app can't sense yet (weather, …) simply disqualify events that require them.
struct ShipContext {
    var mode: TravelMode
    var personality: EnginePersonality
    var speedMPH: Double
    var tripDistanceMiles: Double
    var stopped: Bool
    var hardAccelRecently: Bool
    var flags: Set<String>
    /// True while a sequence/branching event is mid-playback — sources shouldn't
    /// start another long-form event on top of it.
    var longFormActive: Bool = false
    /// How many messages are waiting unplayed — ambient events stop firing
    /// when this backs up (~5+).
    var queuedMessages: Int = 0
    /// Arc position from the mission briefing (nil when length unknown).
    var tripPhase: String?
    /// Errand objectives remaining (nil when no briefing given).
    var stopsRemaining: Int?
    /// Current US state code, if region awareness has a fix (e.g. "OH").
    var state: String?
    /// Multi-day voyage chapter (outbound/returning), if a voyage is active.
    var voyagePhase: String?
    /// Straight-line miles to the active destination, if one is set.
    var milesToDestination: Double?
    var date: Date = .now
}
