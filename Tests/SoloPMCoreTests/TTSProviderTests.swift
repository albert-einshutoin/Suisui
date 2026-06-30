import Darwin
import XCTest
@testable import SoloPMCore

final class TTSProviderTests: XCTestCase {
    func testPhase1DefaultCatalogRegistersReadyGatedKokoroProvider() {
        let catalog = TTSProviderCatalog.phase1Default

        XCTAssertEqual(catalog.availabilities.map(\.providerID), [.kokoro])
        XCTAssertTrue(catalog.availability(for: .kokoro).requiresModelDownload)
        XCTAssertEqual(catalog.availableProviders, [])
        XCTAssertEqual(
            catalog.availability(for: .kokoro).reason,
            "Install the Kokoro model and configure the executable in Settings."
        )
    }

    func testKokoroProviderSynthesizesShortJapanesePromptWithVerifiedModel() async throws {
        let fixture = try makeKokoroFixture(languageCode: "ja", voiceID: "jf_alpha")
        let runner = RecordingKokoroCommandRunner(
            output: KokoroCommandOutput(standardOutput: fixture.outputURL.path, standardError: "", exitCode: 0, timedOut: false)
        )
        let provider = KokoroLocalTTSProvider(configuration: fixture.configuration, commandRunner: runner)

        let audio = try await provider.synthesize(
            TextToSpeechRequest(
                text: "期限切れのタスクが2件あります",
                languageCode: "ja",
                voiceID: "jf_alpha"
            )
        )

        XCTAssertEqual(audio.fileURL, fixture.outputURL)
        XCTAssertEqual(audio.format, .wav)
        XCTAssertEqual(audio.languageCode, "ja")
        XCTAssertEqual(audio.voiceID, "jf_alpha")
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations[0].executableURL, fixture.executableURL.resolvingSymlinksInPath())
        XCTAssertEqual(runner.invocations[0].modelURL, fixture.modelURL)
        XCTAssertEqual(runner.capturedTexts, ["期限切れのタスクが2件あります"])
        XCTAssertEqual(runner.invocations[0].languageCode, "ja")
        XCTAssertEqual(runner.invocations[0].voiceID, "jf_alpha")
        XCTAssertEqual(runner.invocations[0].arguments, [
            "--model", fixture.modelURL.path,
            "--text-file", runner.invocations[0].textFileURL.path,
            "--language", "ja",
            "--voice", "jf_alpha",
            "--output", fixture.outputURL.path
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: runner.invocations[0].textFileURL.path))
    }

    func testKokoroProviderRejectsMissingModelBeforeStartingRunner() async throws {
        let fixture = try makeKokoroFixture(installModel: false)
        let runner = RecordingKokoroCommandRunner()
        let provider = KokoroLocalTTSProvider(configuration: fixture.configuration, commandRunner: runner)

        do {
            _ = try await provider.synthesize(TextToSpeechRequest(text: "Create launch notes", languageCode: "en", voiceID: "af_heart"))
            XCTFail("Expected missing model to fail before local process execution.")
        } catch {
            XCTAssertEqual(error as? TTSProviderError, .modelMissing("Kokoro model is not installed. Download the model in Settings before offline speech."))
            XCTAssertTrue(runner.invocations.isEmpty)
        }
    }

    func testKokoroProviderRequiresAbsoluteExecutablePath() async throws {
        let fixture = try makeKokoroFixture(executablePath: "kokoro-tts")
        let runner = RecordingKokoroCommandRunner()
        let provider = KokoroLocalTTSProvider(configuration: fixture.configuration, commandRunner: runner)

        do {
            _ = try await provider.synthesize(TextToSpeechRequest(text: "Create launch notes", languageCode: "en", voiceID: "af_heart"))
            XCTFail("Expected relative executable path to fail.")
        } catch {
            XCTAssertEqual(error as? TTSProviderError, .unavailable("Kokoro executable path must be absolute."))
            XCTAssertTrue(runner.invocations.isEmpty)
        }
    }

    func testKokoroProviderRejectsCredentialLikeExecutablePathBeforeStartingRunner() async throws {
        let fixture = try makeKokoroFixture()
        let sensitiveExecutableURL = fixture.executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("api-key-runner")
        try Data("#!/bin/sh\n".utf8).write(to: sensitiveExecutableURL)
        chmod(sensitiveExecutableURL.path, 0o755)
        let runner = RecordingKokoroCommandRunner()
        let provider = KokoroLocalTTSProvider(
            configuration: KokoroLocalTTSConfiguration(
                executablePath: sensitiveExecutableURL.path,
                model: fixture.configuration.model,
                cache: fixture.configuration.cache,
                outputURL: fixture.outputURL
            ),
            commandRunner: runner
        )

        do {
            _ = try await provider.synthesize(TextToSpeechRequest(text: "Create launch notes", languageCode: "en", voiceID: "af_heart"))
            XCTFail("Expected credential-like executable path to fail.")
        } catch {
            XCTAssertEqual(error as? TTSProviderError, .unavailable("Kokoro executable path must not point to a credential or token file."))
            XCTAssertTrue(runner.invocations.isEmpty)
        }
    }

    func testKokoroProviderRejectsLongPromptsBeforeStartingRunner() async throws {
        let fixture = try makeKokoroFixture()
        let runner = RecordingKokoroCommandRunner()
        let provider = KokoroLocalTTSProvider(configuration: fixture.configuration, commandRunner: runner)
        let longText = String(repeating: "a", count: 281)

        do {
            _ = try await provider.synthesize(TextToSpeechRequest(text: longText, languageCode: "en", voiceID: "af_heart"))
            XCTFail("Expected long prompt to fail.")
        } catch {
            XCTAssertEqual(error as? TTSProviderError, .promptRejected("Kokoro prompts are limited to 280 characters in this release."))
            XCTAssertTrue(runner.invocations.isEmpty)
        }
    }

    func testKokoroProviderSanitizesFailedProcessOutput() async throws {
        let fixture = try makeKokoroFixture(languageCode: "en", voiceID: "af_heart")
        let secret = "sk-" + "localKokoroSecret123"
        let runner = RecordingKokoroCommandRunner(
            output: KokoroCommandOutput(
                standardOutput: "",
                standardError: "failed for \(fixture.outputURL.path)?token=\(secret)",
                exitCode: 2,
                timedOut: false
            )
        )
        let provider = KokoroLocalTTSProvider(configuration: fixture.configuration, commandRunner: runner)

        do {
            _ = try await provider.synthesize(TextToSpeechRequest(text: "Create launch notes", languageCode: "en", voiceID: "af_heart"))
            XCTFail("Expected failed local process.")
        } catch {
            guard case .synthesisFailed(let message) = error as? TTSProviderError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("exit code 2"))
            XCTAssertFalse(message.contains(secret))
            XCTAssertFalse(message.contains(fixture.outputURL.path))
            XCTAssertFalse(message.contains(fixture.modelURL.path))
        }
    }

    func testTextToSpeechPreviewServiceSynthesizesThenPlaysAudio() async throws {
        let audio = SynthesizedSpeech(
            fileURL: URL(fileURLWithPath: "/tmp/solopm-preview.wav"),
            format: .wav,
            languageCode: "en",
            voiceID: "af_heart"
        )
        let provider = RecordingTextToSpeechProvider(audio: audio)
        let player = RecordingSpeechAudioPlayer()
        let service = TextToSpeechPreviewService(provider: provider, audioPlayer: player)
        let request = TextToSpeechRequest(
            text: "SoloPM local voice test is ready.",
            languageCode: "en",
            voiceID: "af_heart"
        )

        try await service.playPreview(request)

        XCTAssertEqual(provider.requests, [request])
        XCTAssertEqual(player.playedAudio, [audio])
    }

    private func makeKokoroFixture(
        executablePath: String? = nil,
        installModel: Bool = true,
        languageCode: String = "en",
        voiceID: String = "af_heart"
    ) throws -> KokoroFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-kokoro-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let executableURL = root.appendingPathComponent("kokoro-tts")
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        chmod(executableURL.path, 0o755)

        let modelData = Data("tiny local kokoro model".utf8)
        let model = VoiceModelDescriptor(
            id: .kokoro82M,
            displayName: "Kokoro 82M Test",
            purpose: .textToSpeech,
            engine: .kokoro,
            languages: [
                VoiceModelLanguage(code: "ja", displayName: "Japanese"),
                VoiceModelLanguage(code: "en", displayName: "English")
            ],
            sourceURL: URL(string: "https://models.example.com/kokoro-v1_0.pth")!,
            licenseName: "Apache-2.0",
            licenseURL: URL(string: "https://models.example.com/license")!,
            estimatedSizeBytes: Int64(modelData.count),
            checksum: VoiceModelChecksum(algorithm: .sha256, value: VoiceModelChecksum.sha256Hex(for: modelData)),
            cacheFileName: "kokoro-v1_0.pth",
            isBundledInApp: false
        )
        let cache = VoiceModelCache(rootDirectory: root.appendingPathComponent("VoiceModels", isDirectory: true))
        if installModel {
            try cache.write(modelData, for: model)
        }
        let outputURL = root.appendingPathComponent("kokoro-output.wav")

        return KokoroFixture(
            executableURL: executableURL,
            modelURL: cache.localURL(for: model),
            outputURL: outputURL,
            configuration: KokoroLocalTTSConfiguration(
                executablePath: executablePath ?? executableURL.path,
                model: model,
                cache: cache,
                languageCode: languageCode,
                voiceID: voiceID,
                outputURL: outputURL
            )
        )
    }
}

