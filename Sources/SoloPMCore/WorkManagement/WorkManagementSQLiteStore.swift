import Foundation

private struct ProjectBoardStoreIndexes {
    static let empty = ProjectBoardStoreIndexes(tasksByProjectID: [:], artifactsByProjectID: [:], milestonesByProjectID: [:])

    var tasksByProjectID: [Int64: [ProjectBoardTask]]
    var artifactsByProjectID: [Int64: [ProjectBoardArtifact]]
    var milestonesByProjectID: [Int64: [ProjectBoardMilestone]]

    init(
        tasksByProjectID: [Int64: [ProjectBoardTask]],
        artifactsByProjectID: [Int64: [ProjectBoardArtifact]],
        milestonesByProjectID: [Int64: [ProjectBoardMilestone]]
    ) {
        self.tasksByProjectID = tasksByProjectID
        self.artifactsByProjectID = artifactsByProjectID
        self.milestonesByProjectID = milestonesByProjectID
    }

    init(boardData: (
        projects: [ProjectRecord],
        tasks: [ProjectBoardTask],
        artifacts: [ProjectBoardArtifact],
        milestones: [ProjectBoardMilestone]
    )) {
        tasksByProjectID = Dictionary(grouping: boardData.tasks, by: \.projectID)
        milestonesByProjectID = Dictionary(grouping: boardData.milestones, by: \.projectID)

        let projectIDByTaskID = Dictionary(uniqueKeysWithValues: boardData.tasks.map { ($0.id, $0.projectID) })
        let artifactsByDeclaredProject = Dictionary(grouping: boardData.artifacts, by: \.projectID)
        var artifactsByProjectID: [Int64: [ProjectBoardArtifact]] = [:]
        for (projectID, artifacts) in artifactsByDeclaredProject {
            guard let projectID else {
                continue
            }
            artifactsByProjectID[projectID, default: []].append(contentsOf: artifacts)
        }
        for artifact in boardData.artifacts {
            guard let taskID = artifact.taskID,
                  let projectID = projectIDByTaskID[taskID],
                  artifact.projectID != projectID else {
                continue
            }
            artifactsByProjectID[projectID, default: []].append(artifact)
        }

        // Grouping once keeps board load linear as local projects grow; per-project
        // filter scans used to repeat the full task/artifact/milestone arrays.
        self.artifactsByProjectID = artifactsByProjectID
    }
}

