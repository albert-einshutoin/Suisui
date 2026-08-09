import XCTest
@testable import Suisui

final class TodayOnboardingPreferencesTests: XCTestCase {
    func testDailyCapacityLabelsRemainUniqueAtEveryThirtyMinutePickerStep() {
        let minutes = Array(stride(
            from: 60,
            through: 16 * 60,
            by: 30
        ))
        let labels = minutes.map(localizedDurationMinutes)

        XCTAssertEqual(labels.count, Set(labels).count)
        XCTAssertNotEqual(localizedDurationMinutes(60), localizedDurationMinutes(90))
    }
}
