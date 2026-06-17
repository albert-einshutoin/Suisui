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
}
