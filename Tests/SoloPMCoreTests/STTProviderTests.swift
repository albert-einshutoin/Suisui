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
}

