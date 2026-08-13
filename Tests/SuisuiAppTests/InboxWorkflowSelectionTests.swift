import XCTest
@testable import Suisui

final class InboxWorkflowSelectionTests: XCTestCase {
    func testVisibleSelectionFollowsFilterUnprocessedAndTaskChanges() {
        XCTAssertEqual(
            inboxVisibleSelectionID(current: nil, visibleTaskIDs: [2, 3]),
            2,
            "the first rendered task must populate an empty detail selection"
        )
        XCTAssertEqual(
            inboxVisibleSelectionID(current: 1, visibleTaskIDs: [2, 3]),
            2,
            "a filter change must replace a selection hidden from the rendered list"
        )
        XCTAssertEqual(
            inboxVisibleSelectionID(current: 2, visibleTaskIDs: [2]),
            2,
            "the unprocessed-only toggle must preserve a still-visible selection"
        )
        XCTAssertNil(
            inboxVisibleSelectionID(current: 2, visibleTaskIDs: []),
            "an empty task update must clear the stale detail selection"
        )
    }
}
