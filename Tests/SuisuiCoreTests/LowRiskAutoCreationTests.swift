import XCTest
@testable import SuisuiCore

final class LowRiskAutoCreationTests: XCTestCase {
    // MARK: - Settings round trip

    func testTaskAutoExecutionSettingsRoundTripWithAutoCreateMode() throws {
        let settings = TaskAutoExecutionSettings(
            isEnabled: true,
            mode: .autoCreateLowRisk,
            cadence: .daily,
            maxTasksPerRun: 4,
            dailyLLMCallLimit: 8,
            lookaheadHours: 24,
            urgentReviewCooldownMinutes: 30
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TaskAutoExecutionSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.mode, .autoCreateLowRisk)
    }

    func testLegacyReviewOnlySettingsStillDecode() throws {
        let legacyJSON = """
        {"isEnabled":true,"cadence":"manual","maxTasksPerRun":3,"dailyLLMCallLimit":6,"lookaheadHours":48}
        """
        let decoded = try JSONDecoder().decode(TaskAutoExecutionSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.mode, .reviewOnly)
        XCTAssertEqual(decoded.urgentReviewCooldownMinutes, 60)
    }

    func testModeLabels() {
        XCTAssertEqual(TaskAutoExecutionMode.reviewOnly.label, "Review before execution")
        XCTAssertEqual(TaskAutoExecutionMode.autoCreateLowRisk.label, "Auto-create low-risk tasks")
        XCTAssertEqual(TaskAutoExecutionMode.allCases, [.reviewOnly, .autoCreateLowRisk])
    }

}
