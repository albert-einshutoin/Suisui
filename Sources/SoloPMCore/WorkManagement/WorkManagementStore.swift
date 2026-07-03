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
