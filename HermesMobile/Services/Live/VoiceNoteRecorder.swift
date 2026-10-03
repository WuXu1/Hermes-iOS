import AVFoundation
import Foundation

/// Records a short voice note as AAC (.m4a) for transcription on the server.
@MainActor
@Observable
final class VoiceNoteRecorder {
    static let maxDuration: TimeInterval = 300

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw NSError(domain: "VoiceNote", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access is off. Turn it on in Settings."])
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
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
        fileURL = url
        elapsed = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
        }
    }

    func stop() throws -> Data {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = fileURL else { return Data() }
        fileURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }
}
