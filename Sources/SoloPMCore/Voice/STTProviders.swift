import Darwin
import Foundation

public struct OpenAITranscribeProvider: SpeechToTextProvider {
    public static let defaultAvailability = STTProviderAvailability(
        providerID: .openAITranscribe,
        isAvailable: true,
        requiresAPIKey: true
    )

    public let id: STTProviderID = .openAITranscribe
    public var availability: STTProviderAvailability
    private let secretStore: any SecretStore
    private let httpClient: any HTTPDataClient
    private let requestBuilder: OpenAITranscriptionRequestBuilder
    private let responseParser: OpenAITranscriptionResponseParser

    public init(
        availability: STTProviderAvailability = Self.defaultAvailability,
        secretStore: any SecretStore,
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        configuration: OpenAITranscriptionConfiguration = OpenAITranscriptionConfiguration(),
        responseParser: OpenAITranscriptionResponseParser = OpenAITranscriptionResponseParser()
    ) {
        self.availability = availability
        self.secretStore = secretStore
        self.httpClient = httpClient
        self.requestBuilder = OpenAITranscriptionRequestBuilder(configuration: configuration)
        self.responseParser = responseParser
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        guard availability.isAvailable else {
            throw STTProviderError.unavailable(availability.reason ?? "OpenAI transcription is unavailable.")
        }

        let apiKey: String
        let storedAPIKey = try secretStore.read(.openAIAPIKey)
        do {
            apiKey = try APIKeyValidator.normalize(storedAPIKey)
        } catch APIKeyValidationError.empty {
            throw STTProviderError.unavailable("OpenAI API key is not configured.")
        } catch APIKeyValidationError.containsWhitespace {
            throw STTProviderError.unavailable("OpenAI API key is invalid.")
        }

        let request: URLRequest
        do {
            request = try requestBuilder.makeRequest(apiKey: apiKey, audio: audio)
        } catch let error as OpenAITranscriptionRequestError {
            throw STTProviderError.transcriptionFailed(error.userMessage)
        } catch {
            throw STTProviderError.transcriptionFailed(ProviderErrorMessageSanitizer.message(from: error))
        }
        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw STTProviderError.transcriptionFailed(ProviderErrorMessageSanitizer.message(from: error))
        }

        guard (200..<300).contains(response.statusCode) else {
            throw STTProviderError.transcriptionFailed("OpenAI transcription failed with HTTP \(response.statusCode).")
        }

        return try responseParser.parse(data: data, audio: audio)
    }
}

public struct WhisperCppLocalSTTConfiguration: Equatable, Sendable {
    public var executablePath: String
    public var model: VoiceModelDescriptor
    public var cache: VoiceModelCache
    public var languageCode: String
    public var timeoutInterval: TimeInterval

    public init(
        executablePath: String,
        model: VoiceModelDescriptor,
        cache: VoiceModelCache = VoiceModelCache(),
        languageCode: String = "auto",
        timeoutInterval: TimeInterval = 120
    ) {
        self.executablePath = executablePath
        self.model = model
        self.cache = cache
        self.languageCode = languageCode
        self.timeoutInterval = timeoutInterval
    }

    public init(
        executablePath: String,
        cache: VoiceModelCache = VoiceModelCache(),
        languageCode: String = "auto",
        timeoutInterval: TimeInterval = 120
    ) {
        self.init(
            executablePath: executablePath,
            model: VoiceModelCatalog.phase1Default.model(for: .whisperCppTinyMultilingual)!,
            cache: cache,
            languageCode: languageCode,
            timeoutInterval: timeoutInterval
        )
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.executablePath == rhs.executablePath
            && lhs.model == rhs.model
            && lhs.cache.rootDirectory == rhs.cache.rootDirectory
            && lhs.languageCode == rhs.languageCode
            && lhs.timeoutInterval == rhs.timeoutInterval
    }
}

public struct WhisperCppInvocation: Equatable, Sendable {
    public var executableURL: URL
    public var modelURL: URL
    public var audioURL: URL
    public var languageCode: String
    public var timeoutInterval: TimeInterval
    public var arguments: [String]

    public init(
        executableURL: URL,
        modelURL: URL,
        audioURL: URL,
        languageCode: String,
        timeoutInterval: TimeInterval
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.audioURL = audioURL
        self.languageCode = languageCode
        self.timeoutInterval = timeoutInterval
        self.arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-l", languageCode,
            "-np",
            "-nt"
        ]
    }
}

public struct WhisperCppCommandOutput: Equatable, Sendable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32
    public var timedOut: Bool

    public init(
        standardOutput: String,
        standardError: String,
        exitCode: Int32,
        timedOut: Bool
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}

