import CoreGraphics
import SuisuiCore
import XCTest
@testable import Suisui

final class ScheduleTimelineGeometryTests: XCTestCase {
    func testOverlapPositionsShareWidthAcrossLocalAndExternalIntervals() {
        let base = Date(timeIntervalSince1970: 0)
        let positions = ScheduleTimelineGeometry.overlapPositions(for: [
            DateInterval(start: base, duration: 60 * 60),
            DateInterval(start: base.addingTimeInterval(15 * 60), duration: 60 * 60),
            DateInterval(start: base.addingTimeInterval(2 * 60 * 60), duration: 30 * 60)
        ])

        XCTAssertEqual(positions, [
            .init(lane: 0, groupSize: 2),
            .init(lane: 1, groupSize: 2),
            .init(lane: 0, groupSize: 1)
        ])
    }

    func testBlockFrameUsesMinuteDurationDayAndOverlapLane() {
        let frame = ScheduleTimelineGeometry.blockFrame(
            startMinute: 9 * 60 + 30,
            durationMinutes: 90,
            dayIndex: 2,
            dayCount: 7,
            overlapLane: 1,
            overlapGroupSize: 2,
            gridWidth: 752,
            timeAxisWidth: 52,
            hourHeight: 60
        )

        XCTAssertEqual(frame.origin.x, 304, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 570, accuracy: 0.001)
        XCTAssertEqual(frame.width, 46, accuracy: 0.001)
        XCTAssertEqual(frame.height, 90, accuracy: 0.001)
    }

    func testSnappedMinuteUsesFifteenMinuteIntervalsAndDayBounds() {
        XCTAssertEqual(ScheduleTimelineGeometry.snappedMinute(at: -20, hourHeight: 60), 0)
        XCTAssertEqual(ScheduleTimelineGeometry.snappedMinute(at: 68, hourHeight: 60), 75)
        XCTAssertEqual(ScheduleTimelineGeometry.snappedMinute(at: 2_000, hourHeight: 60), 24 * 60)
    }

    func testSnappedDeltaPreservesDragDirection() {
        XCTAssertEqual(ScheduleTimelineGeometry.snappedDelta(for: -31, hourHeight: 60), -30)
        XCTAssertEqual(ScheduleTimelineGeometry.snappedDelta(for: 31, hourHeight: 60), 30)
    }

    func testAllDayEventUsesGoogleDateKeysAcrossTimezoneBoundaries() {
        let localDay = Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 86_400)
        let event = ExternalScheduleEvent(
            id: "external",
            title: "All day",
            startAt: Date(timeIntervalSince1970: -86_400),
            endAt: Date(timeIntervalSince1970: 0),
            isAllDay: true,
            allDayStartDateKey: "2026-08-19",
            allDayEndDateKey: "2026-08-20"
        )

        XCTAssertTrue(ScheduleTimelineGeometry.allDayEvent(
            event,
            occursOn: "2026-08-19",
            fallback: localDay
        ))
        XCTAssertFalse(ScheduleTimelineGeometry.allDayEvent(
            event,
            occursOn: "2026-08-20",
            fallback: localDay
        ))
    }

    func testTimedEventAppearsOnEveryAgendaDayItOverlaps() {
        let event = ExternalScheduleEvent(
            id: "overnight",
            title: "Overnight maintenance",
            startAt: Date(timeIntervalSince1970: 23 * 60 * 60),
            endAt: Date(timeIntervalSince1970: 25 * 60 * 60),
            isAllDay: false
        )

        XCTAssertTrue(ScheduleTimelineGeometry.eventOccurs(
            event,
            on: "1970-01-01",
            during: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 24 * 60 * 60)
        ))
        XCTAssertTrue(ScheduleTimelineGeometry.eventOccurs(
            event,
            on: "1970-01-02",
            during: Date(timeIntervalSince1970: 24 * 60 * 60)..<Date(timeIntervalSince1970: 48 * 60 * 60)
        ))
        XCTAssertFalse(ScheduleTimelineGeometry.eventOccurs(
            event,
            on: "1970-01-03",
            during: Date(timeIntervalSince1970: 48 * 60 * 60)..<Date(timeIntervalSince1970: 72 * 60 * 60)
        ))
    }

    func testScheduleSearchMatchesAnyVisibleEventValue() {
        XCTAssertTrue(ScheduleTimelineGeometry.matchesSearch("", values: ["Design review"]))
        XCTAssertTrue(ScheduleTimelineGeometry.matchesSearch("DESIGN", values: ["Design review"]))
        XCTAssertTrue(ScheduleTimelineGeometry.matchesSearch("client", values: ["Follow up", "Client A"]))
        XCTAssertFalse(ScheduleTimelineGeometry.matchesSearch("invoice", values: ["Design review", "Client A"]))
    }
}
