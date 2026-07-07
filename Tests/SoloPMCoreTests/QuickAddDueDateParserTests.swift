import XCTest
@testable import SoloPMCore

final class QuickAddDueDateParserTests: XCTestCase {
    // Tuesday 2026-07-07T10:00:00Z
    private let now = Date(timeIntervalSince1970: 1_783_418_400)
    private let utc = TimeZone(identifier: "UTC")!

    private func parse(_ input: String) -> QuickAddParseResult {
        QuickAddDueDateParser.parse(input, now: now, timeZone: utc)
    }

    private func expectedDate(daysFromToday: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let day = calendar.date(byAdding: .day, value: daysFromToday, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testPlainTitleIsUntouched() {
        let result = parse("Write the launch checklist")

        XCTAssertEqual(result.title, "Write the launch checklist")
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.matchedPhrase)
    }

    func testJapaneseTomorrowWithHour() {
        let result = parse("明日15時 レポート提出")

        XCTAssertEqual(result.title, "レポート提出")
        XCTAssertEqual(result.dueAt, expectedDate(daysFromToday: 1, hour: 15))
        XCTAssertEqual(result.matchedPhrase, "明日 15時")
    }

    func testJapaneseAfternoonHourWithMinutes() {
        let result = parse("資料レビュー 午後3時半")

        XCTAssertEqual(result.title, "資料レビュー")
        XCTAssertEqual(result.dueAt, expectedDate(daysFromToday: 0, hour: 15, minute: 30))
    }

    func testJapaneseDayOnlyUsesDefaultHour() {
        let result = parse("明後日 打ち合わせ準備")

        XCTAssertEqual(result.title, "打ち合わせ準備")
        XCTAssertEqual(
            result.dueAt,
            expectedDate(daysFromToday: 2, hour: QuickAddDueDateParser.defaultDayHour)
        )
    }

    func testJapaneseWeekdayResolvesToUpcomingOccurrence() {
        // Now is Tuesday; 金曜 is 3 days ahead.
        let result = parse("金曜 リリース作業")

        XCTAssertEqual(result.title, "リリース作業")
        XCTAssertEqual(
            result.dueAt,
            expectedDate(daysFromToday: 3, hour: QuickAddDueDateParser.defaultDayHour)
        )
    }

    func testJapaneseNextWeekWeekday() {
        // Now is Tuesday; 来週月曜 is 6 days ahead.
        let result = parse("来週月曜 キックオフ")

        XCTAssertEqual(result.title, "キックオフ")
        XCTAssertEqual(
            result.dueAt,
            expectedDate(daysFromToday: 6, hour: QuickAddDueDateParser.defaultDayHour)
        )
    }

    func testEnglishWeekdayWithMeridiemTime() {
        let result = parse("ship notes fri 3pm")

        XCTAssertEqual(result.title, "ship notes")
        XCTAssertEqual(result.dueAt, expectedDate(daysFromToday: 3, hour: 15))
        XCTAssertEqual(result.matchedPhrase, "fri 3pm")
    }

    func testEnglishTomorrowWithClockTime() {
        let result = parse("tomorrow at 9:30 standup prep")

        XCTAssertEqual(result.title, "standup prep")
        XCTAssertEqual(result.dueAt, expectedDate(daysFromToday: 1, hour: 9, minute: 30))
    }

    func testEnglishInNDays() {
        let result = parse("renew certificate in 10 days")

        XCTAssertEqual(result.title, "renew certificate")
        XCTAssertEqual(
            result.dueAt,
            expectedDate(daysFromToday: 10, hour: QuickAddDueDateParser.defaultDayHour)
        )
    }

    func testTonightUsesEveningHour() {
        let result = parse("tonight backup the vault")

        XCTAssertEqual(result.title, "backup the vault")
        XCTAssertEqual(
            result.dueAt,
            expectedDate(daysFromToday: 0, hour: QuickAddDueDateParser.eveningHour)
        )
    }

    func testBareTimeInThePastRollsToTomorrow() {
        // Now is 10:00Z; 9am already passed today.
        let result = parse("9am daily review")

        XCTAssertEqual(result.title, "daily review")
        XCTAssertEqual(result.dueAt, expectedDate(daysFromToday: 1, hour: 9))
    }

    func testBareTimeLaterTodayStaysToday() {
        let result = parse("15:00 sync with designer")

        XCTAssertEqual(result.title, "sync with designer")
        XCTAssertEqual(result.dueAt, expectedDate(daysFromToday: 0, hour: 15))
    }

    func testDateOnlyInputStaysATitle() {
        let result = parse("明日")

        XCTAssertEqual(result.title, "明日")
        XCTAssertNil(result.dueAt)
    }

    func testWeekdayInsideWordDoesNotTrigger() {
        let result = parse("update satellite dashboard")

        XCTAssertNil(result.dueAt)
        XCTAssertEqual(result.title, "update satellite dashboard")
    }

    func testQuickCaptureControllerAppliesParsedDueDate() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let controller = MenuBarQuickCaptureController(store: SQLiteProjectBoardStore(connection: connection))

        let task = try XCTUnwrap(controller.createInboxTask(title: "明日15時 レポート提出"))

        XCTAssertEqual(task.title, "レポート提出")
        let dueDate = try XCTUnwrap(DeadlineDateParser.date(from: try XCTUnwrap(task.dueAt)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        XCTAssertEqual(calendar.component(.hour, from: dueDate), 15)
    }
}
