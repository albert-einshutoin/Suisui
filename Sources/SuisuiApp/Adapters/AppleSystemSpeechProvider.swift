@preconcurrency import AVFoundation
import Foundation
import SuisuiCore

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

private final class AppleSystemSpeechSynthesisSession: @unchecked Sendable {
    private var synthesizer: AVSpeechSynthesizer?
    private var audioFile: AVAudioFile?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private let outputURL: URL
    private let lock = NSLock()

    static func write(utterance: AVSpeechUtterance, outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let session = AppleSystemSpeechSynthesisSession(
                outputURL: outputURL,
                continuation: continuation
            )
            session.start(utterance: utterance)
        }
    }

    private init(outputURL: URL, continuation: CheckedContinuation<Void, Error>) {
        self.outputURL = outputURL
        self.continuation = continuation
    }

    private func start(utterance: AVSpeechUtterance) {
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

        let synthesizer = AVSpeechSynthesizer()
        self.synthesizer = synthesizer
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.finish(
                .failure(
                    TTSProviderError.synthesisFailed("System Speech synthesis timed out.")
                )
            )
        }
        // The synthesizer owns the callback and the callback owns this session;
        // `finish` clears our synthesizer reference to break that temporary
        // retention cycle after the final zero-length buffer.
        synthesizer.write(utterance) { buffer in
            self.consume(buffer)
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

        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: pcmBuffer.format.settings
                )
            }
            try audioFile?.write(from: pcmBuffer)
        } catch {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        audioFile = nil
        synthesizer = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        if case .failure = result {
            try? FileManager.default.removeItem(at: outputURL)
        }
        continuation.resume(with: result)
    }
}
