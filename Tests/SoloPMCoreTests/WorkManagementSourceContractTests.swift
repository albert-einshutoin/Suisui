import Foundation
import XCTest

final class WorkManagementSourceContractTests: XCTestCase {
    func testProjectBoardWorkManagementModelsAreExtractedFromMonolith() throws {
        let projectBoard = try readPackageFile("Sources/SoloPMCore/App/ProjectBoard.swift")
        let models = try readPackageFile("Sources/SoloPMCore/WorkManagement/WorkManagementModels.swift")

        for marker in workManagementModelMarkers {
            XCTAssertTrue(models.contains(marker), "Work Management models file must contain \(marker)")
            XCTAssertFalse(projectBoard.contains(marker), "ProjectBoard.swift should no longer own \(marker)")
        }

        XCTAssertTrue(projectBoard.contains("public final class ProjectBoardViewModel"))
        XCTAssertTrue(projectBoard.contains("public final class SQLiteProjectBoardStore"))
        XCTAssertTrue(projectBoard.contains("public protocol ProjectBoardStore"))
    }

    private let workManagementModelMarkers = [
        "public enum ProjectTaskStatus",
        "public enum ProjectTaskPriority",
        "public struct ProjectBoardSnapshot",
        "public struct ProjectBoardProject",
        "public struct ProjectBoardArtifact",
        "public struct ProjectBoardMilestone",
        "public struct ProjectBoardColumn",
        "public struct ProjectBoardTask",
        "public struct ProjectBoardTaskDraft",
        "public struct TodayTimeBlock",
        "public struct TodayWorkflowPlan",
        "public enum TodayAssistantRailSource",
        "public struct TodayAssistantRailContext",
        "public enum TodayRecommendationKind",
        "public struct TodayRecommendationChip",
        "public struct TodayWorkflowSnapshot",
        "public struct TodayScheduleDraft",
        "public struct ScheduleDraft",
        "public enum ProjectPortfolioHealth",
        "public struct ProjectPortfolioSummary",
        "public struct DoneAnalyticsSummary",
        "public struct DoneAnalyticsDayBucket",
        "public struct DoneAnalyticsBestWeekdaySummary",
        "public struct DoneAnalyticsBestHourSummary",
        "public enum DoneAnalyticsTimeOfDay",
        "public struct InboxClassificationFeedback",
        "public struct InboxTriageSummary",
        "public enum InboxTriageFilter"
    ]

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