public protocol WhisperCppCommandRunning: Sendable {
    func run(_ invocation: WhisperCppInvocation) async throws -> WhisperCppCommandOutput
}

public struct WhisperCppPreparedAudio: Equatable, Sendable {
    public var audioURL: URL
    public var temporaryDirectory: URL?

    public init(audioURL: URL, temporaryDirectory: URL?) {
        self.audioURL = audioURL
        self.temporaryDirectory = temporaryDirectory
    }
}

public protocol WhisperCppAudioPreparing: Sendable {
    func prepare(_ audio: RecordedAudio) async throws -> WhisperCppPreparedAudio
}

public struct WhisperCppLocalSTTProvider: SpeechToTextProvider {
    public static let defaultAvailability = STTProviderAvailability(
        providerID: .whisperCpp,
        isAvailable: true,
        requiresModelDownload: true
    )

    public let id: STTProviderID = .whisperCpp
    public var availability: STTProviderAvailability
    private let configuration: WhisperCppLocalSTTConfiguration
    private let commandRunner: any WhisperCppCommandRunning
    private let audioPreparer: any WhisperCppAudioPreparing

    public init(
        availability: STTProviderAvailability = Self.defaultAvailability,
        configuration: WhisperCppLocalSTTConfiguration,
        commandRunner: any WhisperCppCommandRunning = ProcessWhisperCppCommandRunner(),
        audioPreparer: any WhisperCppAudioPreparing = AfconvertWhisperCppAudioPreparer()
    ) {
        self.availability = availability
        self.configuration = configuration
        self.commandRunner = commandRunner
        self.audioPreparer = audioPreparer
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> STTTranscript {
        guard availability.isAvailable else {
            throw STTProviderError.unavailable(availability.reason ?? "whisper.cpp transcription is unavailable.")
        }

        let executableURL = try validatedExecutableURL()
        let modelURL = try verifiedModelURL()
        let languageCode = try normalizedLanguageCode()
        let preparedAudio: WhisperCppPreparedAudio
        do {
            preparedAudio = try await audioPreparer.prepare(audio)
        } catch let error as STTProviderError {
            throw error
        } catch {
            throw STTProviderError.transcriptionFailed("whisper.cpp audio preparation failed. \(ProviderErrorMessageSanitizer.message(from: error))")
        }
        defer {
            if let temporaryDirectory = preparedAudio.temporaryDirectory {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
        }

        let invocation = WhisperCppInvocation(
            executableURL: executableURL,
            modelURL: modelURL,
            audioURL: preparedAudio.audioURL,
            languageCode: languageCode,
            timeoutInterval: configuration.timeoutInterval
        )
        let output: WhisperCppCommandOutput
        do {
            output = try await commandRunner.run(invocation)
        } catch let error as STTProviderError {
            throw error
        } catch {
            throw STTProviderError.transcriptionFailed("whisper.cpp execution failed to start. \(ProviderErrorMessageSanitizer.message(from: error))")
        }

        if output.timedOut {
            throw STTProviderError.transcriptionFailed("whisper.cpp transcription timed out.")
        }
        guard output.exitCode == 0 else {
            throw STTProviderError.transcriptionFailed("whisper.cpp transcription failed with exit code \(output.exitCode).")
        }

        let transcript = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw STTProviderError.transcriptionFailed("whisper.cpp transcription did not return text.")
        }

        return STTTranscript(
            text: transcript,
            languageCode: languageCode == "auto" ? nil : languageCode,
            duration: audio.duration
        )
    }

    private func validatedExecutableURL() throws -> URL {
        let trimmedPath = configuration.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw STTProviderError.unavailable("whisper.cpp executable path is required.")
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            throw STTProviderError.unavailable("whisper.cpp executable path must be absolute.")
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw STTProviderError.unavailable("whisper.cpp executable is unavailable.")
        }
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            throw STTProviderError.unavailable("whisper.cpp executable is not executable.")
        }

        return URL(fileURLWithPath: expandedPath).resolvingSymlinksInPath()
    }

    private func verifiedModelURL() throws -> URL {
        let modelURL = configuration.cache.localURL(for: configuration.model)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw STTProviderError.modelMissing("whisper.cpp model is not installed. Download the model in Settings before offline transcription.")
        }

        let actualDigest: String
        do {
            actualDigest = try configuration.model.checksum.hexDigest(forFileAt: modelURL)
        } catch {
            throw STTProviderError.modelMissing("whisper.cpp model checksum verification failed. Reinstall the model in Settings.")
        }
        guard actualDigest == configuration.model.checksum.value else {
            throw STTProviderError.modelMissing("whisper.cpp model checksum verification failed. Reinstall the model in Settings.")
        }
        return modelURL
    }

    private func normalizedLanguageCode() throws -> String {
        let languageCode = configuration.languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = languageCode.isEmpty ? "auto" : languageCode
        guard ["auto", "ja", "en"].contains(normalized) else {
            throw STTProviderError.unavailable("whisper.cpp language must be auto, ja, or en.")
        }
        return normalized
    }
}

