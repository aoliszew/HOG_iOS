import AVFoundation

enum SoundEffect: String {
    case powerUp = "power_up"
    case powerDown = "power_down"
    case hail = "hail"
    case thruster = "thruster"
}

/// Owns the audio session and sound-effect playback. Configured to keep running
/// in the background and duck other audio (e.g. Maps guidance) while speaking.
final class AudioEngine {
    private var players: [SoundEffect: AVAudioPlayer] = [:]
    // Session setup and player priming block on CoreAudio XPC and must never run
    // on the main thread (deadlocks app launch); all state is confined to this queue.
    private let queue = DispatchQueue(label: "com.oliszewski.heartofgold.audio")

    init() {
        queue.async { [self] in
            configureSession()
            preload()
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playAndRecord so push-to-talk can use the mic; still ducks Maps guidance.
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers,
                                              .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

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
            players[effect]?.currentTime = 0
            players[effect]?.play()
        }
    }

    func deactivate() {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
