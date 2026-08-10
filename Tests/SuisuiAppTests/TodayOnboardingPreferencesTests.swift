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

    func testPackagedAppLocalizationResolvesJapaneseWithoutSwiftPMResourceBundle() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Suisui-localization-\(UUID().uuidString).app", isDirectory: true)
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appURL) }

        try FileManager.default.createDirectory(
            at: resourcesURL.appendingPathComponent("ja.lproj", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        let info = NSDictionary(dictionary: [
            "CFBundleIdentifier": "dev.suisui.localization-test",
            "CFBundleExecutable": "Suisui",
            "CFBundlePackageType": "APPL"
        ])
        XCTAssertTrue(info.write(
            to: appURL.appendingPathComponent("Contents/Info.plist"),
            atomically: true
        ))
        try #""Could not save your Today preferences." = "Todayの設定を保存できませんでした。";"#
            .write(
                to: resourcesURL.appendingPathComponent("ja.lproj/Localizable.strings"),
                atomically: true,
                encoding: .utf8
            )

        let appBundle = try XCTUnwrap(Bundle(path: appURL.path))
        let localizationBundle = try XCTUnwrap(
            localizedDisplayBundle(for: .japanese, appBundle: appBundle)
        )

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: resourcesURL.appendingPathComponent("Suisui_Suisui.bundle").path
        ))
        XCTAssertEqual(
            localizationBundle.localizedString(
                forKey: "Could not save your Today preferences.",
                value: nil,
                table: nil
            ),
            "Todayの設定を保存できませんでした。"
        )
    }
}
