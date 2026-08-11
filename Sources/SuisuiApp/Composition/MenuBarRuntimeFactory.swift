import Foundation
import SuisuiCore

extension AppRuntimeFactory {
    @MainActor
    static func makeMenuBarSummaryController() -> MenuBarSummaryController {
        MenuBarSummaryController {
            do {
                return try SQLiteMenuBarSummaryProvider(path: applicationDatabaseURL().path)
            } catch {
                return UnavailableMenuBarSummaryProvider(error: error)
            }
        }
    }

    @MainActor
    static func makeMenuBarQuickCaptureController() -> MenuBarQuickCaptureController {
        MenuBarQuickCaptureController(
            storeFactory: {
                do {
                    let connection = try migratedConnection()
                    return SQLiteProjectBoardStore(connection: connection)
                } catch {
                    return UnavailableMenuBarQuickCaptureStore(error: error)
                }
            },
            onChange: postProjectBoardDidChange
        )
    }
}

private struct UnavailableMenuBarSummaryProvider: MenuBarSummaryProviding {
    let error: Error

    func loadMenuBarSummary() throws -> MenuBarSummary {
        throw error
    }
}

private struct UnavailableMenuBarQuickCaptureStore: ProjectBoardStore {
    let error: Error

    func loadSnapshot() throws -> ProjectBoardSnapshot {
        throw error
    }

    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        throw error
    }

    func createProject(title: String) throws -> ProjectBoardProject {
        throw error
    }

    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        throw error
    }

    func completeProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func archiveProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func restoreProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func deleteProject(id: Int64) throws {
        throw error
    }

    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func loadInboxTriageRecords(taskIDs: Set<Int64>) throws -> [Int64: InboxTriageRecord] {
        throw error
    }

    func createInboxTask(title: String) throws -> ProjectBoardTask {
        throw error
    }

    func performInboxTriage(
        taskID: Int64,
        action: InboxTriageAction,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> InboxTriageMutation {
        throw error
    }

    func undoInboxTriage(_ mutation: InboxTriageMutation) throws -> ProjectBoardTask {
        throw error
    }

    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        throw error
    }

    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        throw error
    }

    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask] {
        throw error
    }

    func deleteTask(id: Int64) throws {
        throw error
    }

    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact {
        throw error
    }

    func deleteProjectArtifact(id: Int64) throws {
        throw error
    }

    func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone {
        throw error
    }

    func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone {
        throw error
    }

    func deleteProjectMilestone(id: Int64) throws {
        throw error
    }
}
