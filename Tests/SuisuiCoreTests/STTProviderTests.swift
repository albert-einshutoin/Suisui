import Darwin
import XCTest
@testable import SuisuiCore

final class STTProviderTests: XCTestCase {
    func testCatalogReturnsOnlyAvailableProviders() {
        let catalog = STTProviderCatalog(
            availabilities: [
                STTProviderAvailability(providerID: .appleSpeechAnalyzer, isAvailable: false, reason: "Requires macOS 26."),
                STTProviderAvailability(providerID: .whisperKit, isAvailable: true, requiresModelDownload: true),
                STTProviderAvailability(providerID: .openAITranscribe, isAvailable: true, requiresAPIKey: true)
            ]
        )

        XCTAssertEqual(catalog.availableProviders.map(\.providerID), [.whisperKit, .openAITranscribe])
        XCTAssertEqual(catalog.availability(for: .appleSpeechAnalyzer).reason, "Requires macOS 26.")
    }

    func testFakeSTTProviderReturnsTranscriptWhenAvailable() async throws {
        let provider = FakeSTTProvider(transcript: STTTranscript(text: "Create a task"))

        let transcript = try await provider.transcribe(
            RecordedAudio(fileURL: URL(filePath: "/tmp/input.m4a"), format: .m4a)
        )

        XCTAssertEqual(transcript.text, "Create a task")
    }

