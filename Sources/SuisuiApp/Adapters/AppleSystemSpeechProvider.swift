@preconcurrency import AVFoundation
import Foundation
import SuisuiCore

enum SystemSpeechReadinessSnapshotReader {
    static func snapshot() -> SystemSpeechReadinessSnapshot {
        let voices = AVSpeechSynthesisVoice.speechVoices().map { voice in
            SystemSpeechVoiceOption(
                identifier: voice.identifier,
                name: voice.name,
                languageCode: voice.language,
                qualityLabel: qualityLabel(for: voice.quality)
            )
        }
        return SystemSpeechReadinessSnapshot(
            isAvailable: !voices.isEmpty,
            isInventoryAuthoritative: true,
            voices: voices
        )
    }

    private static func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default:
            String(localized: "Default")
        case .enhanced:
            String(localized: "Enhanced")
        case .premium:
            String(localized: "Premium")
        @unknown default:
            String(localized: "Unknown")
        }
    }
}

/// Synthesizes speech with voices installed in macOS and writes a temporary CAF
/// that follows the same preview/playback pipeline as the local Kokoro provider.
final class AppleSystemSpeechProvider: TextToSpeechPreviewing, @unchecked Sendable {
    private let outputURL: URL?
    private let audioPlayer: any SpeechAudioPlaying

    init(
        outputURL: URL? = nil,
        audioPlayer: any SpeechAudioPlaying = AVFoundationSpeechAudioPlayer()
    ) {
        self.outputURL = outputURL
        self.audioPlayer = audioPlayer
    }

    func playPreview(_ request: TextToSpeechRequest) async throws {
        let speech = try await synthesize(request)
        try await audioPlayer.play(speech)
    }

    private func synthesize(_ request: TextToSpeechRequest) async throws -> SynthesizedSpeech {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TTSProviderError.promptRejected("Speech text is empty.")
        }
        // Voice previews and assistant readouts are intentionally bounded so a
        // malformed plan cannot allocate unbounded audio buffers.
        guard text.count <= 4_000 else {
            throw TTSProviderError.promptRejected("Speech text exceeds 4000 characters.")
        }

        let languageCode = normalizedLanguageCode(request.languageCode)
        let voice = resolvedVoice(requestedID: request.voiceID, languageCode: languageCode)
        guard let voice else {
            throw TTSProviderError.unavailable(
                "No installed macOS voice is available for \(languageCode)."
            )
        }

        let destination = outputURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-system-speech-\(UUID().uuidString).caf")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice

        do {
            try await AppleSystemSpeechSynthesisSession.write(
                utterance: utterance,
                outputURL: destination
            )
        } catch let error as TTSProviderError {
            throw error
        } catch {
            throw TTSProviderError.synthesisFailed(
                UserFacingErrorMessageSanitizer.message(
                    from: error,
                    fallback: "System Speech synthesis failed."
                )
            )
        }

        return SynthesizedSpeech(
            fileURL: destination,
            format: destination.pathExtension.lowercased() == "wav" ? .wav : .caf,
            languageCode: languageCode,
            voiceID: voice.identifier
        )
    }

    private func normalizedLanguageCode(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ja", "ja-jp":
            "ja-JP"
        case "en", "en-us":
            "en-US"
        default:
            value.isEmpty ? Locale.current.identifier : value
        }
    }

    private func resolvedVoice(requestedID: String, languageCode: String) -> AVSpeechSynthesisVoice? {
        let trimmedID = requestedID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty,
           let selected = AVSpeechSynthesisVoice(identifier: trimmedID),
           baseLanguageCode(selected.language) == baseLanguageCode(languageCode) {
            return selected
        }
        return AVSpeechSynthesisVoice(language: languageCode)
    }

    private func baseLanguageCode(_ languageCode: String) -> String {
        languageCode
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first?
            .lowercased() ?? ""
    }
}

protocol AppleSystemSpeechSynthesizing: AnyObject {
    func write(
        _ utterance: AVSpeechUtterance,
        toBufferCallback bufferCallback: @escaping (AVAudioBuffer) -> Void
    )

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: AppleSystemSpeechSynthesizing {}

protocol AppleSystemSpeechAudioWriting: AnyObject {
    func write(_ buffer: AVAudioPCMBuffer) throws
}

private final class AVAudioFileSystemSpeechWriter: AppleSystemSpeechAudioWriting {
    private let audioFile: AVAudioFile

    init(outputURL: URL, format: AVAudioFormat) throws {
        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: format.settings
        )
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        try audioFile.write(from: buffer)
    }
}

