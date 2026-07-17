import Foundation
import XCTest
@testable import SoloPMCore

final class TaskDueDateFieldStateTests: XCTestCase {
    func testEmptyPersistedValueStartsWithoutDueDate() {
        let state = TaskDueDateFieldState.empty

        XCTAssertNil(state.persistedDate)
    }

    func testValidPersistedValueRoundTripsAsDate() throws {
        let date = try isoDate("2026-07-20T09:30:00Z")
        let state = TaskDueDateFieldState.value(date)

        XCTAssertEqual(state.persistedDate, date)
    }

    func testSetAndClearUseOptionalDateWithoutFreeFormParsing() throws {
        var state = TaskDueDateFieldState.empty
        let selectedDate = try isoDate("2026-07-21T10:45:00Z")

        state = .value(selectedDate)

        XCTAssertEqual(state.persistedDate, selectedDate)

        state = .empty

        XCTAssertNil(state.persistedDate)
    }

    func testPersistedParserAcceptsStandardFractionalAndDateOnlyContracts() throws {
        let standard = TaskDueDateFieldState.parsePersisted("2026-07-21T10:45:00Z")
        let fractional = TaskDueDateFieldState.parsePersisted("2026-07-21T10:45:00.123Z")
        let dateOnly = TaskDueDateFieldState.parsePersisted(
            "2026-07-21",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        XCTAssertFalse(standard.isInvalid)
        XCTAssertFalse(fractional.isInvalid)
        XCTAssertFalse(dateOnly.isInvalid)
        XCTAssertNotNil(standard.state.persistedDate)
        XCTAssertNotNil(fractional.state.persistedDate)
        XCTAssertNotNil(dateOnly.state.persistedDate)
    }

    func testPersistedParserDistinguishesEmptyFromInvalidValues() {
        let empty = TaskDueDateFieldState.parsePersisted(nil)
        let invalid = TaskDueDateFieldState.parsePersisted("tomorrow afternoon")

        XCTAssertEqual(empty.state, .empty)
        XCTAssertFalse(empty.isInvalid)
        XCTAssertEqual(invalid.state, .empty)
        XCTAssertTrue(invalid.isInvalid)
    }

    private func isoDate(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
