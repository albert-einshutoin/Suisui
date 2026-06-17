import AVFoundation
import Foundation
import SoloPMCore

final class AVFoundationAudioRecorder: AudioRecorder {
    private(set) var state: AudioRecordingState = .idle

    private var recorder: AVAudioRecorder?
    private var recordingStartedAt: Date?
    private let temporaryDirectory: URL

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    func start(at date: Date = Date()) throws {
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
            throw AudioRecorderError.microphonePermissionDenied
        @unknown default:
            state = .failed("Unknown microphone permission status.")
            throw AudioRecorderError.failed("Unknown microphone permission status.")
        }

        let url = temporaryRecordingURL(startedAt: date)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
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
            state = .failed(error.localizedDescription)
            throw AudioRecorderError.failed(error.localizedDescription)
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
            state = .failed(error.localizedDescription)
            throw AudioRecorderError.failed(error.localizedDescription)
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

    private func temporaryRecordingURL(startedAt date: Date) -> URL {
        let timestamp = Int(date.timeIntervalSince1970)
        return temporaryDirectory.appendingPathComponent("solopm-recording-\(timestamp).m4a")
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
