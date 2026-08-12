@preconcurrency import AVFoundation
import Foundation
import XCTest
@testable import Suisui

final class InboxAudioPlaybackTests: XCTestCase {
    @MainActor
    func testManagedValidatorRejectsOutsideAndSymlinkWithoutExposingPaths() throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        let store = try ManagedInboxAudioFileStore(rootURL: fixture.root)

        XCTAssertThrowsError(try store.validatedManagedURL(fixture.outsideAudio)) { error in
            XCTAssertEqual(
                (error as? InboxAudioPlaybackError)?.userMessage,
                "Audio playback is unavailable for this capture."
            )
            XCTAssertFalse(error.localizedDescription.contains(fixture.outsideAudio.path))
        }

        let link = fixture.root.appendingPathComponent("escape.caf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.outsideAudio)
        XCTAssertThrowsError(try store.validatedManagedURL(link)) { error in
            XCTAssertFalse(error.localizedDescription.contains(fixture.outsideAudio.path))
        }
    }

    @MainActor
    func testControllerPlaysPausesSeeksAndStopsWhenSelectionChanges() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        let engine = FakeInboxAudioPlaybackEngine(duration: 8)
        let waveformLoader = CountingWaveformLoader(samples: [0.25, 1])
        let controller = InboxAudioPlaybackController(engine: engine, waveformLoader: waveformLoader)

        controller.load(captureID: 1, fileURL: fixture.managedAudio)
        await waitUntil { controller.waveform == [0.25, 1] }
        try controller.play()

        XCTAssertEqual(controller.state, .playing)
        controller.toggle()
        XCTAssertEqual(controller.state, .paused)
        controller.toggle()
        XCTAssertEqual(controller.state, .playing)
        controller.pause()
        controller.seek(to: 3)
        XCTAssertEqual(controller.currentTime, 3, accuracy: 0.001)

