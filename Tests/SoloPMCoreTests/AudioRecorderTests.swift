import XCTest
@testable import SoloPMCore

final class AudioRecorderTests: XCTestCase {
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

