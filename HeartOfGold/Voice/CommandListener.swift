import Speech
import AVFoundation

enum ShipCommand: CaseIterable {
    case playMessage
    case statusReport
    case powerDown

    /// Phrases that trigger the command (matched as substrings of the transcript).
    var phrases: [String] {
        switch self {
        case .playMessage: return ["play message", "play the message", "play messages", "played message"]
        case .statusReport: return ["status report", "status update", "report status", "status"]
        case .powerDown: return ["power down", "shut down", "power off", "powered down"]
        }
    }

    static func match(_ transcript: String) -> ShipCommand? {
        let lower = transcript.lowercased()
        return allCases.first { $0.phrases.contains { lower.contains($0) } }
    }
}

/// Why listening couldn't start or produced nothing usable — surfaced so the
/// ship can tell the captain what's wrong instead of a generic failure.
enum ListenFailure {
    case unauthorized          // mic or speech permission missing
    case unavailable           // recognizer offline/unsupported
    case heard(String)         // heard something but no command matched
    case heardNothing          // timed out in silence
}

/// Push-to-talk command recognition.
/// Listens after activation and finishes on a matched command, ~2.5s of
/// post-speech silence, or an 8s cap.
/// (Always-on wake word is a Phase 4 task — this is the driver-safe stepping stone.)
final class CommandListener: NSObject, ObservableObject {
    @Published var isListening = false

    var onCommand: ((ShipCommand) -> Void)?
    var onFailure: ((ListenFailure) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var capTimer: Timer?
    private var silenceTimer: Timer?
    private var lastTranscript = ""

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func startListening() {
        guard !isListening else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else {
            onFailure?(.unauthorized)
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            onFailure?(.unavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device but never require it: it is unreliable in the
        // Simulator and unavailable for some locales/voices.
        #if !targetEnvironment(simulator)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        #endif
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            onFailure?(.unavailable)
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do { try audioEngine.start() } catch {
            input.removeTap(onBus: 0)
            onFailure?(.unavailable)
            return
        }

        lastTranscript = ""
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                if let command = ShipCommand.match(transcript) {
                    self.finish(.command(command))
                    return
                }
                if !transcript.isEmpty {
                    self.lastTranscript = transcript
                    // Captain is talking: wait for ~2.5s of silence before giving up.
                    self.restartSilenceTimer()
                }
                if result.isFinal {
                    self.finish(self.noMatchOutcome())
                }
            } else if error != nil {
                self.finish(self.noMatchOutcome())
            }
        }

        // Absolute cap so we never listen forever.
        capTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.finish(self.noMatchOutcome())
        }
    }

    func stopListening() {
        finish(nil)
    }

    private enum Outcome {
        case command(ShipCommand)
        case failure(ListenFailure)
    }

    private func noMatchOutcome() -> Outcome {
        lastTranscript.isEmpty ? .failure(.heardNothing) : .failure(.heard(lastTranscript))
    }

    private func restartSilenceTimer() {
        // Recognition callbacks arrive on a background queue; timers need the main run loop.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isListening else { return }
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.finish(self.noMatchOutcome())
            }
        }
    }

    private func finish(_ outcome: Outcome?) {
        guard isListening else { return }
        isListening = false
        capTimer?.invalidate()
        silenceTimer?.invalidate()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        guard let outcome else { return }
        DispatchQueue.main.async { [weak self] in
            switch outcome {
            case .command(let command): self?.onCommand?(command)
            case .failure(let failure): self?.onFailure?(failure)
            }
        }
    }
}