public struct ProcessWhisperCppCommandRunner: WhisperCppCommandRunning {
    public init() {}

    public func run(_ invocation: WhisperCppInvocation) async throws -> WhisperCppCommandOutput {
        #if os(iOS) || targetEnvironment(macCatalyst)
        throw STTProviderError.unavailable("whisper.cpp local transcription is available only on macOS.")
        #else
        let process = Process()
        let standardOutput = ProcessPipeCollector(maxBytes: 1024 * 1024)
        let standardError = ProcessPipeCollector(maxBytes: 64 * 1024)

        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.audioURL.deletingLastPathComponent()
        process.standardOutput = standardOutput.pipe
        process.standardError = standardError.pipe
        process.environment = [
            "LANG": "C",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        try process.run()

        let deadline = Date().addingTimeInterval(invocation.timeoutInterval)
        var didTimeOut = false
        while process.isRunning {
            if Date() >= deadline {
                didTimeOut = true
                process.terminate()
                try? await Task.sleep(nanoseconds: 150_000_000)
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        process.waitUntilExit()
        let stdoutText = standardOutput.finish()
        let stderrText = standardError.finish()

        return WhisperCppCommandOutput(
            standardOutput: stdoutText,
            standardError: DeveloperSecretRedactor()
                .redact(stderrText)
                .text,
            exitCode: process.terminationStatus,
            timedOut: didTimeOut
        )
        #endif
    }
}

public struct AfconvertWhisperCppAudioPreparer: WhisperCppAudioPreparing {
    public init() {}

    public func prepare(_ audio: RecordedAudio) async throws -> WhisperCppPreparedAudio {
        switch audio.format {
        case .wav:
            return WhisperCppPreparedAudio(audioURL: audio.fileURL, temporaryDirectory: nil)
        case .m4a, .caf:
            return try await convertToWAV(audio)
        }
    }

    private func convertToWAV(_ audio: RecordedAudio) async throws -> WhisperCppPreparedAudio {
        #if os(iOS) || targetEnvironment(macCatalyst)
        throw STTProviderError.unavailable("whisper.cpp audio conversion is available only on macOS.")
        #else
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-whisper-prepared-\(UUID().uuidString)", isDirectory: true)
        let preparedURL = temporaryDirectory.appendingPathComponent("prepared.wav", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try await runAfconvert(inputURL: audio.fileURL, outputURL: preparedURL)
            return WhisperCppPreparedAudio(audioURL: preparedURL, temporaryDirectory: temporaryDirectory)
        } catch let error as STTProviderError {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw STTProviderError.transcriptionFailed("Audio could not be converted for whisper.cpp. \(ProviderErrorMessageSanitizer.message(from: error))")
        }
        #endif
    }

    #if !(os(iOS) || targetEnvironment(macCatalyst))
    private func runAfconvert(inputURL: URL, outputURL: URL) async throws {
        let process = Process()
        let standardOutput = ProcessPipeCollector(maxBytes: 1024)
        let standardError = ProcessPipeCollector(maxBytes: 16 * 1024)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            inputURL.path,
            outputURL.path
        ]
        process.standardError = standardError.pipe
        process.standardOutput = standardOutput.pipe
        process.environment = [
            "LANG": "C",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw STTProviderError.transcriptionFailed("Audio conversion failed with exit code \(process.terminationStatus).")
        }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw STTProviderError.transcriptionFailed("Audio conversion did not create a WAV file.")
        }
        _ = standardOutput.finish()
        _ = standardError.finish()
    }
    #endif
}

#if !(os(iOS) || targetEnvironment(macCatalyst))
private final class ProcessPipeCollector: @unchecked Sendable {
    let pipe = Pipe()
    private let maxBytes: Int
    private let lock = NSLock()
    private var data = Data()

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData)
        }
    }

    func finish() -> String {
        pipe.fileHandleForReading.readabilityHandler = nil
        append(pipe.fileHandleForReading.readDataToEndOfFile())
        return lock.withLock {
            String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }
        lock.withLock {
            let remainingBytes = maxBytes - data.count
            guard remainingBytes > 0 else {
                return
            }
            data.append(chunk.prefix(remainingBytes))
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
#endif

public struct OpenAITranscriptionConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var timeoutInterval: TimeInterval
    public var maxAudioFileBytes: Int64

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-4o-mini-transcribe",
        timeoutInterval: TimeInterval = 120,
        maxAudioFileBytes: Int64 = 25 * 1024 * 1024
    ) {
        self.baseURL = baseURL
        self.model = model
        self.timeoutInterval = timeoutInterval
        self.maxAudioFileBytes = maxAudioFileBytes
    }
}

