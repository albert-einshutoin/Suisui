import Combine
import Foundation

public enum ProjectTaskStatus: String, CaseIterable, Identifiable, Sendable {
    case backlog
    case planned
    case inProgress = "in_progress"
    case blocked
    case done = "completed"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .backlog:
            "Backlog"
        case .planned:
            "Planned"
        case .inProgress:
            "In Progress"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        }
    }

    public static func normalized(_ rawStatus: String) -> ProjectTaskStatus {
        switch rawStatus.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "planned", "next":
            .planned
        case "in_progress", "doing", "active":
            .inProgress
        case "blocked":
            .blocked
        case "completed", "done", "closed":
            .done
        default:
            .backlog
        }
    }
}

public enum ProjectTaskPriority: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var label: String {
        rawValue.capitalized
    }

    public static func normalized(_ rawPriority: String?, column: String) throws -> ProjectTaskPriority {
        guard let rawPriority else {
            return .medium
        }

        let normalized = rawPriority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let priority = ProjectTaskPriority(rawValue: normalized) else {
            throw LocalStoreDecodingError.invalidEnum(column: column, value: rawPriority)
        }
        return priority
    }
}

public struct ProjectBoardSnapshot: Equatable, Sendable {
    public var projects: [ProjectBoardProject]

    public init(projects: [ProjectBoardProject]) {
        self.projects = projects
    }

    public static let empty = ProjectBoardSnapshot(projects: [])
}

public struct ProjectBoardProject: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var status: String
    public var subtitle: String
    public var columns: [ProjectBoardColumn]

    public init(id: Int64, title: String, status: String = "active", subtitle: String, columns: [ProjectBoardColumn]) {
        self.id = id
        self.title = title
        self.status = status
        self.subtitle = subtitle
        self.columns = columns
    }

    public var taskCount: Int {
        columns.reduce(0) { $0 + $1.tasks.count }
    }

    public var tasks: [ProjectBoardTask] {
        columns.flatMap(\.tasks)
    }

    public var isCompleted: Bool {
        status == "completed"
    }

    public var isArchived: Bool {
        status == "archived"
    }
}

public struct ProjectBoardColumn: Identifiable, Equatable, Sendable {
    public var id: String { status.id }
    public var status: ProjectTaskStatus
    public var title: String
    public var tasks: [ProjectBoardTask]

    public init(status: ProjectTaskStatus, tasks: [ProjectBoardTask]) {
        self.status = status
        self.title = status.title
        self.tasks = tasks
    }
}

public struct ProjectBoardTask: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?

    public init(
        id: Int64,
        projectID: Int64,
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
    }

    public var dueLabel: String? {
        dueAt
    }
}

public struct ProjectBoardTaskDraft: Equatable, Sendable {
    public var projectID: Int64
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?

    public init(
        projectID: Int64,
        title: String,
        detail: String = "",
        status: ProjectTaskStatus = .backlog,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) {
        self.projectID = projectID
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
    }
}

public enum ProjectBoardStoreError: Error, Equatable, Sendable {
    case emptyTitle
    case emptyProjectTitle
    case archivedProjectCannotAcceptTasks
}

public protocol ProjectBoardStore {
    func loadSnapshot() throws -> ProjectBoardSnapshot
    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot
    func createProject(title: String) throws -> ProjectBoardProject
    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject
    func completeProject(id: Int64) throws -> ProjectBoardProject
    func archiveProject(id: Int64) throws -> ProjectBoardProject
    func restoreProject(id: Int64) throws -> ProjectBoardProject
    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask
    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask]
    func deleteTask(id: Int64) throws
}

