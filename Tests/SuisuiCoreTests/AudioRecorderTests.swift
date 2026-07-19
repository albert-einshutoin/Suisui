import XCTest
@testable import SuisuiCore

@MainActor
final class AudioRecorderTests: XCTestCase {
    func testUserFacingErrorMessageSanitizerRedactsRecorderErrors() {
        let secret = "sk-" + "audioRecorderSecret123"
        let error = NSError(
            domain: "SuisuiAudioRecorder",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Recorder failed for fileURL=/tmp/input.m4a?token=\(secret)&request_id=audio-recorder-1"
            ]
        )

        let message = UserFacingErrorMessageSanitizer.message(from: error)

        XCTAssertTrue(message.contains("Recorder failed"))
        XCTAssertTrue(message.contains("request_id=audio-recorder-1"))
        XCTAssertFalse(message.contains(secret))
        XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
    }

    func testFakeRecorderTransitionsFromIdleToCompleted() async throws {
        var recorder = FakeAudioRecorder()
        let startedAt = Date(timeIntervalSince1970: 100)
        let stoppedAt = Date(timeIntervalSince1970: 103)

        try await recorder.start(at: startedAt)
        XCTAssertEqual(recorder.state, .recording(startedAt: startedAt))

        let audio = try recorder.stop(outputURL: URL(filePath: "/tmp/output.m4a"), at: stoppedAt)

        XCTAssertEqual(audio.duration, 3)
        XCTAssertEqual(recorder.state, .completed(audio))
    }

    func testFakeRecorderRequestsPermissionBeforeRecordingWhenDecisionGrantsAccess() async throws {
        var recorder = FakeAudioRecorder(permissionGranted: false, permissionGrantDecisions: [true])
        let startedAt = Date(timeIntervalSince1970: 100)

        try await recorder.start(at: startedAt)

        XCTAssertEqual(recorder.state, .recording(startedAt: startedAt))
    }

    func testFakeRecorderRejectsStartWhenPermissionDenied() async {
        var recorder = FakeAudioRecorder(permissionGranted: false)

        do {
            try await recorder.start(at: Date())
            XCTFail("Expected microphone permission denial.")
        } catch {
            XCTAssertEqual(error as? AudioRecorderError, .microphonePermissionDenied)
        }
    }

    func testFakeRecorderRejectsStopWhenNotRecording() {
        var recorder = FakeAudioRecorder()

        XCTAssertThrowsError(try recorder.stop(outputURL: URL(filePath: "/tmp/output.m4a"), at: Date())) { error in
            XCTAssertEqual(error as? AudioRecorderError, .notRecording)
        }
    }
}
