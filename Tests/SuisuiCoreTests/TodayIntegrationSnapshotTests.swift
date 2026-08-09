import XCTest
@testable import SuisuiCore

final class TodayIntegrationSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testProjectionKeepsEveryConnectionStateLocalizedAndAccessible() {
        let states: [TodayIntegrationState] = [
            .notConnected,
            .permissionPending,
            .connected,
            .syncing,
            .synced(lastSyncedAt: now, itemCount: 1),
            .failed(lastSyncedAt: now, itemCount: 2, message: "Access denied.")
        ]

        for state in states {
            let snapshot = TodayIntegrationSnapshotBuilder.make(
                service: .calendar,
                state: state,
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "en_US")
            )
            XCTAssertEqual(snapshot.title, "Calendar")
            XCTAssertFalse(snapshot.detail.isEmpty)
            XCTAssertTrue(snapshot.accessibilityLabel.contains("Calendar"))
        }

        let japanese = TodayIntegrationSnapshotBuilder.make(
            service: .slack,
            state: .failed(lastSyncedAt: now, itemCount: 2, message: "接続が切れました。"),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "ja_JP")
        )
        XCTAssertEqual(japanese.title, "Slack")
        XCTAssertTrue(japanese.detail.contains("接続が切れました。"))
        XCTAssertTrue(japanese.detail.contains("最終同期"))
        XCTAssertTrue(japanese.detail.contains("2件を同期済み"))
        XCTAssertTrue(japanese.accessibilityLabel.contains("Slack"))
    }

    func testCalendarRuntimeReadinessMapsToSafeTodayStates() {
        XCTAssertEqual(
            TodayIntegrationState.calendar(from: .runtimeNotConfigured),
            .notConnected
        )
        XCTAssertEqual(
            TodayIntegrationState.calendar(from: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .oauthDisconnected)),
            .permissionPending
        )
        XCTAssertEqual(
            TodayIntegrationState.calendar(from: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready)),
            .connected
        )
        XCTAssertEqual(
            TodayIntegrationState.calendar(from: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .failed(message: "safe error"))),
            .failed(lastSyncedAt: nil, itemCount: 0, message: "safe error")
        )
    }
}
