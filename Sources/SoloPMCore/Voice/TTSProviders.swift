import Darwin
import Foundation

public struct KokoroLocalTTSConfiguration: Equatable, Sendable {
    public var executablePath: String
    public var model: VoiceModelDescriptor
    public var cache: VoiceModelCache
    public var languageCode: String
    public var voiceID: String
    public var outputURL: URL?
    public var timeoutInterval: TimeInterval

    public init(
        executablePath: String,
        model: VoiceModelDescriptor,
        cache: VoiceModelCache = VoiceModelCache(),
        languageCode: String = "en",
        voiceID: String = "af_heart",
        outputURL: URL? = nil,
        timeoutInterval: TimeInterval = 30
    ) {
        self.executablePath = executablePath
        self.model = model
        self.cache = cache
        self.languageCode = languageCode
        self.voiceID = voiceID
        self.outputURL = outputURL
        self.timeoutInterval = timeoutInterval
    }

    public init(
        executablePath: String,
        cache: VoiceModelCache = VoiceModelCache(),
        languageCode: String = "en",
        voiceID: String = "af_heart",
        outputURL: URL? = nil,
        timeoutInterval: TimeInterval = 30
    ) {
        self.init(
            executablePath: executablePath,
            model: VoiceModelCatalog.phase1Default.model(for: .kokoro82M)!,
            cache: cache,
            languageCode: languageCode,
            voiceID: voiceID,
            outputURL: outputURL,
            timeoutInterval: timeoutInterval
        )
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.executablePath == rhs.executablePath
            && lhs.model == rhs.model
            && lhs.cache.rootDirectory == rhs.cache.rootDirectory
            && lhs.languageCode == rhs.languageCode
            && lhs.voiceID == rhs.voiceID
            && lhs.outputURL == rhs.outputURL
            && lhs.timeoutInterval == rhs.timeoutInterval
    }
}

public struct KokoroInvocation: Equatable, Sendable {
    public var executableURL: URL
    public var modelURL: URL
    public var textFileURL: URL
    public var outputURL: URL
    public var languageCode: String
    public var voiceID: String
    public var timeoutInterval: TimeInterval
    public var arguments: [String]

    public init(
        executableURL: URL,
        modelURL: URL,
        textFileURL: URL,
        outputURL: URL,
        languageCode: String,
        voiceID: String,
        timeoutInterval: TimeInterval
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.textFileURL = textFileURL
        self.outputURL = outputURL
        self.languageCode = languageCode
        self.voiceID = voiceID
        self.timeoutInterval = timeoutInterval
        self.arguments = [
            "--model", modelURL.path,
            "--text-file", textFileURL.path,
            "--language", languageCode,
            "--voice", voiceID,
            "--output", outputURL.path
        ]
    }
}

public struct KokoroCommandOutput: Equatable, Sendable {
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

public protocol KokoroCommandRunning: Sendable {
    func run(_ invocation: KokoroInvocation) async throws -> KokoroCommandOutput
}

public struct KokoroLocalTTSProvider: TextToSpeechProvider {
    public static let defaultAvailability = TTSProviderAvailability(
        providerID: .kokoro,
        isAvailable: true,
        requiresModelDownload: true
    )

    public let id: TTSProviderID = .kokoro
    public var availability: TTSProviderAvailability
    private let configuration: KokoroLocalTTSConfiguration
    private let commandRunner: any KokoroCommandRunning

    public init(
        availability: TTSProviderAvailability = Self.defaultAvailability,
        configuration: KokoroLocalTTSConfiguration,
        commandRunner: any KokoroCommandRunning = ProcessKokoroCommandRunner()
    ) {
        self.availability = availability
        self.configuration = configuration
        self.commandRunner = commandRunner
    }

    public func synthesize(_ request: TextToSpeechRequest) async throws -> SynthesizedSpeech {
        guard availability.isAvailable else {
            throw TTSProviderError.unavailable(availability.reason ?? "Kokoro speech synthesis is unavailable.")
        }

        let executableURL = try validatedExecutableURL()
        let modelURL = try verifiedModelURL()
        let normalizedText = try normalizedPromptText(request.text)
        let languageCode = try normalizedLanguageCode(request.languageCode)
        let voiceID = try normalizedVoiceID(request.voiceID, languageCode: languageCode)
        let preparedPrompt = try writePromptFile(normalizedText)
        defer {
            try? FileManager.default.removeItem(at: preparedPrompt.directoryURL)
        }
        let outputURL = try preparedOutputURL()

        let invocation = KokoroInvocation(
            executableURL: executableURL,
            modelURL: modelURL,
            textFileURL: preparedPrompt.fileURL,
            outputURL: outputURL,
            languageCode: languageCode,
            voiceID: voiceID,
            timeoutInterval: configuration.timeoutInterval
        )
        let output: KokoroCommandOutput
        do {
            output = try await commandRunner.run(invocation)
        } catch let error as TTSProviderError {
            throw error
        } catch {
            throw TTSProviderError.synthesisFailed("Kokoro execution failed to start. \(ProviderErrorMessageSanitizer.message(from: error))")
        }

        if output.timedOut {
            throw TTSProviderError.synthesisFailed("Kokoro synthesis timed out.")
        }
        guard output.exitCode == 0 else {
            throw TTSProviderError.synthesisFailed("Kokoro synthesis failed with exit code \(output.exitCode).")
        }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw TTSProviderError.synthesisFailed("Kokoro synthesis did not create a WAV file.")
        }

