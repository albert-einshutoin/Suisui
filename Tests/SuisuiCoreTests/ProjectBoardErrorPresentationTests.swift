import XCTest
@testable import SuisuiCore

final class ProjectBoardErrorPresentationTests: XCTestCase {
    func testInitialLoadFailureIsFatalAndRetryable() {
        XCTAssertEqual(
            ProjectBoardErrorPresentation.classify(.initialLoadFailed("Could not load.")),
            .fatal(message: "Could not load.", canRetry: true)
        )
    }

    func testRecoverableFailuresStayInlineWithRetry() {
        XCTAssertEqual(
            ProjectBoardErrorPresentation.classify(.saveFailed("Could not save.")),
            .inline(message: "Could not save.", canRetry: true)
        )
        XCTAssertEqual(
            ProjectBoardErrorPresentation.classify(.providerFailed("Provider unavailable.")),
            .inline(message: "Provider unavailable.", canRetry: true)
        )
        XCTAssertEqual(
            ProjectBoardErrorPresentation.classify(.readinessCheckFailed("Check failed.")),
            .inline(message: "Check failed.", canRetry: true)
        )
    }
}
