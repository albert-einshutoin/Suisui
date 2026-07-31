@preconcurrency import AVFoundation
import XCTest
@testable import Suisui
import SuisuiCore

final class AppleVoiceProviderSessionTests: XCTestCase {
    func testSpeechRecognitionCancellationCancelsNativeTaskAndReturnsPromptly() async throws {
        let nativeTask = RecordingAppleSpeechRecognitionTask()
        let started = expectation(description: "recognition started")

        let recognition = Task {
            try await AppleSpeechRecognitionSession.recognize(
                timeout: .seconds(5),
                start: { _ in
                    started.fulfill()
                    return nativeTask.handle
                }
            )
        }
        await fulfillment(of: [started], timeout: 1)

        recognition.cancel()

        do {
            _ = try await recognition.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(nativeTask.cancelCount, 1)
            XCTAssertEqual(nativeTask.finishCount, 0)
        }
    }

    func testSpeechRecognitionTimeoutCancelsNativeTask() async throws {
        let nativeTask = RecordingAppleSpeechRecognitionTask()

        do {
            _ = try await AppleSpeechRecognitionSession.recognize(
                timeout: .milliseconds(20),
                start: { _ in nativeTask.handle }
            )
            XCTFail("Expected timeout")
        } catch let error as STTProviderError {
            XCTAssertEqual(
                error,
                .transcriptionFailed("Apple Speech transcription timed out.")
            )
            XCTAssertEqual(nativeTask.cancelCount, 1)
            XCTAssertEqual(nativeTask.finishCount, 0)
        }
    }

    func testSystemSpeechTimeoutStopsSynthesizerAndIgnoresLateBuffers() async throws {
        let synthesizer = RecordingSystemSpeechSynthesizer()
        let writerFactory = RecordingSystemSpeechWriterFactory()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-system-speech-test-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            try await AppleSystemSpeechSynthesisSession.write(
                utterance: AVSpeechUtterance(string: "Timeout"),
                outputURL: outputURL,
                synthesizer: synthesizer,
                writerFactory: writerFactory.makeWriter,
                timeout: .milliseconds(20)
            )
            XCTFail("Expected timeout")
        } catch let error as TTSProviderError {
            XCTAssertEqual(
                error,
                .synthesisFailed("System Speech synthesis timed out.")
            )
        }

        XCTAssertEqual(synthesizer.stopCount, 1)
        synthesizer.emit(makePCMBuffer(frameLength: 32))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(writerFactory.makeWriterCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testSystemSpeechCancellationStopsSynthesizer() async throws {
        let synthesizer = RecordingSystemSpeechSynthesizer()
        let writerFactory = RecordingSystemSpeechWriterFactory()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-system-speech-cancel-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let started = expectation(description: "synthesis started")
        synthesizer.onWrite = {
            started.fulfill()
        }

        let synthesis = Task {
            try await AppleSystemSpeechSynthesisSession.write(
                utterance: AVSpeechUtterance(string: "Cancel"),
                outputURL: outputURL,
                synthesizer: synthesizer,
                writerFactory: writerFactory.makeWriter,
                timeout: .seconds(5)
            )
        }
        await fulfillment(of: [started], timeout: 1)

        synthesis.cancel()

        do {
            try await synthesis.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(synthesizer.stopCount, 1)
        }
    }

    func testSystemSpeechCancellationDuringWriteStartupStopsSynthesizerAfterStartup() async throws {
        let synthesizer = RecordingSystemSpeechSynthesizer(blockWriteStartup: true)
        let writerFactory = RecordingSystemSpeechWriterFactory()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-system-speech-start-race-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let synthesis = Task {
            try await AppleSystemSpeechSynthesisSession.write(
                utterance: AVSpeechUtterance(string: "Cancel during startup"),
                outputURL: outputURL,
                synthesizer: synthesizer,
                writerFactory: writerFactory.makeWriter,
                timeout: .seconds(5)
            )
        }
        XCTAssertTrue(synthesizer.waitUntilWriteStartupBegins(timeout: 1))

        synthesis.cancel()
        XCTAssertTrue(synthesizer.waitUntilStopped(timeout: 1))
        synthesizer.allowWriteStartupToFinish()

        do {
            try await synthesis.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // The first stop covers cancellation before native startup, and
            // the second closes the race after `write` returns.
            XCTAssertEqual(synthesizer.stopCount, 2)
        }
    }

    private func makePCMBuffer(frameLength: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength)!
        buffer.frameLength = frameLength
        return buffer
    }
}

private final class RecordingAppleSpeechRecognitionTask: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelCount = 0
    private var _finishCount = 0

    var handle: AppleSpeechRecognitionTaskHandle {
        AppleSpeechRecognitionTaskHandle(
            cancel: { [weak self] in self?.recordCancel() },
            finish: { [weak self] in self?.recordFinish() }
        )
    }

    var cancelCount: Int {
        lock.withLock { _cancelCount }
    }

    var finishCount: Int {
        lock.withLock { _finishCount }
    }

    private func recordCancel() {
        lock.withLock { _cancelCount += 1 }
    }

    private func recordFinish() {
        lock.withLock { _finishCount += 1 }
    }
}

private final class RecordingSystemSpeechSynthesizer: AppleSystemSpeechSynthesizing, @unchecked Sendable {
    private let lock = NSLock()
    private let writeStarted = DispatchSemaphore(value: 0)
    private let writeMayFinish = DispatchSemaphore(value: 0)
    private let stopped = DispatchSemaphore(value: 0)
    private let blockWriteStartup: Bool
    private var callback: ((AVAudioBuffer) -> Void)?
    private var _stopCount = 0
    var onWrite: (() -> Void)?

    init(blockWriteStartup: Bool = false) {
        self.blockWriteStartup = blockWriteStartup
    }

    var stopCount: Int {
        lock.withLock { _stopCount }
    }

    func write(
        _ utterance: AVSpeechUtterance,
        toBufferCallback bufferCallback: @escaping (AVAudioBuffer) -> Void
    ) {
        writeStarted.signal()
        if blockWriteStartup {
            writeMayFinish.wait()
        }
        lock.withLock {
            callback = bufferCallback
        }
        onWrite?()
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        lock.withLock {
            _stopCount += 1
        }
        stopped.signal()
        return true
    }

    func waitUntilWriteStartupBegins(timeout: TimeInterval) -> Bool {
        writeStarted.wait(timeout: .now() + timeout) == .success
    }

    func allowWriteStartupToFinish() {
        writeMayFinish.signal()
    }

    func waitUntilStopped(timeout: TimeInterval) -> Bool {
        stopped.wait(timeout: .now() + timeout) == .success
    }

    func emit(_ buffer: AVAudioBuffer) {
        let storedCallback: ((AVAudioBuffer) -> Void)? = lock.withLock {
            self.callback
        }
        storedCallback?(buffer)
    }
}

private final class RecordingSystemSpeechWriterFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var _makeWriterCount = 0

    var makeWriterCount: Int {
        lock.withLock { _makeWriterCount }
    }

    func makeWriter(
        outputURL: URL,
        format: AVAudioFormat
    ) throws -> any AppleSystemSpeechAudioWriting {
        lock.withLock {
            _makeWriterCount += 1
        }
        return RecordingSystemSpeechWriter()
    }
}

private final class RecordingSystemSpeechWriter: AppleSystemSpeechAudioWriting, @unchecked Sendable {
    func write(_ buffer: AVAudioPCMBuffer) throws {}
}
