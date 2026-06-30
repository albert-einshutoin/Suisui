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
    public var hasWorkspaceDirectory: Bool
    public var workspaceDisplayName: String?
    public var columns: [ProjectBoardColumn]
    public var artifacts: [ProjectBoardArtifact]
    public var milestones: [ProjectBoardMilestone]

    public init(
        id: Int64,
        title: String,
        status: String = "active",
        subtitle: String,
        hasWorkspaceDirectory: Bool = false,
        workspaceDisplayName: String? = nil,
        columns: [ProjectBoardColumn],
        artifacts: [ProjectBoardArtifact] = [],
        milestones: [ProjectBoardMilestone] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.subtitle = subtitle
        self.hasWorkspaceDirectory = hasWorkspaceDirectory
        self.workspaceDisplayName = workspaceDisplayName
        self.columns = columns
        self.artifacts = artifacts
        self.milestones = milestones
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

    public var milestoneSummary: String {
        let completedCount = milestones.filter(\.isCompleted).count
        return "\(completedCount)/\(milestones.count) milestones complete"
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

public struct ProjectBoardMilestone: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64
    public var title: String
    public var dueAt: String?
    public var isCompleted: Bool

    public init(id: Int64, projectID: Int64, title: String, dueAt: String?, isCompleted: Bool) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.dueAt = dueAt
        self.isCompleted = isCompleted
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
    public var completedAt: String?
    public var updatedAt: String?

    public init(
        id: Int64,
        projectID: Int64,
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?,
        completedAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }

    public var dueLabel: String? {
        dueAt
    }
}

public struct TaskAutomationDocumentSourceReview: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var redactedSummary: String
    public var inclusionReason: String

    public init(id: String, title: String, redactedSummary: String, inclusionReason: String) {
        let redactor = DeveloperSecretRedactor()
        self.id = redactor.redact(id).text
        self.title = redactor.redact(title).text
        self.redactedSummary = redactor.redact(redactedSummary).text
        self.inclusionReason = redactor.redact(inclusionReason).text
    }
}

public struct TaskAutomationDocumentDeliverableReview: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: DocumentAutomationOutputKind
    public var title: String
    public var suggestedPath: String
    public var sourceDocuments: [TaskAutomationDocumentSourceReview]
    public var rationale: String
    public var riskLevel: RiskLevel
    public var requiresApproval: Bool

    public init(
        kind: DocumentAutomationOutputKind,
        title: String,
        suggestedPath: String,
        sourceDocuments: [TaskAutomationDocumentSourceReview],
        rationale: String,
        riskLevel: RiskLevel,
        requiresApproval: Bool
    ) {
        let redactor = DeveloperSecretRedactor()
        self.kind = kind
        self.title = redactor.redact(title).text
        self.suggestedPath = redactor.redact(suggestedPath).text
        self.sourceDocuments = sourceDocuments
        self.rationale = redactor.redact(rationale).text
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
        self.id = [kind.rawValue, self.suggestedPath].joined(separator: ":")
    }
}

public struct TodayTimeBlock: Identifiable, Equatable, Sendable {
    public var id: String { "\(task.id)-\(label)" }
    public var label: String
    public var task: ProjectBoardTask
    public var startAt: String?
    public var endAt: String?

    public init(label: String, task: ProjectBoardTask, startAt: String? = nil, endAt: String? = nil) {
        self.label = label
        self.task = task
        self.startAt = startAt
        self.endAt = endAt
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

public enum TodayAssistantRailSource: String, Codable, Equatable, Sendable {
    case selected
    case recommended
    case empty
}

public struct TodayAssistantRailContext: Equatable, Sendable {
    public var source: TodayAssistantRailSource
    public var task: ProjectBoardTask?
    public var projectTitle: String
    public var nextActionTitle: String
    public var nextActionReason: String
    public var nextBlockLabel: String?
    public var notes: String
    public var subtaskSummary: String
    public var reminderSummary: String

    public init(
        source: TodayAssistantRailSource,
        task: ProjectBoardTask?,
        projectTitle: String,
        nextActionTitle: String,
        nextActionReason: String,
        nextBlockLabel: String?,
        notes: String,
        subtaskSummary: String,
        reminderSummary: String
    ) {
        self.source = source
        self.task = task
        self.projectTitle = projectTitle
        self.nextActionTitle = nextActionTitle
        self.nextActionReason = nextActionReason
        self.nextBlockLabel = nextBlockLabel
        self.notes = notes
        self.subtaskSummary = subtaskSummary
        self.reminderSummary = reminderSummary
    }
}

public enum TodayRecommendationKind: String, Codable, Equatable, Sendable {
    case blocker
    case overdue
    case highPriority
}

public struct TodayRecommendationChip: Identifiable, Equatable, Sendable {
    public var id: String { "\(kind.rawValue)-\(taskID)" }
    public var kind: TodayRecommendationKind
    public var taskID: Int64
    public var taskTitle: String
    public var title: String
    public var systemImage: String
    public var reason: String

    public init(
        kind: TodayRecommendationKind,
        taskID: Int64,
        taskTitle: String,
        title: String,
        systemImage: String,
        reason: String
    ) {
        self.kind = kind
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.title = title
        self.systemImage = systemImage
        self.reason = reason
    }
}

public struct TodayScheduleDraft: Equatable, Sendable {
    public var timeBlocks: [TodayTimeBlock]

    public init(timeBlocks: [TodayTimeBlock]) {
        self.timeBlocks = timeBlocks
    }
}

public struct ScheduleDraft: Equatable, Sendable {
    public var timeBlocks: [TodayTimeBlock]
    public var unscheduledTasks: [ProjectBoardTask]

    public init(timeBlocks: [TodayTimeBlock], unscheduledTasks: [ProjectBoardTask]) {
        self.timeBlocks = timeBlocks
        self.unscheduledTasks = unscheduledTasks
    }
}

public enum ScheduleApplyResult: Equatable, Sendable {
    case approvalRequired
    case calendarNotConfigured
    case noDraft
    case applied(eventCount: Int)
    case failed(String)
}

public enum ProjectPortfolioHealth: String, CaseIterable, Identifiable, Sendable {
    case onTrack
    case attention
    case atRisk
    case completed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onTrack:
            "On Track"
        case .attention:
            "Needs Attention"
        case .atRisk:
            "At Risk"
        case .completed:
            "Completed"
        }
    }
}

public struct ProjectPortfolioSummary: Identifiable, Equatable, Sendable {
    public var id: Int64 { projectID }
    public var projectID: Int64
    public var title: String
    public var status: String
    public var progress: Double
    public var openTaskCount: Int
    public var doneTaskCount: Int
    public var blockedTaskCount: Int
    public var overdueTaskCount: Int
    public var nextDueAt: String?
    public var recentTaskID: Int64?
    public var nextActionTitle: String
    public var health: ProjectPortfolioHealth
    public var riskReason: String
    public var localHealthRuleDescription: String

    public init(
        projectID: Int64,
        title: String,
        status: String,
        progress: Double,
        openTaskCount: Int,
        doneTaskCount: Int,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        nextDueAt: String?,
        recentTaskID: Int64?,
        nextActionTitle: String,
        health: ProjectPortfolioHealth,
        riskReason: String,
        localHealthRuleDescription: String
    ) {
        self.projectID = projectID
        self.title = title
        self.status = status
        self.progress = progress
        self.openTaskCount = openTaskCount
        self.doneTaskCount = doneTaskCount
        self.blockedTaskCount = blockedTaskCount
        self.overdueTaskCount = overdueTaskCount
        self.nextDueAt = nextDueAt
        self.recentTaskID = recentTaskID
        self.nextActionTitle = nextActionTitle
        self.health = health
        self.riskReason = riskReason
        self.localHealthRuleDescription = localHealthRuleDescription
    }
}

public struct DoneAnalyticsSummary: Equatable, Sendable {
    public var completedTaskCount: Int
    public var completedProjectCount: Int
    public var completedTodayCount: Int
    public var completedThisWeekCount: Int
    public var streakDays: Int
    public var recentTasks: [ProjectBoardTask]
    public var localRuleInsight: String

    public init(
        completedTaskCount: Int,
        completedProjectCount: Int,
        completedTodayCount: Int,
        completedThisWeekCount: Int,
        streakDays: Int,
        recentTasks: [ProjectBoardTask],
        localRuleInsight: String
    ) {
        self.completedTaskCount = completedTaskCount
        self.completedProjectCount = completedProjectCount
        self.completedTodayCount = completedTodayCount
        self.completedThisWeekCount = completedThisWeekCount
        self.streakDays = streakDays
        self.recentTasks = recentTasks
        self.localRuleInsight = localRuleInsight
    }
}

public struct ProjectAssistantAnswer: Equatable, Sendable {
    public var projectID: Int64
    public var question: String
    public var message: String
    public var suggestedActionTitle: String
    public var requiresReview: Bool

    public init(projectID: Int64, question: String, message: String, suggestedActionTitle: String, requiresReview: Bool) {
        self.projectID = projectID
        self.question = question
        self.message = message
        self.suggestedActionTitle = suggestedActionTitle
        self.requiresReview = requiresReview
    }
}

public struct ProjectAssistantReviewDraft: Equatable, Sendable {
    public var projectID: Int64
    public var suggestedActionTitle: String
    public var summary: String

    public init(projectID: Int64, suggestedActionTitle: String, summary: String) {
        self.projectID = projectID
        self.suggestedActionTitle = suggestedActionTitle
        self.summary = summary
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

public struct InboxTriageSummary: Equatable, Sendable {
    public var sourceLabel: String
    public var interpretationLabel: String
    public var systemImage: String
    public var tintName: String
    public var accessibilityValue: String

    public init(
        sourceLabel: String,
        interpretationLabel: String,
        systemImage: String,
        tintName: String,
        accessibilityValue: String
    ) {
        self.sourceLabel = sourceLabel
        self.interpretationLabel = interpretationLabel
        self.systemImage = systemImage
        self.tintName = tintName
        self.accessibilityValue = accessibilityValue
    }
}

public enum InboxTriageFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case voice
    case aiSuggested
    case manual
    case unprocessed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            "All"
        case .voice:
            "Voice"
        case .aiSuggested:
            "AI Suggested"
        case .manual:
            "Manual"
        case .unprocessed:
            "Unprocessed"
        }
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

