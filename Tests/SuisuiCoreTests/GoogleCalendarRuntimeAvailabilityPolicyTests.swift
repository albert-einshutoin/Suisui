import XCTest
@testable import SuisuiCore

final class GoogleCalendarRuntimeAvailabilityPolicyTests: XCTestCase {
    func testPublicAlphaAlwaysDisablesGoogleCalendarRuntime() {
        XCTAssertFalse(
            GoogleCalendarRuntimeAvailabilityPolicy.isEnabled(
                buildPolicy: .publicAlpha,
                environmentOptIn: true
            )
        )
        XCTAssertFalse(
            GoogleCalendarRuntimeAvailabilityPolicy.isEnabled(
                buildPolicy: .publicAlpha,
                environmentOptIn: false
            )
        )
    }

    func testDevelopmentBuildRequiresExplicitRuntimeOptIn() {
        XCTAssertFalse(
            GoogleCalendarRuntimeAvailabilityPolicy.isEnabled(
                buildPolicy: .development,
                environmentOptIn: false
            )
        )
        XCTAssertTrue(
            GoogleCalendarRuntimeAvailabilityPolicy.isEnabled(
                buildPolicy: .development,
                environmentOptIn: true
            )
        )
    }
}
