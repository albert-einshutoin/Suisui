import Foundation
import XCTest
@testable import SuisuiCore

/// "Waiting on someone else" is the stop-state a solo operator loses money on,
/// and it reached no surface before: not the user's next action so Today skips
/// it, not past due so Overdue skips it, not finished so Completed skips it.
final class TaskWaitingOnTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func task(
        id: Int64 = 1,
        status: ProjectTaskStatus = .inProgress,
        waitingOn: String? = nil,
        waitingSince: String? = nil
    ) -> ProjectBoardTask {
        ProjectBoardTask(
            id: id,
            projectID: 1,
            title: "Send revised estimate",
            detail: "",
            status: status,
            priority: .medium,
            dueAt: nil,
            waitingOn: waitingOn,
            waitingSince: waitingSince
        )
    }

    func testWaitingIsIndependentOfStatus() {
        // In-progress work can still be waiting on a review, and `blocked` can
        // mean a technical blocker with no counterparty. The two must not be
        // collapsed into one another.
        XCTAssertTrue(task(status: .inProgress, waitingOn: "Client").isWaiting)
        XCTAssertTrue(task(status: .planned, waitingOn: "Client").isWaiting)
        XCTAssertFalse(task(status: .blocked).isWaiting)
    }

    func testCompletedWorkIsNeverWaiting() {
        // A finished task keeps its counterparty for history, but it must drop
        // out of the follow-up list.
        XCTAssertFalse(task(status: .done, waitingOn: "Client").isWaiting)
    }

    func testBlankCounterpartyDoesNotCountAsWaiting() {
        XCTAssertFalse(task(waitingOn: "").isWaiting)
        XCTAssertFalse(task(waitingOn: "   ").isWaiting)
    }

    func testWaitingDayCountMeasuresWholeDaysFromTheStart() throws {
        let reference = try XCTUnwrap(
            SuisuiTimestampDisplay.parse("2026-07-27T09:00:00Z", calendar: calendar)
        ).date

        let waiting = task(waitingOn: "Client", waitingSince: "2026-07-20T15:00:00Z")
        XCTAssertEqual(waiting.waitingDayCount(on: reference, calendar: calendar), 7)

        let sameDay = task(waitingOn: "Client", waitingSince: "2026-07-27T02:00:00Z")
        XCTAssertEqual(sameDay.waitingDayCount(on: reference, calendar: calendar), 0)
    }

    func testWaitingDayCountIsNilWhenTheDurationIsUnknown() throws {
        let reference = try XCTUnwrap(
            SuisuiTimestampDisplay.parse("2026-07-27T09:00:00Z", calendar: calendar)
        ).date

        // No start recorded, or an unparseable one: the UI must stay silent
        // rather than assert a duration it does not actually know.
        XCTAssertNil(task(waitingOn: "Client").waitingDayCount(on: reference, calendar: calendar))
        XCTAssertNil(
            task(waitingOn: "Client", waitingSince: "not a date")
                .waitingDayCount(on: reference, calendar: calendar)
        )
        XCTAssertNil(task().waitingDayCount(on: reference, calendar: calendar))
    }

    func testClockNeverRunsBackwards() throws {
        let reference = try XCTUnwrap(
            SuisuiTimestampDisplay.parse("2026-07-27T09:00:00Z", calendar: calendar)
        ).date
        // A future start (clock skew, edited data) reads as zero, not negative.
        let future = task(waitingOn: "Client", waitingSince: "2026-08-10T09:00:00Z")
        XCTAssertEqual(future.waitingDayCount(on: reference, calendar: calendar), 0)
    }
}
