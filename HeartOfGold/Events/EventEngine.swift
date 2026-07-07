import Foundation

struct ShipEvent {
    let source: String   // e.g. "MEDBAY", "SCIENCE"
    let text: String
}

/// Supplies encounter events. The POC uses CannedEvents; Phase 3 swaps in a
/// Claude-backed story source without touching the rest of the app.
protocol EventSource {
    func nextEvent(mode: TravelMode, speedMPH: Double) -> ShipEvent
}

/// Schedules random encounters while the ship is powered up.
final class EventEngine {
    var onEvent: ((ShipEvent) -> Void)?

    private let source: EventSource
    private var timer: Timer?
    private var mode: TravelMode = .roadtrip
    private var currentSpeed: () -> Double

    init(source: EventSource, currentSpeed: @escaping () -> Double) {
        self.source = source
        self.currentSpeed = currentSpeed
    }

    func start(mode: TravelMode) {
        self.mode = mode
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNext() {
        let interval = TimeInterval.random(in: mode.encounterInterval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.onEvent?(self.source.nextEvent(mode: self.mode, speedMPH: self.currentSpeed()))
            self.scheduleNext()
        }
    }
}
