import Foundation

/// Plays a `branching` event: a node graph where the captain answers by voice
/// (choice phrases) or tap. Ignoring the ship long enough follows the node's
/// timeout path — not responding is itself a choice.
@MainActor
final class BranchingPlayer {
    let eventID: String

    private let nodes: [String: EventDefinition.Node]
    private let speak: (ShipEvent) -> Void
    private let setChoices: ([EventDefinition.Choice]) -> Void
    private let onComplete: (Set<String>) -> Void

    private var collectedFlags: Set<String> = []
    private var timeoutTimer: Timer?
    private var timeoutDeadline: Date?
    private var timeoutNextNode: String?
    private var pausedTimeoutRemaining: TimeInterval?
    private let entry: String

    init(event: EventDefinition,
         speak: @escaping (ShipEvent) -> Void,
         setChoices: @escaping ([EventDefinition.Choice]) -> Void,
         onComplete: @escaping (Set<String>) -> Void) {
        self.eventID = event.id
        self.entry = event.content.entry ?? "end"
        self.nodes = event.content.nodes ?? [:]
        self.speak = speak
        self.setChoices = setChoices
        self.onComplete = onComplete
    }

    func start() {
        goto(entry)
    }

    func stop() {
        timeoutTimer?.invalidate()
        setChoices([])
    }

    /// Freeze the answer clock (game pause); choices stay on offer.
    func pause() {
        if let deadline = timeoutDeadline {
            pausedTimeoutRemaining = max(1, deadline.timeIntervalSinceNow)
        }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    func resume() {
        guard let remaining = pausedTimeoutRemaining, let target = timeoutNextNode else { return }
        pausedTimeoutRemaining = nil
        armTimeout(after: remaining, then: target)
    }

    func choose(_ choice: EventDefinition.Choice) {
        timeoutTimer?.invalidate()
        timeoutDeadline = nil
        timeoutNextNode = nil
        currentChoices = []
        setChoices([])
        if let flags = choice.setFlags { collectedFlags.formUnion(flags) }
        goto(choice.resolvedNext)
    }

    private(set) var currentChoices: [EventDefinition.Choice] = []

    private func goto(_ nodeID: String) {
        guard nodeID != "end", let node = nodes[nodeID] else {
            finish()
            return
        }
        speak(ShipEvent(source: node.source, text: MessageTemplate.render(node.text)))
        if let flags = node.setFlags { collectedFlags.formUnion(flags) }

        if let choices = node.choices, !choices.isEmpty {
            currentChoices = choices
            setChoices(choices)
            if let timeout = node.timeoutSeconds, let timeoutNext = node.timeoutNext {
                armTimeout(after: timeout, then: timeoutNext)
            }
        } else if let next = node.next {
            goto(next)
        } else {
            finish()
        }
    }

    private func armTimeout(after seconds: TimeInterval, then nodeID: String) {
        timeoutDeadline = Date().addingTimeInterval(seconds)
        timeoutNextNode = nodeID
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.timeoutDeadline = nil
                self.currentChoices = []
                self.setChoices([])
                self.goto(nodeID)
            }
        }
    }

    private func finish() {
        timeoutTimer?.invalidate()
        currentChoices = []
        setChoices([])
        onComplete(collectedFlags)
    }
}
