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
    mutating func reset()
}

public enum AudioRecorderError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case failed(String)
}