public final class SQLiteProjectBoardStore: ProjectBoardStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore

    public init(connection: SQLiteConnection) {
        self.connection = connection
        self.projectStore = SQLiteProjectStore(connection: connection)
        self.taskStore = SQLiteTaskStore(connection: connection)
    }

    public convenience init(path: String, migrations: [DatabaseMigration] = CoreMigrations.current) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection)
    }

    public func loadSnapshot() throws -> ProjectBoardSnapshot {
        try loadSnapshot(includeArchived: false)
    }

    public func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        let boardData = try loadBoardData(includeArchived: includeArchived)

        let boardProjects = boardData.projects.map { makeBoardProject(project: $0, tasks: boardData.tasks) }

        return ProjectBoardSnapshot(projects: boardProjects)
    }

    @discardableResult
    public func createProject(title: String) throws -> ProjectBoardProject {
        let normalizedTitle = try normalizedProjectTitle(title)
        let record = try projectStore.create(title: normalizedTitle, tags: ["local"], sourceCommand: "app.project-board")
        return makeBoardProject(project: record, tasks: [])
    }

    @discardableResult
    public func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        let normalizedTitle = try normalizedProjectTitle(title)
        let record = try projectStore.update(id: id, title: normalizedTitle)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks)
    }

    @discardableResult
    public func completeProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.update(id: id, status: "completed")
        _ = try taskStore.completeOpenTasks(projectID: id)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks)
    }

    @discardableResult
    public func archiveProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.archive(id: id)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks)
    }

    @discardableResult
    public func restoreProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.restore(id: id)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks)
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
        let record = try taskStore.update(
            id: id,
            title: normalized.title,
            status: normalized.status.rawValue,
            detail: normalized.detail,
            dueAt: normalized.dueAt ?? "",
            priority: normalized.priority.rawValue,
            projectID: normalized.projectID
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

    public func deleteTask(id: Int64) throws {
        try taskStore.delete(id: id)
    }

    private func prepareProjectForTaskMutation(projectID: Int64, taskStatus: ProjectTaskStatus) throws {
        let project = try projectStore.get(id: projectID)
        if project.status == "archived" {
            throw ProjectBoardStoreError.archivedProjectCannotAcceptTasks
        }

        if project.status == "completed", taskStatus != .done {
            _ = try projectStore.restore(id: projectID)
        }
    }

    private func ensureProjects(includeArchived: Bool) throws -> [ProjectRecord] {
        let activeProjects = try projectStore.list()
        if activeProjects.isEmpty {
            _ = try projectStore.create(title: "Inbox", tags: ["local"], sourceCommand: "app.project-board")
        }

        return try projectStore.list(includeArchived: includeArchived)
    }

    private func loadBoardData(includeArchived: Bool) throws -> (projects: [ProjectRecord], tasks: [ProjectBoardTask]) {
        var projects = try ensureProjects(includeArchived: includeArchived)
        let taskRecords = try taskStore.listAll()
        let fallbackProjectID: Int64?

        if taskRecords.contains(where: { $0.projectID == nil }) {
            fallbackProjectID = try ensureActiveInboxProject().id
            projects = try projectStore.list(includeArchived: includeArchived)
        } else {
            fallbackProjectID = nil
        }

        let tasks = try taskRecords.map { record in
            try makeBoardTask(record, fallbackProjectID: fallbackProjectID).requiredTask()
        }
        return (projects, tasks)
    }

    private func ensureActiveInboxProject() throws -> ProjectRecord {
        if let inbox = try projectStore.list().first(where: { $0.title == "Inbox" }) {
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

    private func makeBoardProject(project: ProjectRecord, tasks: [ProjectBoardTask]) -> ProjectBoardProject {
        let projectTasks = tasks.filter { $0.projectID == project.id }
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
        return ProjectBoardProject(id: project.id, title: project.title, status: project.status, subtitle: subtitle, columns: columns)
    }

    private func makeBoardTask(_ record: TaskRecord, fallbackProjectID: Int64? = nil) throws -> ProjectBoardTask? {
        guard let projectID = record.projectID ?? fallbackProjectID else {
            return nil
        }

        return ProjectBoardTask(
            id: record.id,
            projectID: projectID,
            title: record.title,
            detail: record.detail ?? "",
            status: ProjectTaskStatus.normalized(record.status),
            priority: try ProjectTaskPriority.normalized(record.priority, column: "tasks.priority"),
            dueAt: record.dueAt
        )
    }
}

@MainActor
public final class ProjectBoardViewModel: ObservableObject {
    @Published public private(set) var snapshot: ProjectBoardSnapshot
    @Published public var selectedProjectID: Int64?
    @Published public var selectedTaskID: Int64?
    @Published public private(set) var showsArchivedProjects: Bool
    @Published public private(set) var errorMessage: String?

    private let store: any ProjectBoardStore
    private let onChange: () -> Void

    public init(
        store: any ProjectBoardStore,
        snapshot: ProjectBoardSnapshot = .empty,
        onChange: @escaping () -> Void = {}
    ) {
        self.store = store
        self.snapshot = snapshot
        self.onChange = onChange
        self.selectedProjectID = snapshot.projects.first?.id
        self.showsArchivedProjects = false
    }

    public var selectedProject: ProjectBoardProject? {
        snapshot.projects.first { $0.id == selectedProjectID } ?? snapshot.projects.first
    }

    public var selectedTask: ProjectBoardTask? {
        guard let selectedTaskID else {
            return nil
        }

        return snapshot.projects
            .flatMap(\.tasks)
            .first { $0.id == selectedTaskID }
    }

    public var isEmptyProjectStateVisible: Bool {
        errorMessage == nil && selectedProject == nil
    }

    public func load() {
        do {
            snapshot = try store.loadSnapshot(includeArchived: showsArchivedProjects)
            if selectedProjectID == nil || !snapshot.projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = snapshot.projects.first?.id
            }
            if selectedTaskID != nil, selectedTask == nil {
                self.selectedTaskID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func setShowsArchivedProjects(_ isShown: Bool) {
        showsArchivedProjects = isShown
        load()
    }

    @discardableResult
    public func createTask(
        title: String,
        detail: String = "",
        projectID: Int64? = nil,
        status: ProjectTaskStatus = .backlog,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) -> ProjectBoardTask? {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return nil
        }

        do {
            let task = try store.createTask(ProjectBoardTaskDraft(
                projectID: targetProjectID,
                title: title,
                detail: detail,
                status: status,
                priority: priority,
                dueAt: dueAt
            ))
            selectedProjectID = targetProjectID
            selectedTaskID = task.id
            load()
            selectedTaskID = task.id
            onChange()
            return task
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before adding tasks."
            return nil
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
            return nil
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }

    @discardableResult
    public func createProject(title: String = "Untitled Project") -> ProjectBoardProject? {
        do {
            let project = try store.createProject(title: title)
            load()
            selectedProjectID = project.id
            selectedTaskID = nil
            onChange()
            return project
        } catch ProjectBoardStoreError.emptyProjectTitle {
            errorMessage = "Project title is required."
            return nil
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }

    public func updateSelectedProject(title: String) {
        guard let selectedProjectID else {
            return
        }

        do {
            _ = try store.updateProject(id: selectedProjectID, title: title)
            load()
            self.selectedProjectID = selectedProjectID
            onChange()
        } catch ProjectBoardStoreError.emptyProjectTitle {
            errorMessage = "Project title is required."
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func completeSelectedProject() {
        guard let selectedProjectID else {
            return
        }

        do {
            _ = try store.completeProject(id: selectedProjectID)
            load()
            self.selectedProjectID = selectedProjectID
            onChange()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func archiveSelectedProject() {
        guard let selectedProjectID else {
            return
        }

        do {
            _ = try store.archiveProject(id: selectedProjectID)
            self.selectedProjectID = nil
            selectedTaskID = nil
            load()
            onChange()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func restoreSelectedProject() {
        guard let selectedProjectID else {
            return
        }

        do {
            _ = try store.restoreProject(id: selectedProjectID)
            load()
            self.selectedProjectID = selectedProjectID
            onChange()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func updateSelectedTask(
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?
    ) {
        guard let selectedTask else {
            return
        }

        do {
            _ = try store.updateTask(
                id: selectedTask.id,
                ProjectBoardTaskDraft(
                    projectID: selectedTask.projectID,
                    title: title,
                    detail: detail,
                    status: status,
                    priority: priority,
                    dueAt: dueAt
                )
            )
            load()
            selectedTaskID = selectedTask.id
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func moveSelectedTask(to status: ProjectTaskStatus) {
        guard let selectedTask else {
            return
        }

        moveTask(id: selectedTask.id, to: status)
    }

    public func moveTask(id: Int64, to status: ProjectTaskStatus) {
        do {
            let task = try store.moveTask(id: id, to: status)
            selectedProjectID = task.projectID
            load()
            selectedProjectID = task.projectID
            selectedTaskID = id
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
        } catch {
            errorMessage = String(describing: error)
        }
    }

    @discardableResult
    public func moveDroppedTasks(ids rawIDs: [String], to status: ProjectTaskStatus) -> Bool {
        guard !rawIDs.isEmpty else {
            return false
        }

        var taskIDs: [Int64] = []
        for rawID in rawIDs {
            guard let taskID = Int64(rawID) else {
                errorMessage = "Could not move task: invalid drag payload."
                return false
            }
            taskIDs.append(taskID)
        }

        return moveDroppedTasks(ids: taskIDs, to: status)
    }

    @discardableResult
    public func moveDroppedTasks(ids taskIDs: [Int64], to status: ProjectTaskStatus) -> Bool {
        guard !taskIDs.isEmpty else {
            return false
        }

        let visibleTaskIDs = Set(snapshot.projects.flatMap(\.tasks).map(\.id))
        guard taskIDs.allSatisfy({ visibleTaskIDs.contains($0) }) else {
            errorMessage = "Could not move task: task is no longer available."
            return false
        }

        do {
            let movedTasks = try store.moveTasks(ids: taskIDs, to: status)
            load()
            if let lastMovedTask = movedTasks.last {
                selectedProjectID = lastMovedTask.projectID
                selectedTaskID = lastMovedTask.id
            }
            onChange()
            return true
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
            return false
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }

    public func deleteSelectedTask() {
        guard let selectedTaskID else {
            return
        }

        do {
            try store.deleteTask(id: selectedTaskID)
            self.selectedTaskID = nil
            load()
            onChange()
        } catch {
            errorMessage = String(describing: error)
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
