import Foundation

/// Versioned, JSON-stable envelope for a full local workspace backup.
///
/// The document intentionally uses its own DTO structs instead of the SQLite
/// record types so the on-disk format stays stable even when store records
/// gain fields. It contains projects (including archived and completed),
/// tasks (including completed, with recurrence/detail/completedAt), and
/// knowledge frames.
///
/// SECURITY: the backed-up stores hold no secrets (no API keys, tokens, or
/// Keychain material), and this format must never grow secret-bearing fields.
/// Security-scoped workspace bookmark data is deliberately excluded because
/// it is machine-specific binary data that cannot be restored elsewhere.
public struct WorkspaceBackupDocument: Codable, Equatable, Sendable {
    public struct Project: Codable, Equatable, Sendable {
        public var id: Int64
        public var title: String
        public var status: String
        public var priority: String?
        public var deadline: String?
        public var workspacePath: String?
        public var tags: [String]
        public var sourceCommand: String?

        public init(
            id: Int64,
            title: String,
            status: String,
            priority: String? = nil,
            deadline: String? = nil,
            workspacePath: String? = nil,
            tags: [String] = [],
            sourceCommand: String? = nil
        ) {
            self.id = id
            self.title = title
            self.status = status
            self.priority = priority
            self.deadline = deadline
            self.workspacePath = workspacePath
            self.tags = tags
            self.sourceCommand = sourceCommand
        }

        init(record: ProjectRecord) {
            self.init(
                id: record.id,
                title: record.title,
                status: record.status,
                priority: record.priority,
                deadline: record.deadline,
                workspacePath: record.workspacePath,
                tags: record.tags,
                sourceCommand: record.sourceCommand
            )
        }
    }

    public struct Task: Codable, Equatable, Sendable {
        public var id: Int64
        public var projectID: Int64?
        public var title: String
        public var status: String
        public var dueAt: String?
        public var completedAt: String?
        public var priority: String?
        public var sourceCommand: String?
        public var detail: String?
        public var recurrence: String?

        public init(
            id: Int64,
            projectID: Int64? = nil,
            title: String,
            status: String,
            dueAt: String? = nil,
            completedAt: String? = nil,
            priority: String? = nil,
            sourceCommand: String? = nil,
            detail: String? = nil,
            recurrence: String? = nil
        ) {
            self.id = id
            self.projectID = projectID
            self.title = title
            self.status = status
            self.dueAt = dueAt
            self.completedAt = completedAt
            self.priority = priority
            self.sourceCommand = sourceCommand
            self.detail = detail
            self.recurrence = recurrence
        }

        init(record: TaskRecord) {
            self.init(
                id: record.id,
                projectID: record.projectID,
                title: record.title,
                status: record.status,
                dueAt: record.dueAt,
                completedAt: record.completedAt,
                priority: record.priority,
                sourceCommand: record.sourceCommand,
                detail: record.detail,
                recurrence: record.recurrence
            )
        }
    }

    public struct KnowledgeFrame: Codable, Equatable, Sendable {
        public var id: Int64
        public var name: String
        public var body: String
        public var triggers: [String]

        public init(id: Int64, name: String, body: String, triggers: [String] = []) {
            self.id = id
            self.name = name
            self.body = body
            self.triggers = triggers
        }

        init(record: KnowledgeFrameRecord) {
            self.init(id: record.id, name: record.name, body: record.body, triggers: record.triggers)
        }
    }

    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var projects: [Project]
    public var tasks: [Task]
    public var knowledgeFrames: [KnowledgeFrame]

    public init(
        formatVersion: Int = WorkspaceBackupDocument.currentFormatVersion,
        exportedAt: Date,
        projects: [Project],
        tasks: [Task],
        knowledgeFrames: [KnowledgeFrame]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.projects = projects
        self.tasks = tasks
        self.knowledgeFrames = knowledgeFrames
    }
}

/// Result counts for a merge restore, shown to the user before and after
/// applying a backup document.
public struct WorkspaceRestoreSummary: Equatable, Sendable {
    public var projectsCreated: Int
    public var tasksCreated: Int
    public var framesCreated: Int
    public var framesSkipped: Int

    public init(projectsCreated: Int, tasksCreated: Int, framesCreated: Int, framesSkipped: Int) {
        self.projectsCreated = projectsCreated
        self.tasksCreated = tasksCreated
        self.framesCreated = framesCreated
        self.framesSkipped = framesSkipped
    }
}

