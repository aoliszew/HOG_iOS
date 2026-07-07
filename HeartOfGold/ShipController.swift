import Foundation
import Combine

/// Central coordinator: wires audio, voice, trip tracking, and events together.
@MainActor
final class ShipController: ObservableObject {
    @Published var poweredUp = false
    @Published var mode: TravelMode = .roadtrip
    @Published var log: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let time = Date()
        let source: String
        let text: String
    }

    let trip = TripTracker()

    private let audio = AudioEngine()
    private let voice: VoiceSynthesizing = ShipVoice()
    private lazy var events: EventEngine = EventEngine(source: CannedEvents()) { [weak self] in
        self?.trip.speedMPH ?? 0
    }

    init() {
        trip.onThresholdCrossed = { [weak self] mph in
            Task { @MainActor in self?.speedCallout(mph) }
        }
        events.onEvent = { [weak self] event in
            Task { @MainActor in self?.deliver(event) }
        }
    }

    func powerUp() {
        guard !poweredUp else { return }
        poweredUp = true
        trip.resetTrip()
        trip.start()
        audio.play(.powerUp)

        let shields = Int.random(in: 94...99)
        let startup = "Systems online. Shields at \(shields) percent. Infinite Improbability Drive on standby. \(mode.startupGreeting)"
        say(source: "SHIP", startup, delay: 1.2)

        events.start(mode: mode)
    }

    func powerDown() {
        guard poweredUp else { return }
        events.stop()
        trip.stop()
        voice.stopSpeaking()
        say(source: "SHIP", "Powering down. Mission distance: \(String(format: "%.1f", trip.distanceMiles)) miles. It has been a pleasure, Captain. So long, and thanks for all the fish.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [audio] in
            audio.play(.powerDown)
        }
        poweredUp = false
    }

    private func speedCallout(_ mph: Int) {
        let line: String
        switch mph {
        case 30: line = "Entering cruise velocity."
        case 55: line = "Sublight velocity fifty-five. Engines purring, Captain."
        default: line = "Approaching maximum recommended sublight. Shields tightened."
        }
        say(source: "HELM", line)
    }

    private func deliver(_ event: ShipEvent) {
        audio.play(.hail)
        say(source: event.source, event.text, delay: 0.8)
    }

    private func say(source: String, _ text: String, delay: TimeInterval = 0) {
        log.insert(LogEntry(source: source, text: text), at: 0)
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [voice] in
                voice.speak(text)
            }
        } else {
            voice.speak(text)
        }
    }
}
