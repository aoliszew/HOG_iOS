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

    /// Freeze the current wait gate (game pause), remembering time left.
    func pause() {
        if let gate = currentGate {
            pausedRemaining = max(0, gate.resumeAt.timeIntervalSinceNow)
        }
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard let gate = currentGate else { return }
        let remaining = pausedRemaining ?? 0
        pausedRemaining = nil
        currentGate = (Date().addingTimeInterval(remaining), gate.targetMiles)
        startPolling()
    }

    private var currentGate: (resumeAt: Date, targetMiles: Double)?
    private var pausedRemaining: TimeInterval?

    private func advance() {
        currentGate = nil
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
            currentGate = (Date().addingTimeInterval(wait.seconds ?? 0),
                           currentDistance() + (wait.miles ?? 0))
            startPolling()
        } else if let source = step.source, let text = step.text {
            deliver(ShipEvent(source: source, text: MessageTemplate.render(text), sfx: step.sfx))
            advance()
        } else {
            advance()
        }
    }

    private func startPolling() {
        let distance = currentDistance
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self, let gate = self.currentGate else { t.invalidate(); return }
                if Date() >= gate.resumeAt && distance() >= gate.targetMiles {
                    t.invalidate()
                    self.advance()
                }
            }
        }
    }
}
