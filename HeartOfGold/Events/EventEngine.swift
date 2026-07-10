import Foundation

struct ShipEvent {
    let source: String   // e.g. "MEDBAY", "SCIENCE"
    let text: String
    /// Ambient chatter may be dropped if it sits unheard too long; plot never is.
    var ambient: Bool = false
    var queuedAt: Date = .now
    /// Quick tap-replies offered after the message plays (spoken reaction, no plot effect).
    var responses: [EventDefinition.QuickResponse] = []
}

/// What an encounter slot produced: a one-shot message, or a multi-step
/// sequence the controller should hand to a SequencePlayer.
enum PlayableEvent {
    case message(ShipEvent)
    case sequence(EventDefinition)
    case branching(EventDefinition)
}

/// Supplies encounter events. The POC used hard-coded lines; ContentEventSource
/// reads JSON content, and Phase 3's Claude generator is another implementation.
protocol EventSource {
    /// Called when a trip starts (reset cooldowns/counters).
    func tripStarted()
    /// Return the next event qualified for this context, or nil to skip this slot.
    func nextEvent(context: ShipContext) -> PlayableEvent?
    /// Called when a multi-step event finishes playback (applies its effects
    /// plus any flags collected along the way, e.g. from branching choices).
    func completed(eventID: String, extraFlags: Set<String>)
}

/// Schedules random encounters while the ship is powered up.
final class EventEngine {
    var onEvent: ((PlayableEvent) -> Void)?

    private let source: EventSource
    private var timer: Timer?
    private var mode: TravelMode = .roadtrip
    private let currentContext: () -> ShipContext

    init(source: EventSource, currentContext: @escaping () -> ShipContext) {
        self.source = source
        self.currentContext = currentContext
    }

    func start(mode: TravelMode) {
        self.mode = mode
        source.tripStarted()
        scheduleNext()
    }

    /// Resume scheduling without wiping the source's per-trip state
    /// (used for crash recovery — cooldowns and fired counts were restored).
    func startWithoutReset(mode: TravelMode) {
        self.mode = mode
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        nextFireDate = nil
        pausedRemaining = nil
    }

    /// Freeze the encounter clock, remembering how much time was left.
    func pause() {
        if let fireDate = nextFireDate {
            pausedRemaining = max(1, fireDate.timeIntervalSinceNow)
        }
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        if let remaining = pausedRemaining {
            pausedRemaining = nil
            schedule(after: remaining)
        } else {
            scheduleNext()
        }
    }

    private var nextFireDate: Date?
    private var pausedRemaining: TimeInterval?

    private func scheduleNext() {
        schedule(after: TimeInterval.random(in: mode.encounterInterval))
    }

    private func schedule(after interval: TimeInterval) {
        nextFireDate = Date().addingTimeInterval(interval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            if let event = self.source.nextEvent(context: self.currentContext()) {
                self.onEvent?(event)
            }
            self.scheduleNext()
        }
    }
}
