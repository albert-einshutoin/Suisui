import Combine
import Foundation

public enum ProjectTaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
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

public enum ProjectTaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
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
    public var artifacts: [ProjectBoardArtifact]

    public init(
        id: Int64,
        title: String,
        status: String = "active",
        subtitle: String,
        columns: [ProjectBoardColumn],
        artifacts: [ProjectBoardArtifact] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.subtitle = subtitle
        self.columns = columns
        self.artifacts = artifacts
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

public struct ProjectBoardArtifact: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64?
    public var taskID: Int64?
    public var expectedPath: String
    public var createdState: ArtifactCreatedState
    public var lastModifiedAt: Date?

    public init(
        id: Int64,
        projectID: Int64?,
        taskID: Int64?,
        expectedPath: String,
        createdState: ArtifactCreatedState,
        lastModifiedAt: Date?
    ) {
        self.id = id
        self.projectID = projectID
        self.taskID = taskID
        self.expectedPath = expectedPath
        self.createdState = createdState
        self.lastModifiedAt = lastModifiedAt
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

public struct TodayTimeBlock: Identifiable, Equatable, Sendable {
    public var id: String { "\(task.id)-\(label)" }
    public var label: String
    public var task: ProjectBoardTask

    public init(label: String, task: ProjectBoardTask) {
        self.label = label
        self.task = task
    }
}

public struct TodayWorkflowPlan: Equatable, Sendable {
    public var tasks: [ProjectBoardTask]
    public var overdueCount: Int
    public var dueTodayCount: Int
    public var recommendedTask: ProjectBoardTask?
    public var recommendationReason: String
    public var timeBlocks: [TodayTimeBlock]

    public init(
        tasks: [ProjectBoardTask],
        overdueCount: Int,
        dueTodayCount: Int,
        recommendedTask: ProjectBoardTask?,
        recommendationReason: String,
        timeBlocks: [TodayTimeBlock]
    ) {
        self.tasks = tasks
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.recommendedTask = recommendedTask
        self.recommendationReason = recommendationReason
        self.timeBlocks = timeBlocks
    }
}

public struct InboxClassificationFeedback: Equatable, Sendable {
    public var message: String
    public var systemImage: String
    public var canUndo: Bool

    public init(message: String, systemImage: String, canUndo: Bool) {
        self.message = message
        self.systemImage = systemImage
        self.canUndo = canUndo
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
    case emptyArtifactPath
    case nonAbsoluteArtifactPath
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
    func deleteProject(id: Int64) throws
    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask
    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask
    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask]
    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask]
    func deleteTask(id: Int64) throws
    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact
    func deleteProjectArtifact(id: Int64) throws
}

public final class SQLiteProjectBoardStore: ProjectBoardStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let artifactStore: SQLiteArtifactStore

    public init(connection: SQLiteConnection) {
        self.connection = connection
        self.projectStore = SQLiteProjectStore(connection: connection)
        self.taskStore = SQLiteTaskStore(connection: connection)
        self.artifactStore = SQLiteArtifactStore(connection: connection)
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

        let boardProjects = boardData.projects.map {
            makeBoardProject(project: $0, tasks: boardData.tasks, artifacts: boardData.artifacts)
        }

        return ProjectBoardSnapshot(projects: boardProjects)
    }

    @discardableResult
    public func createProject(title: String) throws -> ProjectBoardProject {
        let normalizedTitle = try normalizedProjectTitle(title)
        let record = try projectStore.create(title: normalizedTitle, tags: ["local"], sourceCommand: "app.project-board")
        return makeBoardProject(project: record, tasks: [], artifacts: [])
    }

    @discardableResult
    public func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        let normalizedTitle = try normalizedProjectTitle(title)
        let record = try projectStore.updateTitleForProjectBoard(id: id, title: normalizedTitle)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts)
    }

    @discardableResult
    public func completeProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.completeForProjectBoard(id: id, taskStore: taskStore)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts)
    }

    @discardableResult
    public func archiveProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.updateStatusForProjectBoard(id: id, status: "archived")
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts)
    }

    @discardableResult
    public func restoreProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.updateStatusForProjectBoard(id: id, status: "active")
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts)
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
        artifacts: [ProjectBoardArtifact]
    ) {
        var projects = try ensureProjects(includeArchived: includeArchived)
        let taskRecords = try taskStore.listAll()
        let artifacts = try artifactStore.list().map(makeBoardArtifact(_:))
        let fallbackProjectID: Int64?

        if taskRecords.contains(where: { $0.projectID == nil }) {
            fallbackProjectID = try ensureActiveInboxProject().id
            projects = try projectStore.listForProjectBoard(includeArchived: includeArchived)
        } else {
            fallbackProjectID = nil
        }

        let tasks = try taskRecords.map { record in
            try makeBoardTask(record, fallbackProjectID: fallbackProjectID).requiredTask()
        }
        return (projects, tasks, artifacts)
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

    private func makeBoardProject(
        project: ProjectRecord,
        tasks: [ProjectBoardTask],
        artifacts: [ProjectBoardArtifact]
    ) -> ProjectBoardProject {
        let projectTasks = tasks.filter { $0.projectID == project.id }
        let projectTaskIDs = Set(projectTasks.map(\.id))
        let projectArtifacts = artifacts.filter { artifact in
            artifact.projectID == project.id || artifact.taskID.map { projectTaskIDs.contains($0) } == true
        }
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
            columns: columns,
            artifacts: projectArtifacts
        )
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
}