    func testFakeSTTProviderThrowsWhenUnavailable() async {
        let provider = FakeSTTProvider(
            availability: STTProviderAvailability(providerID: .whisperKit, isAvailable: false, reason: "Model missing."),
            transcript: STTTranscript(text: "")
        )

        do {
            _ = try await provider.transcribe(
                RecordedAudio(fileURL: URL(filePath: "/tmp/input.m4a"), format: .m4a)
            )
            XCTFail("Expected unavailable provider to throw.")
        } catch let error as STTProviderError {
            XCTAssertEqual(error, .unavailable("Model missing."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingTranscriptFixtureEmitsPartialFinalAndStopEventsInOrder() async throws {
        let provider = StreamingSTTProviderFixture()
        let stream = try XCTUnwrap(provider.streamingTranscriptionEvents())
        let eventsTask = Task {
            var events: [STTStreamingEvent] = []
            for try await event in stream {
                events.append(event)
                if event == .stopped {
                    break
                }
            }
            return events
        }

        provider.yield(.partial(STTTranscript(text: "Create")))
        provider.yield(.final(STTTranscript(text: "Create a task")))
        provider.yield(.stopped)
        provider.finish()

        let events = try await eventsTask.value
        XCTAssertEqual(events, [
            .partial(STTTranscript(text: "Create")),
            .final(STTTranscript(text: "Create a task")),
            .stopped
        ])
    }

    func testPhase1DefaultCatalogRegistersAppleOpenAIAndReadyGatedWhisperCppProviders() {
        let catalog = STTProviderCatalog.phase1Default

        XCTAssertEqual(catalog.availabilities.map(\.providerID), [.appleSpeechAnalyzer, .openAITranscribe, .whisperCpp])
        XCTAssertEqual(catalog.availableProviders.map(\.providerID), [.appleSpeechAnalyzer, .openAITranscribe])
        XCTAssertFalse(catalog.availability(for: .appleSpeechAnalyzer).requiresAPIKey)
        XCTAssertFalse(catalog.availability(for: .appleSpeechAnalyzer).requiresModelDownload)
        XCTAssertTrue(catalog.availability(for: .openAITranscribe).requiresAPIKey)
        XCTAssertTrue(catalog.availability(for: .whisperCpp).requiresModelDownload)
        XCTAssertEqual(
            catalog.availability(for: .whisperCpp).reason,
            "Install the whisper.cpp model and configure the executable in Settings."
        )
    }

    func testWhisperCppProviderTranscribesWithVerifiedModelAndJapaneseLanguage() async throws {
        let fixture = try makeWhisperCppFixture(languageCode: "ja")
        let runner = RecordingWhisperCppCommandRunner(
            output: WhisperCppCommandOutput(
                standardOutput: " 起動準備をタスク化 ",
                standardError: "",
                exitCode: 0,
                timedOut: false
            )
        )
        let provider = WhisperCppLocalSTTProvider(
            configuration: fixture.configuration,
            commandRunner: runner,
            audioPreparer: PassthroughWhisperCppAudioPreparer()
        )

        let transcript = try await provider.transcribe(
            RecordedAudio(fileURL: fixture.audioURL, format: .wav, duration: 1.4)
        )

        XCTAssertEqual(transcript.text, "起動準備をタスク化")
        XCTAssertEqual(transcript.languageCode, "ja")
        XCTAssertEqual(transcript.duration, 1.4)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations[0].executableURL, fixture.executableURL.resolvingSymlinksInPath())
        XCTAssertEqual(runner.invocations[0].modelURL, fixture.modelURL)
        XCTAssertEqual(runner.invocations[0].audioURL, fixture.audioURL)
        XCTAssertEqual(runner.invocations[0].arguments, [
            "-m", fixture.modelURL.path,
            "-f", fixture.audioURL.path,
            "-l", "ja",
            "-np",
            "-nt"
        ])
    }

    func testWhisperCppProviderRejectsMissingModelBeforeStartingRunner() async throws {
        let fixture = try makeWhisperCppFixture(installModel: false)
        let runner = RecordingWhisperCppCommandRunner()
        let provider = WhisperCppLocalSTTProvider(
            configuration: fixture.configuration,
            commandRunner: runner,
            audioPreparer: PassthroughWhisperCppAudioPreparer()
        )

        do {
            _ = try await provider.transcribe(RecordedAudio(fileURL: fixture.audioURL, format: .wav))
            XCTFail("Expected missing model to fail before local process execution.")
        } catch {
            XCTAssertEqual(error as? STTProviderError, .modelMissing("whisper.cpp model is not installed. Download the model in Settings before offline transcription."))
            XCTAssertTrue(runner.invocations.isEmpty)
        }
    }

    func testWhisperCppProviderRejectsCorruptModelBeforeStartingRunner() async throws {
        let fixture = try makeWhisperCppFixture(modelData: Data("expected-model".utf8))
        try Data("corrupt-model".utf8).write(to: fixture.modelURL, options: [.atomic])
        let runner = RecordingWhisperCppCommandRunner()
        let provider = WhisperCppLocalSTTProvider(
            configuration: fixture.configuration,
            commandRunner: runner,
            audioPreparer: PassthroughWhisperCppAudioPreparer()
        )

        do {
            _ = try await provider.transcribe(RecordedAudio(fileURL: fixture.audioURL, format: .wav))
            XCTFail("Expected corrupt model to fail before local process execution.")
        } catch {
            XCTAssertEqual(error as? STTProviderError, .modelMissing("whisper.cpp model checksum verification failed. Reinstall the model in Settings."))
            XCTAssertTrue(runner.invocations.isEmpty)
        }
    }

    func testWhisperCppProviderRequiresAbsoluteExecutablePath() async throws {
        let fixture = try makeWhisperCppFixture(executablePath: "whisper-cli")
        let runner = RecordingWhisperCppCommandRunner()
        let provider = WhisperCppLocalSTTProvider(
            configuration: fixture.configuration,
            commandRunner: runner,
            audioPreparer: PassthroughWhisperCppAudioPreparer()
        )

        do {
            _ = try await provider.transcribe(RecordedAudio(fileURL: fixture.audioURL, format: .wav))
            XCTFail("Expected relative executable path to fail.")
        } catch {
            XCTAssertEqual(error as? STTProviderError, .unavailable("whisper.cpp executable path must be absolute."))
            XCTAssertTrue(runner.invocations.isEmpty)
        }
    }

    func testWhisperCppProviderPreparesM4AAudioInTemporaryDirectoryAndCleansUp() async throws {
        let fixture = try makeWhisperCppFixture(languageCode: "en")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-whisper-prepared-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let preparedURL = temporaryDirectory.appendingPathComponent("prepared.wav")
        try Data("prepared-audio".utf8).write(to: preparedURL)
        let audioPreparer = RecordingWhisperCppAudioPreparer(
            preparedAudio: WhisperCppPreparedAudio(audioURL: preparedURL, temporaryDirectory: temporaryDirectory)
        )
        let runner = RecordingWhisperCppCommandRunner(
            output: WhisperCppCommandOutput(standardOutput: "Create launch notes", standardError: "", exitCode: 0, timedOut: false)
        )
        let provider = WhisperCppLocalSTTProvider(
            configuration: fixture.configuration,
            commandRunner: runner,
            audioPreparer: audioPreparer
        )

        _ = try await provider.transcribe(RecordedAudio(fileURL: fixture.audioURL, format: .m4a))

        XCTAssertEqual(audioPreparer.inputs.map(\.format), [.m4a])
        XCTAssertEqual(runner.invocations[0].audioURL, preparedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.path))
    }

    func testWhisperCppProviderSanitizesFailedProcessOutput() async throws {
        let fixture = try makeWhisperCppFixture(languageCode: "en")
        let secret = "sk-" + "localWhisperSecret123"
        let runner = RecordingWhisperCppCommandRunner(
            output: WhisperCppCommandOutput(
                standardOutput: "",
                standardError: "failed for \(fixture.audioURL.path)?token=\(secret)",
                exitCode: 2,
                timedOut: false
            )
        )
        let provider = WhisperCppLocalSTTProvider(
            configuration: fixture.configuration,
            commandRunner: runner,
            audioPreparer: PassthroughWhisperCppAudioPreparer()
        )

        do {
            _ = try await provider.transcribe(RecordedAudio(fileURL: fixture.audioURL, format: .wav))
            XCTFail("Expected failed local process.")
        } catch {
            guard case .transcriptionFailed(let message) = error as? STTProviderError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("exit code 2"))
            XCTAssertFalse(message.contains(secret))
            XCTAssertFalse(message.contains(fixture.audioURL.path))
            XCTAssertFalse(message.contains(fixture.modelURL.path))
        }
    }

    func testProcessWhisperCppCommandRunnerDrainsAndCapsLargeStderr() async throws {
        #if os(iOS) || targetEnvironment(macCatalyst)
        throw XCTSkip("Local process execution is macOS-only.")
        #else
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-whisper-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executableURL = root.appendingPathComponent("fake-whisper-cli")
        try Data(
            """
            #!/bin/sh
            i=0
            while [ "$i" -lt 3000 ]; do
              printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
              i=$((i + 1))
            done 1>&2
            printf 'transcript\\n'
            """.utf8
        ).write(to: executableURL)
        chmod(executableURL.path, 0o755)
        let invocation = WhisperCppInvocation(
            executableURL: executableURL,
            modelURL: root.appendingPathComponent("model.bin"),
            audioURL: root.appendingPathComponent("audio.wav"),
            languageCode: "en",
            timeoutInterval: 5
        )

        let output = try await ProcessWhisperCppCommandRunner().run(invocation)

        XCTAssertFalse(output.timedOut)
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "transcript")
        XCTAssertLessThanOrEqual(output.standardError.utf8.count, 64 * 1024)
        #endif
    }

