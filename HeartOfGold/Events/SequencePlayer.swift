import Foundation

/// Plays a `sequence` event: steps in order, with `wait` gates on time and/or
/// distance between them. This is how a story unfolds across a drive
/// ("every 5 miles you get a new clue").
@MainActor
final class SequencePlayer {
    let eventID: String

    private let steps: [EventDefinition.Step]
    private let currentDistance: () -> Double
    private let deliver: (ShipEvent) -> Void
    private let onComplete: () -> Void

    private var index = 0
    private var timer: Timer?

    init(event: EventDefinition,
         currentDistance: @escaping () -> Double,
         deliver: @escaping (ShipEvent) -> Void,
         onComplete: @escaping () -> Void) {
        self.eventID = event.id
        self.steps = event.content.steps ?? []
        self.currentDistance = currentDistance
        self.deliver = deliver
        self.onComplete = onComplete
    }

    func start() {
        advance()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard index < steps.count else {
            onComplete()
            return
        }
        let step = steps[index]
        index += 1

        if let wait = step.wait {
            // Gate on time and/or distance; when both are given, both must pass.
            // Waiting naturally tolerates stops: parked miles don't accumulate
            // and the story simply resumes when the numbers are met.
            let resumeAt = Date().addingTimeInterval(wait.seconds ?? 0)
            let distance = currentDistance
            let targetMiles = distance() + (wait.miles ?? 0)
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if Date() >= resumeAt && distance() >= targetMiles {
                    t.invalidate()
                    Task { @MainActor in self?.advance() }
                }
            }
        } else if let source = step.source, let text = step.text {
            deliver(ShipEvent(source: source, text: text))
            advance()
        } else {
            advance()
        }
    }
}
