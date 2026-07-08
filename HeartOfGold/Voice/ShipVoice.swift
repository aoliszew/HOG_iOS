import AVFoundation

/// Abstraction over speech output so a network TTS (ElevenLabs etc.) can swap in later.
protocol VoiceSynthesizing {
    func speak(_ text: String, completion: (() -> Void)?)
    func stopSpeaking()
    func setDelivery(rate: Float, pitch: Float)
}

extension VoiceSynthesizing {
    func speak(_ text: String) { speak(text, completion: nil) }
}

final class ShipVoice: NSObject, VoiceSynthesizing, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    /// Fired when the synthesizer finishes its whole queue (for session release).
    var onIdle: (() -> Void)?
    var isSpeaking: Bool { synthesizer.isSpeaking }

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var rate: Float = 0.48
    private var pitch: Float = 0.95
    private var completions: [ObjectIdentifier: () -> Void] = [:]

    override init() {
        // Prefer an enhanced/premium en voice if one is downloaded on the device.
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        voice = candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-GB")
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: (() -> Void)?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.preUtteranceDelay = 0.15
        if let completion {
            completions[ObjectIdentifier(utterance)] = completion
        }
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        completions.removeAll()   // cancelled speech shouldn't trigger follow-ups
        synthesizer.stopSpeaking(at: .word)
    }

    func setDelivery(rate: Float, pitch: Float) {
        self.rate = rate
        self.pitch = pitch
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completions.removeValue(forKey: ObjectIdentifier(utterance))?()
        if !synthesizer.isSpeaking { onIdle?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completions.removeValue(forKey: ObjectIdentifier(utterance))
    }
}
