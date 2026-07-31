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

struct AppleSpeechRecognitionTaskHandle: @unchecked Sendable {
    private let cancelAction: () -> Void
    private let finishAction: () -> Void

    init(cancel: @escaping () -> Void, finish: @escaping () -> Void) {
        self.cancelAction = cancel
        self.finishAction = finish
    }

    func cancel() {
        cancelAction()
    }

    func finish() {
        finishAction()
    }
}

final class AppleSpeechRecognitionSession: @unchecked Sendable {
    typealias StartRecognition = (
        @escaping (Result<String, Error>) -> Void
    ) -> AppleSpeechRecognitionTaskHandle

    private enum NativeTaskDisposition {
        case cancel
        case finish
    }

    private var task: AppleSpeechRecognitionTaskHandle?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var terminalResult: Result<String, Error>?
    private var terminalDisposition: NativeTaskDisposition?
    private let lock = NSLock()

    static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechRecognitionRequest
    ) async throws -> String {
        try await recognize(timeout: .seconds(30)) { callback in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    callback(
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
                    callback(.success(text))
                }
            }
            return AppleSpeechRecognitionTaskHandle(
                cancel: { task.cancel() },
                finish: { task.finish() }
            )
        }
    }

    static func recognize(
        timeout: Duration,
        start: @escaping StartRecognition
    ) async throws -> String {
        let session = AppleSpeechRecognitionSession()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                session.start(
                    continuation: continuation,
                    timeout: timeout,
                    startRecognition: start
                )
            }
        } onCancel: {
            session.complete(
                .failure(CancellationError()),
                disposition: .cancel
            )
        }
    }

    private init() {}

    private func start(
        continuation: CheckedContinuation<String, Error>,
        timeout: Duration,
        startRecognition: StartRecognition
    ) {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            continuation.resume(with: terminalResult)
            return
        }
        self.continuation = continuation
        lock.unlock()

        // The framework task may invoke its callback before this assignment
        // returns. `install` therefore checks terminal state and disposes a
        // late handle instead of reviving a completed session.
        let task = startRecognition { [weak self] result in
            self?.complete(
                result,
                disposition: result.isSuccess ? .finish : .cancel
            )
        }
        install(task)
        installTimeout(after: timeout)
    }

    private func install(_ task: AppleSpeechRecognitionTaskHandle) {
        lock.lock()
        if let terminalDisposition {
            lock.unlock()
            dispose(task, disposition: terminalDisposition)
            return
        }
        self.task = task
        lock.unlock()
    }

    private func installTimeout(after duration: Duration) {
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            self?.complete(
                .failure(
                    STTProviderError.transcriptionFailed(
                        "Apple Speech transcription timed out."
                    )
                ),
                disposition: .cancel
            )
        }

        lock.lock()
        if terminalResult != nil {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    private func complete(
        _ result: Result<String, Error>,
        disposition: NativeTaskDisposition
    ) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        terminalDisposition = disposition
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        if let task {
            dispose(task, disposition: disposition)
        }
        continuation?.resume(with: result)
    }

    private func dispose(
        _ task: AppleSpeechRecognitionTaskHandle,
        disposition: NativeTaskDisposition
    ) {
        switch disposition {
        case .cancel:
            task.cancel()
        case .finish:
            task.finish()
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
