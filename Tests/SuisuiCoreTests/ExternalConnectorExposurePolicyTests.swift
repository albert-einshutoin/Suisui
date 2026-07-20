import XCTest
@testable import SuisuiCore

final class ExternalConnectorExposurePolicyTests: XCTestCase {
    func testGoogleCalendarIsOnlySettingsVisibleConnector() {
        XCTAssertEqual(
            ExternalConnectorExposurePolicy.settingsVisible.map(\.id),
            [.googleCalendar]
        )
        XCTAssertEqual(
            ExternalConnectorExposurePolicy.exposure(for: .googleCalendar).state,
            .visible
        )
    }

    func testExternalMessageConnectorsStayAssistantQueueDraftOnly() {
        XCTAssertEqual(
            ExternalConnectorExposurePolicy.assistantQueueDraftOnly.map(\.id),
            [.slack, .gmail]
        )
        XCTAssertTrue(
            ExternalConnectorExposurePolicy.assistantQueueDraftOnly.allSatisfy {
                $0.detail.contains("draft") || $0.detail.contains("review")
            }
        )
    }

    func testConnectorsWithoutCompleteSettingsFlowsAreHiddenFromSettings() {
        let hiddenIDs = ExternalConnectorExposurePolicy.all
            .filter { $0.state == .internalOnly || $0.state == .notSupported }
            .map(\.id)

        XCTAssertEqual(
            hiddenIDs,
            [.googleDrive, .notion, .todoist, .linear, .githubIssues]
        )
        XCTAssertFalse(hiddenIDs.contains(.googleCalendar))
    }
}
