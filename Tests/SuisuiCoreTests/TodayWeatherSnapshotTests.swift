import XCTest
@testable import SuisuiCore

final class TodayWeatherSnapshotTests: XCTestCase {
    func testWeatherProjectionHasSafeLocalizedFallbacksForEveryUnavailableState() {
        let date = ISO8601DateFormatter().date(from: "2026-08-09T10:30:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        for state in [TodayWeatherState.notConfigured, .permissionPending, .loading, .failed] {
            let english = TodayWeatherSnapshotBuilder.make(
                state: state,
                now: date,
                calendar: calendar,
                locale: Locale(identifier: "en")
            )
            let japanese = TodayWeatherSnapshotBuilder.make(
                state: state,
                now: date,
                calendar: calendar,
                locale: Locale(identifier: "ja")
            )

            XCTAssertFalse(english.title.isEmpty)
            XCTAssertFalse(english.detail.isEmpty)
            XCTAssertTrue(english.accessibilityLabel.contains("Weather"))
            XCTAssertTrue(japanese.accessibilityLabel.contains("天気"))
        }
    }

    func testWeatherProjectionFormatsTemperatureLocationAndUpdateTimeInEnglishAndJapanese() {
        let date = ISO8601DateFormatter().date(from: "2026-08-09T10:30:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let state = TodayWeatherState.available(
            temperatureCelsius: 22,
            location: "Tokyo",
            updatedAt: date
        )

        let english = TodayWeatherSnapshotBuilder.make(
            state: state,
            now: date,
            calendar: calendar,
            locale: Locale(identifier: "en")
        )
        let japanese = TodayWeatherSnapshotBuilder.make(
            state: state,
            now: date,
            calendar: calendar,
            locale: Locale(identifier: "ja")
        )

        XCTAssertEqual(english.title, "Tokyo · 22°C")
        XCTAssertEqual(english.detail, "Updated 10:30")
        XCTAssertEqual(english.accessibilityLabel, "Weather: Tokyo, 22°C. Updated 10:30.")
        XCTAssertEqual(japanese.title, "Tokyo・22°C")
        XCTAssertEqual(japanese.detail, "10:30更新")
        XCTAssertEqual(japanese.accessibilityLabel, "天気: Tokyo、22°C。10:30更新。")
    }

    func testNotConfiguredWeatherDoesNotSuggestANonexistentSettingsRoute() {
        let snapshot = TodayWeatherSnapshotBuilder.make(
            state: .notConfigured,
            now: Date(timeIntervalSince1970: 0),
            calendar: .current,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(snapshot.detail, "Weather is unavailable right now.")
        XCTAssertFalse(snapshot.detail.contains("Settings"))
    }
}
