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

    public static func normalized(_ rawPriority: String?) -> ProjectTaskPriority {
        guard let rawPriority else {
            return .medium
        }

        return ProjectTaskPriority(rawValue: rawPriority.lowercased()) ?? .medium
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
    public var subtitle: String
    public var columns: [ProjectBoardColumn]

    public init(id: Int64, title: String, subtitle: String, columns: [ProjectBoardColumn]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.columns = columns
    }

    public var taskCount: Int {
        columns.reduce(0) { $0 + $1.tasks.count }
    }

    public var tasks: [ProjectBoardTask] {
        columns.flatMap(\.tasks)
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
}

public protocol ProjectBoardStore {
    func loadSnapshot() throws -> ProjectBoardSnapshot
    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
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
        let projects = try ensureProjects()
        let tasks = try taskStore.listAll().compactMap(makeBoardTask)

        let boardProjects = projects.map { project in
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
            return ProjectBoardProject(id: project.id, title: project.title, subtitle: subtitle, columns: columns)
        }

        return ProjectBoardSnapshot(projects: boardProjects)
    }

    @discardableResult
    public func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        let normalized = try normalizedDraft(draft)
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

    private func ensureProjects() throws -> [ProjectRecord] {
        let projects = try projectStore.list()
        if !projects.isEmpty {
            return projects
        }

        _ = try projectStore.create(title: "Inbox", tags: ["local"], sourceCommand: "app.project-board")
        return try projectStore.list()
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

    private func makeBoardTask(_ record: TaskRecord) -> ProjectBoardTask? {
        guard let projectID = record.projectID else {
            return nil
        }

        return ProjectBoardTask(
            id: record.id,
            projectID: projectID,
            title: record.title,
            detail: record.detail ?? "",
            status: ProjectTaskStatus.normalized(record.status),
            priority: ProjectTaskPriority.normalized(record.priority),
            dueAt: record.dueAt
        )
    }
}

public final class InMemoryProjectBoardStore: ProjectBoardStore, @unchecked Sendable {
    private var snapshot: ProjectBoardSnapshot
    private var nextTaskID: Int64

    public init(snapshot: ProjectBoardSnapshot = ProjectBoardSnapshot(projects: [
        ProjectBoardProject(
            id: 1,
            title: "Inbox",
            subtitle: "0 open / 0 total",
            columns: ProjectTaskStatus.allCases.map { ProjectBoardColumn(status: $0, tasks: []) }
        )
    ])) {
        self.snapshot = snapshot
        self.nextTaskID = snapshot.projects.flatMap(\.tasks).map(\.id).max().map { $0 + 1 } ?? 1
    }

    public func loadSnapshot() throws -> ProjectBoardSnapshot {
        snapshot
    }

    @discardableResult
    public func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ProjectBoardStoreError.emptyTitle
        }

        let task = ProjectBoardTask(
            id: nextTaskID,
            projectID: draft.projectID,
            title: title,
            detail: draft.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            status: draft.status,
            priority: draft.priority,
            dueAt: draft.dueAt
        )
        nextTaskID += 1
        upsert(task)
        return task
    }

    @discardableResult
    public func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ProjectBoardStoreError.emptyTitle
        }

        let task = ProjectBoardTask(
            id: id,
            projectID: draft.projectID,
            title: title,
            detail: draft.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            status: draft.status,
            priority: draft.priority,
            dueAt: draft.dueAt
        )
        upsert(task)
        return task
    }

    private func upsert(_ task: ProjectBoardTask) {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == task.projectID }) else {
            return
        }

        for columnIndex in snapshot.projects[projectIndex].columns.indices {
            snapshot.projects[projectIndex].columns[columnIndex].tasks.removeAll { $0.id == task.id }
        }

        guard let columnIndex = snapshot.projects[projectIndex].columns.firstIndex(where: { $0.status == task.status }) else {
            return
        }

        snapshot.projects[projectIndex].columns[columnIndex].tasks.insert(task, at: 0)
        refreshProjectSubtitle(at: projectIndex)
    }

    private func refreshProjectSubtitle(at projectIndex: Int) {
        let tasks = snapshot.projects[projectIndex].tasks
        let openCount = tasks.filter { $0.status != .done }.count
        snapshot.projects[projectIndex].subtitle = "\(openCount) open / \(tasks.count) total"
    }
}

@MainActor
public final class ProjectBoardViewModel: ObservableObject {
    @Published public private(set) var snapshot: ProjectBoardSnapshot
    @Published public var selectedProjectID: Int64?
    @Published public var selectedTaskID: Int64?
    @Published public private(set) var errorMessage: String?

    private let store: any ProjectBoardStore

    public init(store: any ProjectBoardStore, snapshot: ProjectBoardSnapshot = .empty) {
        self.store = store
        self.snapshot = snapshot
        self.selectedProjectID = snapshot.projects.first?.id
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

    public func load() {
        do {
            snapshot = try store.loadSnapshot()
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
            return task
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
            return nil
        } catch {
            errorMessage = String(describing: error)
            return nil
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
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
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