        let boardProjects = boardData.projects.map {
            makeBoardProject(project: $0, tasks: boardData.tasks, artifacts: boardData.artifacts, milestones: boardData.milestones)
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
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts, milestones: boardData.milestones)
    }

    @discardableResult
    public func completeProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.completeForProjectBoard(id: id, taskStore: taskStore)
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts, milestones: boardData.milestones)
    }

    @discardableResult
    public func archiveProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.updateStatusForProjectBoard(id: id, status: "archived")
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts, milestones: boardData.milestones)
    }

    @discardableResult
    public func restoreProject(id: Int64) throws -> ProjectBoardProject {
        let record = try projectStore.updateStatusForProjectBoard(id: id, status: "active")
        let boardData = try loadBoardData(includeArchived: true)
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts, milestones: boardData.milestones)
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
        return makeBoardProject(project: record, tasks: boardData.tasks, artifacts: boardData.artifacts, milestones: boardData.milestones)
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
        tasks: [ProjectBoardTask],
        artifacts: [ProjectBoardArtifact],
        milestones: [ProjectBoardMilestone] = []
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
            hasWorkspaceDirectory: project.workspacePath != nil,
            workspaceDisplayName: workspaceDisplayName(for: project.workspacePath),
            columns: columns,
            artifacts: projectArtifacts,
            milestones: milestones.filter { $0.projectID == project.id }
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
    @Published public private(set) var inboxTriageFilter: InboxTriageFilter
    @Published public private(set) var todayCommandFeedback: String?
    @Published public private(set) var todayFocusTaskID: Int64?
    @Published public private(set) var todayScheduleDraft: TodayScheduleDraft?
    @Published public private(set) var dailyPlanningReview: DailyPlanningReview?
    @Published public private(set) var scheduleDraft: ScheduleDraft?
    @Published public private(set) var scheduleApplyResult: ScheduleApplyResult?
    @Published public private(set) var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus
    @Published public private(set) var projectAssistantAnswer: ProjectAssistantAnswer?
    @Published public private(set) var projectAssistantReviewDraft: ProjectAssistantReviewDraft?
    @Published public private(set) var taskAutomationReviewDecision: TaskAutoExecutionDecision?
    @Published public private(set) var taskAutomationDocumentDeliverableReviews: [TaskAutomationDocumentDeliverableReview]
    @Published public private(set) var lastApprovedAutomationExecutionReceipt: ApprovedAutomationExecutionReceipt?
    @Published public private(set) var approvedAutomationExecutionReceipts: [ApprovedAutomationExecutionReceipt]
    @Published public private(set) var assistantQueueSnapshot: AssistantQueueSnapshot
    @Published public private(set) var assistantQueueViewFilter: AssistantQueueViewFilter
    @Published public private(set) var assistantQueueSort: AssistantQueueSort
    @Published public private(set) var assistantQueueSelectedItemIDs: Set<String>
    @Published public private(set) var executionReceiptHistorySnapshot: ExecutionReceiptHistorySnapshot
    @Published public private(set) var executionReceiptHistorySearchText: String
    @Published public private(set) var executionReceiptHistoryStatusFilter: ExecutionReceiptStatus?
    @Published public private(set) var executionReceiptHistoryReferenceKindFilter: ExecutionReceiptReferenceKind?
    @Published public private(set) var executionReceiptHistoryExportData: Data?
    @Published public private(set) var executionReceiptHistoryExportMessage: String?

    private let store: any ProjectBoardStore
    private let inboxCaptureStore: (any InboxCaptureStore)?
    private let assistantQueueStore: (any AssistantQueueStore)?
    private let assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator?
    private let executionReceiptStore: (any ExecutionReceiptStore)?
    private let missedTaskReviewStateStore: any MissedTaskReviewStateStore
    private let missedTaskFollowUpNotificationClient: (any NotificationClient)?
    private let externalTaskLinkStore: (any ExternalTaskLinkStore)?
    private let scheduleCalendarClient: (any CalendarClient)?
    private let googleCalendarSync: (any GoogleCalendarRuntimeSyncing)?
    private let onChange: () -> Void
    private var lastInboxClassificationUndo: InboxClassificationUndo?
    // Inbox rows render often during filtering and selection changes, so capture
    // metadata is cached at board load time instead of hitting SQLite from SwiftUI body rendering.
    private var inboxCaptureRecordsByTaskID: [Int64: [InboxCaptureRecord]]
    // Inspector receipt rows are cached as redacted read-model snapshots so
    // SwiftUI rendering never performs file I/O or holds raw receipt details.
    private var executionReceiptHistorySnapshotsByTaskID: [Int64: ExecutionReceiptHistorySnapshot]
    private var executionReceiptHistorySnapshotsByProjectID: [Int64: ExecutionReceiptHistorySnapshot]
    private var taskAutomationSessionHistory: TaskAutoExecutionHistory

    public init(
        store: any ProjectBoardStore,
        inboxCaptureStore: (any InboxCaptureStore)? = nil,
        assistantQueueStore: (any AssistantQueueStore)? = nil,
        assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator? = nil,
        executionReceiptStore: (any ExecutionReceiptStore)? = nil,
        missedTaskReviewStateStore: any MissedTaskReviewStateStore = InMemoryMissedTaskReviewStateStore(),
        missedTaskFollowUpNotificationClient: (any NotificationClient)? = nil,
        externalTaskLinkStore: (any ExternalTaskLinkStore)? = nil,
        scheduleCalendarClient: (any CalendarClient)? = nil,
        googleCalendarSync: (any GoogleCalendarRuntimeSyncing)? = nil,
        snapshot: ProjectBoardSnapshot = .empty,
        onChange: @escaping () -> Void = {}
    ) {
        self.store = store
        self.inboxCaptureStore = inboxCaptureStore
        self.assistantQueueStore = assistantQueueStore
        self.assistantQueueExecutionCoordinator = assistantQueueExecutionCoordinator
        self.executionReceiptStore = executionReceiptStore
        self.missedTaskReviewStateStore = missedTaskReviewStateStore
        self.missedTaskFollowUpNotificationClient = missedTaskFollowUpNotificationClient
        self.externalTaskLinkStore = externalTaskLinkStore
        self.scheduleCalendarClient = scheduleCalendarClient
        self.googleCalendarSync = googleCalendarSync
        self.snapshot = snapshot
        self.onChange = onChange
        self.selectedProjectID = snapshot.projects.first?.id
        self.showsArchivedProjects = false
        self.showsCompletedWorkflowTasks = false
        self.inboxTriageFilter = .all
        self.todayCommandFeedback = nil
        self.inboxCaptureRecordsByTaskID = [:]
        self.todayFocusTaskID = nil
        self.todayScheduleDraft = nil
        self.dailyPlanningReview = nil
        self.scheduleDraft = nil
        self.scheduleApplyResult = nil
        self.googleCalendarSyncStatus = .runtimeNotConfigured
        self.projectAssistantAnswer = nil
        self.projectAssistantReviewDraft = nil
        self.taskAutomationReviewDecision = nil
        self.taskAutomationDocumentDeliverableReviews = []
        self.lastApprovedAutomationExecutionReceipt = nil
        self.approvedAutomationExecutionReceipts = []
        self.assistantQueueSnapshot = .empty
        self.assistantQueueViewFilter = .needsAttention
        self.assistantQueueSort = .needsActionFirst
        self.assistantQueueSelectedItemIDs = []
        self.executionReceiptHistorySnapshot = .empty
        self.executionReceiptHistorySearchText = ""
        self.executionReceiptHistoryStatusFilter = nil
        self.executionReceiptHistoryReferenceKindFilter = nil
        self.executionReceiptHistoryExportData = nil
        self.executionReceiptHistoryExportMessage = nil
        self.executionReceiptHistorySnapshotsByTaskID = [:]
        self.executionReceiptHistorySnapshotsByProjectID = [:]
        self.taskAutomationSessionHistory = .empty
        refreshGoogleCalendarSyncStatus()
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

    public var canSyncGoogleCalendar: Bool {
        googleCalendarSyncStatus.canSync
    }

    public var googleCalendarSyncHelp: String {
        googleCalendarSyncStatus.detailLabel
    }

    public var selectedInboxCaptureRecords: [InboxCaptureRecord] {
        guard let selectedTaskID else {
            return []
        }

        return captureRecords(for: selectedTaskID, reportErrors: true)
    }

    @discardableResult
    public func updateSelectedInboxCaptureMemo(_ memo: String) -> InboxCaptureRecord? {
        guard let capture = selectedInboxCaptureRecords.first, let inboxCaptureStore else {
            errorMessage = "Inbox capture is no longer available."
            return nil
        }

        do {
            let updated = try inboxCaptureStore.updateMemo(id: capture.id, memo: memo)
            replaceCachedCapture(updated)
            let taskTitle = selectedTask?.title ?? "selected Inbox item"
            inboxClassificationFeedback = InboxClassificationFeedback(
                message: String(format: String(localized: "Saved note for \"%@\"."), taskTitle),
                systemImage: "note.text",
                canUndo: false
            )
            errorMessage = nil
            onChange()
            return updated
        } catch {
            errorMessage = InboxCaptureStoreError.userMessage(for: error)
            return nil
        }
    }

    public var filteredInboxTasks: [ProjectBoardTask] {
        inboxTasks.filter { task in
            matchesInboxTriageFilter(task, filter: inboxTriageFilter)
        }
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

    public func inboxTriageCount(for filter: InboxTriageFilter) -> Int {
        refreshInboxCaptureCacheForInbox()
        return inboxTasks.filter { task in
            matchesInboxTriageFilter(task, filter: filter)
        }.count
    }

    public func inboxTriageSummary(for task: ProjectBoardTask) -> InboxTriageSummary {
        let captures = captureRecords(for: task.id)
        guard let capture = captures.first else {
            return InboxTriageSummary(
                sourceLabel: "Manual",
                interpretationLabel: task.status == .backlog && task.dueAt == nil ? "Unprocessed" : "Manual",
                systemImage: "square.and.pencil",
                tintName: "secondary",
                accessibilityValue: task.status == .backlog && task.dueAt == nil
                    ? "Source: Manual, Interpretation: Unprocessed"
                    : "Source: Manual, Interpretation: Manual"
            )
        }

        if capture.transcriptionStatus == .failed {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript failed",
                systemImage: "waveform.badge.exclamationmark",
                tintName: "red",
                accessibilityValue: "Source: Voice, Interpretation: Transcript failed"
            )
        }

        if capture.transcriptionStatus == .pending {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript pending",
                systemImage: "waveform",
                tintName: "secondary",
                accessibilityValue: "Source: Voice, Interpretation: Transcript pending"
            )
        }

        guard capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript ready",
                systemImage: "waveform",
                tintName: "blue",
                accessibilityValue: "Source: Voice, Interpretation: Transcript ready"
            )
        }

        let confidence = Self.inboxInterpretationConfidence(from: capture.memo)
        let confidenceValue = confidence.map { ", Confidence: \($0)" } ?? ""
        return InboxTriageSummary(
            sourceLabel: "Voice",
            interpretationLabel: "AI interpreted",
            systemImage: "sparkles",
            tintName: "blue",
            accessibilityValue: "Source: Voice, Interpretation: AI interpreted\(confidenceValue)"
        )
    }

    public func setInboxTriageFilter(_ filter: InboxTriageFilter) {
        refreshInboxCaptureCacheForInbox()
        inboxTriageFilter = filter
        ensureSelectedTaskIsVisibleInInboxFilter()
    }

    public func ensureSelectedInboxTaskIsVisible() {
        refreshInboxCaptureCacheForInbox()
        // Inbox actions and voice metadata are contextual; auto-selecting the
        // first visible item prevents a loaded Inbox from presenting disabled
        // classification controls with available work hidden in the list.
        ensureSelectedTaskIsVisibleInInboxFilter()
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

    public func unscheduledScheduleTasks() -> [ProjectBoardTask] {
        snapshot.projects
            .filter { project in
                !project.isArchived && !project.isCompleted
            }
            .flatMap(\.tasks)
            .filter { task in
                task.status != .done && task.dueAt == nil
            }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return lhs.id > rhs.id
            }
    }

    public func dailyWorkloadOverview(
        around referenceDate: Date = Date(),
        calendar: Calendar = .current,
        visibleDayCount: Int = 7
    ) -> DailyWorkloadOverview {
        DailyWorkloadDashboardBuilder.overview(
            from: snapshot,
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: visibleDayCount
        )
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

    public func makeDailyPlanningReview(
        transcript: String,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlanningReview {
        DailyPlanningReviewBuilder.review(
            transcript: transcript,
            plan: todayPlan(on: referenceDate, calendar: calendar),
            workload: dailyWorkloadOverview(around: referenceDate, calendar: calendar),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    @discardableResult
    public func prepareDailyPlanningReview(
        transcript: String,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlanningReview {
        let review = makeDailyPlanningReview(
            transcript: transcript,
            on: referenceDate,
            calendar: calendar
        )
        dailyPlanningReview = review
        todayCommandFeedback = String(localized: "Prepared daily planning review.")
        return review
    }

    public func todayAssistantRailContext(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayAssistantRailContext {
        let plan = todayPlan(on: referenceDate, calendar: calendar)
        if let selectedTask = selectedTask,
           plan.tasks.contains(where: { $0.id == selectedTask.id }) {
            return todayAssistantRailContext(
                source: .selected,
                task: selectedTask,
                plan: plan,
                nextActionTitle: String(localized: "Review selected task"),
                nextActionReason: String(localized: "You selected this Today task for review.")
            )
        }

        if let recommendedTask = plan.recommendedTask {
            return todayAssistantRailContext(
                source: .recommended,
                task: recommendedTask,
                plan: plan,
                nextActionTitle: String(localized: "Start recommended task"),
                nextActionReason: plan.recommendationReason
            )
        }

        return TodayAssistantRailContext(
            source: .empty,
            task: nil,
            projectTitle: String(localized: "No project selected"),
            nextActionTitle: String(localized: "Capture the next task"),
            nextActionReason: plan.recommendationReason,
            nextBlockLabel: nil,
            notes: String(localized: "Add a Today command or schedule Inbox work to create a focus path."),
            // Subtasks and reminders stay as command drafts until those domains
            // have approval-gated writes wired into the Today workflow.
            subtaskSummary: String(localized: "Subtask capture is staged through the Today command."),
            reminderSummary: String(localized: "Reminder draft only; external writes require approval.")
        )
    }

    @discardableResult
    public func submitTodayCommand(_ rawTitle: String) -> ProjectBoardTask? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            todayCommandFeedback = String(localized: "Today command needs a title.")
            return nil
        }

        let task = createInboxTask(title: title)
        if task != nil {
            todayCommandFeedback = String(format: String(localized: "Added \"%@\" to Inbox."), title)
        }
        return task
    }

    public func todayRecommendationChips(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodayRecommendationChip] {
        let tasks = todayTasks(on: referenceDate, calendar: calendar)
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        var usedTaskIDs = Set<Int64>()

        func firstTask(
            matching predicate: (ProjectBoardTask) -> Bool
        ) -> ProjectBoardTask? {
            tasks.first { task in
                !usedTaskIDs.contains(task.id) && predicate(task)
            }
        }

        var chips: [TodayRecommendationChip] = []
        if let task = firstTask(matching: { $0.status == .blocked }) {
            usedTaskIDs.insert(task.id)
            chips.append(TodayRecommendationChip(
                kind: .blocker,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "Resolve blocker"),
                systemImage: "exclamationmark.triangle",
                reason: String(format: String(localized: "%@ is blocking today's plan."), task.title)
            ))
        }
        if let task = firstTask(matching: { dueDate(for: $0.dueAt).map { $0 < dayStart } == true }) {
            usedTaskIDs.insert(task.id)
            chips.append(TodayRecommendationChip(
                kind: .overdue,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "Clear overdue"),
                systemImage: "clock.badge.exclamationmark",
                reason: String(format: String(localized: "%@ is overdue."), task.title)
            ))
        }
        if let task = firstTask(matching: { $0.priority == .high }) {
            chips.append(TodayRecommendationChip(
                kind: .highPriority,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "High priority"),
                systemImage: "flag.fill",
                reason: String(format: String(localized: "%@ is high priority."), task.title)
            ))
        }

        return chips
    }

    public func missedTaskReview(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current,
        staleAfterDays: Int = 7
    ) -> MissedTaskReviewSummary {
        guard let dayInterval = calendar.dateInterval(of: .day, for: referenceDate) else {
            return .empty
        }

        let staleCutoff = calendar.date(byAdding: .day, value: -max(staleAfterDays, 1), to: dayInterval.start) ?? dayInterval.start
        // Inbox is intake, not committed work; Catch Up should not make raw captures
        // look like forgotten tasks before the user triages them into a project.
        let activeProjects = snapshot.projects.filter { !$0.isArchived && !$0.isCompleted && !isInboxProject($0) }
        var didFailToLoadReviewState = false
        let items = activeProjects
            .flatMap { project in
                project.tasks.compactMap { task -> MissedTaskReviewItem? in
                    guard task.status != .done else {
                        return nil
                    }

                    let reasons = missedTaskReasons(
                        for: task,
                        dayInterval: dayInterval,
                        staleCutoff: staleCutoff
                    )
                    guard !reasons.isEmpty else {
                        return nil
                    }

                    let reviewState = missedTaskReviewState(
                        taskID: task.id,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        didFail: &didFailToLoadReviewState
                    )
                    return MissedTaskReviewItem(
                        task: task,
                        projectTitle: project.title,
                        reasons: reasons,
                        lastReviewedAt: reviewState.lastReviewedAt,
                        isNewlyMissed: reviewState.isNewlyMissed
                    )
                }
            }
            .sorted(by: sortMissedTaskReviewItems)

        let immediateQueue = items
            .filter { $0.isNewlyMissed && isImmediateMissedTask($0) }
            .sorted(by: sortMissedTaskReviewItems)

        return MissedTaskReviewSummary(
            items: items,
            immediateQueue: immediateQueue,
            overdueCount: items.filter { $0.reasons.contains(.overdue) }.count,
            dueTodayCount: items.filter { $0.reasons.contains(.dueToday) }.count,
            blockedCount: items.filter { $0.reasons.contains(.blocked) }.count,
            unscheduledCount: items.filter { $0.reasons.contains(.unscheduled) }.count,
            staleCount: items.filter { $0.reasons.contains(.stale) }.count,
            newlyMissedCount: immediateQueue.count,
            stateErrorMessage: didFailToLoadReviewState ? String(localized: "Missed task review state could not be loaded.") : nil
        )
    }

    @discardableResult
    public func scheduleMissedTaskDailyFollowUp(
        settings: AppSettings,
        dateProvider: any DateProvider = SystemDateProvider(),
        calendar: Calendar? = nil
    ) -> MissedTaskDailyFollowUpResult? {
        guard let missedTaskFollowUpNotificationClient else {
            return nil
        }

        let normalizedSettings = settings.normalizedForRuntime
        let reviewCalendar = calendar ?? Self.reviewCalendar(timeZoneIdentifier: normalizedSettings.timeZoneIdentifier)
        let summary = missedTaskReview(on: dateProvider.now, calendar: reviewCalendar)
        let result = MissedTaskDailyFollowUpScheduler(
            stateStore: missedTaskReviewStateStore,
            notificationClient: missedTaskFollowUpNotificationClient,
            dateProvider: dateProvider,
            settings: normalizedSettings
        )
        .scheduleIfNeeded(summary: summary)

        if result.status == .failed {
            integrationStatusMessage = result.message
        }
        return result
    }

    public func completeMissedTask(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        do {
            _ = try store.moveTask(id: taskID, to: .done)
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            load()
            selectedProjectID = task.projectID
            selectedTaskID = taskID
            todayCommandFeedback = String(format: String(localized: "Completed \"%@\" from missed review."), task.title)
            errorMessage = nil
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func rescheduleMissedTaskForToday(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        do {
            let updatedTask = try store.updateTask(
                id: taskID,
                ProjectBoardTaskDraft(
                    projectID: task.projectID,
                    title: task.title,
                    detail: task.detail,
                    status: .planned,
                    priority: task.priority,
                    dueAt: ISO8601DateFormatter().string(from: referenceDate)
                )
            )
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            load()
            selectedProjectID = updatedTask.projectID
            selectedTaskID = updatedTask.id
            todayCommandFeedback = String(format: String(localized: "Rescheduled \"%@\" for today."), task.title)
            errorMessage = nil
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func deferMissedTaskForLater(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        do {
            // Deferring from Catch Up is review-state only: it removes the item
            // from today's recovery queue without hiding or mutating the task.
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            selectedProjectID = task.projectID
            selectedTaskID = task.id
            todayCommandFeedback = String(format: String(localized: "Deferred \"%@\" from today's missed queue."), task.title)
            errorMessage = nil
            onChange()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func startFocus(taskID: Int64) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        // Focus is intentionally local UI state. It must not move task status or
        // write Calendar/Reminder records before the user reviews a schedule.
        todayFocusTaskID = task.id
        selectedProjectID = task.projectID
        selectedTaskID = task.id
        todayCommandFeedback = String(format: String(localized: "Focused on \"%@\"."), task.title)
        errorMessage = nil
    }

    public func startFocusOnRecommendedTask(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard let task = todayPlan(on: referenceDate, calendar: calendar).recommendedTask else {
            todayCommandFeedback = String(localized: "No focus task is available.")
            return
        }
        startFocus(taskID: task.id)
    }

    @discardableResult
    public func prepareTaskAutomationReview(
        settings: TaskAutoExecutionSettings,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAutoExecutionDecision {
        let history = sessionAutomationHistory(for: referenceDate, calendar: calendar)
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )

        // Preparing a local review candidate must not spend the LLM API budget.
        // The session ledger is charged only after a provider request is
        // successfully assembled, so opening the review UI cannot exhaust the
        // user's configured daily automation allowance.
        taskAutomationSessionHistory = history
        return decision
    }

    @discardableResult
    public func prepareTaskAutomationReview(
        settings: TaskAutoExecutionSettings,
        history: TaskAutoExecutionHistory,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAutoExecutionDecision {
        // Whole-board automation must reuse the deterministic planner before
        // any provider request so cadence, lookahead, trigger, and LLM budget
        // settings cannot be bypassed by a UI or future scheduled entry point.
        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )

        guard decision.status == .readyForReview else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = decision.reason
            return decision
        }

        taskAutomationReviewDecision = decision
        taskAutomationDocumentDeliverableReviews = []
        if let firstTask = decision.selectedTasks.first {
            selectedProjectID = firstTask.projectID
            selectedTaskID = firstTask.id
        }
        todayCommandFeedback = String(
            format: String(localized: "Prepared review-only automation for %d tasks."),
            decision.selectedTasks.count
        )
        integrationStatusMessage = String(
            format: String(localized: "Prepared review-only automation for %d tasks."),
            decision.selectedTasks.count
        )
        errorMessage = nil
        return decision
    }

    public func makeTaskAutomationPlanningRequest(
        settings: TaskAutoExecutionSettings,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft] = []
    ) throws -> PlanningRequest {
        let history = sessionAutomationHistory(for: referenceDate, calendar: calendar)
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let request = try buildTaskAutomationPlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
        taskAutomationDocumentDeliverableReviews = documentDeliverableReviews(from: documentDeliverableDrafts)

        // The session budget is charged only after the provider request is
        // successfully assembled. Throttled or invalid review attempts still
        // update feedback but do not consume the daily LLM review allowance.
        taskAutomationSessionHistory = TaskAutoExecutionHistory(
            lastRunAt: referenceDate,
            llmCallsToday: history.llmCallsToday + 1
        )
        return request
    }

    public func makeTaskAutomationPlanningRequest(
        settings: TaskAutoExecutionSettings,
        history: TaskAutoExecutionHistory,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft] = []
    ) throws -> PlanningRequest {
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let request = try buildTaskAutomationPlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
        taskAutomationDocumentDeliverableReviews = documentDeliverableReviews(from: documentDeliverableDrafts)
        return request
    }

    private func buildTaskAutomationPlanningRequest(
        decision: TaskAutoExecutionDecision,
        settings: TaskAutoExecutionSettings,
        referenceDate: Date,
        timeZoneIdentifier: String,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft]
    ) throws -> PlanningRequest {
        try TaskAutoExecutionPlanningRequestBuilder().makePlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
    }

    private func sessionAutomationHistory(
        for referenceDate: Date,
        calendar: Calendar
    ) -> TaskAutoExecutionHistory {
        guard let lastRunAt = taskAutomationSessionHistory.lastRunAt,
              calendar.isDate(lastRunAt, inSameDayAs: referenceDate) else {
            return TaskAutoExecutionHistory(lastRunAt: taskAutomationSessionHistory.lastRunAt, llmCallsToday: 0)
        }
        return taskAutomationSessionHistory
    }

    public func prepareAutomationReviewForSelectedTask() {
        guard let selectedTask else {
            todayCommandFeedback = String(localized: "Select a task before reviewing automation.")
            return
        }
        guard isEligibleForTaskAutomation(selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Only open unblocked tasks can be reviewed for automation.")
            return
        }

        taskAutomationReviewDecision = TaskAutoExecutionDecision(
            status: .readyForReview,
            selectedTasks: [selectedTask],
            reason: String(localized: "Selected task is ready for review-only automation."),
            llmCallBudgetRemaining: 1,
            requiresUserApproval: true,
            allowsDirectExecution: false
        )
        taskAutomationDocumentDeliverableReviews = []
        integrationStatusMessage = String(format: String(localized: "Prepared review-only automation for \"%@\"."), selectedTask.title)
        errorMessage = nil
    }

    public func runApprovedAutomationForSelectedTask() {
        guard let selectedTask else {
            todayCommandFeedback = String(localized: "Select a task before running automation.")
            return
        }
        guard let reviewDecision = taskAutomationReviewDecision,
              let reviewedTask = reviewDecision.selectedTasks.first(where: { $0.id == selectedTask.id }) else {
            todayCommandFeedback = String(localized: "Review the automation plan before running it.")
            return
        }
        guard isEligibleForTaskAutomation(selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Task automation stopped because the task is blocked or complete.")
            return
        }
        guard matchesReviewedAutomationTask(reviewedTask, current: selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Review the automation plan again because the task changed after review.")
            return
        }

        do {
            let updatedTask = try store.updateTask(
                id: selectedTask.id,
                ProjectBoardTaskDraft(
                    projectID: selectedTask.projectID,
                    title: selectedTask.title,
                    detail: approvedAutomationExecutionDetail(for: selectedTask),
                    status: .inProgress,
                    priority: selectedTask.priority,
                    dueAt: selectedTask.dueAt
                )
            )
            selectedProjectID = updatedTask.projectID
            load()
            selectedProjectID = updatedTask.projectID
            selectedTaskID = selectedTask.id
            let receipt = ApprovedAutomationExecutionReceipt(
                task: selectedTask,
                statusAfter: updatedTask.status,
                reviewReason: reviewDecision.reason
            )
            lastApprovedAutomationExecutionReceipt = receipt
            approvedAutomationExecutionReceipts.append(receipt)
            let receiptPersistenceMessage = saveApprovedAutomationExecutionReceipt(receipt)
            // Approved automation is still local and review-gated, but it must
            // leave a visible content-execution trail so a status move cannot
            // masquerade as executing the reviewed task body.
            todayCommandFeedback = String(format: String(localized: "Executed approved automation for \"%@\"."), selectedTask.title)
            integrationStatusMessage = String(format: String(localized: "Executed approved automation for \"%@\"."), selectedTask.title)
            errorMessage = receiptPersistenceMessage
            retainUnexecutedReviewedTasks(from: reviewDecision, excludingTaskID: selectedTask.id)
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before running automation."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func saveApprovedAutomationExecutionReceipt(_ receipt: ApprovedAutomationExecutionReceipt) -> String? {
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return nil
        }

        let commonReceipt = ExecutionReceiptFactory.makeApprovedAutomationReceipt(
            receipt,
            runID: "approved-automation-run:\(UUID().uuidString)",
            approvalID: nil,
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(commonReceipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            return String(localized: "Approved automation ran, but the execution receipt could not be saved.")
        }
    }

    private func saveScheduleDraftApplyReceipt(
        writeCandidates: [ScheduleDraftApplyWriteCandidate],
        unscheduledTaskCount: Int,
        createdEvents: [ScheduleDraftApplyCreatedEvent],
        approvalID: String?,
        status: ExecutionReceiptStatus,
        errorSummary: String? = nil
    ) -> String? {
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return nil
        }

        let projectTitlesByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.title) })
        let receipt = ExecutionReceiptFactory.makeScheduleDraftApplyReceipt(
            writeCandidates: writeCandidates,
            unscheduledTaskCount: unscheduledTaskCount,
            createdEvents: createdEvents,
            projectTitlesByID: projectTitlesByID,
            runID: "schedule-draft-apply-run:\(UUID().uuidString)",
            approvalID: approvalID,
            status: status,
            errorSummary: errorSummary,
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(receipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            if status == .failed {
                return String(localized: "Calendar apply failed, and the execution receipt could not be saved.")
            }
            if status == .skipped {
                return String(localized: "Schedule apply was skipped, and the execution receipt could not be saved.")
            }
            return String(localized: "Schedule applied to Calendar, but the execution receipt could not be saved.")
        }
    }

    private static func scheduleDraftApplyApprovalID() -> String {
        "schedule-draft-apply-approval:\(UUID().uuidString)"
    }

    private func scheduleDraftWriteCandidates(for draft: ScheduleDraft) -> [ScheduleDraftApplyWriteCandidate] {
        draft.timeBlocks.compactMap(ScheduleDraftApplyWriteCandidate.init(block:))
    }

    private func isEligibleForTaskAutomation(_ task: ProjectBoardTask) -> Bool {
        task.status != .blocked && task.status != .done
    }

    private func approvedAutomationExecutionDetail(for task: ProjectBoardTask) -> String {
        let marker = "SoloPM approved automation execution"
        let note = "\(marker): Run approved plan moved this task into active work after reviewing its current title, detail, priority, and due date."
        let trimmedDetail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetail.contains(marker) else {
            return task.detail
        }
        guard !trimmedDetail.isEmpty else {
            return note
        }
        return "\(trimmedDetail)\n\n\(note)"
    }

    private func retainUnexecutedReviewedTasks(
        from reviewDecision: TaskAutoExecutionDecision,
        excludingTaskID executedTaskID: Int64
    ) {
        let remainingTasks = reviewDecision.selectedTasks.filter { $0.id != executedTaskID }
        guard !remainingTasks.isEmpty else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            return
        }
        // A configured review can contain several priority/due-date selected
        // tasks. Keep the still-unexecuted snapshots so one approved task run
        // cannot erase the user's review queue or hide missing execution
        // receipts for the rest of the batch.
        taskAutomationReviewDecision = TaskAutoExecutionDecision(
            status: reviewDecision.status,
            selectedTasks: remainingTasks,
            reason: reviewDecision.reason,
            llmCallBudgetRemaining: reviewDecision.llmCallBudgetRemaining,
            requiresUserApproval: reviewDecision.requiresUserApproval,
            allowsDirectExecution: reviewDecision.allowsDirectExecution
        )
    }

    private func documentDeliverableReviews(
        from drafts: [DocumentAutomationDeliverableDraft]
    ) -> [TaskAutomationDocumentDeliverableReview] {
        // Keep the review UI bound to the same approval-gated draft set that
        // enters provider planning. Rendering only redacted previews lets users
        // audit source evidence without exposing raw document bodies in the UI.
        return TaskAutomationDocumentDeliverableReviewPolicy()
            .reviewableDeliverables(from: drafts)
            .map { deliverable in
                let draft = deliverable.draft
                return TaskAutomationDocumentDeliverableReview(
                    kind: draft.kind,
                    title: draft.title,
                    suggestedPath: draft.suggestedPath,
                    sourceDocuments: deliverable.sourceDocuments.map {
                        TaskAutomationDocumentSourceReview(
                            id: $0.id,
                            title: $0.title,
                            redactedSummary: $0.redactedSummary,
                            inclusionReason: $0.inclusionReason
                        )
                    },
                    rationale: draft.rationale,
                    riskLevel: draft.riskLevel,
                    requiresApproval: draft.requiresApproval
                )
            }
    }

    private func matchesReviewedAutomationTask(_ reviewedTask: ProjectBoardTask, current: ProjectBoardTask) -> Bool {
        // The LLM plan is based on a point-in-time task snapshot. Requiring the
        // same content and scheduling fields keeps a reviewed plan from being
        // reused after the user edits the work it was meant to describe.
        reviewedTask.id == current.id
            && reviewedTask.projectID == current.projectID
            && reviewedTask.title == current.title
            && reviewedTask.detail == current.detail
            && reviewedTask.status == current.status
            && reviewedTask.priority == current.priority
            && reviewedTask.dueAt == current.dueAt
    }

    @discardableResult
    public func prepareTodayScheduleDraft(
        prioritizing taskID: Int64? = nil,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayScheduleDraft {
        let plan = todayPlan(on: referenceDate, calendar: calendar)
        let timeBlocks = prioritizedTodayTimeBlocks(
            plan: plan,
            taskID: taskID,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let draft = TodayScheduleDraft(timeBlocks: timeBlocks)
        todayScheduleDraft = draft
        todayCommandFeedback = String(format: String(localized: "Prepared %d time blocks for schedule review."), draft.timeBlocks.count)
        return draft
    }

    @discardableResult
    public func prepareScheduleDraft(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ScheduleDraft {
        let todayDraft = prepareTodayScheduleDraft(on: referenceDate, calendar: calendar)
        let draft = ScheduleDraft(
            timeBlocks: todayDraft.timeBlocks,
            unscheduledTasks: unscheduledScheduleTasks()
        )
        scheduleDraft = draft
        scheduleApplyResult = nil
        todayCommandFeedback = String(
            format: String(localized: "Prepared schedule draft with %d time blocks and %d unscheduled tasks."),
            draft.timeBlocks.count,
            draft.unscheduledTasks.count
        )
        return draft
    }

    @discardableResult
    public func applyScheduleDraftToCalendar(approvalToken: String?) -> ScheduleApplyResult {
        guard approvalToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            scheduleApplyResult = .approvalRequired
            todayCommandFeedback = String(localized: "Schedule review approval is required before Calendar write.")
            return .approvalRequired
        }
        let executionApprovalID = Self.scheduleDraftApplyApprovalID()
        guard let draft = scheduleDraft else {
            scheduleApplyResult = .noDraft
            todayCommandFeedback = String(localized: "Create a schedule draft before applying to Calendar.")
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: [],
                unscheduledTaskCount: 0,
                createdEvents: [],
                approvalID: executionApprovalID,
                status: .skipped
            )
            return .noDraft
        }
        let writeCandidates = scheduleDraftWriteCandidates(for: draft)
        guard let scheduleCalendarClient else {
            scheduleApplyResult = .calendarNotConfigured
            todayCommandFeedback = String(localized: "Calendar is not configured. No external write was performed.")
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: [],
                approvalID: executionApprovalID,
                status: .skipped
            )
            return .calendarNotConfigured
        }

        var createdEvents: [ScheduleDraftApplyCreatedEvent] = []
        do {
            for candidate in writeCandidates {
                let event = try scheduleCalendarClient.createEvent(CalendarEventDraft(
                    title: candidate.taskTitle,
                    startAt: candidate.startAt,
                    endAt: candidate.endAt,
                    notes: String(localized: "Created from a reviewed SoloPM schedule draft.")
                ))
                createdEvents.append(ScheduleDraftApplyCreatedEvent(candidate: candidate, record: event))
            }
            let result = ScheduleApplyResult.applied(eventCount: createdEvents.count)
            scheduleApplyResult = result
            todayCommandFeedback = String(format: String(localized: "Applied %d Calendar events."), createdEvents.count)
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: createdEvents,
                approvalID: executionApprovalID,
                status: .succeeded
            )
            return result
        } catch {
            let message = Self.userFacingMessage(for: error)
            let result = ScheduleApplyResult.failed(message)
            scheduleApplyResult = result
            todayCommandFeedback = String(localized: "Calendar apply failed.")
            // The Calendar client does not expose rollback, so preserve partial
            // write evidence in a failed receipt instead of hiding the attempt.
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: createdEvents,
                approvalID: executionApprovalID,
                status: .failed,
                errorSummary: message
            )
            return result
        }
    }

    public func refreshGoogleCalendarSyncStatus(now: Date = Date()) {
        guard let googleCalendarSync else {
            googleCalendarSyncStatus = .runtimeNotConfigured
            return
        }

        do {
            googleCalendarSyncStatus = try googleCalendarSync.status(now: now)
        } catch {
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .failed(message: Self.userFacingMessage(for: error, fallback: "Google Calendar sync status is unavailable."))
            )
        }
    }

    @discardableResult
    public func syncDueTasksToGoogleCalendar(approvalToken: String?) -> GoogleCalendarTaskSyncResult? {
        refreshGoogleCalendarSyncStatus()
        guard let googleCalendarSync else {
            errorMessage = GoogleCalendarRuntimeSyncStatus.runtimeNotConfigured.detailLabel
            return nil
        }
        guard googleCalendarSyncStatus.canSync else {
            errorMessage = googleCalendarSyncStatus.detailLabel
            return nil
        }
        guard let approvalToken,
              !approvalToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Google Calendar sync requires approval before writing events."
            return nil
        }

        do {
            let context = ToolExecutionContext(
                approvalToken: ApprovalToken(id: approvalToken, sessionID: "project-board-google-calendar-sync"),
                source: .reviewUI
            )
            let result = try googleCalendarSync.syncDueTasks(context: context)
            integrationStatusMessage = Self.googleCalendarSyncStatusMessage(for: result)
            errorMessage = nil
            refreshGoogleCalendarSyncStatus()
            onChange()
            return result
        } catch GoogleCalendarRuntimeSyncError.approvalRequired {
            errorMessage = "Google Calendar sync requires approval before writing events."
            return nil
        } catch GoogleCalendarRuntimeSyncError.notReady(let state) {
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(plan: googleCalendarSyncStatus.plan, state: state)
            errorMessage = googleCalendarSyncStatus.detailLabel
            return nil
        } catch SyncServiceError.upgradeRequired(let requiredPlan) {
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .upgradeRequired(requiredPlan: requiredPlan)
            )
            errorMessage = googleCalendarSyncStatus.detailLabel
            return nil
        } catch {
            let message = Self.userFacingMessage(for: error, fallback: "Google Calendar sync failed.")
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .failed(message: message)
            )
            errorMessage = message
            return nil
        }
    }

    public func projectPortfolioSummaries(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectPortfolioSummary] {
        snapshot.projects
            .filter { !$0.isArchived && !isInboxProject($0) }
            .map { projectPortfolioSummary(for: $0, on: referenceDate, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.health.sortRank != rhs.health.sortRank {
                    return lhs.health.sortRank < rhs.health.sortRank
                }
                if lhs.overdueTaskCount != rhs.overdueTaskCount {
                    return lhs.overdueTaskCount > rhs.overdueTaskCount
                }
                return lhs.projectID > rhs.projectID
            }
    }

    public func doneAnalytics(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DoneAnalyticsSummary {
        let completedProjects = snapshot.projects.filter { !$0.isArchived && $0.isCompleted && !isInboxProject($0) }
        let historyTasks = snapshot.projects
            .filter { !$0.isArchived }
            .flatMap(\.tasks)
            .filter { task in task.completedAt != nil || task.status == .done }
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let rollingWeekStart = calendar.date(byAdding: .day, value: -6, to: dayInterval?.start ?? referenceDate) ?? referenceDate
        let completedTodayCount = historyTasks.filter { task in
            guard let dayInterval, let completedDate = completedDate(for: task) else {
                return false
            }
            return completedDate >= dayInterval.start && completedDate < dayInterval.end
        }.count
        let completedThisWeekCount = historyTasks.filter { task in
            guard let completedDate = completedDate(for: task) else {
                return false
            }
            return completedDate >= rollingWeekStart && completedDate <= referenceDate
        }.count
        let completedDayStarts = Set(historyTasks.compactMap { task -> Date? in
            guard let completedDate = completedDate(for: task) else {
                return nil
            }
            return calendar.dateInterval(of: .day, for: completedDate)?.start
        })
        let streakDays = Self.doneStreakDays(
            from: completedDayStarts,
            on: referenceDate,
            calendar: calendar
        )
        let recentTasks = historyTasks
            .sorted { lhs, rhs in
                switch (completedDate(for: lhs), completedDate(for: rhs)) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.id > rhs.id
                    }
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id > rhs.id
                }
            }

        return DoneAnalyticsSummary(
            completedTaskCount: historyTasks.count,
            completedProjectCount: completedProjects.count,
            completedTodayCount: completedTodayCount,
            completedThisWeekCount: completedThisWeekCount,
            streakDays: streakDays,
            recentTasks: Array(recentTasks.prefix(12)),
            localRuleInsight: "Done analytics uses local completed_at history; reopened tasks remain visible in completion history."
        )
    }

    @discardableResult
    public func openProjectFromPortfolioCard(projectID: Int64) -> Bool {
        guard snapshot.projects.contains(where: { $0.id == projectID && !$0.isArchived }) else {
            errorMessage = "Project is no longer available."
            return false
        }

        selectedProjectID = projectID
        selectedTaskID = nil
        errorMessage = nil
        return true
    }

    public func projectTitle(for task: ProjectBoardTask) -> String {
        snapshot.projects.first { $0.id == task.projectID }?.title ?? "Unknown Project"
    }

    public var isEmptyProjectStateVisible: Bool {
        errorMessage == nil && selectedProject == nil
    }

    public func load() {
        do {
            let loadedSnapshot = try store.loadSnapshot(includeArchived: showsArchivedProjects)
            let captureCacheErrorMessage = refreshInboxCaptureCache(for: loadedSnapshot)
            let assistantQueueErrorMessage = refreshAssistantQueueSnapshot()
            refreshExecutionReceiptHistorySnapshot(for: loadedSnapshot)
            snapshot = loadedSnapshot
            if selectedProjectID == nil || !snapshot.projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = snapshot.projects.first?.id
            }
            if selectedTaskID != nil, selectedTask == nil {
                self.selectedTaskID = nil
            }
            errorMessage = assistantQueueErrorMessage ?? captureCacheErrorMessage
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func refreshExecutionReceiptHistorySnapshot() {
        refreshExecutionReceiptHistorySnapshot(for: snapshot)
    }

    public func setExecutionReceiptHistorySearchText(_ text: String) {
        guard executionReceiptHistorySearchText != text else {
            return
        }
        executionReceiptHistorySearchText = text
        clearExecutionReceiptHistoryExport()
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func setExecutionReceiptHistoryStatusFilter(_ status: ExecutionReceiptStatus?) {
        guard executionReceiptHistoryStatusFilter != status else {
            return
        }
        executionReceiptHistoryStatusFilter = status
        clearExecutionReceiptHistoryExport()
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func setExecutionReceiptHistoryReferenceKindFilter(_ referenceKind: ExecutionReceiptReferenceKind?) {
        guard executionReceiptHistoryReferenceKindFilter != referenceKind else {
            return
        }
        executionReceiptHistoryReferenceKindFilter = referenceKind
        clearExecutionReceiptHistoryExport()
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func prepareExecutionReceiptHistoryExport(exportedAt: Date = Date()) {
        do {
            let data = try ExecutionReceiptHistoryExporter.exportJSON(
                snapshot: executionReceiptHistorySnapshot,
                exportedAt: exportedAt
            )
            executionReceiptHistoryExportData = data
            executionReceiptHistoryExportMessage = exportPreparedMessage(rowCount: executionReceiptHistorySnapshot.rows.count)
        } catch {
            executionReceiptHistoryExportData = nil
            executionReceiptHistoryExportMessage = String(localized: "Receipt export could not be prepared.")
        }
    }

    public func recordExecutionReceiptHistoryExportCompleted() {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = String(localized: "Saved redacted receipt export JSON.")
    }

    public func recordExecutionReceiptHistoryFileFailure(_ error: Error) {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = String(localized: "Receipt export could not be saved.")
    }

    private func clearExecutionReceiptHistoryExport() {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = nil
    }

    private func executionReceiptHistoryFilter() -> ExecutionReceiptSearchFilter {
        ExecutionReceiptSearchFilter(
            query: executionReceiptHistorySearchText,
            statuses: executionReceiptHistoryStatusFilter.map { Set([$0]) } ?? [],
            referenceKinds: executionReceiptHistoryReferenceKindFilter.map { Set([$0]) } ?? [],
            visibleSurface: .auditLog
        )
    }

    private func exportPreparedMessage(rowCount: Int) -> String {
        if rowCount == 1 {
            return String(format: String(localized: "Prepared %d redacted receipt export row."), rowCount)
        }
        return String(format: String(localized: "Prepared %d redacted receipt export rows."), rowCount)
    }

    private func refreshGlobalExecutionReceiptHistorySnapshot() {
        guard let executionReceiptStore else {
            executionReceiptHistorySnapshot = .empty
            return
        }

        do {
            executionReceiptHistorySnapshot = try globalExecutionReceiptHistorySnapshot(store: executionReceiptStore)
        } catch {
            executionReceiptHistorySnapshot = ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
        }
    }

    private func globalExecutionReceiptHistorySnapshot(
        store: any ExecutionReceiptStore
    ) throws -> ExecutionReceiptHistorySnapshot {
        let receipts = try store.list(matching: executionReceiptHistoryFilter(), limit: 100)
        return ExecutionReceiptHistoryReadModel.snapshot(
            from: receipts,
            limit: 10
        )
    }

    private func refreshExecutionReceiptHistorySnapshot(for snapshot: ProjectBoardSnapshot) {
        guard let executionReceiptStore else {
            executionReceiptHistorySnapshot = .empty
            executionReceiptHistorySnapshotsByTaskID = [:]
            executionReceiptHistorySnapshotsByProjectID = [:]
            return
        }

        do {
            executionReceiptHistorySnapshot = try globalExecutionReceiptHistorySnapshot(store: executionReceiptStore)
            executionReceiptHistorySnapshotsByTaskID = try scopedExecutionReceiptSnapshotsByTaskID(
                in: snapshot,
                store: executionReceiptStore
            )
            executionReceiptHistorySnapshotsByProjectID = try scopedExecutionReceiptSnapshotsByProjectID(
                in: snapshot,
                store: executionReceiptStore
            )
        } catch {
            executionReceiptHistorySnapshotsByTaskID = [:]
            executionReceiptHistorySnapshotsByProjectID = [:]
            executionReceiptHistorySnapshot = ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
        }
    }

    public func executionReceiptHistorySnapshot(forTaskID taskID: Int64) -> ExecutionReceiptHistorySnapshot {
        executionReceiptHistorySnapshotsByTaskID[taskID]
            ?? ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: executionReceiptHistorySnapshot.unavailableMessage
            )
    }

    public func executionReceiptHistorySnapshot(forProjectID projectID: Int64) -> ExecutionReceiptHistorySnapshot {
        executionReceiptHistorySnapshotsByProjectID[projectID]
            ?? ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: executionReceiptHistorySnapshot.unavailableMessage
            )
    }

    private func scopedExecutionReceiptSnapshotsByTaskID(
        in snapshot: ProjectBoardSnapshot,
        store: any ExecutionReceiptStore
    ) throws -> [Int64: ExecutionReceiptHistorySnapshot] {
        try Dictionary(uniqueKeysWithValues: Set(snapshot.projects.flatMap(\.tasks).map(\.id)).map { taskID in
            let receipts = try store.list(
                referenceKind: .task,
                referenceID: String(taskID),
                visibleSurface: .taskDetail,
                limit: 5
            )
            return (taskID, ExecutionReceiptHistoryReadModel.snapshot(from: receipts, limit: 5))
        })
    }

    private func scopedExecutionReceiptSnapshotsByProjectID(
        in snapshot: ProjectBoardSnapshot,
        store: any ExecutionReceiptStore
    ) throws -> [Int64: ExecutionReceiptHistorySnapshot] {
        try Dictionary(uniqueKeysWithValues: Set(snapshot.projects.map(\.id)).map { projectID in
            let receipts = try store.list(
                referenceKind: .project,
                referenceID: String(projectID),
                visibleSurface: .projectDetail,
                limit: 5
            )
            return (projectID, ExecutionReceiptHistoryReadModel.snapshot(from: receipts, limit: 5))
        })
    }

    private func refreshAssistantQueueSnapshot() -> String? {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            return nil
        }

        do {
            // Project Board owns the central task cockpit, so it reads a compact
            // queue snapshot instead of querying local stores from SwiftUI views.
            // Receipts are outcome-only metadata; queue state remains the source of truth.
            // Counts come from state aggregates so terminal queue history cannot
            // hide older review work behind the row fetch limit.
            let stateCounts = try assistantQueueStore.stateCounts()
            let visibleItems = try assistantQueueStore.list(filter: assistantQueueViewFilter.storeFilter(limit: 100))
            var receiptErrorMessage: String?
            let receipts: [ExecutionReceipt]
            do {
                receipts = try executionReceiptStore?.list(limit: 100) ?? []
            } catch {
                receipts = []
                receiptErrorMessage = String(localized: "Assistant Queue execution receipts are unavailable. Queue state is still shown.")
            }
            assistantQueueSnapshot = AssistantQueueReadModel.snapshot(
                from: visibleItems,
                receipts: receipts,
                viewFilter: assistantQueueViewFilter,
                sort: assistantQueueSort,
                stateCounts: stateCounts
            )
            pruneAssistantQueueSelectionToVisibleRows()
            return receiptErrorMessage
        } catch {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            return AssistantQueueStoreError.userMessage(for: error)
        }
    }

    public func setAssistantQueueViewFilter(_ filter: AssistantQueueViewFilter) {
        guard assistantQueueViewFilter != filter else {
            return
        }
        assistantQueueViewFilter = filter
        assistantQueueSelectedItemIDs = []
        _ = refreshAssistantQueueSnapshot()
    }

    public func setAssistantQueueSort(_ sort: AssistantQueueSort) {
        guard assistantQueueSort != sort else {
            return
        }
        assistantQueueSort = sort
        _ = refreshAssistantQueueSnapshot()
    }

    @discardableResult
    public func toggleAssistantQueueSelection(id: String) -> Bool {
        setAssistantQueueSelection(
            id: id,
            selected: !assistantQueueSelectedItemIDs.contains(id)
        )
    }

    @discardableResult
    public func setAssistantQueueSelection(id: String, selected: Bool) -> Bool {
        guard assistantQueueSnapshot.rows.contains(where: { $0.id == id }) else {
            return false
        }
        if selected {
            assistantQueueSelectedItemIDs.insert(id)
        } else {
            assistantQueueSelectedItemIDs.remove(id)
        }
        return true
    }

    @discardableResult
    public func deferSelectedAssistantQueueItems() -> Bool {
        transitionSelectedAssistantQueueItems(
            eligible: \.canDefer,
            emptyMessage: String(localized: "No selected Assistant Queue items can be deferred."),
            successMessage: { count in
                String(format: String(localized: "Deferred %d Assistant Queue items."), count)
            }
        ) { item in
            AssistantQueueStateMachine.deferItem(item)
        }
    }

    @discardableResult
    public func rejectSelectedAssistantQueueItems() -> Bool {
        transitionSelectedAssistantQueueItems(
            eligible: \.canReject,
            emptyMessage: String(localized: "No selected Assistant Queue items can be rejected."),
            successMessage: { count in
                String(format: String(localized: "Rejected %d Assistant Queue items."), count)
            }
        ) { item in
            AssistantQueueStateMachine.reject(item)
        }
    }

    @discardableResult
    public func approveAssistantQueueItem(id: String) -> Bool {
        transitionAssistantQueueItem(id: id) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
    }

    @discardableResult
    public func deferAssistantQueueItem(id: String) -> Bool {
        transitionAssistantQueueItem(id: id) { item in
            AssistantQueueStateMachine.deferItem(item)
        }
    }

    @discardableResult
    public func rejectAssistantQueueItem(id: String) -> Bool {
        transitionAssistantQueueItem(id: id) { item in
            AssistantQueueStateMachine.reject(item)
        }
    }

    @discardableResult
    public func editAssistantQueueItem(
        id: String,
        reviewReason: String,
        redactedSummary: String
    ) -> Bool {
        transitionAssistantQueueItem(id: id, successMessage: "Updated Assistant Queue review details.") { item in
            try AssistantQueueStateMachine.editReviewDetails(
                item,
                reviewReason: reviewReason,
                redactedSummary: redactedSummary
            )
        }
    }

    @discardableResult
    public func retryAssistantQueueItem(id: String) -> Bool {
        transitionAssistantQueueItem(id: id, successMessage: "Reopened Assistant Queue item for review.") { item in
            try AssistantQueueStateMachine.reopenFailedForReview(item)
        }
    }

    @discardableResult
    public func runAssistantQueueItem(id: String) -> Bool {
        guard let assistantQueueExecutionCoordinator else {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Assistant Queue execution is unavailable in this build."
            integrationStatusMessage = nil
            return false
        }

        do {
            let result = try assistantQueueExecutionCoordinator.execute(id: id)
            _ = refreshAssistantQueueSnapshot()
            refreshExecutionReceiptHistorySnapshot()
            if result.item.state == .done {
                errorMessage = nil
                integrationStatusMessage = "Executed Assistant Queue item."
                onChange()
                return true
            }
            errorMessage = "Assistant Queue execution failed. Review the receipt before retrying."
            integrationStatusMessage = nil
            onChange()
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            refreshExecutionReceiptHistorySnapshot()
            errorMessage = Self.assistantQueueExecutionMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    private func transitionAssistantQueueItem(
        id: String,
        successMessage: String? = nil,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            errorMessage = "Assistant Queue is unavailable in this build."
            return false
        }

        do {
            _ = try assistantQueueStore.transition(id: id, transform)
            _ = refreshAssistantQueueSnapshot()
            errorMessage = nil
            integrationStatusMessage = successMessage
            onChange()
            return true
        } catch AssistantQueueTransitionError.blockedItemCannotBeApproved {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Blocked Assistant Queue items cannot be approved."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.dangerousPayloadCannotBeApproved {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Dangerous action plans cannot be approved from Assistant Queue."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.terminalItemCannotTransition {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Assistant Queue item was already reviewed."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.retryRequiresFailedActionPlan {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Only failed action-plan Assistant Queue items can be retried."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.editRequiresReviewableItem {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Only reviewable Assistant Queue items can be edited."
            integrationStatusMessage = nil
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    private func transitionSelectedAssistantQueueItems(
        eligible: KeyPath<AssistantQueueReadModelRow, Bool>,
        emptyMessage: String,
        successMessage: (Int) -> String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = "Assistant Queue is unavailable in this build."
            return false
        }

        let eligibleIDs = assistantQueueSnapshot.rows
            .filter { row in
                assistantQueueSelectedItemIDs.contains(row.id) && row[keyPath: eligible]
            }
            .map(\.id)
        guard !eligibleIDs.isEmpty else {
            errorMessage = emptyMessage
            integrationStatusMessage = nil
            return false
        }

        do {
            for id in eligibleIDs {
                _ = try assistantQueueStore.transition(id: id, transform)
            }
            assistantQueueSelectedItemIDs = []
            _ = refreshAssistantQueueSnapshot()
            errorMessage = nil
            integrationStatusMessage = successMessage(eligibleIDs.count)
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    private func pruneAssistantQueueSelectionToVisibleRows() {
        let visibleIDs = Set(assistantQueueSnapshot.rows.map(\.id))
        assistantQueueSelectedItemIDs = assistantQueueSelectedItemIDs.intersection(visibleIDs)
    }

    private static func assistantQueueExecutionMessage(for error: Error) -> String {
        switch error {
        case AssistantQueueExecutionError.unsupportedPayload:
            return "This Assistant Queue item cannot run from Project Board yet."
        case AssistantQueueTransitionError.approvalRequiredBeforeRunning:
            return "Approve this Assistant Queue item before running it."
        case AssistantQueueTransitionError.approvedPayloadChanged:
            return "Review this Assistant Queue item again because it changed after approval."
        case AssistantQueueTransitionError.runningRequiredBeforeCompletion:
            return "Assistant Queue execution is not in a runnable state."
        case AssistantQueueTransitionError.blockedItemCannotBeApproved,
             AssistantQueueTransitionError.dangerousPayloadCannotBeApproved:
            return "Dangerous Assistant Queue items cannot be executed."
        case AssistantQueueTransitionError.terminalItemCannotTransition:
            return "Assistant Queue item was already reviewed."
        case AssistantQueueTransitionError.editRequiresReviewableItem:
            return "Only reviewable Assistant Queue items can be edited."
        default:
            return "Assistant Queue execution could not be completed."
        }
    }

    private static func reviewCalendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
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

    private static func googleCalendarSyncStatusMessage(for result: GoogleCalendarTaskSyncResult) -> String {
        let createdLabel = String(
            format: String(localized: result.createdEventCount == 1 ? "%d Google Calendar event" : "%d Google Calendar events"),
            result.createdEventCount
        )
        guard result.skippedAlreadyLinkedCount > 0 else {
            return String(format: String(localized: "Created %@."), createdLabel)
        }

        let skippedLabel = String(
            format: String(localized: result.skippedAlreadyLinkedCount == 1 ? "%d already-linked task" : "%d already-linked tasks"),
            result.skippedAlreadyLinkedCount
        )
        return String(format: String(localized: "Created %@. Skipped %@."), createdLabel, skippedLabel)
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

    @discardableResult
    public func assignProjectWorkspacePath(_ path: String, bookmarkData: Data? = nil, projectID: Int64? = nil) -> Bool {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return false
        }

        do {
            _ = try store.setProjectWorkspacePath(id: targetProjectID, path: path, bookmarkData: bookmarkData)
            load()
            selectedProjectID = targetProjectID
            selectedTaskID = nil
            errorMessage = nil
            onChange()
            return true
        } catch ProjectBoardStoreError.nonAbsoluteWorkspacePath {
            errorMessage = "Project directory must be an absolute local path."
            return false
        } catch ProjectBoardStoreError.missingWorkspaceBookmark {
            errorMessage = "Project directory permission could not be saved. Choose the directory again."
            return false
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func clearProjectWorkspacePath(projectID: Int64? = nil) -> Bool {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return false
        }

        do {
            _ = try store.setProjectWorkspacePath(id: targetProjectID, path: nil, bookmarkData: nil)
            load()
            selectedProjectID = targetProjectID
            selectedTaskID = nil
            errorMessage = nil
            onChange()
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func reportProjectWorkspaceSelectionFailure() {
        errorMessage = "Project directory permission could not be saved. Choose the directory again."
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
                // Project conversion deletes the original Inbox task with its
                // project. Move capture metadata first so voice memos keep their
                // transcript and retry state across Undo.
                _ = try inboxCaptureStore?.relinkCaptures(fromTaskID: originalTask.id, toTaskID: recreatedTask.id)
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

    public func reopenCompletedTask(id: Int64) {
        moveTask(id: id, to: .planned)
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

    @discardableResult
    public func createProjectMilestone(title: String, dueAt: String? = nil, projectID: Int64? = nil) -> ProjectBoardMilestone? {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return nil
        }

        do {
            let milestone = try store.createProjectMilestone(projectID: targetProjectID, title: title, dueAt: dueAt)
            load()
            selectedProjectID = targetProjectID
            errorMessage = nil
            onChange()
            return milestone
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Milestone title is required."
            return nil
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func completeProjectMilestone(id: Int64, projectID: Int64? = nil) -> ProjectBoardMilestone? {
        guard let milestone = snapshot.projects.flatMap(\.milestones).first(where: { $0.id == id }) else {
            errorMessage = "Milestone is no longer available."
            return nil
        }

        do {
            let updated = try store.updateProjectMilestone(
                id: id,
                title: milestone.title,
                dueAt: milestone.dueAt,
                isCompleted: true
            )
            load()
            selectedProjectID = projectID ?? milestone.projectID
            errorMessage = nil
            onChange()
            return updated
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func answerProjectAssistantQuestion(_ rawQuestion: String, projectID: Int64? = nil) -> ProjectAssistantAnswer? {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            errorMessage = "Assistant question is required."
            return nil
        }
        guard let project = project(for: projectID) else {
            errorMessage = "Project is required."
            return nil
        }

        let task = project.tasks.first { $0.status == .blocked }
            ?? project.tasks.first { $0.status != .done && $0.priority == .high }
            ?? project.tasks.filter { $0.status != .done }.sorted { ($0.dueAt ?? "9999") < ($1.dueAt ?? "9999") }.first
        let milestone = project.milestones.filter { !$0.isCompleted }.sorted { ($0.dueAt ?? "9999") < ($1.dueAt ?? "9999") }.first
        let actionTitle = task?.status == .blocked
            ? String(localized: "Review unblock plan")
            : String(localized: "Review next action")
        let answer = ProjectAssistantAnswer(
            projectID: project.id,
            question: question,
            message: localAssistantMessage(project: project, task: task, milestone: milestone),
            suggestedActionTitle: actionTitle,
            requiresReview: true
        )
        projectAssistantAnswer = answer
        projectAssistantReviewDraft = nil
        errorMessage = nil
        return answer
    }

    @discardableResult
    public func prepareProjectAssistantSuggestedActionForReview(projectID: Int64? = nil) -> Bool {
        guard let answer = projectAssistantAnswer,
              let project = project(for: projectID ?? answer.projectID) else {
            errorMessage = "Ask the project assistant before preparing review."
            return false
        }

        // Assistant suggestions stay approval-first. This records the proposed
        // next step for a Review flow instead of mutating tasks immediately.
        projectAssistantReviewDraft = ProjectAssistantReviewDraft(
            projectID: project.id,
            suggestedActionTitle: answer.suggestedActionTitle,
            summary: answer.message
        )
        selectedProjectID = project.id
        selectedTaskID = nil
        errorMessage = nil
        return true
    }

    private func project(for projectID: Int64?) -> ProjectBoardProject? {
        if let projectID {
            return snapshot.projects.first { $0.id == projectID }
        }
        return selectedProject
    }

    private func localAssistantMessage(
        project: ProjectBoardProject,
        task: ProjectBoardTask?,
        milestone: ProjectBoardMilestone?
    ) -> String {
        if let task, let milestone {
            return String(
                format: String(localized: "Start with %@, then check milestone %@."),
                task.title,
                milestone.title
            )
        }
        if let task {
            return String(format: String(localized: "Start with %@."), task.title)
        }
        if let milestone {
            return String(format: String(localized: "Next milestone is %@."), milestone.title)
        }
        return String(localized: "No open tasks or milestones need attention.")
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

        if shouldAdvanceInboxSelection, let nextInboxTask = filteredInboxTasks.first(where: { $0.id != originalTask.id }) {
            selectedProjectID = nextInboxTask.projectID
            selectedTaskID = nextInboxTask.id
        }

        inboxClassificationFeedback = feedback
        lastInboxClassificationUndo = undo
        errorMessage = nil
    }

    private func ensureSelectedTaskIsVisibleInInboxFilter() {
        let visibleTasks = filteredInboxTasks
        guard let selectedTaskID else {
            if let first = visibleTasks.first {
                selectedProjectID = first.projectID
                self.selectedTaskID = first.id
            }
            return
        }

        guard !visibleTasks.contains(where: { $0.id == selectedTaskID }) else {
            return
        }

        selectedProjectID = visibleTasks.first?.projectID ?? inboxProject?.id
        self.selectedTaskID = visibleTasks.first?.id
    }

    private func matchesInboxTriageFilter(_ task: ProjectBoardTask, filter: InboxTriageFilter) -> Bool {
        guard filter != .all else {
            return true
        }

        let captures = captureRecords(for: task.id)
        switch filter {
        case .all:
            return true
        case .voice:
            return captures.contains { $0.sourceKind == .voiceMemo }
        case .aiSuggested:
            return captures.contains {
                $0.transcriptionStatus == .succeeded
                    && $0.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        case .manual:
            return captures.isEmpty
        case .unprocessed:
            return task.status == .backlog && task.dueAt == nil
        }
    }

    private func captureRecords(for taskID: Int64, reportErrors: Bool = false) -> [InboxCaptureRecord] {
        if let records = inboxCaptureRecordsByTaskID[taskID] {
            return records
        }
        guard let inboxCaptureStore else {
            // Older test/runtime surfaces can instantiate the board without
            // capture metadata. Treat those items as manual captures so the
            // Inbox remains usable instead of hiding work behind a missing store.
            return []
        }

        do {
            let records = try inboxCaptureStore.list(taskID: taskID)
            inboxCaptureRecordsByTaskID[taskID] = records
            return records
        } catch {
            if reportErrors {
                errorMessage = InboxCaptureStoreError.userMessage(for: error)
            }
            return []
        }
    }

    private func refreshInboxCaptureCache(for snapshot: ProjectBoardSnapshot) -> String? {
        guard let inboxCaptureStore else {
            inboxCaptureRecordsByTaskID = [:]
            return nil
        }

        var refreshedRecords = inboxCaptureRecordsByTaskID
        var firstErrorMessage: String?
        let taskIDs = Self.inboxTaskIDs(in: snapshot)
        for taskID in taskIDs {
            do {
                refreshedRecords[taskID] = try inboxCaptureStore.list(taskID: taskID)
            } catch {
                refreshedRecords[taskID] = []
                if firstErrorMessage == nil {
                    firstErrorMessage = InboxCaptureStoreError.userMessage(for: error)
                }
            }
        }
        inboxCaptureRecordsByTaskID = refreshedRecords
        return firstErrorMessage
    }

    private func refreshInboxCaptureCacheForInbox() {
        if let errorMessage = refreshInboxCaptureCache(for: snapshot) {
            self.errorMessage = errorMessage
        }
    }

    private static func inboxTaskIDs(in snapshot: ProjectBoardSnapshot) -> Set<Int64> {
        guard let inboxProject = snapshot.projects.first(where: {
            $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived
        }) else {
            return []
        }
        return Set(inboxProject.tasks.map(\.id))
    }

    private func replaceCachedCapture(_ updated: InboxCaptureRecord) {
        var records = inboxCaptureRecordsByTaskID[updated.taskID] ?? []
        if let index = records.firstIndex(where: { $0.id == updated.id }) {
            records[index] = updated
        } else {
            records.insert(updated, at: 0)
        }
        inboxCaptureRecordsByTaskID[updated.taskID] = records.sorted { $0.id > $1.id }
    }

    private static func inboxInterpretationConfidence(from memo: String?) -> String? {
        guard let memo else {
            return nil
        }
        let prefix = "Confidence:"
        guard let range = memo.range(of: prefix, options: [.caseInsensitive]) else {
            return nil
        }
        let value = memo[range.upperBound...]
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return value?.isEmpty == false ? value : nil
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

    private func updatedDate(for rawUpdatedAt: String?) -> Date? {
        guard let rawUpdatedAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawUpdatedAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: rawUpdatedAt) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawUpdatedAt)
    }

    private func missedTaskReasons(
        for task: ProjectBoardTask,
        dayInterval: DateInterval,
        staleCutoff: Date
    ) -> [MissedTaskReviewReason] {
        var reasons: [MissedTaskReviewReason] = []
        let taskDueDate = dueDate(for: task.dueAt)
        if taskDueDate.map({ $0 < dayInterval.start }) == true {
            reasons.append(.overdue)
        } else if let taskDueDate, taskDueDate >= dayInterval.start && taskDueDate < dayInterval.end {
            reasons.append(.dueToday)
        }
        if task.status == .blocked {
            reasons.append(.blocked)
        }
        if task.dueAt == nil {
            reasons.append(.unscheduled)
        }
        if updatedDate(for: task.updatedAt).map({ $0 < staleCutoff }) == true {
            reasons.append(.stale)
        }
        return reasons
    }

    private func missedTaskReviewState(
        taskID: Int64,
        referenceDate: Date,
        calendar: Calendar,
        didFail: inout Bool
    ) -> (lastReviewedAt: Date?, isNewlyMissed: Bool) {
        do {
            let lastReviewedAt = try missedTaskReviewStateStore.lastReviewedAt(taskID: taskID)
            return (
                lastReviewedAt,
                lastReviewedAt.map { !calendar.isDate($0, inSameDayAs: referenceDate) } ?? true
            )
        } catch {
            // Review state failures use a conservative fallback so a corrupted
            // local store cannot re-queue tasks the user already acknowledged.
            didFail = true
            return (nil, false)
        }
    }

    private func isImmediateMissedTask(_ item: MissedTaskReviewItem) -> Bool {
        item.reasons.contains(.overdue)
            || item.reasons.contains(.blocked)
            || item.reasons.contains(.unscheduled)
            || item.reasons.contains(.stale)
    }

    private func sortMissedTaskReviewItems(_ lhs: MissedTaskReviewItem, _ rhs: MissedTaskReviewItem) -> Bool {
        let lhsRank = missedTaskQueueRank(lhs)
        let rhsRank = missedTaskQueueRank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.task.priority.sortRank != rhs.task.priority.sortRank {
            return lhs.task.priority.sortRank < rhs.task.priority.sortRank
        }
        let lhsDueDate = dueDate(for: lhs.task.dueAt) ?? .distantFuture
        let rhsDueDate = dueDate(for: rhs.task.dueAt) ?? .distantFuture
        if lhsDueDate != rhsDueDate {
            return lhsDueDate < rhsDueDate
        }
        return lhs.task.id > rhs.task.id
    }

    private func missedTaskQueueRank(_ item: MissedTaskReviewItem) -> Int {
        if item.reasons.contains(.overdue) {
            return 0
        }
        if item.reasons.contains(.blocked) {
            return 1
        }
        if item.reasons.contains(.stale) {
            return 2
        }
        if item.reasons.contains(.unscheduled) {
            return 3
        }
        return 4
    }

    private func completedDate(for task: ProjectBoardTask) -> Date? {
        guard let rawCompletedAt = task.completedAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawCompletedAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: rawCompletedAt) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawCompletedAt)
    }

    private static func doneStreakDays(
        from completedDayStarts: Set<Date>,
        on referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start else {
            return 0
        }

        var streak = 0
        var cursor = referenceDayStart
        while completedDayStarts.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }

    private func projectPortfolioSummary(
        for project: ProjectBoardProject,
        on referenceDate: Date,
        calendar: Calendar
    ) -> ProjectPortfolioSummary {
        let tasks = project.tasks
        let openTasks = tasks.filter { $0.status != .done }
        let doneTaskCount = tasks.count - openTasks.count
        let blockedTaskCount = openTasks.filter { $0.status == .blocked }.count
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let overdueTasks = openTasks.filter { task in
            dueDate(for: task.dueAt).map { $0 < dayStart } == true
        }
        let nextDueTask = openTasks
            .filter { dueDate(for: $0.dueAt) != nil }
            .sorted { lhs, rhs in
                let lhsDate = dueDate(for: lhs.dueAt) ?? .distantFuture
                let rhsDate = dueDate(for: rhs.dueAt) ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.id > rhs.id
                }
                return lhsDate < rhsDate
            }
            .first
        let nextActionTask = openTasks
            .sorted { lhs, rhs in
                if lhs.status == .blocked && rhs.status != .blocked {
                    return true
                }
                if lhs.status != .blocked && rhs.status == .blocked {
                    return false
                }
                let lhsDate = dueDate(for: lhs.dueAt) ?? .distantFuture
                let rhsDate = dueDate(for: rhs.dueAt) ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.id > rhs.id
                }
                return lhsDate < rhsDate
            }
            .first
        let progress = tasks.isEmpty ? 0 : Double(doneTaskCount) / Double(tasks.count)
        let health = projectPortfolioHealth(
            project: project,
            openTaskCount: openTasks.count,
            blockedTaskCount: blockedTaskCount,
            overdueTaskCount: overdueTasks.count,
            progress: progress
        )

        return ProjectPortfolioSummary(
            projectID: project.id,
            title: project.title,
            status: project.status,
            progress: progress,
            openTaskCount: openTasks.count,
            doneTaskCount: doneTaskCount,
            blockedTaskCount: blockedTaskCount,
            overdueTaskCount: overdueTasks.count,
            nextDueAt: nextDueTask?.dueAt,
            recentTaskID: tasks.map(\.id).max(),
            nextActionTitle: nextActionTask?.title ?? "No open tasks",
            health: health,
            riskReason: projectPortfolioRiskReason(
                health: health,
                blockedTaskCount: blockedTaskCount,
                overdueTaskCount: overdueTasks.count,
                progress: progress
            ),
            // The portfolio view must be explainable and work offline; keep this
            // deterministic instead of routing health through an LLM.
            localHealthRuleDescription: "Local Health prioritizes blocked tasks, then overdue work, then open task progress."
        )
    }

    private func projectPortfolioHealth(
        project: ProjectBoardProject,
        openTaskCount: Int,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        progress: Double
    ) -> ProjectPortfolioHealth {
        if project.isCompleted || (openTaskCount == 0 && progress > 0) {
            return .completed
        }
        if blockedTaskCount > 0 || overdueTaskCount > 0 {
            return .atRisk
        }
        if progress < 0.25 && openTaskCount > 0 {
            return .attention
        }
        return .onTrack
    }

    private func projectPortfolioRiskReason(
        health: ProjectPortfolioHealth,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        progress: Double
    ) -> String {
        var reasons: [String] = []
        if blockedTaskCount > 0 {
            reasons.append("\(blockedTaskCount) blocked")
        }
        if overdueTaskCount > 0 {
            reasons.append("\(overdueTaskCount) overdue")
        }
        if !reasons.isEmpty {
            return reasons.joined(separator: ", ")
        }
        switch health {
        case .completed:
            return "All tracked tasks are done."
        case .attention:
            return "Progress is below 25% with open work."
        case .onTrack:
            return "No blocked or overdue open tasks."
        case .atRisk:
            return "Local risk rule detected schedule pressure."
        }
    }

    private func isInboxProject(_ project: ProjectBoardProject) -> Bool {
        project.title.caseInsensitiveCompare("Inbox") == .orderedSame
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

    private func todayAssistantRailContext(
        source: TodayAssistantRailSource,
        task: ProjectBoardTask,
        plan: TodayWorkflowPlan,
        nextActionTitle: String,
        nextActionReason: String
    ) -> TodayAssistantRailContext {
        TodayAssistantRailContext(
            source: source,
            task: task,
            projectTitle: projectTitle(for: task),
            nextActionTitle: nextActionTitle,
            nextActionReason: nextActionReason,
            nextBlockLabel: plan.timeBlocks.first { $0.task.id == task.id }?.label,
            notes: task.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "No notes yet.")
                : task.detail,
            // This context powers a personal-MVP rail, so it exposes draft state
            // without pretending a subtask/reminder persistence model exists yet.
            subtaskSummary: String(localized: "Subtask capture is staged through the Today command."),
            reminderSummary: String(localized: "Reminder draft only; external writes require approval.")
        )
    }

    private func prioritizedTodayTimeBlocks(
        plan: TodayWorkflowPlan,
        taskID: Int64?,
        referenceDate: Date,
        calendar: Calendar
    ) -> [TodayTimeBlock] {
        guard let taskID,
              let task = plan.tasks.first(where: { $0.id == taskID }) else {
            return plan.timeBlocks
        }

        // The rail action is an explicit user choice, so the draft must include
        // that task even when the normal recommendation order would place it later.
        return timeBlocks(
            for: orderedTimeBlockTasks(plan.tasks, recommendedTask: task),
            startingAt: referenceDate,
            calendar: calendar
        )
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
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = calendar.timeZone

        return tasks.prefix(4).enumerated().compactMap { offset, task in
            guard let start = calendar.date(byAdding: .minute, value: offset * 30, to: firstBlockStart),
                  let end = calendar.date(byAdding: .minute, value: 30, to: start) else {
                return nil
            }
            return TodayTimeBlock(
                label: "\(formatter.string(from: start))-\(formatter.string(from: end))",
                task: task,
                startAt: isoFormatter.string(from: start),
                endAt: isoFormatter.string(from: end)
            )
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

private extension ProjectPortfolioHealth {
    var sortRank: Int {
        switch self {
        case .atRisk:
            0
        case .attention:
            1
        case .onTrack:
            2
        case .completed:
            3
        }
    }
}

private extension ProjectTaskPriority {
    var sortRank: Int {
        switch self {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
    }
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
