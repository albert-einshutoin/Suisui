@preconcurrency import Speech
import Foundation
import SuisuiCore

extension Notification.Name {
    static let suisuiAppleSpeechAuthorizationDidChange = Notification.Name(
        "dev.suisui.appleSpeechAuthorizationDidChange"
    )
}

enum AppleSpeechReadinessSnapshotReader {
    static func snapshot(locale: Locale = .current) -> AppleSpeechReadinessSnapshot {
        let recognizer = SFSpeechRecognizer(locale: locale)
        return AppleSpeechReadinessSnapshot(
            authorization: authorizationStatus(),
            isRecognizerAvailable: recognizer?.isAvailable == true,
            supportsOnDeviceRecognition: recognizer?.supportsOnDeviceRecognition == true
        )
    }

    private static func authorizationStatus() -> AppleSpeechAuthorizationStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .authorized:
            .authorized
        @unknown default:
            // Unknown framework states must not accidentally advertise the
            // provider as ready before the runtime can safely use it.
            .restricted
        }
    }
}

/// Apple-native, on-device speech recognition for recorded Voice Command audio.
///
/// The persisted provider case remains `appleSpeechAnalyzer` for settings
/// compatibility, while this adapter uses the Speech framework API available
/// across Suisui's macOS 14 deployment range.
final class AppleSpeechRecognitionProvider: SpeechToTextProvider, @unchecked Sendable {
    static let defaultAvailability = STTProviderAvailability(
        providerID: .appleSpeechAnalyzer,
        isAvailable: true
    )

    let id: STTProviderID = .appleSpeechAnalyzer
    let availability: STTProviderAvailability
    private let locale: Locale

    init(
        availability: STTProviderAvailability = AppleSpeechRecognitionProvider.defaultAvailability,
        locale: Locale = .current
    ) {
        self.availability = availability
        self.locale = locale
    }

    func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        guard availability.isAvailable else {
            throw STTProviderError.unavailable(
                availability.reason ?? "Apple Speech is unavailable."
            )
        }
        guard FileManager.default.fileExists(atPath: audio.fileURL.path) else {
            throw STTProviderError.transcriptionFailed("Recorded audio is unavailable.")
        }

        let authorization = await speechRecognitionAuthorization()
        guard authorization == .authorized else {
            if authorization == .denied || authorization == .restricted {
                throw STTProviderError.permissionDenied
            }
            throw STTProviderError.unavailable("Speech recognition permission was not granted.")
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw STTProviderError.unavailable("Apple Speech is unavailable for the current language.")
        }
        // Suisui's Apple provider is intentionally local-only. Silently
        // switching to Apple's network recognizer would violate the no-key,
        // on-device privacy expectation communicated by Settings.
        guard recognizer.supportsOnDeviceRecognition else {
            throw STTProviderError.unavailable(
                "On-device Apple Speech is unavailable for the current language."
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: audio.fileURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation

        let text = try await AppleSpeechRecognitionSession.recognize(
            recognizer: recognizer,
            request: request
        )
        guard !text.isEmpty else {
            throw STTProviderError.transcriptionFailed("Apple Speech returned an empty transcript.")
        }
        return STTTranscript(
            text: text,
            languageCode: locale.identifier,
            duration: audio.duration
        )
    }

    private func speechRecognitionAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else {
            return current
        }
        let resolved = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .suisuiAppleSpeechAuthorizationDidChange, object: nil)
        }
        return resolved
    }
}

private final class AppleSpeechRecognitionSession: @unchecked Sendable {
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, Error>?
    private let lock = NSLock()

    static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechRecognitionRequest
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = AppleSpeechRecognitionSession(continuation: continuation)
            // The recognition task retains this callback, and the callback
            // retains the session until `finish` clears the task. This keeps
            // the task alive without global mutable state.
            session.task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    session.finish(
                        .failure(
                            STTProviderError.transcriptionFailed(
                                UserFacingErrorMessageSanitizer.message(
                                    from: error,
                                    fallback: "Apple Speech transcription failed."
                                )
                            )
                        )
                    )
                    return
                }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    session.finish(.success(text))
                }
            }
        }
    }

    private init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let task = self.task
        self.task = nil
        lock.unlock()

        task?.finish()
        continuation.resume(with: result)
    }
}