        return SynthesizedSpeech(fileURL: outputURL, format: .wav, languageCode: languageCode, voiceID: voiceID)
    }

    private func validatedExecutableURL() throws -> URL {
        let trimmedPath = configuration.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw TTSProviderError.unavailable("Kokoro executable path is required.")
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            throw TTSProviderError.unavailable("Kokoro executable path must be absolute.")
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw TTSProviderError.unavailable("Kokoro executable is unavailable.")
        }
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            throw TTSProviderError.unavailable("Kokoro executable is not executable.")
        }

        return URL(fileURLWithPath: expandedPath).resolvingSymlinksInPath()
    }

    private func verifiedModelURL() throws -> URL {
        let modelURL = configuration.cache.localURL(for: configuration.model)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TTSProviderError.modelMissing("Kokoro model is not installed. Download the model in Settings before offline speech.")
        }

        let actualDigest: String
        do {
            actualDigest = try configuration.model.checksum.hexDigest(forFileAt: modelURL)
        } catch {
            throw TTSProviderError.modelMissing("Kokoro model checksum verification failed. Reinstall the model in Settings.")
        }
        guard actualDigest == configuration.model.checksum.value else {
            throw TTSProviderError.modelMissing("Kokoro model checksum verification failed. Reinstall the model in Settings.")
        }
        return modelURL
    }

    private func normalizedPromptText(_ text: String) throws -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw TTSProviderError.promptRejected("Kokoro prompt text is required.")
        }
        guard normalized.count <= 280 else {
            throw TTSProviderError.promptRejected("Kokoro prompts are limited to 280 characters in this release.")
        }
        return DeveloperSecretRedactor().redact(normalized).text
    }

    private func normalizedLanguageCode(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let languageCode = normalized.isEmpty ? configuration.languageCode : normalized
        guard ["ja", "en"].contains(languageCode) else {
            throw TTSProviderError.unavailable("Kokoro language must be ja or en.")
        }
        return languageCode
    }

    private func normalizedVoiceID(_ value: String, languageCode: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceID = normalized.isEmpty ? configuration.voiceID : normalized
        let allowedPrefix = languageCode == "ja" ? "j" : "a"
        guard voiceID.hasPrefix(allowedPrefix), voiceID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw TTSProviderError.unavailable("Kokoro voice does not match the selected language.")
        }
        return voiceID
    }

    private func writePromptFile(_ text: String) throws -> PreparedKokoroPrompt {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-kokoro-prompt-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("prompt.txt", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Prompt text may contain customer task details, so it is written to
            // a short-lived file instead of argv where process inspectors can read it.
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return PreparedKokoroPrompt(directoryURL: directory, fileURL: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw TTSProviderError.synthesisFailed("Kokoro prompt could not be prepared.")
        }
    }

    private func preparedOutputURL() throws -> URL {
        if let outputURL = configuration.outputURL {
            return outputURL
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-kokoro-output-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("speech.wav", isDirectory: false)
        } catch {
            throw TTSProviderError.synthesisFailed("Kokoro output file could not be prepared.")
        }
    }
}

private struct PreparedKokoroPrompt {
    var directoryURL: URL
    var fileURL: URL
}

public struct ProcessKokoroCommandRunner: KokoroCommandRunning {
    public init() {}

    public func run(_ invocation: KokoroInvocation) async throws -> KokoroCommandOutput {
        #if os(iOS) || targetEnvironment(macCatalyst)
        throw TTSProviderError.unavailable("Kokoro local speech synthesis is available only on macOS.")
        #else
        let process = Process()
        let standardOutput = TTSProcessPipeCollector(maxBytes: 64 * 1024)
        let standardError = TTSProcessPipeCollector(maxBytes: 64 * 1024)

        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.outputURL.deletingLastPathComponent()
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

        return KokoroCommandOutput(
            standardOutput: DeveloperSecretRedactor().redact(stdoutText).text,
            standardError: DeveloperSecretRedactor().redact(stderrText).text,
            exitCode: process.terminationStatus,
            timedOut: didTimeOut
        )
        #endif
    }
}

#if !(os(iOS) || targetEnvironment(macCatalyst))
private final class TTSProcessPipeCollector: @unchecked Sendable {
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
