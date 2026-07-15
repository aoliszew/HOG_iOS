import Foundation

/// EventSource backed by the JSON content library.
/// Plays `single` and `sequence` events; branching lands next
/// (those files load fine but stay dormant until their player exists).
final class ContentEventSource: EventSource {
    private let library: ContentLibrary
    private let evaluator = TriggerEvaluator()

    /// Story flags set by event effects; persists across the app session,
    /// resets per trip. (Cross-drive persistence is a later decision.)
    private(set) var flags: Set<String> = []

    init(library: ContentLibrary = ContentLibrary()) {
        self.library = library
    }

    func event(withID id: String) -> EventDefinition? {
        library.events.first { $0.id == id }
    }

    func tripStarted() {
        evaluator.resetTrip()
        flags = []
    }

    // MARK: - Persistence (crash-safe resume)

    var snapshot: (flags: Set<String>, firedCounts: [String: Int], lastFired: [String: Date]) {
        let s = evaluator.snapshot
        return (flags, s.firedCounts, s.lastFired)
    }

    func restore(flags: Set<String>, firedCounts: [String: Int], lastFired: [String: Date]) {
        self.flags = flags
        evaluator.restore(firedCounts: firedCounts, lastFired: lastFired)
    }

    func nextEvent(context: ShipContext) -> PlayableEvent? {
        var context = context
        context.flags.formUnion(flags)

        var playable = library.events
        if context.longFormActive {
            playable = playable.filter { $0.type == .single }
        }
        // Queue backed up: stop generating ambient chatter; plot still flows.
        if context.queuedMessages >= 5 {
            playable = playable.filter { $0.messageClass == .plot }
        }
        guard let event = evaluator.pick(from: playable, context: context) else { return nil }
        evaluator.recordFired(event)

        switch event.type {
        case .single:
            guard let source = event.content.source, let text = event.content.text else { return nil }
            applyEffects(of: event)
            return .message(ShipEvent(source: source, text: MessageTemplate.render(text),
                                      ambient: event.messageClass == .ambient,
                                      responses: event.content.responses ?? [],
                                      sfx: event.content.sfx))
        case .sequence:
            // Effects apply on completion, via completed(eventID:extraFlags:).
            return .sequence(event)
        case .branching:
            return .branching(event)
        }
    }

    func requestEvent(tag: String, context: ShipContext) -> PlayableEvent? {
        var context = context
        context.flags.formUnion(flags)
        guard let event = evaluator.pickRequested(tag: tag, from: library.events, context: context) else { return nil }
        evaluator.recordFired(event)
        switch event.type {
        case .branching: return .branching(event)
        case .sequence: return .sequence(event)
        case .single:
            guard let source = event.content.source, let text = event.content.text else { return nil }
            applyEffects(of: event)
            return .message(ShipEvent(source: source, text: MessageTemplate.render(text),
                                      ambient: event.messageClass == .ambient,
                                      responses: event.content.responses ?? [],
                                      sfx: event.content.sfx))
        }
    }

    func completed(eventID: String, extraFlags: Set<String>) {
        flags.formUnion(extraFlags)
        guard let event = library.events.first(where: { $0.id == eventID }) else { return }
        applyEffects(of: event)
    }

    private func applyEffects(of event: EventDefinition) {
        if let newFlags = event.effects?.setFlags {
            flags.formUnion(newFlags)
        }
    }
}
