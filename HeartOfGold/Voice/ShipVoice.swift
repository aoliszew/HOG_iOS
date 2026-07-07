import AVFoundation

/// Abstraction over speech output so a network TTS (ElevenLabs etc.) can swap in later.
protocol VoiceSynthesizing {
    func speak(_ text: String)
    func stopSpeaking()
}

final class ShipVoice: NSObject, VoiceSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

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
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.95
        utterance.preUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .word)
    }
}
