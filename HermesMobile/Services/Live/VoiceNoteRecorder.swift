import AVFoundation
import Foundation

/// Records a short voice note as AAC (.m4a) for transcription on the server.
@MainActor
@Observable
final class VoiceNoteRecorder {
    static let maxDuration: TimeInterval = 300

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    /// Called with the audio when the recording ends by itself (the 5 minute limit).
    @ObservationIgnored var onFinished: (@MainActor (Data) -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var isStarting = false

    /// New composer text once a transcript arrives: the transcript is marked with a microphone
    /// and appended after anything already typed.
    nonisolated static func composerText(existing: String, transcript: String) -> String {
        let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = "🎙️ \(transcript.trimmingCharacters(in: .whitespacesAndNewlines))"
        return base.isEmpty ? note : "\(base) \(note)"
    }

    func start() async throws {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw NSError(domain: "VoiceNote", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access is off. Turn it on in Settings."])
        }
        let session = AVAudioSession.sharedInstance()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record(forDuration: Self.maxDuration) else {
                throw NSError(domain: "VoiceNote", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't start recording."])
            }
            self.recorder = recorder
        } catch {
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        fileURL = url
        elapsed = 0
        isRecording = true
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.cancel() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                guard let recorder = self.recorder else { return }
                if recorder.isRecording {
                    self.elapsed = recorder.currentTime
                } else {
                    self.finishAutomatically()
                }
            }
        }
    }

    func stop() throws -> Data {
        let url = fileURL
        teardown()
        guard let url else { return Data() }
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    /// Discards the recording (view left, app backgrounded, call interrupted).
    func cancel() {
        let url = fileURL
        teardown()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func finishAutomatically() {
        guard let data = try? stop(), !data.isEmpty else { return }
        onFinished?(data)
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        let wasActive = recorder != nil
        recorder?.stop()
        recorder = nil
        fileURL = nil
        isRecording = false
        if wasActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
