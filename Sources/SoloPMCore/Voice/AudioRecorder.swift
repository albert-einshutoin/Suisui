import Foundation

public enum AudioRecordingState: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording(startedAt: Date)
    case stopping
    case completed(RecordedAudio)
    case failed(String)
}

public protocol AudioRecorder {
    var state: AudioRecordingState { get }

    mutating func start(at date: Date) throws
    mutating func stop(outputURL: URL, at date: Date) throws -> RecordedAudio
}

public enum AudioRecorderError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case failed(String)
}

public struct FakeAudioRecorder: AudioRecorder {
    public private(set) var state: AudioRecordingState
    private var permissionGranted: Bool

    public init(state: AudioRecordingState = .idle, permissionGranted: Bool = true) {
        self.state = state
        self.permissionGranted = permissionGranted
    }

    public mutating func start(at date: Date = Date()) throws {
        guard permissionGranted else {
            state = .failed("Microphone permission denied.")
            throw AudioRecorderError.microphonePermissionDenied
        }

        guard case .idle = state else {
            throw AudioRecorderError.alreadyRecording
        }

        state = .recording(startedAt: date)
    }

    public mutating func stop(outputURL: URL, at date: Date = Date()) throws -> RecordedAudio {
        guard case .recording(let startedAt) = state else {
            throw AudioRecorderError.notRecording
        }

        state = .stopping
        let audio = RecordedAudio(
            fileURL: outputURL,
            format: .m4a,
            duration: max(0, date.timeIntervalSince(startedAt))
        )
        state = .completed(audio)
        return audio
    }
}
