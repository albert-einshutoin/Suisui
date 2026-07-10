import XCTest
@testable import SoloPMCore

final class VisualEvidenceRuntimeContextTests: XCTestCase {
    func testCompleteCaptureContextPinsReferenceInstantLocaleAndTimeZone() throws {
        let context = try XCTUnwrap(VisualEvidenceRuntimeContext(environment: [
            VisualEvidenceRuntimeContext.referenceInstantEnvironmentKey: "2026-07-10T12:00:00Z",
            VisualEvidenceRuntimeContext.timeZoneEnvironmentKey: "UTC",
            VisualEvidenceRuntimeContext.localeEnvironmentKey: "en-US"
        ]))

        XCTAssertEqual(ISO8601DateFormatter().string(from: context.referenceInstant), "2026-07-10T12:00:00Z")
        XCTAssertEqual(context.timeZoneIdentifier, "UTC")
        XCTAssertEqual(context.localeIdentifier, "en-US")
        XCTAssertEqual(context.calendar.timeZone.identifier, "GMT")
        XCTAssertEqual(context.calendar.locale?.identifier, "en-US")
    }

    func testPartialOrInvalidCaptureContextFallsBackToSystemClockAndCalendar() {
        let systemNow = Date(timeIntervalSince1970: 123)
        var systemCalendar = Calendar(identifier: .iso8601)
        systemCalendar.timeZone = TimeZone(secondsFromGMT: 3_600)!
        let partialEnvironment = [
            VisualEvidenceRuntimeContext.referenceInstantEnvironmentKey: "2026-07-10T12:00:00Z"
        ]

        XCTAssertNil(VisualEvidenceRuntimeContext(environment: partialEnvironment))
        XCTAssertEqual(
            VisualEvidenceRuntimeContext.referenceDate(
                environment: partialEnvironment,
                systemNow: { systemNow }
            ),
            systemNow
        )
        XCTAssertEqual(
            VisualEvidenceRuntimeContext.runtimeCalendar(
                environment: partialEnvironment,
                systemCalendar: { systemCalendar }
            ).timeZone,
            systemCalendar.timeZone
        )
    }
}
