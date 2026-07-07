import AVFoundation

enum SoundEffect: String {
    case powerUp = "power_up"
    case powerDown = "power_down"
    case hail = "hail"
}

/// Owns the audio session and sound-effect playback. Configured to keep running
/// in the background and duck other audio (e.g. Maps guidance) while speaking.
final class AudioEngine {
    private var players: [SoundEffect: AVAudioPlayer] = [:]

    init() {
        configureSession()
        preload()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback,
                                    mode: .voicePrompt,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func preload() {
        for effect in [SoundEffect.powerUp, .powerDown, .hail] {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf") else {
                print("Missing SFX: \(effect.rawValue).caf")
                continue
            }
            players[effect] = try? AVAudioPlayer(contentsOf: url)
            players[effect]?.prepareToPlay()
        }
    }

    func play(_ effect: SoundEffect) {
        players[effect]?.currentTime = 0
        players[effect]?.play()
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
