import Foundation
import XCTest
@testable import SuisuiCore

/// Guards the single timestamp-display path. Before it existed the same stored
/// instant rendered as `2026-07-10` on a kanban card, `Overdue Jul 10` on
/// Today, and `2026-07-09T12:00:00Z` on Done.
final class SuisuiTimestampDisplayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private let english = Locale(identifier: "en_US")

    func testParsesBothStoredTimestampShapes() throws {
        let instant = try XCTUnwrap(
            SuisuiTimestampDisplay.parse("2026-07-10T09:00:00Z", calendar: calendar)
        )
        XCTAssertTrue(instant.includesTime)

        let day = try XCTUnwrap(
            SuisuiTimestampDisplay.parse("2026-07-10", calendar: calendar)
        )
        // A day-only value must not gain a midnight the user never entered.
        XCTAssertFalse(day.includesTime)

        XCTAssertNil(SuisuiTimestampDisplay.parse("", calendar: calendar))
        XCTAssertNil(SuisuiTimestampDisplay.parse("not a date", calendar: calendar))
    }

    func testAbsoluteNeverEmitsTheRawStoredString() {
        let rendered = SuisuiTimestampDisplay.absolute(
            "2026-07-09T12:00:00Z",
            calendar: calendar,
            locale: english
        )

        XCTAssertFalse(rendered.contains("T"))
        XCTAssertFalse(rendered.contains("Z"))
        XCTAssertTrue(rendered.contains("2026"))
    }

    func testUnparseableValueIsShownRatherThanBlanked() {
        // A malformed stored value should be visible to the user and to
        // whoever debugs it, not silently swallowed.
        XCTAssertEqual(
            SuisuiTimestampDisplay.absolute("garbage", calendar: calendar, locale: english),
            "garbage"
        )
    }

    func testDayLabelDropsTheYearOnlyInsideTheReferenceYear() throws {
        let reference = try XCTUnwrap(
            SuisuiTimestampDisplay.parse("2026-07-01", calendar: calendar)
        ).date

        let sameYear = SuisuiTimestampDisplay.dayLabel(
            "2026-07-10",
            relativeTo: reference,
            calendar: calendar,
            locale: english
        )
        XCTAssertFalse(sameYear.contains("2026"))

        // A task due two years out must not look like it is due this month.
        let otherYear = SuisuiTimestampDisplay.dayLabel(
            "2028-07-10",
            relativeTo: reference,
            calendar: calendar,
            locale: english
        )
        XCTAssertTrue(otherYear.contains("2028"))
    }

    func testWeekdayAndDayFollowsTheLocaleInsteadOfAFixedPattern() {
        let date = Date(timeIntervalSince1970: 1_783_000_000)

        let englishLabel = SuisuiTimestampDisplay.weekdayAndDay(
            date,
            calendar: calendar,
            locale: english
        )
        let japaneseLabel = SuisuiTimestampDisplay.weekdayAndDay(
            date,
            calendar: calendar,
            locale: Locale(identifier: "ja_JP")
        )

        XCTAssertFalse(englishLabel.isEmpty)
        XCTAssertFalse(japaneseLabel.isEmpty)
        XCTAssertNotEqual(englishLabel, japaneseLabel)
    }

    func testDayKeyStaysPOSIXAcrossLocales() {
        let date = Date(timeIntervalSince1970: 1_783_000_000)
        var japaneseCalendar = calendar
        japaneseCalendar.locale = Locale(identifier: "ja_JP")

        XCTAssertEqual(
            SuisuiTimestampDisplay.dayKey(date, calendar: calendar),
            SuisuiTimestampDisplay.dayKey(date, calendar: japaneseCalendar)
        )
    }

    func testTaskDueLabelIsDisplayTextWhileDueAtStaysStorage() {
        let task = ProjectBoardTask(
            id: 1,
            projectID: 1,
            title: "Review release",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-07-10"
        )

        XCTAssertEqual(task.dueAt, "2026-07-10")
        XCTAssertNotEqual(task.dueLabel, "2026-07-10")
        XCTAssertNotNil(task.dueLabel)
    }
}
