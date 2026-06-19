import XCTest
@testable import SoloPMCore

final class AudioRecorderTests: XCTestCase {
    func testUserFacingErrorMessageSanitizerRedactsRecorderErrors() {
        let secret = "sk-" + "audioRecorderSecret123"
        let error = NSError(
            domain: "SoloPMAudioRecorder",
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

    func testFakeRecorderTransitionsFromIdleToCompleted() throws {
        var recorder = FakeAudioRecorder()
        let startedAt = Date(timeIntervalSince1970: 100)
        let stoppedAt = Date(timeIntervalSince1970: 103)

        try recorder.start(at: startedAt)
        XCTAssertEqual(recorder.state, .recording(startedAt: startedAt))

        let audio = try recorder.stop(outputURL: URL(filePath: "/tmp/output.m4a"), at: stoppedAt)

        XCTAssertEqual(audio.duration, 3)
        XCTAssertEqual(recorder.state, .completed(audio))
    }

    func testFakeRecorderRejectsStartWhenPermissionDenied() {
        var recorder = FakeAudioRecorder(permissionGranted: false)

        XCTAssertThrowsError(try recorder.start(at: Date())) { error in
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
