import Foundation
import Combine

/// Central coordinator: wires audio, voice, trip tracking, and events together.
@MainActor
final class ShipController: ObservableObject {
    @Published var poweredUp = false
    @Published var mode: TravelMode = .errands
    @Published var plan = TripPlan()
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
    /// A crashed/interrupted mission that can be resumed (set at launch).
    @Published var resumableTrip: TripSnapshot?
    /// Video-game pause: all story clocks frozen, GPS tracking suspended.
    @Published var isPaused = false

    struct LogEntry: Identifiable {
        let id = UUID()
        let time = Date()
        let source: String
        let text: String
    }

    let trip = TripTracker()
    let commands = CommandListener()

    private let audio = AudioEngine()
    private let shipVoice = ShipVoice()
    private var voice: VoiceSynthesizing { shipVoice }
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
                           queuedMessages: self.pendingMessages.count,
                           tripPhase: self.plan.phase(distanceMiles: self.trip.distanceMiles),
                           stopsRemaining: self.plan.stopsRemaining)
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Session lifecycle: release audio focus when the ship stops talking so
        // the captain's music comes back to full volume between messages.
        audio.isVoiceSpeaking = { [weak self] in self?.shipVoice.isSpeaking ?? false }
        shipVoice.onIdle = { [weak self] in self?.audio.relinquishIfIdle() }

        // Nested ObservableObjects don't propagate to SwiftUI; forward their changes.
        // (trip drives the live speed/distance readout — without this the
        // speedometer only refreshes when something else redraws the view.)
        commands.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        trip.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
                self?.updateStopDetection()
                self?.persistIfFlying()
            }
            .store(in: &cancellables)

        resumableTrip = TripStore.loadResumable()
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
            Task { @MainActor in
                self?.audio.exitListeningMode()
                self?.handle(command)
            }
        }
        commands.onFailure = { [weak self] failure in
            Task { @MainActor in
                guard let self else { return }
                self.audio.exitListeningMode()
                if self.briefingQuery != nil {
                    self.abandonBriefing()   // no interrogation — one shot, then wing it
                } else {
                    self.reportListenFailure(failure)
                }
            }
        }
        commands.onChoice = { [weak self] index in
            Task { @MainActor in
                guard let self else { return }
                self.audio.exitListeningMode()
                if let query = self.briefingQuery {
                    self.handleBriefingAnswer(query, index: index)
                    return
                }
                guard let player = self.activeBranching,
                      self.activeChoices.indices.contains(index) else { return }
                let choice = self.activeChoices[index]
                self.log.insert(LogEntry(source: "CAPTAIN", text: choice.label), at: 0)
                player.choose(choice)
            }
        }
    }

    // MARK: - Mission briefing (voice fallback when the tap flow was skipped)

    private enum BriefingQuery { case stops, length }
    private var briefingQuery: BriefingQuery?

    private func askBriefing() {
        guard poweredUp else { return }
        if plan.plannedStops == nil {
            briefingQuery = .stops
            commands.setChoicePhrases([
                ["zero", "none", "no stops", "straight"],
                ["one", "1"],
                ["two", "2"],
                ["three", "3", "many", "more"],
            ])
            say(source: "SHIP", "Mission briefing, Captain. How many stops before we return to base? Zero, one, two, or three or more?") { [weak self] in
                Task { @MainActor in self?.listenForBriefing() }
            }
        } else if plan.length == nil {
            briefingQuery = .length
            commands.setChoicePhrases([
                ["quick", "hop", "short"],
                ["hour", "under an hour", "medium"],
                ["long", "haul", "road trip"],
            ])
            say(source: "SHIP", "And the flight plan: a quick hop, under an hour, or a long haul?") { [weak self] in
                Task { @MainActor in self?.listenForBriefing() }
            }
        } else {
            briefingQuery = nil
            commands.setChoicePhrases([])
            let stops = plan.plannedStops ?? 0
            let stopsText = stops == 0 ? "a direct flight" : "\(stops)\(stops == 3 ? " or more" : "") stop\(stops == 1 ? "" : "s")"
            say(source: "SHIP", "Briefing logged: \(stopsText), \(plan.length?.spoken ?? "duration unknown"). Plotting narrative course.")
        }
    }

    private func listenForBriefing() {
        guard briefingQuery != nil, poweredUp, !isPaused else { return }
        audio.enterListeningMode { [weak self] in
            self?.commands.startListening()
        }
    }

    private func handleBriefingAnswer(_ query: BriefingQuery, index: Int) {
        switch query {
        case .stops:
            plan.plannedStops = index      // choice order matches 0,1,2,3+
        case .length:
            plan.length = TripPlan.Length.allCases[safe: index] ?? .underAnHour
        }
        askBriefing()   // ask the next missing piece, or confirm
    }

    private func abandonBriefing() {
        briefingQuery = nil
        commands.setChoicePhrases([])
        say(source: "SHIP", "Very well, we'll improvise. The best missions usually are.")
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
        audio.enterListeningMode { [weak self] in
            self?.commands.startListening()
        }
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

        plan.stopsCompleted = 0
        let shields = Int.random(in: 94...99)
        let startup = "Systems online. Shields at \(shields) percent. Infinite Improbability Drive on standby. \(mode.startupGreeting)"
        say(source: "SHIP", startup, delay: 1.2) { [weak self] in
            Task { @MainActor in
                guard let self, self.poweredUp else { return }
                if !self.plan.isComplete { self.askBriefing() }
            }
        }

        events.start(mode: mode)
        resumableTrip = nil
        persistIfFlying()
    }

    /// Continue an interrupted mission: mileage, story flags, and fired-event
    /// history come back so nothing repeats and the odometer stays honest.
    func resumeMission() {
        guard !poweredUp, let saved = resumableTrip else { return }
        mode = TravelMode(rawValue: saved.mode) ?? mode
        personality = EnginePersonality(rawValue: saved.personality) ?? personality
        plan = TripPlan(length: saved.planLength.flatMap(TripPlan.Length.init(rawValue:)),
                        plannedStops: saved.plannedStops,
                        stopsCompleted: saved.stopsCompleted ?? 0)
        poweredUp = true
        trip.resetTrip()
        trip.restoreDistance(saved.distanceMiles)
        trip.start()
        commands.requestPermissions()
        voice.setDelivery(rate: personality.speechRate, pitch: personality.pitch)
        eventSource.restore(flags: Set(saved.flags),
                            firedCounts: saved.firedCounts,
                            lastFired: saved.lastFired)
        audio.play(.powerUp)
        say(source: "SHIP",
            "Resuming mission. Distance so far: \(String(format: "%.1f", saved.distanceMiles)) miles. All systems restored. As I was saying, Captain.",
            delay: 1.2)
        events.startWithoutReset(mode: mode)
        resumableTrip = nil
        persistIfFlying()
    }

    func pauseMission() {
        guard poweredUp, !isPaused else { return }
        isPaused = true
        events.pause()
        activeSequence?.pause()
        activeBranching?.pause()
        commands.stopListening()
        audio.exitListeningMode()
        voice.stopSpeaking()
        trip.stop()
        persistIfFlying()
    }

    func resumeFromPause() {
        guard poweredUp, isPaused else { return }
        isPaused = false
        trip.start()
        events.resume()
        activeSequence?.resume()
        activeBranching?.resume()
        say(source: "SHIP", "Resuming, Captain.")
    }

    // MARK: - Stop (docking) detection

    private var stoppedSince: Date?
    private var docked = false

    /// Stationary 4+ minutes = a docking (traffic lights don't count);
    /// pulling away afterwards ticks off an errand objective.
    private func updateStopDetection() {
        guard poweredUp, !isPaused else { return }
        let speed = trip.speedMPH
        if speed < 2 {
            if let since = stoppedSince {
                if !docked, Date().timeIntervalSince(since) > 240 { docked = true }
            } else {
                stoppedSince = Date()
            }
        } else if speed > 8 {
            if docked {
                docked = false
                plan.stopsCompleted += 1
                if let remaining = plan.stopsRemaining {
                    let line = remaining > 0
                        ? "Docking complete. \(remaining) objective\(remaining == 1 ? "" : "s") remaining before home."
                        : "Final objective complete. Setting course for home base, Captain."
                    say(source: "SHIP", line)
                } else {
                    say(source: "SHIP", "Docking complete. Resuming course.")
                }
            }
            stoppedSince = nil
        }
    }

    private func persistIfFlying() {
        guard poweredUp else { return }
        let state = eventSource.snapshot
        TripStore.save(TripSnapshot(active: true,
                                    startedAt: .now,
                                    updatedAt: .now,
                                    mode: mode.rawValue,
                                    personality: personality.rawValue,
                                    distanceMiles: trip.distanceMiles,
                                    flags: Array(state.flags),
                                    firedCounts: state.firedCounts,
                                    lastFired: state.lastFired,
                                    planLength: plan.length?.rawValue,
                                    plannedStops: plan.plannedStops,
                                    stopsCompleted: plan.stopsCompleted))
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
        commands.stopListening()
        audio.exitListeningMode()
        trip.stop()
        voice.stopSpeaking()
        pendingMessages.removeAll()
        say(source: "SHIP", "Powering down. Mission distance: \(String(format: "%.1f", trip.distanceMiles)) miles. It has been a pleasure, Captain. So long, and thanks for all the fish.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [audio] in
            audio.play(.powerDown)
        }
        poweredUp = false
        isPaused = false
        briefingQuery = nil
        stoppedSince = nil
        docked = false
        plan = TripPlan()   // fresh briefing next drive
        TripStore.clear()
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
                        self.audio.enterListeningMode { [weak self] in
                            self?.commands.startListening()
                        }
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
        // Audio self-sufficiency: spoken attribution + a per-character delivery
        // so the captain knows who's talking without looking at the screen.
        let style = CharacterVoices.style(for: source)
        let spoken: String
        if let lead = CharacterVoices.attribution(for: source, text: text) {
            spoken = "\(lead) \(text)"
        } else {
            spoken = text
        }
        let speak: @Sendable () -> Void = { [audio, shipVoice] in
            // Take the session, but let a nav prompt finish first.
            audio.ensurePlayback()
            audio.performWhenClear {
                shipVoice.speak(spoken,
                                rateMultiplier: style.rateMultiplier,
                                pitchMultiplier: style.pitchMultiplier,
                                completion: completion)
            }
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: speak)
        } else {
            speak()
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
