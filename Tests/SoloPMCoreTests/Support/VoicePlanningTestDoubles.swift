import Foundation
@testable import SoloPMCore

struct FakeAudioRecorder: AudioRecorder {
    private(set) var state: AudioRecordingState
    private var permissionGranted: Bool
    private var permissionGrantDecisions: [Bool]

    init(
        state: AudioRecordingState = .idle,
        permissionGranted: Bool = true,
        permissionGrantDecisions: [Bool] = []
    ) {
        self.state = state
        self.permissionGranted = permissionGranted
        self.permissionGrantDecisions = permissionGrantDecisions
    }

    mutating func start(at date: Date = Date()) async throws {
        if !permissionGranted {
            state = .requestingPermission
            let isGranted = permissionGrantDecisions.isEmpty ? false : permissionGrantDecisions.removeFirst()
            guard isGranted else {
                state = .failed("Microphone permission denied.")
                throw AudioRecorderError.microphonePermissionDenied
            }
            permissionGranted = true
            state = .idle
        }

        guard state.canStartRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        state = .recording(startedAt: date)
    }

    mutating func stop(outputURL: URL, at date: Date = Date()) throws -> RecordedAudio {
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

    mutating func reset() {
        state = .idle
    }
}

struct FakeSTTProvider: SpeechToTextProvider {
    var id: STTProviderID
    var availability: STTProviderAvailability
    private var transcript: STTTranscript

    init(
        id: STTProviderID = .whisperKit,
        availability: STTProviderAvailability? = nil,
        transcript: STTTranscript
    ) {
        self.id = id
        self.availability = availability ?? STTProviderAvailability(providerID: id, isAvailable: true)
        self.transcript = transcript
    }

    func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        guard availability.isAvailable else {
            throw STTProviderError.unavailable(availability.reason ?? "STT provider is unavailable.")
        }
        return transcript
    }
}

struct FakeLLMProvider: LLMProvider {
    var providerID: String
    private var response: PlanningResponse

    init(providerID: String = "fake", response: PlanningResponse) {
        self.providerID = providerID
        self.response = response
    }

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        response
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
