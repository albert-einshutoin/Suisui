import AVFoundation
import Foundation
import SuisuiCore

final class AVFoundationAudioRecorder: AudioRecorder {
    private(set) var state: AudioRecordingState = .idle

    private var recorder: AVAudioRecorder?
    private var recordingStartedAt: Date?
    private let temporaryDirectory: URL

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    func start(at date: Date = Date()) async throws {
        guard state.canStartRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch permissionStatus {
        case .authorized:
            break
        case .denied, .restricted:
            state = .failed("Microphone permission denied.")
            throw AudioRecorderError.microphonePermissionDenied
        case .notDetermined:
            state = .requestingPermission
            let isGranted = await requestMicrophoneAccess()
            guard isGranted else {
                state = .failed("Microphone permission denied.")
                throw AudioRecorderError.microphonePermissionDenied
            }
            state = .idle
        @unknown default:
            state = .failed("Unknown microphone permission status.")
            throw AudioRecorderError.failed("Unknown microphone permission status.")
        }

        let url = temporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            // Metering feeds the live input-level meter and the silence hint
            // in the voice capture window.
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            guard recorder.record() else {
                state = .failed("Audio recording did not start.")
                throw AudioRecorderError.failed("Audio recording did not start.")
            }

            self.recorder = recorder
            recordingStartedAt = date
            state = .recording(startedAt: date)
        } catch let error as AudioRecorderError {
            throw error
        } catch {
            let message = UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: "Audio recording failed."
            )
            state = .failed(message)
            throw AudioRecorderError.failed(message)
        }
    }

    func stop(outputURL: URL, at date: Date = Date()) throws -> RecordedAudio {
        guard case .recording(let startedAt) = state, let recorder else {
            throw AudioRecorderError.notRecording
        }

        state = .stopping
        recorder.stop()

        do {
            try replaceItem(at: outputURL, with: recorder.url)
        } catch {
            let message = UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: "Audio recording could not be saved."
            )
            state = .failed(message)
            throw AudioRecorderError.failed(message)
        }

        let audio = RecordedAudio(
            fileURL: outputURL,
            format: .m4a,
            duration: max(0, date.timeIntervalSince(startedAt))
        )
        self.recorder = nil
        recordingStartedAt = nil
        state = .completed(audio)
        return audio
    }

    func reset() {
        let temporaryURL = recorder?.url
        recorder?.stop()
        recorder = nil
        recordingStartedAt = nil
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        state = .idle
    }

    func temporaryRecordingURL(identifier: UUID = UUID()) -> URL {
        temporaryDirectory.appendingPathComponent("suisui-recording-\(identifier.uuidString).m4a")
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            // AVCaptureDevice is the API that registers Suisui with macOS TCC; without this
            // first-run users never receive the system microphone permission prompt.
            AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: source, to: destination)
    }
}

extension AVFoundationAudioRecorder: AudioInputLevelReading {
    /// Average power of the current buffer converted to a normalized 0...1
    /// level with a -50dB floor (see `MicrophoneInputLevelNormalizer`).
    var currentNormalizedInputLevel: Double? {
        guard case .recording = state, let recorder else {
            return nil
        }
        recorder.updateMeters()
        return MicrophoneInputLevelNormalizer.normalizedLevel(
            fromAveragePowerDecibels: Double(recorder.averagePower(forChannel: 0))
        )
    }
}

private extension AudioRecordingState {
    var canStartRecording: Bool {
        switch self {
        case .idle, .completed, .failed:
            return true
        case .requestingPermission, .recording, .stopping:
            return false
        }
    }
}