final class AppleSystemSpeechSynthesisSession: @unchecked Sendable {
    typealias WriterFactory = (
        _ outputURL: URL,
        _ format: AVAudioFormat
    ) throws -> any AppleSystemSpeechAudioWriting

    private var synthesizer: (any AppleSystemSpeechSynthesizing)?
    private var audioWriter: (any AppleSystemSpeechAudioWriting)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var terminalResult: Result<Void, Error>?
    private var writerFactory: WriterFactory?
    private let outputURL: URL
    private let lock = NSLock()

    static func write(utterance: AVSpeechUtterance, outputURL: URL) async throws {
        try await write(
            utterance: utterance,
            outputURL: outputURL,
            synthesizer: AVSpeechSynthesizer(),
            writerFactory: { outputURL, format in
                try AVAudioFileSystemSpeechWriter(
                    outputURL: outputURL,
                    format: format
                )
            },
            timeout: .seconds(30)
        )
    }

    static func write(
        utterance: AVSpeechUtterance,
        outputURL: URL,
        synthesizer: any AppleSystemSpeechSynthesizing,
        writerFactory: @escaping WriterFactory,
        timeout: Duration
    ) async throws {
        let session = AppleSystemSpeechSynthesisSession(
            outputURL: outputURL,
            synthesizer: synthesizer
        )
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                session.start(
                    utterance: utterance,
                    continuation: continuation,
                    writerFactory: writerFactory,
                    timeout: timeout
                )
            }
        } onCancel: {
            session.complete(.failure(CancellationError()))
        }
    }

    private init(
        outputURL: URL,
        synthesizer: any AppleSystemSpeechSynthesizing
    ) {
        self.outputURL = outputURL
        self.synthesizer = synthesizer
    }

    private func start(
        utterance: AVSpeechUtterance,
        continuation: CheckedContinuation<Void, Error>,
        writerFactory: @escaping WriterFactory,
        timeout: Duration
    ) {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            continuation.resume(with: terminalResult)
            return
        }
        self.continuation = continuation
        self.writerFactory = writerFactory
        lock.unlock()

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
        } catch {
            finish(.failure(error))
            return
        }

        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.finish(
                .failure(
                    TTSProviderError.synthesisFailed("System Speech synthesis timed out.")
                )
            )
        }

        lock.lock()
        if terminalResult != nil {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        let synthesizer = self.synthesizer
        lock.unlock()

        // All mutable session state is guarded by `lock`. Framework callbacks
        // may arrive after timeout or cancellation, so `consume` rejects them
        // before touching the writer or filesystem.
        guard let synthesizer else {
            finish(
                .failure(
                    TTSProviderError.synthesisFailed(
                        "System Speech synthesizer is unavailable."
                    )
                )
            )
            return
        }
        synthesizer.write(utterance) { buffer in
            self.consume(buffer)
        }

        // Cancellation can win after the synthesizer is captured but before
        // native startup finishes. Stopping again after `write` closes that
        // narrow race without keeping the session lock across framework code.
        lock.lock()
        let terminatedDuringStartup = terminalResult != nil
        lock.unlock()
        if terminatedDuringStartup {
            _ = synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func consume(_ buffer: AVAudioBuffer) {
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
            finish(
                .failure(
                    TTSProviderError.synthesisFailed(
                        "System Speech returned an unsupported audio buffer."
                    )
                )
            )
            return
        }
        guard pcmBuffer.frameLength > 0 else {
            finish(.success(()))
            return
        }

        var writeError: Error?
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        do {
            if audioWriter == nil {
                guard let writerFactory else {
                    throw TTSProviderError.synthesisFailed(
                        "System Speech audio writer is unavailable."
                    )
                }
                audioWriter = try writerFactory(outputURL, pcmBuffer.format)
            }
            try audioWriter?.write(pcmBuffer)
        } catch {
            writeError = error
        }
        lock.unlock()

        if let writeError {
            finish(.failure(writeError))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        complete(result)
    }

    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = self.continuation
        self.continuation = nil
        audioWriter = nil
        writerFactory = nil
        let synthesizer = self.synthesizer
        self.synthesizer = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        if case .failure = result {
            // stopSpeaking may synchronously trigger callbacks, so it must stay
            // outside the state lock. Those callbacks observe terminal state.
            _ = synthesizer?.stopSpeaking(at: .immediate)
            try? FileManager.default.removeItem(at: outputURL)
        }
        continuation?.resume(with: result)
    }
}
