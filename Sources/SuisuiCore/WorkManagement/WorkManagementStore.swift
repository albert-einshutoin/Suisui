import Foundation

public enum ProjectBoardStoreError: Error, Equatable, Sendable {
    case emptyTitle
    case emptyProjectTitle
    case emptyArtifactPath
    case nonAbsoluteArtifactPath
    case nonAbsoluteWorkspacePath
    case missingWorkspaceBookmark
    case archivedProjectCannotAcceptTasks
    case archivedProjectCannotAcceptArtifacts
}

public protocol ProjectBoardStore {
    func loadSnapshot() throws -> ProjectBoardSnapshot
    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot
    func createProject(title: String) throws -> ProjectBoardProject
    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject
    func completeProject(id: Int64) throws -> ProjectBoardProject
    func archiveProject(id: Int64) throws -> ProjectBoardProject
    func restoreProject(id: Int64) throws -> ProjectBoardProject
    func setProjectWorkspacePath(id: Int64, path: String?, bookmarkData: Data?) throws -> ProjectBoardProject
    func deleteProject(id: Int64) throws
    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask
    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask]
    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask]
    func deleteTask(id: Int64) throws
    func restoreTask(from snapshot: ProjectBoardTask) throws -> ProjectBoardTask
    func applyTaskUndoSnapshot(_ snapshot: ProjectBoardTask) throws -> ProjectBoardTask
    func loadInboxTriageRecords(taskIDs: Set<Int64>) throws -> [Int64: InboxTriageRecord]
    func createInboxTask(title: String) throws -> ProjectBoardTask
    func performInboxTriage(
        taskID: Int64,
        action: InboxTriageAction,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> InboxTriageMutation
    func undoInboxTriage(_ mutation: InboxTriageMutation) throws -> ProjectBoardTask
    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact
    func deleteProjectArtifact(id: Int64) throws
    func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone
    func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone
    func deleteProjectMilestone(id: Int64) throws
}

/// Fail-closed store used when the persistent store cannot be opened. Every
/// operation rethrows the original open error so the UI reports the real cause
/// instead of silently working against an empty in-memory board.
public struct UnavailableProjectBoardStore: ProjectBoardStore {
    public let error: Error

    public init(error: Error) {
        self.error = error
    }

    public func loadSnapshot() throws -> ProjectBoardSnapshot {
        throw error
    }

    public func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        throw error
    }

    public func createProject(title: String) throws -> ProjectBoardProject {
        throw error
    }

    public func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        throw error
    }

    public func completeProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    public func archiveProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    public func restoreProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    public func deleteProject(id: Int64) throws {
        throw error
    }

    public func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    public func loadInboxTriageRecords(taskIDs: Set<Int64>) throws -> [Int64: InboxTriageRecord] {
        throw error
    }

    public func createInboxTask(title: String) throws -> ProjectBoardTask {
        throw error
    }

    public func performInboxTriage(
        taskID: Int64,
        action: InboxTriageAction,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> InboxTriageMutation {
        throw error
    }

    public func undoInboxTriage(_ mutation: InboxTriageMutation) throws -> ProjectBoardTask {
        throw error
    }

    public func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    public func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        throw error
    }

    public func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        throw error
    }

    public func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask] {
        throw error
    }

    public func deleteTask(id: Int64) throws {
        throw error
    }

    public func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact {
        throw error
    }

    public func deleteProjectArtifact(id: Int64) throws {
        throw error
    }

    public func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone {
        throw error
    }

    public func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone {
        throw error
    }

    public func deleteProjectMilestone(id: Int64) throws {
        throw error
    }
}

public extension ProjectBoardStore {
    func setProjectWorkspacePath(id: Int64, path: String?, bookmarkData: Data?) throws -> ProjectBoardProject {
        throw ProjectBoardStoreError.nonAbsoluteWorkspacePath
    }

    func setProjectWorkspacePath(id: Int64, path: String?) throws -> ProjectBoardProject {
        try setProjectWorkspacePath(id: id, path: path, bookmarkData: nil)
    }

    /// Board-operation undo restore for a deleted task. The default recreates
    /// the task through the public create path (which stamps completion "now"
    /// for done tasks); persistent stores override this to preserve the
    /// original `completedAt` (see `SQLiteTaskStore.createForBackupRestore`).
    @discardableResult
    func restoreTask(from snapshot: ProjectBoardTask) throws -> ProjectBoardTask {
        try createTask(ProjectBoardTaskDraft(
            projectID: snapshot.projectID,
            title: snapshot.title,
            detail: snapshot.detail,
            status: snapshot.status,
            priority: snapshot.priority,
            dueAt: snapshot.dueAt,
            recurrence: snapshot.recurrence
        ))
    }

    /// Board-operation undo revert: put a task's editable fields and status
    /// back to a previous snapshot. The default routes through `updateTask`;
    /// persistent stores override this to bypass completion-driven recurrence
    /// so undoing a reopen never regenerates another occurrence.
    @discardableResult
    func applyTaskUndoSnapshot(_ snapshot: ProjectBoardTask) throws -> ProjectBoardTask {
        try updateTask(id: snapshot.id, ProjectBoardTaskDraft(
            projectID: snapshot.projectID,
            title: snapshot.title,
            detail: snapshot.detail,
            status: snapshot.status,
            priority: snapshot.priority,
            dueAt: snapshot.dueAt,
            recurrence: snapshot.recurrence
        ))
    }

}