public final class SQLiteProjectBoardStore: ProjectBoardStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let artifactStore: SQLiteArtifactStore
    private let milestoneStore: SQLiteProjectMilestoneStore
    private let auditLogger: (any AuditLogger)?

    public init(connection: SQLiteConnection, auditLogger: (any AuditLogger)? = nil) {
        self.connection = connection
        self.projectStore = SQLiteProjectStore(connection: connection)
        self.taskStore = SQLiteTaskStore(connection: connection)
        self.artifactStore = SQLiteArtifactStore(connection: connection)
        self.milestoneStore = SQLiteProjectMilestoneStore(connection: connection)
        self.auditLogger = auditLogger ?? RedactingAuditLogger(base: SQLiteAuditLogger(connection: connection))
    }

    public convenience init(
        path: String,
        migrations: [DatabaseMigration] = CoreMigrations.current,
        auditLogger: (any AuditLogger)? = nil
    ) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection, auditLogger: auditLogger)
    }

    public func loadSnapshot() throws -> ProjectBoardSnapshot {
        try loadSnapshot(includeArchived: false)
    }

    public func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        let boardData = try loadBoardData(includeArchived: includeArchived)
        let indexes = ProjectBoardStoreIndexes(boardData: boardData)

        let boardProjects = boardData.projects.map {
            makeBoardProject(project: $0, indexes: indexes)
        }

        return ProjectBoardSnapshot(projects: boardProjects)
    }

    @discardableResult
    public func createProject(title: String) throws -> ProjectBoardProject {
        let normalizedTitle = try normalizedProjectTitle(title)
        let record = try projectStore.create(title: normalizedTitle, tags: ["local"], sourceCommand: "app.project-board")
        return makeBoardProject(project: record)
    }

    @discardableResult
    public func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        let normalizedTitle = try normalizedProjectTitle(title)
        let record = try projectStore.updateTitleForProjectBoard(id: id, title: normalizedTitle)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, indexes: ProjectBoardStoreIndexes(boardData: boardData))
    }

    @discardableResult
    public func completeProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.completeForProjectBoard(id: id, taskStore: taskStore)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, indexes: ProjectBoardStoreIndexes(boardData: boardData))
    }

    @discardableResult
    public func archiveProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.updateStatusForProjectBoard(id: id, status: "archived")
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, indexes: ProjectBoardStoreIndexes(boardData: boardData))
    }

    @discardableResult
    public func restoreProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.updateStatusForProjectBoard(id: id, status: "active")
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, indexes: ProjectBoardStoreIndexes(boardData: boardData))
    }

    @discardableResult
    public func setProjectWorkspacePath(id: Int64, path: String?, bookmarkData: Data? = nil) throws -> ProjectBoardProject {
        let workspacePath = try normalizedWorkspacePath(path)
        let workspaceBookmarkData: NullableFieldUpdate<Data>
        if workspacePath == nil {
            workspaceBookmarkData = .clear
        } else if let bookmarkData, !bookmarkData.isEmpty {
            workspaceBookmarkData = .set(bookmarkData)
        } else {
            throw ProjectBoardStoreError.missingWorkspaceBookmark
        }
        let record = try projectStore.updateFields(
            id: id,
            workspacePath: workspacePath.map { .set($0) } ?? .clear,
            // Security-scoped bookmarks are local-only permission material. Keeping
            // them in SQLite, not the UI snapshot, lets SoloPM restore access later
            // without syncing or displaying raw bookmark bytes.
            workspaceBookmarkData: workspaceBookmarkData
        )
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, indexes: ProjectBoardStoreIndexes(boardData: boardData))
    }

    public func deleteProject(id: Int64) throws {
        try projectStore.deleteForProjectBoard(id: id)
    }

    @discardableResult
    public func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        let normalized = try normalizedDraft(draft)
        try prepareProjectForTaskMutation(projectID: normalized.projectID, taskStatus: normalized.status)
        let record = try taskStore.create(
            title: normalized.title,
            projectID: normalized.projectID,
            dueAt: normalized.dueAt,
            priority: normalized.priority.rawValue,
            sourceCommand: "app.project-board",
            status: normalized.status.rawValue,
            detail: normalized.detail
        )
        return try makeBoardTask(record).requiredTask()
    }

    @discardableResult
    public func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        let normalized = try normalizedDraft(draft)
        try prepareProjectForTaskMutation(projectID: normalized.projectID, taskStatus: normalized.status)
        let record = try taskStore.updateFields(
            id: id,
            title: normalized.title,
            status: normalized.status.rawValue,
            detail: normalized.detail.isEmpty ? .clear : .set(normalized.detail),
            dueAt: normalized.dueAt.map { .set($0) } ?? .clear,
            priority: .set(normalized.priority.rawValue),
            projectID: .set(normalized.projectID)
        )
        return try makeBoardTask(record).requiredTask()
    }

    @discardableResult
    public func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        let current = try taskStore.get(id: id)
        let projectID = try current.projectID ?? ensureActiveInboxProject().id
        try prepareProjectForTaskMutation(projectID: projectID, taskStatus: status)
        let record = try taskStore.update(id: id, status: status.rawValue, projectID: projectID)
        return try makeBoardTask(record).requiredTask()
    }

    @discardableResult
    public func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        try connection.transaction {
            try ids.map { try moveTask(id: $0, to: status) }
        }
    }

    @discardableResult
    public func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask] {
        try connection.transaction {
            try ids.map { taskID in
                let current = try taskStore.get(id: taskID)
                let status = ProjectTaskStatus.normalized(current.status)
                try prepareProjectForTaskMutation(projectID: projectID, taskStatus: status)
                let record = try taskStore.updateFields(id: taskID, projectID: .set(projectID))
                return try makeBoardTask(record).requiredTask()
            }
        }
    }

    public func deleteTask(id: Int64) throws {
        try taskStore.delete(id: id)
    }

    @discardableResult
    public func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact {
        let project = try projectStore.getForProjectBoard(id: projectID)
        if project.status == "archived" {
            throw ProjectBoardStoreError.archivedProjectCannotAcceptArtifacts
        }

        let normalizedPath = try normalizedArtifactPath(expectedPath)
        let workspacePath = URL(fileURLWithPath: normalizedPath).deletingLastPathComponent().path
        let record = try artifactStore.create(
            projectID: projectID,
            workspacePath: workspacePath,
            expectedPath: normalizedPath,
            createdState: .expected
        )
        return makeBoardArtifact(record)
    }

    public func deleteProjectArtifact(id: Int64) throws {
        try artifactStore.delete(id: id)
    }

    @discardableResult
    public func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone {
        _ = try projectStore.getForProjectBoard(id: projectID)
        let milestoneTitle = try normalizedMilestoneTitle(title)
        let record = try milestoneStore.create(projectID: projectID, title: milestoneTitle, dueAt: normalizedOptionalDateString(dueAt))
        return makeBoardMilestone(record)
    }

    @discardableResult
    public func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone {
        let milestoneTitle = try normalizedMilestoneTitle(title)
        let record = try milestoneStore.update(id: id, title: milestoneTitle, dueAt: normalizedOptionalDateString(dueAt), isCompleted: isCompleted)
        return makeBoardMilestone(record)
    }

    public func deleteProjectMilestone(id: Int64) throws {
        try milestoneStore.delete(id: id)
    }

    private func prepareProjectForTaskMutation(projectID: Int64, taskStatus: ProjectTaskStatus) throws {
        let project = try projectStore.getForProjectBoard(id: projectID)
        if project.status == "archived" {
            throw ProjectBoardStoreError.archivedProjectCannotAcceptTasks
        }

        if project.status == "completed", taskStatus != .done {
            _ = try projectStore.updateStatusForProjectBoard(id: projectID, status: "active")
        }
    }

    private func ensureProjects(includeArchived: Bool) throws -> [ProjectRecord] {
        let activeProjects = try projectStore.listForProjectBoard()
        if activeProjects.isEmpty {
            _ = try projectStore.create(title: "Inbox", tags: ["local"], sourceCommand: "app.project-board")
        }

        return try projectStore.listForProjectBoard(includeArchived: includeArchived)
    }

    private func loadBoardData(includeArchived: Bool) throws -> (
        projects: [ProjectRecord],
        tasks: [ProjectBoardTask],
        artifacts: [ProjectBoardArtifact],
        milestones: [ProjectBoardMilestone]
    ) {
        var projects = try ensureProjects(includeArchived: includeArchived)
        let taskRecords = try taskStore.listAll()
        let artifacts = try artifactStore.list().map(makeBoardArtifact(_:))
        let milestones = try milestoneStore.list().map(makeBoardMilestone(_:))
        var projectIDs = Set(projects.map(\.id))
        let fallbackProjectID: Int64?

        let danglingProjectTasks = taskRecords.filter { task in
            task.projectID.map { !projectIDs.contains($0) } ?? false
        }

        if taskRecords.contains(where: { task in task.projectID.map { !projectIDs.contains($0) } ?? true }) {
            fallbackProjectID = try ensureActiveInboxProject().id
            projects = try projectStore.listForProjectBoard(includeArchived: includeArchived)
            projectIDs = Set(projects.map(\.id))
            for task in danglingProjectTasks {
                recordPersistenceAudit(
                    action: "project_board.repair_candidate",
                    metadata: [
                        "record_type": "task",
                        "record_id": "\(task.id)",
                        "column": "tasks.project_id",
                        "reason": "dangling_project_reference"
                    ]
                )
            }
        } else {
            fallbackProjectID = nil
        }

        let tasks = try taskRecords.compactMap { record in
            do {
                return try makeBoardTask(
                    record,
                    fallbackProjectID: fallbackProjectID,
                    projectIDs: projectIDs
                ).requiredTask()
            } catch let error as LocalStoreDecodingError where error.isProjectBoardSkippableRecord {
                // A single corrupted imported task must not make the whole board unavailable; mutation paths still validate strictly.
                recordSkippedTask(record, error: error)
                return nil
            }
        }
        return (projects, tasks, artifacts, milestones)
    }

    private func ensureActiveInboxProject() throws -> ProjectRecord {
        if let inbox = try projectStore.listForProjectBoard().first(where: { $0.title == "Inbox" }) {
            return inbox
        }

        return try projectStore.create(title: "Inbox", tags: ["local"], sourceCommand: "app.project-board")
    }

    private func normalizedDraft(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTaskDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ProjectBoardStoreError.emptyTitle
        }

        let detail = draft.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueAt = draft.dueAt?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ProjectBoardTaskDraft(
            projectID: draft.projectID,
            title: title,
            detail: detail,
            status: draft.status,
            priority: draft.priority,
            dueAt: dueAt?.isEmpty == true ? nil : dueAt
        )
    }

    private func normalizedProjectTitle(_ title: String) throws -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ProjectBoardStoreError.emptyProjectTitle
        }

        return normalizedTitle
    }

    private func normalizedMilestoneTitle(_ title: String) throws -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ProjectBoardStoreError.emptyTitle
        }
        return normalizedTitle
    }

    private func normalizedOptionalDateString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    private func normalizedArtifactPath(_ path: String) throws -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw ProjectBoardStoreError.emptyArtifactPath
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            throw ProjectBoardStoreError.nonAbsoluteArtifactPath
        }

        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }

    private func normalizedWorkspacePath(_ path: String?) throws -> String? {
        guard let path else {
            return nil
        }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            throw ProjectBoardStoreError.nonAbsoluteWorkspacePath
        }

        return URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL.path
    }

    private func workspaceDisplayName(for path: String?) -> String? {
        guard let path else {
            return nil
        }

        let lastComponent = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        guard !lastComponent.isEmpty else {
            return String(localized: "Selected directory")
        }
        return lastComponent
    }

    private func makeBoardProject(
        project: ProjectRecord,
        indexes: ProjectBoardStoreIndexes = .empty
    ) -> ProjectBoardProject {
        let projectTasks = indexes.tasksByProjectID[project.id, default: []]
        let projectArtifacts = indexes.artifactsByProjectID[project.id, default: []]
        let columns = ProjectTaskStatus.allCases.map { status in
            ProjectBoardColumn(
                status: status,
                tasks: projectTasks
                    .filter { $0.status == status }
                    .sorted { $0.id > $1.id }
            )
        }
        let openCount = projectTasks.filter { $0.status != .done }.count
        let subtitle = "\(openCount) open / \(projectTasks.count) total"
        return ProjectBoardProject(
            id: project.id,
            title: project.title,
            status: project.status,
            subtitle: subtitle,
            hasWorkspaceDirectory: project.workspacePath != nil,
            hasWorkspaceBookmark: project.workspaceBookmarkData?.isEmpty == false,
            workspaceDisplayName: workspaceDisplayName(for: project.workspacePath),
            columns: columns,
            artifacts: projectArtifacts,
            milestones: indexes.milestonesByProjectID[project.id, default: []]
        )
    }

    private func makeBoardTask(
        _ record: TaskRecord,
        fallbackProjectID: Int64? = nil,
        projectIDs: Set<Int64>? = nil
    ) throws -> ProjectBoardTask? {
        let rawProjectID = record.projectID
        let projectID = if let rawProjectID, projectIDs?.contains(rawProjectID) != false {
            rawProjectID
        } else {
            fallbackProjectID
        }

        guard let projectID else {
            return nil
        }

        return ProjectBoardTask(
            id: record.id,
            projectID: projectID,
            title: record.title,
            detail: record.detail ?? "",
            status: ProjectTaskStatus.normalized(record.status),
            priority: try ProjectTaskPriority.normalized(record.priority, column: "tasks.priority"),
            dueAt: record.dueAt,
            completedAt: record.completedAt,
            updatedAt: record.updatedAt
        )
    }

    private func makeBoardArtifact(_ record: ArtifactRecord) -> ProjectBoardArtifact {
        ProjectBoardArtifact(
            id: record.id,
            projectID: record.projectID,
            taskID: record.taskID,
            expectedPath: record.expectedPath,
            createdState: record.createdState,
            lastModifiedAt: record.lastModifiedAt
        )
    }

    private func makeBoardMilestone(_ record: ProjectMilestoneRecord) -> ProjectBoardMilestone {
        ProjectBoardMilestone(
            id: record.id,
            projectID: record.projectID,
            title: record.title,
            dueAt: record.dueAt,
            isCompleted: record.isCompleted
        )
    }

    private func recordSkippedTask(_ record: TaskRecord, error: LocalStoreDecodingError) {
        guard let auditReason = error.projectBoardAuditReason else {
            return
        }

        recordPersistenceAudit(
            action: "project_board.record_skipped",
            metadata: [
                "record_type": "task",
                "record_id": "\(record.id)",
                "column": auditReason.column,
                "reason": auditReason.reason
            ]
        )
    }

    private func recordPersistenceAudit(action: String, metadata: [String: String]) {
        guard let auditLogger else {
            return
        }

        do {
            try auditLogger.record(AuditEvent(
                category: "persistence",
                action: action,
                status: .skipped,
                metadata: metadata
            ))
        } catch {
            // Repair diagnostics are best-effort; losing the audit row must not turn a recoverable board load into an outage.
        }
    }
}

private extension LocalStoreDecodingError {
    var isProjectBoardSkippableRecord: Bool {
        switch self {
        case .invalidEnum(column: "tasks.priority", value: _):
            true
        default:
            false
        }
    }

    var projectBoardAuditReason: (column: String, reason: String)? {
        switch self {
        case .invalidEnum(column: "tasks.priority", value: _):
            ("tasks.priority", "unsupported_priority")
        default:
            nil
        }
    }
}

private extension Optional where Wrapped == ProjectBoardTask {
    func requiredTask() throws -> ProjectBoardTask {
        guard let self else {
            throw DatabaseError.stepFailed("Task did not have a project.")
        }
        return self
    }
}
