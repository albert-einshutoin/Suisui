import Foundation

public enum ExternalTaskSource: String, Codable, CaseIterable, Sendable {
    case soloPMJSON = "solopm_json"
    case googleCalendar = "google_calendar"
    case todoist
    case notion
    case linear
    case githubIssues = "github_issues"
}

public struct TaskInteropProject: Codable, Equatable, Sendable {
    public var localID: Int64
    public var title: String
    public var status: String

    public init(localID: Int64, title: String, status: String) {
        self.localID = localID
        self.title = title
        self.status = status
    }
}

public struct TaskInteropTask: Codable, Equatable, Sendable {
    public var localID: Int64
    public var localProjectID: Int64
    public var projectTitle: String
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?

    public init(
        localID: Int64,
        localProjectID: Int64,
        projectTitle: String,
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?
    ) {
        self.localID = localID
        self.localProjectID = localProjectID
        self.projectTitle = projectTitle
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
    }
}

public struct TaskInteropDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var projects: [TaskInteropProject]
    public var tasks: [TaskInteropTask]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        projects: [TaskInteropProject],
        tasks: [TaskInteropTask]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.projects = projects
        self.tasks = tasks
    }

    public static func decode(_ data: Data) throws -> TaskInteropDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TaskInteropDocument.self, from: data)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public final class TaskInteropExportService {
    private let store: any ProjectBoardStore

    public init(store: any ProjectBoardStore) {
        self.store = store
    }

    public func exportDocument(exportedAt: Date = Date()) throws -> TaskInteropDocument {
        let snapshot = try store.loadSnapshot(includeArchived: true)
        let projects = snapshot.projects.map {
            TaskInteropProject(localID: $0.id, title: $0.title, status: $0.status)
        }
        let tasks = snapshot.projects.flatMap { project in
            project.tasks.map { task in
                TaskInteropTask(
                    localID: task.id,
                    localProjectID: project.id,
                    projectTitle: project.title,
                    title: task.title,
                    detail: task.detail,
                    status: task.status,
                    priority: task.priority,
                    dueAt: task.dueAt
                )
            }
        }
        return TaskInteropDocument(exportedAt: exportedAt, projects: projects, tasks: tasks)
    }

    public func exportJSON(exportedAt: Date = Date()) throws -> Data {
        try exportDocument(exportedAt: exportedAt).encode()
    }
}

public struct ExternalTaskImportItem: Equatable, Sendable {
    public var source: ExternalTaskSource
    public var externalID: String
    public var projectTitle: String
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?

    public init(
        source: ExternalTaskSource,
        externalID: String,
        projectTitle: String,
        title: String,
        detail: String = "",
        status: ProjectTaskStatus = .backlog,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) {
        self.source = source
        self.externalID = externalID
        self.projectTitle = projectTitle
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
    }
}

public struct ExternalTaskImportResult: Equatable, Sendable {
    public var createdProjectCount: Int
    public var createdTaskCount: Int
    public var skippedDuplicateCount: Int

    public init(createdProjectCount: Int = 0, createdTaskCount: Int = 0, skippedDuplicateCount: Int = 0) {
        self.createdProjectCount = createdProjectCount
        self.createdTaskCount = createdTaskCount
        self.skippedDuplicateCount = skippedDuplicateCount
    }
}

public final class ExternalTaskImportService {
    private let store: any ProjectBoardStore
    private let linkStore: any ExternalTaskLinkStore

    public init(store: any ProjectBoardStore, linkStore: any ExternalTaskLinkStore) {
        self.store = store
        self.linkStore = linkStore
    }

    public func importItems(_ items: [ExternalTaskImportItem]) throws -> ExternalTaskImportResult {
        var result = ExternalTaskImportResult()

        for item in items {
            if try linkStore.link(providerID: item.source.rawValue, externalID: item.externalID) != nil {
                result.skippedDuplicateCount += 1
                continue
            }

            let project = try projectForImport(title: item.projectTitle, createdProjectCount: &result.createdProjectCount)
            let task = try store.createTask(ProjectBoardTaskDraft(
                projectID: project.id,
                title: item.title,
                detail: item.detail,
                status: item.status,
                priority: item.priority,
                dueAt: item.dueAt
            ))
            _ = try linkStore.link(
                providerID: item.source.rawValue,
                externalID: item.externalID,
                taskID: task.id,
                projectID: task.projectID,
                title: task.title
            )
            result.createdTaskCount += 1
        }

        return result
    }

    private func projectForImport(title: String, createdProjectCount: inout Int) throws -> ProjectBoardProject {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let importTitle = normalizedTitle.isEmpty ? "Imported Tasks" : normalizedTitle
        let snapshot = try store.loadSnapshot(includeArchived: true)
        if let existing = snapshot.projects.first(where: { $0.title == importTitle && !$0.isArchived }) {
            return existing
        }
        let project = try store.createProject(title: importTitle)
        createdProjectCount += 1
        return project
    }
}

public final class TaskInteropDocumentImportService {
    private let store: any ProjectBoardStore
    private let linkStore: any ExternalTaskLinkStore

    public init(store: any ProjectBoardStore, linkStore: any ExternalTaskLinkStore) {
        self.store = store
        self.linkStore = linkStore
    }

    public func importDocument(_ document: TaskInteropDocument) throws -> ExternalTaskImportResult {
        var result = ExternalTaskImportResult()

        for project in document.projects {
            let title = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                continue
            }
            let snapshot = try store.loadSnapshot(includeArchived: true)
            guard snapshot.projects.contains(where: { $0.title == title && !$0.isArchived }) == false else {
                continue
            }
            _ = try store.createProject(title: title)
            result.createdProjectCount += 1
        }

