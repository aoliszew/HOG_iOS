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

    func tripStarted() {
        evaluator.resetTrip()
        flags = []
    }

    func nextEvent(context: ShipContext) -> PlayableEvent? {
        var context = context
        context.flags.formUnion(flags)

        var playable = library.events.filter { $0.type != .branching }
        if context.longFormActive {
            playable = playable.filter { $0.type == .single }
        }
        guard let event = evaluator.pick(from: playable, context: context) else { return nil }
        evaluator.recordFired(event)

        switch event.type {
        case .single:
            guard let source = event.content.source, let text = event.content.text else { return nil }
            applyEffects(of: event)
            return .message(ShipEvent(source: source, text: text))
        case .sequence:
            // Effects apply on completion, via completed(eventID:).
            return .sequence(event)
        case .branching:
            return nil
        }
    }

    func completed(eventID: String) {
        guard let event = library.events.first(where: { $0.id == eventID }) else { return }
        applyEffects(of: event)
    }

    private func applyEffects(of event: EventDefinition) {
        if let newFlags = event.effects?.setFlags {
            flags.formUnion(newFlags)
        }
    }
}
