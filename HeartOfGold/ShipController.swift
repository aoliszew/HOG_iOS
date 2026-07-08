import Foundation
import Combine

/// Central coordinator: wires audio, voice, trip tracking, and events together.
@MainActor
final class ShipController: ObservableObject {
    @Published var poweredUp = false
    @Published var mode: TravelMode = .roadtrip
    @Published var personality: EnginePersonality = .power {
        didSet {
            guard personality != oldValue else { return }
            voice.setDelivery(rate: personality.speechRate, pitch: personality.pitch)
            if poweredUp {
                say(source: "ENGINEERING", personality.confirmation)
            }
        }
    }
    @Published var log: [LogEntry] = []
    @Published var pendingMessages: [ShipEvent] = []
    @Published var activeChoices: [EventDefinition.Choice] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let time = Date()
        let source: String
        let text: String
    }

    let trip = TripTracker()
    let commands = CommandListener()

    private let audio = AudioEngine()
    private let voice: VoiceSynthesizing = ShipVoice()
    private let eventSource = ContentEventSource()
    private var activeSequence: SequencePlayer?
    private var activeBranching: BranchingPlayer?
    private lazy var events: EventEngine = EventEngine(source: eventSource) { [weak self] in
        guard let self else {
            return ShipContext(mode: .roadtrip, personality: .power, speedMPH: 0,
                               tripDistanceMiles: 0, stopped: true, hardAccelRecently: false, flags: [])
        }
        return ShipContext(mode: self.mode,
                           personality: self.personality,
                           speedMPH: self.trip.speedMPH,
                           tripDistanceMiles: self.trip.distanceMiles,
                           stopped: self.trip.speedMPH < 1,
                           hardAccelRecently: self.trip.hardAccelRecently,
                           flags: [],
                           longFormActive: self.activeSequence != nil || self.activeBranching != nil,
                           queuedMessages: self.pendingMessages.count)
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Nested ObservableObjects don't propagate to SwiftUI; forward their changes.
        // (trip drives the live speed/distance readout — without this the
        // speedometer only refreshes when something else redraws the view.)
        commands.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        trip.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        trip.onThresholdCrossed = { [weak self] mph in
            Task { @MainActor in self?.speedCallout(mph) }
        }
        trip.onHardAcceleration = { [weak self] in
            Task { @MainActor in self?.audio.play(.thruster) }
        }
        events.onEvent = { [weak self] playable in
            Task { @MainActor in
                guard let self else { return }
                switch playable {
                case .message(let event): self.deliver(event)
                case .sequence(let definition): self.startSequence(definition)
                case .branching(let definition): self.startBranching(definition)
                }
            }
        }
        commands.onCommand = { [weak self] command in
            Task { @MainActor in self?.handle(command) }
        }
        commands.onFailure = { [weak self] failure in
            Task { @MainActor in self?.reportListenFailure(failure) }
        }
        commands.onChoice = { [weak self] index in
            Task { @MainActor in
                guard let self, let player = self.activeBranching,
                      self.activeChoices.indices.contains(index) else { return }
                let choice = self.activeChoices[index]
                self.log.insert(LogEntry(source: "CAPTAIN", text: choice.label), at: 0)
                player.choose(choice)
            }
        }
    }

    private func reportListenFailure(_ failure: ListenFailure) {
        switch failure {
        case .unauthorized:
            say(source: "COMMS", "I need microphone and speech recognition permissions to hear you, Captain. Check the ship's Settings.")
        case .unavailable:
            say(source: "COMMS", "Speech recognition is unavailable right now, Captain.")
        case .heardNothing:
            say(source: "COMMS", "I didn't catch anything, Captain.")
        case .heard(let transcript):
            log.insert(LogEntry(source: "COMMS", text: "Heard: \"\(transcript)\""), at: 0)
            if !activeChoices.isEmpty {
                let options = activeChoices.map(\.label).joined(separator: ", or ")
                say(source: "COMMS", "I didn't catch that, Captain. Your options are: \(options).")
            } else {
                say(source: "COMMS", "Command not recognized, Captain. Try play message, status report, or power down.")
            }
        }
    }

    func listenForCommand() {
        voice.stopSpeaking()
        commands.startListening()
    }

    private func handle(_ command: ShipCommand) {
        switch command {
        case .playMessage: playNextMessage()
        case .statusReport: statusReport()
        case .powerDown: powerDown()
        }
    }

    func statusReport() {
        let speed = Int(trip.speedMPH.rounded())
        let distance = String(format: "%.1f", trip.distanceMiles)
        let waiting = pendingMessages.isEmpty
            ? "No transmissions waiting."
            : "\(pendingMessages.count) transmission\(pendingMessages.count == 1 ? "" : "s") waiting."
        say(source: "SHIP", "Status report. Sublight velocity \(speed) miles per hour. Mission distance \(distance) miles. All systems nominal. \(waiting)")
    }

    func powerUp() {
        guard !poweredUp else { return }
        poweredUp = true
        trip.resetTrip()
        trip.start()
        commands.requestPermissions()
        voice.setDelivery(rate: personality.speechRate, pitch: personality.pitch)
        audio.play(.powerUp)

        let shields = Int.random(in: 94...99)
        let startup = "Systems online. Shields at \(shields) percent. Infinite Improbability Drive on standby. \(mode.startupGreeting)"
        say(source: "SHIP", startup, delay: 1.2)

        events.start(mode: mode)
    }

    func powerDown() {
        guard poweredUp else { return }
        events.stop()
        activeSequence?.stop()
        activeSequence = nil
        activeBranching?.stop()
        activeBranching = nil
        activeChoices = []
        commands.setChoicePhrases([])
        trip.stop()
        voice.stopSpeaking()
        pendingMessages.removeAll()
        say(source: "SHIP", "Powering down. Mission distance: \(String(format: "%.1f", trip.distanceMiles)) miles. It has been a pleasure, Captain. So long, and thanks for all the fish.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [audio] in
            audio.play(.powerDown)
        }
        poweredUp = false
    }

    private func speedCallout(_ mph: Int) {
        say(source: "HELM", personality.speedCallout(threshold: mph))
    }

    /// Encounters don't interrupt: a hail beep sounds and the message waits in the
    /// queue until the captain asks for it ("play message" / the PLAY MESSAGE button).
    private func startSequence(_ definition: EventDefinition) {
        guard activeSequence == nil else { return }
        let player = SequencePlayer(
            event: definition,
            currentDistance: { [weak self] in self?.trip.distanceMiles ?? 0 },
            deliver: { [weak self] event in self?.deliver(event) },
            onComplete: { [weak self] in
                guard let self else { return }
                self.eventSource.completed(eventID: definition.id, extraFlags: [])
                self.activeSequence = nil
            }
        )
        activeSequence = player
        player.start()
    }

    private func startBranching(_ definition: EventDefinition) {
        guard activeBranching == nil else { return }
        let player = BranchingPlayer(
            event: definition,
            speak: { [weak self] event in
                // Branching moments are interactive: hail + speak immediately
                // rather than queueing, since a timed question is waiting.
                self?.audio.play(.hail)
                self?.say(source: event.source, event.text, delay: 0.8) {
                    // Auto-listen: a question was just asked — open the mic so
                    // the captain can answer hands-free. One shot; the on-screen
                    // buttons and the node timeout remain the fallbacks.
                    Task { @MainActor in
                        guard let self, self.activeBranching != nil,
                              !self.activeChoices.isEmpty else { return }
                        self.commands.startListening()
                    }
                }
            },
            setChoices: { [weak self] choices in
                self?.activeChoices = choices
                self?.commands.setChoicePhrases(choices.map(\.phrases))
            },
            onComplete: { [weak self] flags in
                guard let self else { return }
                self.eventSource.completed(eventID: definition.id, extraFlags: flags)
                self.activeBranching = nil
            }
        )
        activeBranching = player
        player.start()
    }

    /// Captain answered a branching choice by tapping (passenger/parked use).
    func choose(_ choice: EventDefinition.Choice) {
        guard let player = activeBranching else { return }
        log.insert(LogEntry(source: "CAPTAIN", text: choice.label), at: 0)
        player.choose(choice)
    }

    private func deliver(_ event: ShipEvent) {
        pruneStaleAmbient()
        audio.play(.hail)
        pendingMessages.append(event)
        log.insert(LogEntry(source: "COMMS", text: "Incoming transmission from \(event.source). Say or tap PLAY MESSAGE."), at: 0)
    }

    /// Ambient chatter that sat unheard for 10+ minutes is no longer news.
    private func pruneStaleAmbient() {
        pendingMessages.removeAll { $0.ambient && Date().timeIntervalSince($0.queuedAt) > 600 }
    }

    func playNextMessage() {
        pruneStaleAmbient()
        guard !pendingMessages.isEmpty else {
            say(source: "COMMS", "No messages waiting, Captain.")
            return
        }
        let event = pendingMessages.removeFirst()
        say(source: event.source, event.text)
        if !pendingMessages.isEmpty {
            say(source: "COMMS", "\(pendingMessages.count) more message\(pendingMessages.count == 1 ? "" : "s") waiting.", delay: 0.5)
        }
    }

    private func say(source: String, _ text: String, delay: TimeInterval = 0,
                     completion: (() -> Void)? = nil) {
        log.insert(LogEntry(source: source, text: text), at: 0)
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [voice] in
                voice.speak(text, completion: completion)
            }
        } else {
            voice.speak(text, completion: completion)
        }
    }
}
