import Foundation
import XCTest

final class TodayWeatherSettingsSourceTests: XCTestCase {
    func testManualWeatherSettingsExposeLabelAndCoordinatesWithoutCurrentLocationLabelReuse() throws {
        let settings = try source("Sources/SuisuiApp/Views/SettingsFeatureViews.swift")

        XCTAssertTrue(settings.contains("value: weatherLatitudeBinding"))
        XCTAssertTrue(settings.contains("value: weatherLongitudeBinding"))
        XCTAssertTrue(settings.contains("guard (-90...90).contains(latitude)"))
        XCTAssertTrue(settings.contains("guard (-180...180).contains(longitude)"))
        XCTAssertTrue(settings.contains("settings-weather-latitude"))
        XCTAssertTrue(settings.contains("settings-weather-longitude"))
        XCTAssertTrue(settings.contains("case .manual:"))
        XCTAssertFalse(settings.contains("label == \"Not configured\" ? \"Tokyo\" : label"))
    }

    func testWeatherReloadBoundaryDoesNotReplaceCalendarInvalidation() throws {
        let core = try source("Sources/SuisuiCore/App/AppSettings.swift")
        let runtime = try source("Sources/SuisuiApp/Composition/SettingsRuntimeFactory.swift")

        XCTAssertTrue(core.contains("suisuiWeatherLocationDidChange"))
        XCTAssertTrue(core.contains("suisuiGoogleCalendarReadinessDidChange"))
        XCTAssertTrue(runtime.contains("observeTodayWeatherSettingsChanges"))
        XCTAssertTrue(runtime.contains("await model?.refresh()"))
        XCTAssertFalse(runtime.contains("weatherProvider: URLSession"))
    }

    private func source(_ relativePath: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