    func testOpenAITranscriptionRequestBuilderUsesMultipartEndpointAndAuthorization() throws {
        let audioURL = try writeTemporaryAudio()
        let request = try OpenAITranscriptionRequestBuilder(
            configuration: OpenAITranscriptionConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-transcribe-test",
                timeoutInterval: 8
            )
        ).makeRequest(
            apiKey: "sk-test",
            audio: RecordedAudio(fileURL: audioURL, format: .m4a)
        )

        let body = try XCTUnwrap(request.httpBody)
        let bodyText = String(data: body, encoding: .utf8) ?? ""

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 8)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data; boundary=") ?? false)
        XCTAssertTrue(bodyText.contains("name=\"model\""))
        XCTAssertTrue(bodyText.contains("gpt-transcribe-test"))
        XCTAssertTrue(bodyText.contains("name=\"file\""))
        XCTAssertFalse(bodyText.contains("sk-test"))
    }

    func testOpenAITranscriptionRequestBuilderRejectsOversizedAudio() throws {
        let audioURL = try writeTemporaryAudio()
        let configuration = OpenAITranscriptionConfiguration(
            model: "gpt-transcribe-test",
            timeoutInterval: 8,
            maxAudioFileBytes: 1
        )

        XCTAssertThrowsError(
            try OpenAITranscriptionRequestBuilder(configuration: configuration).makeRequest(
                apiKey: "sk-test",
                audio: RecordedAudio(fileURL: audioURL, format: .m4a)
            )
        ) { error in
            guard case .audioFileTooLarge(let actualBytes, let maxBytes) = error as? OpenAITranscriptionRequestError else {
                return XCTFail("Expected audio file size limit error, got \(error)")
            }
            XCTAssertEqual(maxBytes, 1)
            XCTAssertGreaterThan(actualBytes, 1)
        }
    }

    func testOpenAITranscriptionRequestBuilderSkipsReadingAudioWhenOversized() throws {
        let audioURL = try writeTemporaryAudio()
        let reader = FailingOpenAITranscriptionAudioDataReader()
        let configuration = OpenAITranscriptionConfiguration(
            model: "gpt-transcribe-test",
            timeoutInterval: 8,
            maxAudioFileBytes: 1
        )

        XCTAssertThrowsError(
            try OpenAITranscriptionRequestBuilder(
                configuration: configuration,
                audioDataReader: reader
            ).makeRequest(
                apiKey: "sk-test",
                audio: RecordedAudio(fileURL: audioURL, format: .m4a)
            )
        ) { error in
            guard case .audioFileTooLarge = error as? OpenAITranscriptionRequestError else {
                return XCTFail("Expected audio file size limit error, got \(error)")
            }
        }

        XCTAssertEqual(reader.readCallCount, 0)
    }

    func testOpenAITranscribeProviderRejectsMissingAPIKeyBeforeReadingAudio() async throws {
        let provider = OpenAITranscribeProvider(
            secretStore: InMemorySecretStore(),
            httpClient: StubSTTHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.transcribe(
                RecordedAudio(fileURL: URL(filePath: "/tmp/does-not-exist.m4a"), format: .m4a)
            )
            XCTFail("Expected missing key to fail.")
        } catch {
            XCTAssertEqual(error as? STTProviderError, .unavailable("OpenAI API key is not configured."))
        }
    }

    func testOpenAITranscribeProviderRejectsOversizedAudioBeforeUploading() async throws {
        let client = NeverCalledHTTPDataClient()
        let provider = OpenAITranscribeProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test"]),
            httpClient: client,
            configuration: OpenAITranscriptionConfiguration(maxAudioFileBytes: 1)
        )
        let audioURL = try writeTemporaryAudio()

        do {
            _ = try await provider.transcribe(
                RecordedAudio(fileURL: audioURL, format: .m4a)
            )
            XCTFail("Expected oversize audio to fail before upload.")
        } catch {
            guard case .transcriptionFailed(let message) = error as? STTProviderError else {
                return XCTFail("Expected transcription failed, got \(error)")
            }
            XCTAssertTrue(message.contains("OpenAI audio file is too large"))
            XCTAssertEqual(client.requestCount, 0)
            XCTAssertFalse(message.contains(audioURL.path))
        }
    }

    func testOpenAITranscribeProviderRejectsAPIKeyWithInternalWhitespaceBeforeReadingAudio() async throws {
        let provider = OpenAITranscribeProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test invalid"]),
            httpClient: StubSTTHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.transcribe(
                RecordedAudio(fileURL: URL(filePath: "/tmp/does-not-exist.m4a"), format: .m4a)
            )
            XCTFail("Expected malformed API key to fail before reading audio.")
        } catch {
            XCTAssertEqual(error as? STTProviderError, .unavailable("OpenAI API key is invalid."))
        }
    }

    func testOpenAITranscribeProviderParsesSuccessfulResponse() async throws {
        let audioURL = try writeTemporaryAudio()
        let provider = OpenAITranscribeProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test"]),
            httpClient: StubSTTHTTPDataClient(
                data: Data(#"{"text":"Create launch checklist","language":"en","duration":1.25}"#.utf8),
                statusCode: 200
            )
        )

        let transcript = try await provider.transcribe(
            RecordedAudio(fileURL: audioURL, format: .m4a, duration: 1.25)
        )

        XCTAssertEqual(transcript.text, "Create launch checklist")
        XCTAssertEqual(transcript.languageCode, "en")
        XCTAssertEqual(transcript.duration, 1.25)
    }

    func testOpenAITranscribeProviderRedactsTransportErrorMessages() async throws {
        let audioURL = try writeTemporaryAudio()
        let secret = "sk-" + "audioTransportSecret123"
        let provider = OpenAITranscribeProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test"]),
            httpClient: ThrowingSTTHTTPDataClient(
                error: NSError(
                    domain: "SuisuiAudioTransport",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Upload failed for https://proxy.local?token=\(secret)&request_id=audio-1"
                    ]
                )
            )
        )

        do {
            _ = try await provider.transcribe(
                RecordedAudio(fileURL: audioURL, format: .m4a)
            )
            XCTFail("Expected transport failure.")
        } catch {
            guard case .transcriptionFailed(let message) = error as? STTProviderError else {
                return XCTFail("Expected transcription failure, got \(error)")
            }
            XCTAssertTrue(message.contains("Upload failed"))
            XCTAssertTrue(message.contains("request_id=audio-1"))
            XCTAssertFalse(message.contains(secret))
            XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        }
    }

    private func writeTemporaryAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-stt-test-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        return url
    }

    private func makeWhisperCppFixture(
        executablePath: String? = nil,
        installModel: Bool = true,
        modelData: Data = Data("model".utf8),
        languageCode: String = "auto"
    ) throws -> WhisperCppFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-whisper-fixture-\(UUID().uuidString)", isDirectory: true)
        let cache = VoiceModelCache(rootDirectory: root.appendingPathComponent("VoiceModels", isDirectory: true))
        let model = VoiceModelDescriptor(
            id: .custom("test-whisper-cpp-model"),
            displayName: "test whisper.cpp model",
            purpose: .speechToText,
            engine: .whisperCpp,
            languages: [
                VoiceModelLanguage(code: "ja", displayName: "Japanese"),
                VoiceModelLanguage(code: "en", displayName: "English")
            ],
            sourceURL: URL(string: "https://example.com/ggml-test.bin")!,
            licenseName: "MIT",
            licenseURL: URL(string: "https://example.com/license")!,
            estimatedSizeBytes: Int64(modelData.count),
            checksum: VoiceModelChecksum(
                algorithm: .sha256,
                value: VoiceModelChecksum.sha256Hex(for: modelData)
            ),
            cacheFileName: "ggml-test.bin",
            isBundledInApp: false
        )
        if installModel {
            try cache.write(modelData, for: model)
        }
        let executableURL = root.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("whisper-cli")
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        chmod(executableURL.path, 0o755)
        let audioURL = root.appendingPathComponent("voice input.wav")
        try Data("audio".utf8).write(to: audioURL)
        let configuration = WhisperCppLocalSTTConfiguration(
            executablePath: executablePath ?? executableURL.path,
            model: model,
            cache: cache,
            languageCode: languageCode,
            timeoutInterval: 3
        )
        return WhisperCppFixture(
            configuration: configuration,
            executableURL: executableURL,
            modelURL: cache.localURL(for: model),
            audioURL: audioURL
        )
    }
}

