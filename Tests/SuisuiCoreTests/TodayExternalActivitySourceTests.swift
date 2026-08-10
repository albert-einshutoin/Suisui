import Foundation
import XCTest

final class TodayExternalActivitySourceTests: XCTestCase {
    func testDashboardBuildsActivityOnceAndReviewRendersOnlyProjectedRows() throws {
        let model = try source("Sources/SuisuiCore/App/TodayExternalActivityModel.swift")
        let dashboard = try source("Sources/SuisuiCore/App/TodayDashboardSnapshot.swift")
        let dashboardView = try source("Sources/SuisuiApp/Views/TodayDashboardView.swift")
        let cards = try source("Sources/SuisuiApp/Views/TodayDashboardCards.swift")

        XCTAssertTrue(dashboard.contains("TodayExternalActivityModelBuilder.make(integrations: integrations)"))
        XCTAssertTrue(dashboardView.contains("externalActivity: dashboard.externalActivity"))
        XCTAssertTrue(cards.contains("let externalActivity: TodayExternalActivityModel"))
        XCTAssertTrue(cards.contains("ForEach(externalActivity.rows, id: \\.id)"))
        XCTAssertTrue(cards.contains(".accessibilityIdentifier(row.id)"))
        XCTAssertFalse(model.contains("URLSession"))
        XCTAssertFalse(cards.contains("TodayIntegrationState"))
        XCTAssertFalse(cards.contains("TodayIntegrationSnapshotBuilder"))
    }

    private func source(_ relativePath: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
