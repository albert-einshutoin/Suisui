import XCTest
@testable import SoloPMCore

final class TranscriptDraftTests: XCTestCase {
    func testBlankDraftCannotGeneratePlan() {
        XCTAssertFalse(TranscriptDraft(text: "   \n").canGeneratePlan)
    }

    func testNonBlankDraftCanGeneratePlan() {
        let draft = TranscriptDraft(text: "  Create a task  ")

        XCTAssertEqual(draft.normalizedText, "Create a task")
        XCTAssertTrue(draft.canGeneratePlan)
    }
}