        let namespace = Self.externalNamespace(for: document)
        let taskItems = document.tasks.map { task in
            ExternalTaskImportItem(
                source: .soloPMJSON,
                externalID: "\(namespace):task:\(task.localID)",
                projectTitle: task.projectTitle,
                title: task.title,
                detail: task.detail,
                status: task.status,
                priority: task.priority,
                dueAt: task.dueAt
            )
        }
        let taskResult = try ExternalTaskImportService(store: store, linkStore: linkStore).importItems(taskItems)
        result.createdProjectCount += taskResult.createdProjectCount
        result.createdTaskCount += taskResult.createdTaskCount
        result.skippedDuplicateCount += taskResult.skippedDuplicateCount
        return result
    }

    private static func externalNamespace(for document: TaskInteropDocument) -> String {
        "exported_at:\(document.exportedAt.timeIntervalSince1970)"
    }
}

public struct ExternalTaskLinkRecord: Equatable, Sendable {
    public var id: Int64
    public var providerID: String
    public var externalID: String
    public var projectID: Int64?
    public var taskID: Int64
    public var title: String?

    public init(
        id: Int64,
        providerID: String,
        externalID: String,
        projectID: Int64?,
        taskID: Int64,
        title: String?
    ) {
        self.id = id
        self.providerID = providerID
        self.externalID = externalID
        self.projectID = projectID
        self.taskID = taskID
        self.title = title
    }
}

public protocol ExternalTaskLinkStore: Sendable {
    func link(providerID: String, externalID: String, taskID: Int64, projectID: Int64?, title: String?) throws -> ExternalTaskLinkRecord
    func link(providerID: String, externalID: String) throws -> ExternalTaskLinkRecord?
    func link(providerID: String, taskID: Int64) throws -> ExternalTaskLinkRecord?
    func list() throws -> [ExternalTaskLinkRecord]
}

public struct ExternalCalendarEventRecord: Equatable, Sendable {
    public var providerID: String
    public var externalID: String
    public var calendarID: String
    public var timeZoneIdentifier: String
    public var title: String

    public init(providerID: String, externalID: String, calendarID: String, timeZoneIdentifier: String, title: String) {
        self.providerID = providerID
        self.externalID = externalID
        self.calendarID = calendarID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.title = title
    }
}

public protocol ExternalCalendarEventSink: Sendable {
    func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String,
        context: ToolExecutionContext
    ) throws -> ExternalCalendarEventRecord
}

public struct GoogleCalendarTaskSyncResult: Equatable, Sendable {
    public var createdEventCount: Int
    public var skippedAlreadyLinkedCount: Int

    public init(createdEventCount: Int = 0, skippedAlreadyLinkedCount: Int = 0) {
        self.createdEventCount = createdEventCount
        self.skippedAlreadyLinkedCount = skippedAlreadyLinkedCount
    }
}

public final class GoogleCalendarTaskSyncService {
    private let entitlementStore: any EntitlementStore
    private let store: any ProjectBoardStore
    private let linkStore: any ExternalTaskLinkStore
    private let calendarSink: any ExternalCalendarEventSink
    private let calendarID: String
    private let timeZoneIdentifier: String

    public init(
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        calendarSink: any ExternalCalendarEventSink,
        calendarID: String,
        timeZoneIdentifier: String
    ) {
        self.entitlementStore = entitlementStore
        self.store = store
        self.linkStore = linkStore
        self.calendarSink = calendarSink
        self.calendarID = calendarID
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        let snapshot = try entitlementStore.snapshot()
        guard snapshot.plan.allows(.externalConnectorWrite) else {
            // Device sync is a personal data feature; writing to a third-party
            // calendar is an external side effect and must stay behind Pro.
            throw SyncServiceError.upgradeRequired(requiredPlan: FeatureGate.externalConnectorWrite.requiredPlan)
        }

        var result = GoogleCalendarTaskSyncResult()
        for project in try store.loadSnapshot(includeArchived: false).projects where !project.isCompleted && !project.isArchived {
            for task in project.tasks where task.status != .done && task.dueAt != nil {
                if try linkStore.link(providerID: ExternalTaskSource.googleCalendar.rawValue, taskID: task.id) != nil {
                    result.skippedAlreadyLinkedCount += 1
                    continue
                }

                let record = try calendarSink.createEvent(
                    calendarDraft(for: task, project: project),
                    calendarID: calendarID,
                    timeZoneIdentifier: timeZoneIdentifier,
                    context: context
                )
                _ = try linkStore.link(
                    providerID: ExternalTaskSource.googleCalendar.rawValue,
                    externalID: record.externalID,
                    taskID: task.id,
                    projectID: project.id,
                    title: task.title
                )
                result.createdEventCount += 1
            }
        }
        return result
    }

    private func calendarDraft(for task: ProjectBoardTask, project: ProjectBoardProject) -> CalendarEventDraft {
        let dueAt = task.dueAt ?? ""
        let isAllDay = !dueAt.contains("T")
        let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = detail.isEmpty ? "SoloPM project: \(project.title)" : "SoloPM project: \(project.title)\n\n\(detail)"
        return CalendarEventDraft(
            title: task.title,
            startAt: dueAt,
            endAt: dueAt,
            isAllDay: isAllDay,
            notes: notes
        )
    }
}