@MainActor
public final class ProjectBoardViewModel: ObservableObject {
    @Published public private(set) var snapshot: ProjectBoardSnapshot
    @Published public var selectedProjectID: Int64?
    @Published public var selectedTaskID: Int64?
    @Published public private(set) var showsArchivedProjects: Bool
    @Published public private(set) var showsCompletedWorkflowTasks: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var integrationStatusMessage: String?
    @Published public private(set) var inboxClassificationFeedback: InboxClassificationFeedback?

    private let store: any ProjectBoardStore
    private let externalTaskLinkStore: (any ExternalTaskLinkStore)?
    private let onChange: () -> Void
    private var lastInboxClassificationUndo: InboxClassificationUndo?

    public init(
        store: any ProjectBoardStore,
        externalTaskLinkStore: (any ExternalTaskLinkStore)? = nil,
        snapshot: ProjectBoardSnapshot = .empty,
        onChange: @escaping () -> Void = {}
    ) {
        self.store = store
        self.externalTaskLinkStore = externalTaskLinkStore
        self.snapshot = snapshot
        self.onChange = onChange
        self.selectedProjectID = snapshot.projects.first?.id
        self.showsArchivedProjects = false
        self.showsCompletedWorkflowTasks = false
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

    public var inboxTasks: [ProjectBoardTask] {
        inboxProject?
            .tasks
            .filter { showsCompletedWorkflowTasks || $0.status != .done }
            .sorted { $0.id > $1.id } ?? []
    }

    public var completedInboxTaskCount: Int {
        inboxProject?.tasks.filter { $0.status == .done }.count ?? 0
    }

    public var inboxProject: ProjectBoardProject? {
        snapshot.projects
            .first { $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived }
    }

    public func todayTasks(on referenceDate: Date = Date(), calendar: Calendar = .current) -> [ProjectBoardTask] {
        guard let endOfToday = calendar.dateInterval(of: .day, for: referenceDate)?.end else {
            return []
        }

        return snapshot.projects
            .filter { !$0.isArchived }
            .flatMap(\.tasks)
            .filter { task in
                (showsCompletedWorkflowTasks || task.status != .done)
                    && dueDate(for: task.dueAt).map { $0 < endOfToday } == true
            }
            .sorted { lhs, rhs in
                switch (dueDate(for: lhs.dueAt), dueDate(for: rhs.dueAt)) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.id > rhs.id
                    }
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id > rhs.id
                }
            }
    }

    public func todayPlan(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayWorkflowPlan {
        let tasks = todayTasks(on: referenceDate, calendar: calendar)
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let dayStart = dayInterval?.start ?? referenceDate
        let overdueCount = tasks.filter { task in
            dueDate(for: task.dueAt).map { $0 < dayStart } == true
        }.count
        let dueTodayCount = tasks.filter { task in
            guard let dayInterval, let dueDate = dueDate(for: task.dueAt) else {
                return false
            }
            return dueDate >= dayInterval.start && dueDate < dayInterval.end
        }.count
        let recommendedTask = recommendedTodayTask(from: tasks, on: referenceDate, calendar: calendar)

        return TodayWorkflowPlan(
            tasks: tasks,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            recommendedTask: recommendedTask,
            recommendationReason: recommendationReason(for: recommendedTask, on: referenceDate, calendar: calendar),
            timeBlocks: timeBlocks(for: orderedTimeBlockTasks(tasks, recommendedTask: recommendedTask), startingAt: referenceDate, calendar: calendar)
        )
    }

    public func projectTitle(for task: ProjectBoardTask) -> String {
        snapshot.projects.first { $0.id == task.projectID }?.title ?? "Unknown Project"
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
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        userFacingMessage(for: error, fallback: "Project board unavailable")
    }

    private static func userFacingMessage(for error: Error, fallback: String) -> String {
        guard let decodingError = error as? LocalStoreDecodingError else {
            return UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: fallback
            )
        }

        return repairGuidance(for: decodingError)
    }

    private static func repairGuidance(for error: LocalStoreDecodingError) -> String {
        let action = "Restore from backup or repair the local database, then reopen SoloPM."
        switch error {
        case .invalidStringArray(let column):
            return "Local board data needs repair: \(column) contains invalid list JSON. \(action)"
        case .invalidDoubleArray(let column):
            return "Local board data needs repair: \(column) contains invalid numeric vector JSON. \(action)"
        case .invalidStringMap(let column):
            return "Local board data needs repair: \(column) contains invalid key-value JSON. \(action)"
        case .inconsistentDimensions(let column, let expected, let actual):
            return "Local board data needs repair: \(column) has \(actual) values, expected \(expected). \(action)"
        case .missingRequiredColumn(let column):
            return "Local board data needs repair: \(column) is missing. \(action)"
        case .invalidInt64(let column, let value):
            return "Local board data needs repair: \(column) contains invalid integer value \(quotedDisplayValue(value)). \(action)"
        case .invalidEnum(let column, let value):
            return "Local board data needs repair: \(column) contains unsupported value \(quotedDisplayValue(value)). \(action)"
        case .invalidDate(let column, let value):
            return "Local board data needs repair: \(column) contains invalid date value \(quotedDisplayValue(value)). \(action)"
        }
    }

    private static func quotedDisplayValue(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let maxVisibleCharacters = 80
        guard normalized.count > maxVisibleCharacters else {
            return "\"\(normalized)\""
        }
        return "\"\(String(normalized.prefix(maxVisibleCharacters)))...\""
    }

    public func setShowsArchivedProjects(_ isShown: Bool) {
        showsArchivedProjects = isShown
        load()
    }

    public func setShowsCompletedWorkflowTasks(_ isShown: Bool) {
        showsCompletedWorkflowTasks = isShown
        load()
    }

    public func exportTaskInteropJSON(exportedAt: Date = Date()) -> Data? {
        do {
            let data = try TaskInteropExportService(store: store).exportJSON(exportedAt: exportedAt)
            integrationStatusMessage = "Prepared task export JSON."
            errorMessage = nil
            return data
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func importTaskInteropJSON(_ data: Data) -> ExternalTaskImportResult? {
        guard let externalTaskLinkStore else {
            errorMessage = "Task import is unavailable in this build."
            return nil
        }

        do {
            let document = try TaskInteropDocument.decode(data)
            let result = try TaskInteropDocumentImportService(
                store: store,
                linkStore: externalTaskLinkStore
            ).importDocument(document)
            load()
            integrationStatusMessage = Self.importStatusMessage(for: result)
            errorMessage = nil
            onChange()
            return result
        } catch {
            errorMessage = Self.userFacingMessage(
                for: error,
                fallback: "Task import failed. Choose a SoloPM task JSON export."
            )
            return nil
        }
    }

    public func recordTaskInteropFileFailure(_ error: Error) {
        errorMessage = Self.userFacingMessage(
            for: error,
            fallback: "Task import/export failed."
        )
    }

    public func recordTaskInteropExportCompleted() {
        integrationStatusMessage = String(localized: "Exported task JSON.")
        errorMessage = nil
    }

    private static func importStatusMessage(for result: ExternalTaskImportResult) -> String {
        let taskLabel = String(
            format: String(localized: result.createdTaskCount == 1 ? "%d task" : "%d tasks"),
            result.createdTaskCount
        )
        if result.skippedDuplicateCount > 0 {
            let skippedLabel = String(
                format: String(localized: result.skippedDuplicateCount == 1 ? "%d duplicate" : "%d duplicates"),
                result.skippedDuplicateCount
            )
            return String(
                format: String(localized: "Imported %@ from JSON. Skipped %@."),
                taskLabel,
                skippedLabel
            )
        }
        return String(format: String(localized: "Imported %@ from JSON."), taskLabel)
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
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func createInboxTask(
        title: String,
        detail: String = "",
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) -> ProjectBoardTask? {
        do {
            let liveSnapshot = try store.loadSnapshot(includeArchived: false)
            snapshot = liveSnapshot
            let inboxProject: ProjectBoardProject
            if let activeInbox = liveSnapshot.projects.first(where: {
                $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived
            }) {
                inboxProject = activeInbox
            } else {
                inboxProject = try store.createProject(title: "Inbox")
            }
            let task = try store.createTask(ProjectBoardTaskDraft(
                projectID: inboxProject.id,
                title: title,
                detail: detail,
                status: .backlog,
                priority: priority,
                dueAt: dueAt
            ))
            selectedProjectID = inboxProject.id
            selectedTaskID = task.id
            load()
            selectedProjectID = inboxProject.id
            selectedTaskID = task.id
            errorMessage = nil
            onChange()
            return task
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
            return nil
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before adding tasks."
            return nil
        } catch ProjectBoardStoreError.emptyProjectTitle {
            errorMessage = "Project title is required."
            return nil
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func deleteSelectedProject() {
        guard let selectedProjectID else {
            return
        }

        do {
            try store.deleteProject(id: selectedProjectID)
            self.selectedProjectID = nil
            selectedTaskID = nil
            load()
            onChange()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func markSelectedTaskAsTask() {
        guard let selectedTask else {
            return
        }

        applyInboxTaskUpdate(
            originalTask: selectedTask,
            draft: ProjectBoardTaskDraft(
                projectID: selectedTask.projectID,
                title: selectedTask.title,
                detail: selectedTask.detail,
                status: .backlog,
                priority: selectedTask.priority,
                dueAt: selectedTask.dueAt
            ),
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Kept \"%@\" as a task."), selectedTask.title),
                systemImage: "checkmark.circle",
                canUndo: true
            )
        )
    }

    public func convertSelectedTaskToProject() {
        guard let selectedTask else {
            return
        }

        var createdProjectID: Int64?
        do {
            let project = try store.createProject(title: selectedTask.title)
            createdProjectID = project.id
            let movedTask = try store.updateTask(
                id: selectedTask.id,
                ProjectBoardTaskDraft(
                    projectID: project.id,
                    title: selectedTask.title,
                    detail: selectedTask.detail,
                    status: .planned,
                    priority: selectedTask.priority,
                    dueAt: selectedTask.dueAt
                )
            )
            finishInboxClassification(
                originalTask: selectedTask,
                fallbackTask: movedTask,
                feedback: InboxClassificationFeedback(
                    message: String(format: String(localized: "Created project \"%@\"."), selectedTask.title),
                    systemImage: "folder.badge.plus",
                    canUndo: true
                ),
                undo: .restoreTaskAndDeleteProject(originalTask: selectedTask, createdProjectID: project.id)
            )
            onChange()
        } catch ProjectBoardStoreError.emptyProjectTitle {
            errorMessage = "Project title is required."
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            if let createdProjectID {
                try? store.deleteProject(id: createdProjectID)
            }
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            if let createdProjectID {
                try? store.deleteProject(id: createdProjectID)
            }
            errorMessage = "Task title is required."
        } catch {
            if let createdProjectID {
                try? store.deleteProject(id: createdProjectID)
            }
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func scheduleSelectedTaskForToday(referenceDate: Date = Date()) {
        guard let selectedTask else {
            return
        }

        applyInboxTaskUpdate(
            originalTask: selectedTask,
            draft: ProjectBoardTaskDraft(
                projectID: selectedTask.projectID,
                title: selectedTask.title,
                detail: selectedTask.detail,
                status: .planned,
                priority: selectedTask.priority,
                dueAt: ISO8601DateFormatter().string(from: referenceDate)
            ),
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Scheduled \"%@\" for today."), selectedTask.title),
                systemImage: "calendar.badge.plus",
                canUndo: true
            )
        )
    }

    public func deferSelectedTaskForLater() {
        guard let selectedTask else {
            return
        }

        applyInboxTaskUpdate(
            originalTask: selectedTask,
            draft: ProjectBoardTaskDraft(
                projectID: selectedTask.projectID,
                title: selectedTask.title,
                detail: selectedTask.detail,
                status: .backlog,
                priority: selectedTask.priority,
                dueAt: nil
            ),
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Deferred \"%@\" for later review."), selectedTask.title),
                systemImage: "clock",
                canUndo: true
            )
        )
    }

    public func undoLastInboxClassification() {
        guard let undo = lastInboxClassificationUndo else {
            return
        }

        do {
            let restoredTask: ProjectBoardTask
            switch undo {
            case .restoreTask(let originalTask):
                restoredTask = try store.updateTask(id: originalTask.id, originalTask.classificationDraft)
            case .restoreTaskAndDeleteProject(let originalTask, let createdProjectID):
                let recreatedTask = try store.createTask(originalTask.classificationDraft)
                do {
                    try store.deleteProject(id: createdProjectID)
                } catch {
                    try? store.deleteTask(id: recreatedTask.id)
                    throw error
                }
                restoredTask = recreatedTask
            }
            load()
            selectedProjectID = restoredTask.projectID
            selectedTaskID = restoredTask.id
            inboxClassificationFeedback = nil
            lastInboxClassificationUndo = nil
            errorMessage = nil
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before undoing the classification."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func toggleTaskCompletion(id: Int64) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == id }) else {
            errorMessage = "Task is no longer available."
            return
        }

        let previousProjectID = selectedProjectID
        let previousTaskID = selectedTaskID

        do {
            _ = try store.moveTask(id: id, to: task.status == .done ? .planned : .done)
            load()
            selectedProjectID = previousProjectID
            selectedTaskID = previousTaskID
            errorMessage = nil
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func moveDroppedTasks(ids rawIDs: [String], toProjectID projectID: Int64) -> Bool {
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

        return moveDroppedTasks(ids: taskIDs, toProjectID: projectID)
    }

    @discardableResult
    public func moveDroppedTasks(ids taskIDs: [Int64], toProjectID projectID: Int64) -> Bool {
        guard !taskIDs.isEmpty else {
            return false
        }
        guard snapshot.projects.contains(where: { $0.id == projectID }) else {
            errorMessage = "Could not move task: project is no longer available."
            return false
        }
        let visibleTaskIDs = Set(snapshot.projects.flatMap(\.tasks).map(\.id))
        guard taskIDs.allSatisfy({ visibleTaskIDs.contains($0) }) else {
            errorMessage = "Could not move task: task is no longer available."
            return false
        }

        do {
            let movedTasks = try store.moveTasks(ids: taskIDs, toProjectID: projectID)
            load()
            selectedProjectID = projectID
            selectedTaskID = movedTasks.last?.id
            integrationStatusMessage = movedTasks.count == 1
                ? String(localized: "Moved task to project.")
                : String(format: String(localized: "Moved %d tasks to project."), movedTasks.count)
            errorMessage = nil
            onChange()
            return true
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
            return false
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
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
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    @discardableResult
    public func createProjectArtifact(expectedPath: String, projectID: Int64? = nil) -> ProjectBoardArtifact? {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return nil
        }

        do {
            let artifact = try store.createProjectArtifact(projectID: targetProjectID, expectedPath: expectedPath)
            load()
            selectedProjectID = targetProjectID
            errorMessage = nil
            onChange()
            return artifact
        } catch ProjectBoardStoreError.emptyArtifactPath {
            errorMessage = "Artifact path is required."
            return nil
        } catch ProjectBoardStoreError.nonAbsoluteArtifactPath {
            errorMessage = "Use an absolute artifact path."
            return nil
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptArtifacts {
            errorMessage = "Restore the project before linking artifacts."
            return nil
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func deleteProjectArtifact(id: Int64, projectID: Int64? = nil) -> Bool {
        do {
            try store.deleteProjectArtifact(id: id)
            let targetProjectID = projectID ?? selectedProjectID
            load()
            selectedProjectID = targetProjectID
            errorMessage = nil
            onChange()
            return true
        } catch ArtifactStoreError.notFound {
            errorMessage = "Artifact link is no longer available."
            return false
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    private func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) {
        do {
            let updatedTask = try store.updateTask(id: id, draft)
            load()
            selectedProjectID = updatedTask.projectID
            selectedTaskID = updatedTask.id
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func applyInboxTaskUpdate(
        originalTask: ProjectBoardTask,
        draft: ProjectBoardTaskDraft,
        feedback: InboxClassificationFeedback
    ) {
        do {
            let updatedTask = try store.updateTask(id: originalTask.id, draft)
            finishInboxClassification(
                originalTask: originalTask,
                fallbackTask: updatedTask,
                feedback: feedback,
                undo: .restoreTask(originalTask: originalTask)
            )
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func finishInboxClassification(
        originalTask: ProjectBoardTask,
        fallbackTask: ProjectBoardTask,
        feedback: InboxClassificationFeedback,
        undo: InboxClassificationUndo
    ) {
        let shouldAdvanceInboxSelection = inboxProject?.id == originalTask.projectID
        load()
        selectedProjectID = fallbackTask.projectID
        selectedTaskID = fallbackTask.id

        if shouldAdvanceInboxSelection, let nextInboxTask = inboxTasks.first(where: { $0.id != originalTask.id }) {
            selectedProjectID = nextInboxTask.projectID
            selectedTaskID = nextInboxTask.id
        }

        inboxClassificationFeedback = feedback
        lastInboxClassificationUndo = undo
        errorMessage = nil
    }

    private func dueDate(for rawDueAt: String?) -> Date? {
        guard let rawDueAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawDueAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawDueAt)
    }

    private func recommendedTodayTask(
        from tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> ProjectBoardTask? {
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let overdueTasks = tasks.filter { task in
            dueDate(for: task.dueAt).map { $0 < dayStart } == true
        }
        if let highPriorityOverdue = overdueTasks.first(where: { $0.priority == .high }) {
            return highPriorityOverdue
        }
        if let overdueTask = overdueTasks.first {
            return overdueTask
        }
        if let highPriorityTask = tasks.first(where: { $0.priority == .high }) {
            return highPriorityTask
        }
        return tasks.first
    }

    private func recommendationReason(
        for task: ProjectBoardTask?,
        on referenceDate: Date,
        calendar: Calendar
    ) -> String {
        guard let task else {
            return "No due work is scheduled for today."
        }

        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let isOverdue = dueDate(for: task.dueAt).map { $0 < dayStart } == true
        if isOverdue && task.priority == .high {
            return "Overdue high-priority work should be cleared first."
        }
        if isOverdue {
            return "Overdue work should be cleared before new tasks."
        }
        if task.priority == .high {
            return "High-priority work is the best first task."
        }
        return "Earliest due task keeps today on track."
    }

    private func orderedTimeBlockTasks(
        _ tasks: [ProjectBoardTask],
        recommendedTask: ProjectBoardTask?
    ) -> [ProjectBoardTask] {
        guard let recommendedTask else {
            return tasks
        }

        return [recommendedTask] + tasks.filter { $0.id != recommendedTask.id }
    }

    private func timeBlocks(
        for tasks: [ProjectBoardTask],
        startingAt referenceDate: Date,
        calendar: Calendar
    ) -> [TodayTimeBlock] {
        let firstBlockStart = roundedTimeBlockStart(from: referenceDate, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"

        return tasks.prefix(4).enumerated().compactMap { offset, task in
            guard let start = calendar.date(byAdding: .minute, value: offset * 30, to: firstBlockStart),
                  let end = calendar.date(byAdding: .minute, value: 30, to: start) else {
                return nil
            }
            return TodayTimeBlock(label: "\(formatter.string(from: start))-\(formatter.string(from: end))", task: task)
        }
    }

    private func roundedTimeBlockStart(from referenceDate: Date, calendar: Calendar) -> Date {
        guard let hourStart = calendar.dateInterval(of: .hour, for: referenceDate)?.start else {
            return referenceDate
        }

        let slotSeconds = 30.0 * 60.0
        let elapsed = referenceDate.timeIntervalSince(hourStart)
        let remainder = elapsed.truncatingRemainder(dividingBy: slotSeconds)
        let roundedElapsed = remainder == 0 ? elapsed : elapsed + (slotSeconds - remainder)
        return hourStart.addingTimeInterval(roundedElapsed)
    }
}

private enum InboxClassificationUndo {
    case restoreTask(originalTask: ProjectBoardTask)
    case restoreTaskAndDeleteProject(originalTask: ProjectBoardTask, createdProjectID: Int64)
}

private extension ProjectBoardTask {
    var classificationDraft: ProjectBoardTaskDraft {
        ProjectBoardTaskDraft(
            projectID: projectID,
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueAt: dueAt
        )
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
