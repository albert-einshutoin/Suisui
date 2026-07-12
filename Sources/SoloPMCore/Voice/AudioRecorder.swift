import Foundation

public enum AudioRecordingState: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording(startedAt: Date)
    case stopping
    case completed(RecordedAudio)
    case failed(String)
}

@MainActor
public protocol AudioRecorder {
    var state: AudioRecordingState { get }

    mutating func start(at date: Date) async throws
    mutating func stop(outputURL: URL, at date: Date) throws -> RecordedAudio
    mutating func reset()
}

/// Optional capability of an `AudioRecorder`: exposing the current microphone
/// input level so the UI can render a live meter while recording. Recorders
/// without metering simply do not conform and the meter stays hidden.
@MainActor
public protocol AudioInputLevelReading {
    /// Latest normalized input level in 0...1 (see
    /// `MicrophoneInputLevelNormalizer`), or nil while not recording or when
    /// metering is unavailable.
    var currentNormalizedInputLevel: Double? { get }
}

public enum AudioRecorderError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case failed(String)
}
