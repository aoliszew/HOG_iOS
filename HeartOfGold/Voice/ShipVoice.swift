import AVFoundation

/// Abstraction over speech output so a network TTS (ElevenLabs etc.) can swap in later.
protocol VoiceSynthesizing {
    func speak(_ text: String)
    func stopSpeaking()
    func setDelivery(rate: Float, pitch: Float)
}

final class ShipVoice: NSObject, VoiceSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var rate: Float = 0.48
    private var pitch: Float = 0.95

    override init() {
        // Prefer an enhanced/premium en voice if one is downloaded on the device.
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        voice = candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-GB")
        super.init()
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.preUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .word)
    }

    func setDelivery(rate: Float, pitch: Float) {
        self.rate = rate
        self.pitch = pitch
    }
}