/// Restore strategies. Only additive merge is supported in this format
/// version; destructive replace is intentionally unavailable so a restore can
/// never delete existing local data.
public enum WorkspaceRestoreMode: Equatable, Sendable {
    case merge
}

public enum WorkspaceBackupError: Error, Equatable, Sendable {
    case unsupportedFormatVersion(Int)
}

/// Reads every project (including archived and completed), every task
/// (including completed), and every knowledge frame into a backup document.
public struct WorkspaceBackupExporter {
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let knowledgeFrameStore: SQLiteKnowledgeFrameStore

    public init(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        knowledgeFrameStore: SQLiteKnowledgeFrameStore
    ) {
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.knowledgeFrameStore = knowledgeFrameStore
    }

    public func export(now: Date = Date()) throws -> WorkspaceBackupDocument {
        WorkspaceBackupDocument(
            exportedAt: now,
            projects: try projectStore.list(includeArchived: true).map(WorkspaceBackupDocument.Project.init(record:)),
            tasks: try taskStore.listAll().map(WorkspaceBackupDocument.Task.init(record:)),
            knowledgeFrames: try knowledgeFrameStore.list().map(WorkspaceBackupDocument.KnowledgeFrame.init(record:))
        )
    }
}

/// Applies a backup document additively: projects, tasks, and frames are
/// inserted as new rows with fresh IDs, task project references are remapped
/// through an old-to-new project ID map, and knowledge frames that already
/// exist with the same name and body are skipped. Existing rows are never
/// modified or deleted.
public struct WorkspaceBackupImporter {
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let knowledgeFrameStore: SQLiteKnowledgeFrameStore

    public init(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        knowledgeFrameStore: SQLiteKnowledgeFrameStore
    ) {
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.knowledgeFrameStore = knowledgeFrameStore
    }

    @discardableResult
    public func restore(
        _ document: WorkspaceBackupDocument,
        mode: WorkspaceRestoreMode = .merge
    ) throws -> WorkspaceRestoreSummary {
        guard document.formatVersion == WorkspaceBackupDocument.currentFormatVersion else {
            throw WorkspaceBackupError.unsupportedFormatVersion(document.formatVersion)
        }

        switch mode {
        case .merge:
            break
        }

        var projectIDMap: [Int64: Int64] = [:]
        for project in document.projects {
            let created = try projectStore.create(
                title: project.title,
                priority: project.priority,
                deadline: project.deadline,
                workspacePath: project.workspacePath,
                tags: project.tags,
                sourceCommand: project.sourceCommand
            )
            var restored = created
            if project.status != created.status {
                restored = try projectStore.update(id: created.id, status: project.status)
            }
            projectIDMap[project.id] = restored.id
        }

        var tasksCreated = 0
        for task in document.tasks {
            // Tasks whose backup project is missing from the document (or was
            // dangling at export time) restore as Inbox-style unassigned rows.
            let remappedProjectID = task.projectID.flatMap { projectIDMap[$0] }
            _ = try taskStore.createForBackupRestore(
                TaskCreateDraft(
                    title: task.title,
                    projectID: remappedProjectID,
                    dueAt: task.dueAt,
                    priority: task.priority,
                    sourceCommand: task.sourceCommand,
                    status: task.status,
                    detail: task.detail,
                    recurrence: task.recurrence
                ),
                completedAt: task.completedAt
            )
            tasksCreated += 1
        }

        let existingFrames = try knowledgeFrameStore.list()
        var existingFrameKeys = Set(existingFrames.map { FrameKey(name: $0.name, body: $0.body) })
        var framesCreated = 0
        var framesSkipped = 0
        for frame in document.knowledgeFrames {
            let key = FrameKey(name: frame.name, body: frame.body)
            if existingFrameKeys.contains(key) {
                framesSkipped += 1
                continue
            }
            _ = try knowledgeFrameStore.create(name: frame.name, body: frame.body, triggers: frame.triggers)
            existingFrameKeys.insert(key)
            framesCreated += 1
        }

        return WorkspaceRestoreSummary(
            projectsCreated: projectIDMap.count,
            tasksCreated: tasksCreated,
            framesCreated: framesCreated,
            framesSkipped: framesSkipped
        )
    }

    private struct FrameKey: Hashable {
        let name: String
        let body: String
    }
}

/// JSON coding helpers with a deterministic wire format: ISO 8601 dates and
/// sorted keys so backups diff cleanly and round-trip byte-stably.
public enum WorkspaceBackupCoding {
    public static func encode(_ document: WorkspaceBackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> WorkspaceBackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkspaceBackupDocument.self, from: data)
    }
}
