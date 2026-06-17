import XCTest
@testable import SoloPMCore

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

    func testPhase1DefaultCatalogContainsOnlyReleaseReadyProvider() {
        let catalog = STTProviderCatalog.phase1Default

        XCTAssertEqual(catalog.availabilities.map(\.providerID), [.openAITranscribe])
        XCTAssertEqual(catalog.availableProviders.map(\.providerID), [.openAITranscribe])
        XCTAssertTrue(catalog.availability(for: .openAITranscribe).requiresAPIKey)
        XCTAssertEqual(catalog.availability(for: .whisperCpp).reason, "Provider is not registered.")
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

    private func writeTemporaryAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-stt-test-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: url)
        return url
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