        controller.load(captureID: 2, fileURL: fixture.secondManagedAudio)

        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(controller.currentTime, 0)
    }

    @MainActor
    func testControllerPublishesPlaybackProgressAndNaturalCompletion() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        let engine = FakeInboxAudioPlaybackEngine(duration: 8)
        let controller = InboxAudioPlaybackController(
            engine: engine,
            waveformLoader: CountingWaveformLoader(samples: [1])
        )

        controller.load(captureID: 1, fileURL: fixture.managedAudio)
        try controller.play()
        engine.advance(to: 1.25)
        await waitUntil { controller.currentTime >= 1.25 }

        engine.finish(at: 8)
        await waitUntil { controller.state == .paused && controller.currentTime == 8 }
    }

    @MainActor
    func testControllerOffersRetryWhenPlaybackEngineReportsDecodeFailure() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        let engine = FakeInboxAudioPlaybackEngine(duration: 8)
        let controller = InboxAudioPlaybackController(
            engine: engine,
            waveformLoader: CountingWaveformLoader(samples: [1])
        )

        controller.load(captureID: 1, fileURL: fixture.managedAudio)
        try controller.play()
        engine.failDecoding()

        await waitUntil {
            controller.state == .failed(InboxAudioPlaybackError.playbackFailed.userMessage)
        }
        XCTAssertTrue(controller.isRetryAvailable)
        XCTAssertTrue(controller.isPlayable)
        XCTAssertFalse(controller.isSeekable)

        controller.toggle()

        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(engine.loadCount, 2)
    }

    @MainActor
    func testControllerKeepsUnavailableRecordingControlsDisabledWithoutRetry() throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        let engine = FakeInboxAudioPlaybackEngine(duration: 8)
        let controller = InboxAudioPlaybackController(
            engine: engine,
            waveformLoader: CountingWaveformLoader(samples: [1])
        )
        let missingAudio = fixture.root.appendingPathComponent("missing.wav")

        controller.load(captureID: 1, fileURL: missingAudio)

        XCTAssertEqual(
            controller.state,
            .failed(InboxAudioPlaybackError.recordingUnavailable.userMessage)
        )
        XCTAssertFalse(controller.isRetryAvailable)
        XCTAssertFalse(controller.isPlayable)
        XCTAssertFalse(controller.isSeekable)
    }

    @MainActor
    func testControllerCachesOnlyCurrentCaptureByIDAndModificationDate() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        let engine = FakeInboxAudioPlaybackEngine(duration: 4)
        let waveformLoader = CountingWaveformLoader(samples: [1])
        let controller = InboxAudioPlaybackController(engine: engine, waveformLoader: waveformLoader)

        controller.load(captureID: 1, fileURL: fixture.managedAudio)
        await waitUntil { waveformLoader.callCount == 1 }
        controller.load(captureID: 1, fileURL: fixture.managedAudio)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(waveformLoader.callCount, 1)

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: fixture.managedAudio.path
        )
        controller.load(captureID: 1, fileURL: fixture.managedAudio)
        await waitUntil { waveformLoader.callCount == 2 }

        controller.load(captureID: 2, fileURL: fixture.secondManagedAudio)
        await waitUntil { waveformLoader.callCount == 3 }
        controller.load(captureID: 1, fileURL: fixture.managedAudio)
        await waitUntil { waveformLoader.callCount == 4 }
        XCTAssertEqual(waveformLoader.callCount, 4)
    }

    @MainActor
    func testControllerStopAndDeinitStopPlaybackAndDiscardWaveformWork() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        let engine = FakeInboxAudioPlaybackEngine(duration: 5)
        let waveformLoader = DelayedWaveformLoader()
        var controller: InboxAudioPlaybackController? = InboxAudioPlaybackController(
            engine: engine,
            waveformLoader: waveformLoader
        )

        controller?.load(captureID: 1, fileURL: fixture.managedAudio)
        controller?.stop()
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(controller?.state, .idle)

        controller?.load(captureID: 2, fileURL: fixture.secondManagedAudio)
        controller = nil
        await waitUntil { engine.stopCount == 2 }

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(waveformLoader.completedCount, 0)
    }

    func testAVFoundationWaveformReturnsNormalized64Buckets() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        try writeAudioFixture(to: fixture.managedAudio, amplitude: 0.5)
        let loader = AVFoundationInboxWaveformLoader(
            validator: ManagedInboxAudioPathValidator(rootURL: fixture.root)
        )

        let samples = try await loader.loadWaveform(from: fixture.managedAudio)

        XCTAssertEqual(samples.count, 64)
        XCTAssertTrue(samples.allSatisfy { 0 ... 1 ~= $0 })
        XCTAssertTrue(samples.contains { $0 > 0.9 })
    }

    func testAVFoundationWaveformReturns64ZeroBucketsForSilence() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        try writeAudioFixture(to: fixture.managedAudio, amplitude: 0)
        let loader = AVFoundationInboxWaveformLoader(
            validator: ManagedInboxAudioPathValidator(rootURL: fixture.root)
        )

        let samples = try await loader.loadWaveform(from: fixture.managedAudio)

        XCTAssertEqual(samples, Array(repeating: 0, count: 64))
    }

    func testAVFoundationWaveformPropagatesCallerCancellationToDetachedReader() async throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        try writeAudioFixture(to: fixture.managedAudio, amplitude: 0.5, duration: 120)
        let loader = AVFoundationInboxWaveformLoader(
            validator: ManagedInboxAudioPathValidator(rootURL: fixture.root)
        )

        let loadTask = Task {
            try await loader.loadWaveform(from: fixture.managedAudio)
        }
        loadTask.cancel()

        do {
            _ = try await loadTask.value
            XCTFail("A cancelled waveform load must not finish successfully")
        } catch is CancellationError {
            // The detached reader cooperatively observes the caller's cancellation.
        }
    }

    @MainActor
    func testAVFoundationPlayerLoadsSeeksAndStopsValidatedManagedAudio() throws {
        let fixture = try AudioFixture()
        defer { fixture.remove() }
        try writeAudioFixture(to: fixture.managedAudio, amplitude: 0.25)
        let player = AVFoundationInboxAudioPlayer(
            validator: ManagedInboxAudioPathValidator(rootURL: fixture.root)
        )

        try player.load(fixture.managedAudio)
        XCTAssertGreaterThan(player.duration, 0.9)
        player.currentTime = 0.4
        XCTAssertEqual(player.currentTime, 0.4, accuracy: 0.05)

        player.stop()
        XCTAssertEqual(player.currentTime, 0, accuracy: 0.001)
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class FakeInboxAudioPlaybackEngine: InboxAudioPlaybackEngine {
    var duration: TimeInterval
    var currentTime: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var stopCount = 0
    private(set) var loadCount = 0
    var terminalEventHandler: (@MainActor @Sendable (InboxAudioPlaybackTerminalEvent) -> Void)?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    func load(_ fileURL: URL) throws {
        loadCount += 1
        currentTime = 0
        isPlaying = false
    }

    func managedModificationDate(for fileURL: URL) throws -> Date {
        guard let modificationDate = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else {
            throw InboxAudioPlaybackError.recordingUnavailable
        }
        return modificationDate
    }

    func play() throws {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        stopCount += 1
        currentTime = 0
        isPlaying = false
    }

    func advance(to value: TimeInterval) {
        currentTime = value
    }

    func finish(at value: TimeInterval) {
        currentTime = value
        isPlaying = false
        terminalEventHandler?(.finishedSuccessfully)
    }

    func failDecoding() {
        isPlaying = false
        terminalEventHandler?(.decodingFailed)
    }
}

private final class CountingWaveformLoader: InboxAudioWaveformLoading, @unchecked Sendable {
    private let lock = NSLock()
    private let samples: [Double]
    private var _callCount = 0

    var callCount: Int { lock.withLock { _callCount } }

    init(samples: [Double]) {
        self.samples = samples
    }

    func loadWaveform(from fileURL: URL) async throws -> [Double] {
        lock.withLock { _callCount += 1 }
        return samples
    }
}

private final class DelayedWaveformLoader: InboxAudioWaveformLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var _completedCount = 0

    var completedCount: Int { lock.withLock { _completedCount } }

    func loadWaveform(from fileURL: URL) async throws -> [Double] {
        try await Task.sleep(for: .milliseconds(200))
        lock.withLock { _completedCount += 1 }
        return [1]
    }
}

private struct AudioFixture {
    let parent: URL
    let root: URL
    let managedAudio: URL
    let secondManagedAudio: URL
    let outsideAudio: URL

    init() throws {
        parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-inbox-playback-\(UUID().uuidString)", isDirectory: true)
        root = parent.appendingPathComponent("InboxAudio", isDirectory: true)
        managedAudio = root.appendingPathComponent("first.caf")
        secondManagedAudio = root.appendingPathComponent("second.caf")
        outsideAudio = parent.appendingPathComponent("outside.caf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: managedAudio)
        try Data("second".utf8).write(to: secondManagedAudio)
        try Data("outside".utf8).write(to: outsideAudio)
    }

    func remove() {
        try? FileManager.default.removeItem(at: parent)
    }
}

private func writeAudioFixture(to url: URL, amplitude: Float, duration: Int = 1) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
    let frameCount = AVAudioFrameCount(format.sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]
    for frame in 0 ..< Int(frameCount) {
        samples[frame] = sin(2 * .pi * 440 * Float(frame) / Float(format.sampleRate)) * amplitude
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    for _ in 0 ..< duration {
        buffer.frameLength = frameCount
        try file.write(from: buffer)
    }
}
