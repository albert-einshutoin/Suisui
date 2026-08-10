import XCTest
@testable import SuisuiCore

final class TodayWorkloadSnapshotTests: XCTestCase {
    func testEmptyWorkloadUsesConfiguredCapacityWithoutOverage() {
        let snapshot = TodayWorkloadSnapshotBuilder.make(
            timeBlocks: [],
            focusTaskID: nil,
            capacityMinutes: 480
        )

        XCTAssertEqual(snapshot.scheduledMinutes, 0)
        XCTAssertEqual(snapshot.focusTaskBlockMinutes, 0)
        XCTAssertEqual(snapshot.plannedMinutes, 0)
        XCTAssertEqual(snapshot.capacityMinutes, 480)
        XCTAssertEqual(snapshot.ratio, 0)
        XCTAssertFalse(snapshot.isOverCapacity)
        XCTAssertEqual(snapshot.diagnostics, [])
    }

    func testWorkloadSeparatesFocusBlocksAndAllowsExactCapacity() {
        let scheduled = task(id: 1, title: "Meeting")
        let focus = task(id: 2, title: "Ship release")
        let snapshot = TodayWorkloadSnapshotBuilder.make(
            timeBlocks: [
                block("meeting", task: scheduled, start: "2026-08-09T09:00:00Z", end: "2026-08-09T15:00:00Z"),
                block("focus", task: focus, start: "2026-08-09T15:00:00Z", end: "2026-08-09T17:00:00Z")
            ],
            focusTaskID: focus.id,
            capacityMinutes: 480
        )

        XCTAssertEqual(snapshot.scheduledMinutes, 360)
        XCTAssertEqual(snapshot.focusTaskBlockMinutes, 120)
        XCTAssertEqual(snapshot.plannedMinutes, 480)
        XCTAssertEqual(snapshot.ratio, 1)
        XCTAssertFalse(snapshot.isOverCapacity)
    }

    func testOverCapacityAndMalformedBlocksAreExplicit() {
        let scheduled = task(id: 1, title: "Meeting")
        let focus = task(id: 2, title: "Deep work")
        let malformed = block("malformed", task: scheduled, start: nil, end: "2026-08-09T10:00:00Z")
        let snapshot = TodayWorkloadSnapshotBuilder.make(
            timeBlocks: [
                block("meeting", task: scheduled, start: "2026-08-09T09:00:00Z", end: "2026-08-09T10:00:00Z"),
                block("focus", task: focus, start: "2026-08-09T10:00:00Z", end: "2026-08-09T18:00:00Z"),
                malformed
            ],
            focusTaskID: focus.id,
            capacityMinutes: 480
        )

        XCTAssertEqual(snapshot.plannedMinutes, 540)
        XCTAssertEqual(snapshot.ratio, 1.125)
        XCTAssertTrue(snapshot.isOverCapacity)
        XCTAssertEqual(snapshot.diagnostics, [.unparseableBlock(id: malformed.id)])
    }

    func testWorkloadUsesTimestampDurationAcrossMidnightBoundary() {
        let task = task(id: 1, title: "Late review")
        let snapshot = TodayWorkloadSnapshotBuilder.make(
            timeBlocks: [block("late", task: task, start: "2026-08-09T23:30:00Z", end: "2026-08-10T00:30:00Z")],
            focusTaskID: nil,
            capacityMinutes: 480
        )

        XCTAssertEqual(snapshot.scheduledMinutes, 60)
        XCTAssertEqual(snapshot.plannedMinutes, 60)
        XCTAssertFalse(snapshot.isOverCapacity)
    }

    private func task(id: Int64, title: String) -> ProjectBoardTask {
        ProjectBoardTask(id: id, projectID: 1, title: title, detail: "", status: .planned, priority: .high, dueAt: nil)
    }

    private func block(_ label: String, task: ProjectBoardTask, start: String?, end: String?) -> TodayTimeBlock {
        TodayTimeBlock(label: label, task: task, startAt: start, endAt: end)
    }
}