private struct WhisperCppFixture {
    var configuration: WhisperCppLocalSTTConfiguration
    var executableURL: URL
    var modelURL: URL
    var audioURL: URL
}

private final class RecordingWhisperCppCommandRunner: WhisperCppCommandRunning, @unchecked Sendable {
    private let output: WhisperCppCommandOutput
    private let lock = NSLock()
    private var recordedInvocations: [WhisperCppInvocation] = []

    var invocations: [WhisperCppInvocation] {
        lock.withLock { recordedInvocations }
    }

    init(output: WhisperCppCommandOutput = WhisperCppCommandOutput(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)) {
        self.output = output
    }

    func run(_ invocation: WhisperCppInvocation) async throws -> WhisperCppCommandOutput {
        lock.withLock {
            recordedInvocations.append(invocation)
        }
        return output
    }
}

private struct PassthroughWhisperCppAudioPreparer: WhisperCppAudioPreparing {
    func prepare(_ audio: RecordedAudio) async throws -> WhisperCppPreparedAudio {
        WhisperCppPreparedAudio(audioURL: audio.fileURL, temporaryDirectory: nil)
    }
}

private final class RecordingWhisperCppAudioPreparer: WhisperCppAudioPreparing, @unchecked Sendable {
    private let preparedAudio: WhisperCppPreparedAudio
    private let lock = NSLock()
    private var recordedInputs: [RecordedAudio] = []

    var inputs: [RecordedAudio] {
        lock.withLock { recordedInputs }
    }

    init(preparedAudio: WhisperCppPreparedAudio) {
        self.preparedAudio = preparedAudio
    }

    func prepare(_ audio: RecordedAudio) async throws -> WhisperCppPreparedAudio {
        lock.withLock {
            recordedInputs.append(audio)
        }
        return preparedAudio
    }
}

private struct ThrowingSTTHTTPDataClient: HTTPDataClient {
    var error: Error

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

private final class NeverCalledHTTPDataClient: HTTPDataClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: Int = 0

    var requestCount: Int {
        lock.withLock { requests }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests += 1 }
        throw NSError(domain: "Suisui", code: -1, userInfo: nil)
    }
}

private struct StubSTTHTTPDataClient: HTTPDataClient {
    var data: Data
    var statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}

private final class FailingOpenAITranscriptionAudioDataReader: OpenAITranscriptionAudioDataReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0

    var readCallCount: Int {
        lock.withLock { count }
    }

    func readAudioData(for audio: RecordedAudio) throws -> Data {
        lock.withLock { count += 1 }
        return Data("dummy".utf8)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
