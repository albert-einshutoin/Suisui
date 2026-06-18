import XCTest
@testable import SoloPMCore

final class LLMProviderErrorTests: XCTestCase {
    func testProviderErrorsExposeUserFacingMessages() {
        let errors: [LLMProviderError] = [
            .authenticationFailed,
            .rateLimited,
            .network("offline"),
            .invalidResponse("missing JSON"),
            .unknown("unexpected")
        ]

        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty)
            XCTAssertFalse(error.userMessage.localizedCaseInsensitiveContains("nil"))
        }
    }

    func testProviderErrorMessagesPreserveActionableContext() {
        XCTAssertTrue(LLMProviderError.authenticationFailed.userMessage.contains("API key"))
        XCTAssertTrue(LLMProviderError.rateLimited.userMessage.contains("rate limit"))
        XCTAssertTrue(LLMProviderError.network("offline").userMessage.contains("offline"))
        XCTAssertTrue(LLMProviderError.invalidResponse("missing JSON").userMessage.contains("missing JSON"))
    }

    func testHTTPErrorMessageExtractorRedactsStructuredErrorMessages() {
        let secret = "sk-" + "providerSecret123"
        let data = Data(#"{"error":{"message":"provider rejected token=\#(secret) for request req-1"}}"#.utf8)

        let message = LLMHTTPErrorMessageExtractor.message(from: data)

        XCTAssertEqual(message, "provider rejected token=[REDACTED_SECRET] for request req-1")
    }
}
