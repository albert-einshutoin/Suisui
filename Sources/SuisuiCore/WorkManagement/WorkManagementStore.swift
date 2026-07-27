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
    /// Records or clears who this task is waiting on. Separate from
    /// `updateTask` so marking a wait cannot accidentally rewrite title,
    /// status, or due date, and so the wait clock is owned in one place.
    func setTaskWaiting(id: Int64, waitingOn: String?) throws -> ProjectBoardTask
    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask]
    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask]
    func deleteTask(id: Int64) throws
    func restoreTask(from snapshot: ProjectBoardTask) throws -> ProjectBoardTask
    func applyTaskUndoSnapshot(_ snapshot: ProjectBoardTask) throws -> ProjectBoardTask
    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact
    func deleteProjectArtifact(id: Int64) throws
    func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone
    func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone
    func deleteProjectMilestone(id: Int64) throws
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

    @discardableResult
    func createInboxTask(title: String) throws -> ProjectBoardTask {
        let snapshot = try loadSnapshot()
        let inboxProject = snapshot.projects.first { $0.title == "Inbox" } ?? snapshot.projects.first
        guard let inboxProject else {
            throw ProjectBoardStoreError.emptyProjectTitle
        }

        return try createTask(ProjectBoardTaskDraft(
            projectID: inboxProject.id,
            title: title,
            status: .backlog
        ))
    }
}