public enum OpenAITranscriptionRequestError: Error, Equatable, Sendable {
    case audioFileTooLarge(actualBytes: Int64, maxBytes: Int64)

    public var userMessage: String {
        switch self {
        case .audioFileTooLarge(let actualBytes, let maxBytes):
            "OpenAI audio file is too large (\(actualBytes) bytes, max \(maxBytes))."
        }
    }
}

public struct OpenAITranscriptionRequestBuilder: Sendable {
    private let configuration: OpenAITranscriptionConfiguration
    private let audioDataReader: any OpenAITranscriptionAudioDataReading

    public init(
        configuration: OpenAITranscriptionConfiguration = OpenAITranscriptionConfiguration(),
        audioDataReader: any OpenAITranscriptionAudioDataReading = OpenAITranscriptionAudioDataReader()
    ) {
        self.configuration = configuration
        self.audioDataReader = audioDataReader
    }

    public func makeRequest(apiKey: String, audio: RecordedAudio) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent("audio/transcriptions"),
            timeoutInterval: configuration.timeoutInterval
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeMultipartBody(boundary: boundary, audio: audio)
        return request
    }

    private func makeMultipartBody(boundary: String, audio: RecordedAudio) throws -> Data {
        var body = Data()
        body.appendMultipartField(name: "model", value: configuration.model, boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "json", boundary: boundary)

        let fileSize = try audioFileSize(for: audio)
        if let fileSize {
            try validateAudioSize(fileSize)
        }
        let fileData = try readAudioData(for: audio)
        if fileSize == nil {
            try validateAudioSize(Int64(fileData.count))
        }
        let filename = audio.fileURL.lastPathComponent.isEmpty ? "audio.\(audio.format.rawValue)" : audio.fileURL.lastPathComponent
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(audio.format.mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func readAudioData(for audio: RecordedAudio) throws -> Data {
        try audioDataReader.readAudioData(for: audio)
    }

    private func audioFileSize(for audio: RecordedAudio) throws -> Int64? {
        let values = try audio.fileURL.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize.map(Int64.init)
    }

    private func validateAudioSize(_ byteCount: Int64) throws {
        let size = byteCount
        guard size <= configuration.maxAudioFileBytes else {
            throw OpenAITranscriptionRequestError.audioFileTooLarge(
                actualBytes: size,
                maxBytes: configuration.maxAudioFileBytes
            )
        }
    }
}

public protocol OpenAITranscriptionAudioDataReading: Sendable {
    func readAudioData(for audio: RecordedAudio) throws -> Data
}

public struct OpenAITranscriptionAudioDataReader: OpenAITranscriptionAudioDataReading {
    public init() {}

    public func readAudioData(for audio: RecordedAudio) throws -> Data {
        try Data(contentsOf: audio.fileURL)
    }
}

public struct OpenAITranscriptionResponseParser: Sendable {
    public init() {}

    public func parse(data: Data, audio: RecordedAudio) throws -> STTTranscript {
        do {
            let response = try JSONDecoder().decode(OpenAITranscriptionResponseBody.self, from: data)
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw STTProviderError.transcriptionFailed("Transcription response did not contain text.")
            }

            return STTTranscript(text: text, languageCode: response.language, duration: response.duration ?? audio.duration)
        } catch let error as STTProviderError {
            throw error
        } catch {
            throw STTProviderError.transcriptionFailed("Transcription response was invalid.")
        }
    }
}

private struct OpenAITranscriptionResponseBody: Decodable {
    var text: String
    var language: String?
    var duration: TimeInterval?
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}

private extension AudioFileFormat {
    var mimeType: String {
        switch self {
        case .wav:
            "audio/wav"
        case .m4a:
            "audio/mp4"
        case .caf:
            "audio/x-caf"
        }
    }
}

public extension STTProviderCatalog {
    static let phase1Default = STTProviderCatalog(
        availabilities: [
            OpenAITranscribeProvider.defaultAvailability,
            STTProviderAvailability(
                providerID: .whisperCpp,
                isAvailable: false,
                reason: "Install the whisper.cpp model and configure the executable in Settings.",
                requiresModelDownload: true
            )
        ]
    )
}
