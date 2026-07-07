import Speech
import AVFoundation

enum ShipCommand: CaseIterable {
    case playMessage
    case statusReport
    case powerDown

    /// Phrases that trigger the command (matched as substrings of the transcript).
    var phrases: [String] {
        switch self {
        case .playMessage: return ["play message", "play the message", "play messages"]
        case .statusReport: return ["status report", "status update", "report status"]
        case .powerDown: return ["power down", "shut down", "power off"]
        }
    }

    static func match(_ transcript: String) -> ShipCommand? {
        let lower = transcript.lowercased()
        return allCases.first { $0.phrases.contains { lower.contains($0) } }
    }
}

/// Push-to-talk command recognition using on-device speech recognition.
/// Listens for a short window after activation, then reports the matched command.
/// (Always-on wake word is a Phase 4 task — this is the driver-safe stepping stone.)
final class CommandListener: NSObject, ObservableObject {
    @Published var isListening = false

    var onCommand: ((ShipCommand) -> Void)?
    var onNoMatch: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeoutTimer: Timer?

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func startListening() {
        guard !isListening,
              let recognizer, recognizer.isAvailable,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do { try audioEngine.start() } catch { return }

        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result, let command = ShipCommand.match(result.bestTranscription.formattedString) {
                self.finish(command: command)
            } else if error != nil || (result?.isFinal ?? false) {
                self.finish(command: nil)
            }
        }

        // Listen for at most 5 seconds.
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.finish(command: nil)
        }
    }

    func stopListening() {
        finish(command: nil, notify: false)
    }

    private func finish(command: ShipCommand?, notify: Bool = true) {
        guard isListening else { return }
        isListening = false
        timeoutTimer?.invalidate()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        guard notify else { return }
        DispatchQueue.main.async { [weak self] in
            if let command {
                self?.onCommand?(command)
            } else {
                self?.onNoMatch?()
            }
        }
    }
}
