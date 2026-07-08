import Foundation

/// Decides which events qualify in the current context and picks one by weight.
/// Owns per-trip firing state (cooldowns, maxPerTrip counts).
final class TriggerEvaluator {
    private var firedCounts: [String: Int] = [:]
    private var lastFired: [String: Date] = [:]
    private var lastFiredID: String?

    func resetTrip() {
        firedCounts = [:]
        lastFired = [:]
        lastFiredID = nil
    }

    func recordFired(_ event: EventDefinition) {
        firedCounts[event.id, default: 0] += 1
        lastFired[event.id] = .now
        lastFiredID = event.id
    }

    func pick(from events: [EventDefinition], context: ShipContext) -> EventDefinition? {
        let qualified = events.filter { qualifies($0, context: context) }
        guard !qualified.isEmpty else { return nil }

        let total = qualified.reduce(0) { $0 + weight(of: $1) }
        var roll = Double.random(in: 0..<total)
        for event in qualified {
            roll -= weight(of: event)
            if roll < 0 { return event }
        }
        return qualified.last
    }

    private func weight(of event: EventDefinition) -> Double {
        max(event.trigger?.weight ?? 1, 0.001)
    }

    func qualifies(_ event: EventDefinition, context: ShipContext) -> Bool {
        // Never the same event twice in a row, regardless of authoring.
        if event.id == lastFiredID { return false }
        // Unique-per-trip by default; repetition is opt-in via explicit maxPerTrip.
        let maxPerTrip = event.trigger?.maxPerTrip ?? 1
        if firedCounts[event.id, default: 0] >= maxPerTrip { return false }
        if let cooldown = event.trigger?.cooldownMinutes,
           let last = lastFired[event.id],
           Date.now.timeIntervalSince(last) < cooldown * 60 { return false }

        guard let c = event.trigger?.contexts else { return true }

        if let modes = c.tripModes, !modes.contains(context.mode.rawValue.lowercased()) { return false }
        if let personalities = c.personalities, !personalities.contains(context.personality.rawValue.lowercased()) { return false }
        if let speed = c.speedMPH, !speed.contains(context.speedMPH) { return false }
        if let distance = c.tripDistanceMiles, !distance.contains(context.tripDistanceMiles) { return false }
        if let stopped = c.stopped, stopped != context.stopped { return false }
        if let hardAccel = c.hardAccelRecently, hardAccel != context.hardAccelRecently { return false }
        if let required = c.requiresFlags, !Set(required).isSubset(of: context.flags) { return false }
        if let forbidden = c.forbidsFlags, !Set(forbidden).isDisjoint(with: context.flags) { return false }

        // Contexts the ship can't sense yet: any event requiring them stays dormant.
        if c.timeOfDay != nil || c.daysOfWeek != nil || c.weather != nil { return false }

        return true
    }
}
