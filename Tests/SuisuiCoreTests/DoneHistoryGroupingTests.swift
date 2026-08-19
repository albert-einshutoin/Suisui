@testable import SuisuiCore
import XCTest

final class DoneHistoryGroupingTests: XCTestCase {
    func testGroupsCompletedTasksByTodayYesterdayAndLastSevenDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_783_670_400) // 2026-07-10 12:00 UTC
        let today = task("today", completedAt: "2026-07-10T09:00:00Z")
        let yesterday = task("yesterday", completedAt: "2026-07-09T18:00:00Z")
        let lastWeek = task("last-week", completedAt: "2026-07-05T12:00:00Z")
        let older = task("older", completedAt: "2026-06-01T12:00:00Z")

        let grouped = DoneHistoryGrouping.grouped(
            tasks: [older, lastWeek, today, yesterday],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(grouped.map(\.section), [.today, .yesterday, .lastSevenDays, .older])
        XCTAssertEqual(grouped[0].tasks.map(\.title), ["today"])
        XCTAssertEqual(grouped[1].tasks.map(\.title), ["yesterday"])
        XCTAssertEqual(grouped[2].tasks.map(\.title), ["last-week"])
        XCTAssertEqual(grouped[3].tasks.map(\.title), ["older"])
    }

    func testOmitsEmptyHistorySections() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_783_670_400)
        let grouped = DoneHistoryGrouping.grouped(
            tasks: [task("today", completedAt: "2026-07-10T11:00:00Z")],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(grouped.map(\.section), [.today])
    }

    func testLastSevenDaysCoversSevenCalendarDatesIncludingToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_783_670_400) // 2026-07-10 12:00 UTC

        XCTAssertEqual(
            DoneHistoryGrouping.section(
                completedAt: ISO8601DateFormatter().date(from: "2026-07-04T00:00:00Z"),
                now: now,
                calendar: calendar
            ),
            .lastSevenDays
        )
        XCTAssertEqual(
            DoneHistoryGrouping.section(
                completedAt: ISO8601DateFormatter().date(from: "2026-07-03T23:59:59Z"),
                now: now,
                calendar: calendar
            ),
            .older
        )
    }

    private func task(_ title: String, completedAt: String) -> ProjectBoardTask {
        ProjectBoardTask(
            id: Int64(abs(title.hashValue)),
            projectID: 1,
            title: title,
            detail: "",
            status: .done,
            priority: .medium,
            dueAt: nil,
            completedAt: completedAt
        )
    }
}