private final class RecordingTextToSpeechProvider: TextToSpeechProvider, @unchecked Sendable {
    let id: TTSProviderID = .kokoro
    let availability = TTSProviderAvailability(providerID: .kokoro, isAvailable: true)
    private let audio: SynthesizedSpeech
    private(set) var requests: [TextToSpeechRequest] = []

    init(audio: SynthesizedSpeech) {
        self.audio = audio
    }

    func synthesize(_ request: TextToSpeechRequest) async throws -> SynthesizedSpeech {
        requests.append(request)
        return audio
    }
}

private final class RecordingSpeechAudioPlayer: SpeechAudioPlaying, @unchecked Sendable {
    private(set) var playedAudio: [SynthesizedSpeech] = []

    func play(_ speech: SynthesizedSpeech) async throws {
        playedAudio.append(speech)
    }
}

private struct KokoroFixture {
    var executableURL: URL
    var modelURL: URL
    var outputURL: URL
    var configuration: KokoroLocalTTSConfiguration
}

private final class RecordingKokoroCommandRunner: KokoroCommandRunning, @unchecked Sendable {
    private let output: KokoroCommandOutput
    private(set) var invocations: [KokoroInvocation] = []
    private(set) var capturedTexts: [String] = []

    init(output: KokoroCommandOutput = KokoroCommandOutput(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)) {
        self.output = output
    }

    func run(_ invocation: KokoroInvocation) async throws -> KokoroCommandOutput {
        invocations.append(invocation)
        capturedTexts.append((try? String(contentsOf: invocation.textFileURL, encoding: .utf8)) ?? "")
        if output.exitCode == 0 {
            try Data("RIFFfake-wav".utf8).write(to: invocation.outputURL, options: [.atomic])
        }
        return output
    }
}
