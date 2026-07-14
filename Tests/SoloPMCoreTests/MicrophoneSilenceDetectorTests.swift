import XCTest
@testable import SoloPMCore

final class MicrophoneSilenceDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func makeDetector() -> MicrophoneSilenceDetector {
        var detector = MicrophoneSilenceDetector(threshold: 0.05, requiredSilenceDuration: 5)
        detector.beginRecording(at: start)
        return detector
    }

    func testDoesNotTriggerBeforeFiveContinuousSeconds() {
        var detector = makeDetector()

        XCTAssertFalse(detector.recordSample(level: 0.01, at: start.addingTimeInterval(1)))
        XCTAssertFalse(detector.recordSample(level: 0.0, at: start.addingTimeInterval(3)))
        XCTAssertFalse(detector.recordSample(level: 0.02, at: start.addingTimeInterval(4.9)))
    }

    func testTriggersAtExactlyFiveSecondsOfSilenceSinceRecordingStart() {
        var detector = makeDetector()

        XCTAssertFalse(detector.recordSample(level: 0.01, at: start.addingTimeInterval(4.999)))
        XCTAssertTrue(detector.recordSample(level: 0.01, at: start.addingTimeInterval(5)))
    }

    func testStaysTriggeredWhileSilenceContinues() {
        var detector = makeDetector()

        XCTAssertTrue(detector.recordSample(level: 0.0, at: start.addingTimeInterval(6)))
        XCTAssertTrue(detector.recordSample(level: 0.01, at: start.addingTimeInterval(20)))
    }

    func testBriefSpikeResetsTheSilenceWindow() {
        var detector = makeDetector()

        XCTAssertFalse(detector.recordSample(level: 0.0, at: start.addingTimeInterval(4)))
        // A live microphone sample resets the continuous-silence window.
        XCTAssertFalse(detector.recordSample(level: 0.5, at: start.addingTimeInterval(4.5)))
        XCTAssertFalse(detector.recordSample(level: 0.0, at: start.addingTimeInterval(9)))
        XCTAssertTrue(detector.recordSample(level: 0.0, at: start.addingTimeInterval(9.5)))
    }

    func testLevelRecoveryClearsAnAlreadyTriggeredDetector() {
        var detector = makeDetector()

        XCTAssertTrue(detector.recordSample(level: 0.0, at: start.addingTimeInterval(6)))
        XCTAssertFalse(detector.recordSample(level: 0.4, at: start.addingTimeInterval(6.5)))
        XCTAssertFalse(detector.recordSample(level: 0.0, at: start.addingTimeInterval(7)))
    }

    func testSampleAtThresholdCountsAsLiveInput() {
        var detector = makeDetector()

        XCTAssertFalse(detector.recordSample(level: 0.05, at: start.addingTimeInterval(6)))
        XCTAssertFalse(detector.recordSample(level: 0.04, at: start.addingTimeInterval(7)))
    }

    func testSamplesNeverTriggerAfterReset() {
        var detector = makeDetector()
        detector.reset()

        XCTAssertFalse(detector.recordSample(level: 0.0, at: start.addingTimeInterval(60)))
    }

    func testNormalizerClampsDecibelsToUnitRangeWithFloor() {
        XCTAssertEqual(MicrophoneInputLevelNormalizer.normalizedLevel(fromAveragePowerDecibels: 0), 1)
        XCTAssertEqual(MicrophoneInputLevelNormalizer.normalizedLevel(fromAveragePowerDecibels: -50), 0)
        XCTAssertEqual(MicrophoneInputLevelNormalizer.normalizedLevel(fromAveragePowerDecibels: -160), 0)
        XCTAssertEqual(MicrophoneInputLevelNormalizer.normalizedLevel(fromAveragePowerDecibels: 10), 1)
        XCTAssertEqual(
            MicrophoneInputLevelNormalizer.normalizedLevel(fromAveragePowerDecibels: -25),
            0.5,
            accuracy: 0.0001
        )
    }
}
