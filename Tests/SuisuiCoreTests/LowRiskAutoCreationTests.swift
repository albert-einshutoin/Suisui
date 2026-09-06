import XCTest
@testable import SuisuiCore

final class LowRiskAutoCreationTests: XCTestCase {
    // MARK: - Settings round trip

    func testRetiredAutoCreateSettingsDecodeAndSaveAsReviewOnly() throws {
        let settings = TaskAutoExecutionSettings(
            isEnabled: true,
            mode: .reviewOnly,
            cadence: .daily,
            maxTasksPerRun: 4,
            dailyLLMCallLimit: 8,
            lookaheadHours: 24,
            urgentReviewCooldownMinutes: 30
        )

        let data = try JSONEncoder().encode(settings)
        let legacyJSON = try XCTUnwrap(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "reviewOnly", with: "autoCreateLowRisk")
        let decoded = try JSONDecoder().decode(TaskAutoExecutionSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.mode, .reviewOnly)
        let saved = try XCTUnwrap(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
        XCTAssertFalse(saved.contains("autoCreateLowRisk"))
        XCTAssertTrue(saved.contains("reviewOnly"))
    }

    func testLegacyReviewOnlySettingsStillDecode() throws {
        let legacyJSON = """
        {"isEnabled":true,"cadence":"manual","maxTasksPerRun":3,"dailyLLMCallLimit":6,"lookaheadHours":48}
        """
        let decoded = try JSONDecoder().decode(TaskAutoExecutionSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.mode, .reviewOnly)
        XCTAssertEqual(decoded.urgentReviewCooldownMinutes, 60)
    }

    func testUnknownModeStillFailsDecoding() {
        XCTAssertThrowsError(try JSONDecoder().decode(TaskAutoExecutionMode.self, from: Data(#""unknownMode""#.utf8)))
    }

    func testModeLabels() {
        XCTAssertEqual(TaskAutoExecutionMode.reviewOnly.label, "Review before execution")
        XCTAssertEqual(TaskAutoExecutionMode.allCases, [.reviewOnly])
    }

}
