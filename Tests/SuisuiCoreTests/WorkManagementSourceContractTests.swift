import Foundation
import XCTest

final class WorkManagementSourceContractTests: XCTestCase {
    func testProjectBoardWorkManagementModelsAreExtractedFromMonolith() throws {
        let projectBoard = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let models = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift")

        for marker in workManagementModelMarkers {
            XCTAssertTrue(models.contains(marker), "Work Management models file must contain \(marker)")
            XCTAssertFalse(projectBoard.contains(marker), "ProjectBoard.swift should no longer own \(marker)")
        }

        XCTAssertTrue(projectBoard.contains("public final class ProjectBoardViewModel"))
    }

    func testProjectBoardStoresAreExtractedFromMonolith() throws {
        let projectBoard = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let store = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift")
        let sqliteStore = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift")

        for marker in workManagementStoreMarkers {
            XCTAssertTrue(store.contains(marker), "WorkManagementStore.swift must contain \(marker)")
            XCTAssertFalse(projectBoard.contains(marker), "ProjectBoard.swift should no longer own \(marker)")
        }
        XCTAssertTrue(sqliteStore.contains("public final class SQLiteProjectBoardStore"))
        XCTAssertTrue(sqliteStore.contains("private extension LocalStoreDecodingError"))
        XCTAssertTrue(sqliteStore.contains("private func makeBoardTask("))
        XCTAssertTrue(sqliteStore.contains("private func recordPersistenceAudit("))
        XCTAssertTrue(sqliteStore.contains("private extension Optional where Wrapped == ProjectBoardTask"))
        XCTAssertFalse(projectBoard.contains("public final class SQLiteProjectBoardStore"))
        XCTAssertFalse(projectBoard.contains("private extension LocalStoreDecodingError"))
        XCTAssertFalse(projectBoard.contains("private func makeBoardTask("))
        XCTAssertFalse(projectBoard.contains("private func recordPersistenceAudit("))
        XCTAssertFalse(projectBoard.contains("private extension Optional where Wrapped == ProjectBoardTask"))
        XCTAssertTrue(projectBoard.contains("public final class ProjectBoardViewModel"))
    }

    func testProjectBoardAnalyticsAreExtractedFromMonolith() throws {
        let projectBoard = try readPackageFile("Sources/SuisuiCore/App/ProjectBoard.swift")
        let analytics = try readPackageFile("Sources/SuisuiCore/WorkManagement/WorkManagementAnalytics.swift")

        XCTAssertTrue(analytics.contains("enum WorkManagementAnalyticsBuilder"))
        XCTAssertTrue(analytics.contains("static func projectPortfolioSummaries("))
        XCTAssertTrue(analytics.contains("static func doneAnalytics("))
        XCTAssertFalse(projectBoard.contains("private func projectPortfolioSummary("))
        XCTAssertFalse(projectBoard.contains("private static func doneAnalyticsHeatmapBuckets("))
        XCTAssertTrue(projectBoard.contains("WorkManagementAnalyticsBuilder.projectPortfolioSummaries("))
        XCTAssertTrue(projectBoard.contains("WorkManagementAnalyticsBuilder.doneAnalytics("))
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
        "public struct PlanningDayKey",
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

    private let workManagementStoreMarkers = [
        "public enum ProjectBoardStoreError",
        "public protocol ProjectBoardStore",
        "public extension ProjectBoardStore"
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
