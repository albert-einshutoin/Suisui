import XCTest
@testable import SuisuiCore

final class WeatherLocationPreferenceTests: XCTestCase {
    func testManualCityNormalizesLabelAndRoundTripsWithoutCoordinatesInDisplayLabel() throws {
        let preference = WeatherLocationPreference.manual(
            cityLabel: "  Shibuya  ",
            latitude: 35.658034,
            longitude: 139.701636
        ).normalized

        XCTAssertEqual(preference.displayLabel, "Shibuya")
        let data = try JSONEncoder().encode(preference)
        let decoded = try JSONDecoder().decode(WeatherLocationPreference.self, from: data)
        XCTAssertEqual(decoded, preference)
        XCTAssertFalse(preference.displayLabel.contains("35.658"))
    }

    func testInvalidManualCoordinatesFailClosedToUnset() {
        XCTAssertEqual(
            WeatherLocationPreference.manual(cityLabel: "Tokyo", latitude: 91, longitude: 139).normalized,
            .unset
        )
        XCTAssertEqual(
            WeatherLocationPreference.manual(cityLabel: "", latitude: 35, longitude: 139).normalized,
            .unset
        )
    }

    func testLegacySettingsDecodeWeatherAsUnset() throws {
        let encoded = try JSONEncoder().encode(AppSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "weatherLocationPreference")
        let data = try JSONSerialization.data(withJSONObject: object)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.weatherLocationPreference, .unset)
    }

    func testOnboardingDraftCarriesWeatherPreferenceOnlyOnApply() {
        let saved = AppSettings(profileDisplayName: "Ada")
        let draft = OnboardingTodayPreferences(
            displayName: "Ada",
            weatherLocationPreference: .manual(cityLabel: "Tokyo", latitude: 35.6, longitude: 139.7)
        )
        XCTAssertEqual(saved.weatherLocationPreference, .unset)
        XCTAssertEqual(draft.applying(to: saved).weatherLocationPreference.displayLabel, "Tokyo")
    }
}
