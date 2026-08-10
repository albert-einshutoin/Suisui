import XCTest
@testable import SuisuiCore

final class TodayExternalActivityModelTests: XCTestCase {
    func testBuildsCalendarThenSlackSummaryRowsFromPayloadFreeSnapshots() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let integrations = TodayIntegrationSnapshotBuilder.make(
            states: TodayIntegrationStates(
                calendar: .synced(lastSyncedAt: now, itemCount: 1),
                slack: .syncing
            ),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        let model = TodayExternalActivityModelBuilder.make(integrations: integrations)

        XCTAssertEqual(model.rows.map(\.id), ["today-external-activity-calendar"])
        XCTAssertEqual(model.rows.map(\.service), [.calendar])
        XCTAssertEqual(model.rows[0].title, "Calendar")
        XCTAssertEqual(model.rows[0].detail, "Last synced 09:30. 1 item synced")
        XCTAssertEqual(model.rows[0].accessibilityLabel, "Calendar: Last synced 09:30. 1 item synced.")
    }

    func testDoesNotRetainRawProviderFailurePayload() {
        let rawPayload = "token=calendar-secret account=person@example.com body={private}"
        let integrations = TodayIntegrationSnapshotBuilder.make(
            states: TodayIntegrationStates(
                calendar: .failed(lastSyncedAt: nil, itemCount: 0, message: rawPayload),
                slack: .notConnected
            ),
            now: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US")
        )

        let model = TodayExternalActivityModelBuilder.make(integrations: integrations)
        let reflected = String(reflecting: model)

        XCTAssertFalse(reflected.contains(rawPayload))
        XCTAssertFalse(reflected.contains("calendar-secret"))
        XCTAssertFalse(reflected.contains("person@example.com"))
        XCTAssertFalse(reflected.contains("private"))
        XCTAssertTrue(model.rows.isEmpty)
    }
}
