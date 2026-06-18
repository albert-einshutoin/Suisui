import XCTest
@testable import SoloPMCore

final class ToolArgumentsTests: XCTestCase {
    func testOptionalInt64RejectsFractionalNumbersInsteadOfTruncating() throws {
        let arguments = ToolArguments(["projectId": .number(1.9)], tool: .taskCreate)

        XCTAssertThrowsError(try arguments.optionalInt64("projectId")) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskCreate, "Argument 'projectId' must be a 64-bit integer.")
            )
        }
    }

    func testOptionalInt64RejectsInvalidStringInsteadOfTreatingItAsMissing() throws {
        let arguments = ToolArguments(["taskId": .string("not-an-id")], tool: .notificationSchedule)

        XCTAssertThrowsError(try arguments.optionalInt64("taskId")) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.notificationSchedule, "Argument 'taskId' must be a 64-bit integer.")
            )
        }
    }

    func testOptionalStringRejectsNonStringInsteadOfTreatingItAsMissing() throws {
        let arguments = ToolArguments(["dueAt": .number(1)], tool: .taskCreate)

        XCTAssertThrowsError(try arguments.optionalString("dueAt")) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskCreate, "Argument 'dueAt' must be string.")
            )
        }
    }

    func testNullableTrimmedStringTreatsNullAsClearAndOmissionAsUnchanged() throws {
        let arguments = ToolArguments(
            [
                "detail": .null,
                "dueAt": .string("  2026-06-21  ")
            ],
            tool: .taskUpdate
        )

        XCTAssertEqual(try arguments.nullableTrimmedString("detail"), .clear)
        XCTAssertEqual(try arguments.nullableTrimmedString("dueAt"), .set("2026-06-21"))
        XCTAssertEqual(try arguments.nullableTrimmedString("priority"), .unchanged)
    }

    func testNullableInt64TreatsNullAsClearAndOmissionAsUnchanged() throws {
        let arguments = ToolArguments(
            [
                "projectId": .null,
                "taskId": .string("42")
            ],
            tool: .taskUpdate
        )

        XCTAssertEqual(try arguments.nullableInt64("projectId"), .clear)
        XCTAssertEqual(try arguments.nullableInt64("taskId"), .set(42))
        XCTAssertEqual(try arguments.nullableInt64("frameId"), .unchanged)
    }

    func testTrimmedStringArrayRejectsBlankElementsInsteadOfDroppingThem() throws {
        let arguments = ToolArguments(["tags": .array([.string("oss"), .string("  ")])], tool: .projectCreate)

        XCTAssertThrowsError(try arguments.trimmedStringArray("tags")) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.projectCreate, "Argument 'tags[1]' cannot be blank.")
            )
        }
    }
}
