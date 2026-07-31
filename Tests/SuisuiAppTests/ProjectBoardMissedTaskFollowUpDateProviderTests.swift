import Foundation
import SuisuiCore
import XCTest
@testable import Suisui

final class ProjectBoardMissedTaskFollowUpDateProviderTests: XCTestCase {
    func testVisualEvidenceUsesPinnedReferenceInstant() throws {
        let provider = ProjectBoardMissedTaskFollowUpDateProvider(environment: [
            VisualEvidenceRuntimeContext.referenceInstantEnvironmentKey: "2026-07-10T12:00:00Z",
            VisualEvidenceRuntimeContext.timeZoneEnvironmentKey: "UTC",
            VisualEvidenceRuntimeContext.localeEnvironmentKey: "en-US"
        ])

        XCTAssertEqual(
            provider.now,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        )
    }

    func testNormalRuntimeUsesSystemDateProvider() {
        let before = Date()
        let provider = ProjectBoardMissedTaskFollowUpDateProvider(environment: [:])
        let now = provider.now
        let after = Date()

        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, after)
    }
}
