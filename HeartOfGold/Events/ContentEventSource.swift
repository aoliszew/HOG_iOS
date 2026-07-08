import Foundation

/// EventSource backed by the JSON content library.
/// This PR plays `single` events; sequence and branching playback land next
/// (their files load fine but stay dormant until their players exist).
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

    func nextEvent(context: ShipContext) -> ShipEvent? {
        var context = context
        context.flags.formUnion(flags)

        let playable = library.events.filter { $0.type == .single }
        guard let event = evaluator.pick(from: playable, context: context),
              let source = event.content.source,
              let text = event.content.text else { return nil }

        evaluator.recordFired(event)
        if let newFlags = event.effects?.setFlags {
            flags.formUnion(newFlags)
        }
        return ShipEvent(source: source, text: text)
    }
}
