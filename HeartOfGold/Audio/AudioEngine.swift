import AVFoundation

enum SoundEffect: String {
    case powerUp = "power_up"
    case powerDown = "power_down"
    case hail = "hail"
    case thruster = "thruster"
}

/// Owns the audio session (sole owner — see AGENTS.md) and sound-effect playback.
///
/// Session strategy, learned the hard way in the field:
/// - `.playback` + duckOthers ONLY while we're actually making sound, released
///   (with notifyOthers) when idle so music returns to full volume between
///   messages instead of staying cut off/ducked the whole drive.
/// - `.playAndRecord` ONLY while the mic is actively listening — holding it
///   full-time caused crackle and killed other apps' audio.
/// - All session calls stay off the main thread (setActive blocks on XPC and
///   once deadlocked app launch).
final class AudioEngine {
    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private let queue = DispatchQueue(label: "com.oliszewski.heartofgold.audio")

    /// Set by the controller so idle checks can see if TTS is still talking.
    var isVoiceSpeaking: () -> Bool = { false }

    init() {
        queue.async { [self] in preload() }
    }

    // MARK: - Session modes

    private func setPlaybackCategory() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback,
                                    mode: .spokenAudio,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session (playback) error: \(error)")
        }
    }

    /// Grab the session for output; call before speaking or playing SFX.
    func ensurePlayback(then completion: (() -> Void)? = nil) {
        queue.async { [self] in
            setPlaybackCategory()
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    /// Mic-enabled mode, only for the duration of a listening window.
    func enterListeningMode(then completion: @escaping () -> Void) {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord,
                                        mode: .default,
                                        options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true)
            } catch {
                print("Audio session (record) error: \(error)")
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// Back to output-only after listening ends.
    func exitListeningMode() {
        queue.async { [self] in setPlaybackCategory() }
    }

    /// Release the session if nothing is playing so other audio (music) comes
    /// back to full volume. Safe to call often; it re-checks after a beat.
    func relinquishIfIdle() {
        queue.asyncAfter(deadline: .now() + 1.2) { [self] in
            let sfxPlaying = players.values.contains { $0.isPlaying }
            guard !sfxPlaying, !isVoiceSpeaking() else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Wait (up to ~6s) for other transient audio — a nav prompt — to finish
    /// before running `block`. The ship doesn't talk over the GPS.
    func performWhenClear(_ block: @escaping () -> Void) {
        performWhenClear(attemptsLeft: 12, block)
    }

    private func performWhenClear(attemptsLeft: Int, _ block: @escaping () -> Void) {
        queue.async {
            let hint = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
            if !hint || attemptsLeft <= 0 {
                DispatchQueue.main.async(execute: block)
            } else {
                self.queue.asyncAfter(deadline: .now() + 0.5) {
                    self.performWhenClear(attemptsLeft: attemptsLeft - 1, block)
                }
            }
        }
    }

    // MARK: - SFX

    private func preload() {
        for effect in [SoundEffect.powerUp, .powerDown, .hail, .thruster] {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf") else {
                print("Missing SFX: \(effect.rawValue).caf")
                continue
            }
            players[effect] = try? AVAudioPlayer(contentsOf: url)
            players[effect]?.prepareToPlay()
        }
    }

    func play(_ effect: SoundEffect) {
        queue.async { [self] in
            setPlaybackCategory()
            players[effect]?.currentTime = 0
            players[effect]?.play()
        }
        relinquishIfIdle()
    }
}
