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

    func testTodayPreferencesSaveFailureUsesJapaneseLanguageOverride() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppLanguagePreference.storageKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: AppLanguagePreference.storageKey)
            } else {
                defaults.removeObject(forKey: AppLanguagePreference.storageKey)
            }
        }
        defaults.set(AppLanguagePreference.japanese.rawValue, forKey: AppLanguagePreference.storageKey)

        XCTAssertEqual(
            localizedDisplay("Could not save your Today preferences."),
            "Todayの設定を保存できませんでした。"
        )
    }
}
