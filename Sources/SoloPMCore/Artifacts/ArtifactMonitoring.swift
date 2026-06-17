import Foundation

public enum ArtifactCreatedState: String, Equatable, Sendable {
    case expected
    case created
    case missing
}

public struct ArtifactRecord: Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64?
    public var taskID: Int64?
    public var workspacePath: String
    public var expectedPath: String
    public var createdState: ArtifactCreatedState
    public var lastModifiedAt: Date?

    public init(
        id: Int64,
        projectID: Int64? = nil,
        taskID: Int64? = nil,
        workspacePath: String,
        expectedPath: String,
        createdState: ArtifactCreatedState,
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.taskID = taskID
        self.workspacePath = workspacePath
        self.expectedPath = expectedPath
        self.createdState = createdState
        self.lastModifiedAt = lastModifiedAt
    }
}

public enum ArtifactStoreError: Error, Equatable {
    case notFound(Int64)
}

public final class SQLiteArtifactStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func create(
        projectID: Int64? = nil,
        taskID: Int64? = nil,
        workspacePath: String,
        expectedPath: String,
        createdState: ArtifactCreatedState = .expected,
        lastModifiedAt: Date? = nil
    ) throws -> ArtifactRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state, last_modified_at)
            VALUES (
              \(ArtifactSQL.optionalInt(projectID)),
              \(ArtifactSQL.optionalInt(taskID)),
              '\(ArtifactSQL.escape(workspacePath))',
              '\(ArtifactSQL.escape(expectedPath))',
              '\(createdState.rawValue)',
              \(ArtifactSQL.optionalDate(lastModifiedAt))
            );
            """
        )

        return try getLocked(id: connection.lastInsertedRowID)
    }

    public func get(id: Int64) throws -> ArtifactRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    public func list() throws -> [ArtifactRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM artifacts ORDER BY id ASC;").map(ArtifactRecord.init(row:))
    }

    public func updateFromFileEvent(workspacePath: String, path: String, modifiedAt: Date) throws -> [ArtifactRecord] {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            UPDATE artifacts
            SET created_state = '\(ArtifactCreatedState.created.rawValue)',
                last_modified_at = '\(DeadlineDateParser.string(from: modifiedAt))',
                updated_at = CURRENT_TIMESTAMP
            WHERE workspace_path = '\(ArtifactSQL.escape(workspacePath))'
              AND expected_path = '\(ArtifactSQL.escape(path))';
            """
        )

        return try listByWorkspaceAndExpectedPathLocked(workspacePath: workspacePath, path: path)
    }

    public func listStale(workspacePath: String, modifiedBefore cutoff: Date) throws -> [ArtifactRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM artifacts
            WHERE workspace_path = '\(ArtifactSQL.escape(workspacePath))'
              AND created_state = '\(ArtifactCreatedState.created.rawValue)'
              AND last_modified_at IS NOT NULL
              AND last_modified_at < '\(DeadlineDateParser.string(from: cutoff))'
            ORDER BY last_modified_at ASC, id ASC;
            """
        ).map(ArtifactRecord.init(row:))
    }

    private func getLocked(id: Int64) throws -> ArtifactRecord {
        guard let row = try connection.queryRows("SELECT * FROM artifacts WHERE id = \(id) LIMIT 1;").first else {
            throw ArtifactStoreError.notFound(id)
        }

        return ArtifactRecord(row: row)
    }

    private func listByWorkspaceAndExpectedPathLocked(workspacePath: String, path: String) throws -> [ArtifactRecord] {
        try connection.queryRows(
            """
            SELECT * FROM artifacts
            WHERE workspace_path = '\(ArtifactSQL.escape(workspacePath))'
              AND expected_path = '\(ArtifactSQL.escape(path))'
            ORDER BY id ASC;
            """
        ).map(ArtifactRecord.init(row:))
    }
}

public enum FileMonitorEventKind: String, Equatable, Sendable {
    case created
    case modified
    case deleted
}

public struct FileMonitorEvent: Equatable, Sendable {
    public var path: String
    public var kind: FileMonitorEventKind
    public var modifiedAt: Date?

    public init(path: String, kind: FileMonitorEventKind, modifiedAt: Date? = nil) {
        self.path = path
        self.kind = kind
        self.modifiedAt = modifiedAt
    }
}

public protocol FileMonitorClient: Sendable {
    func nextEvent() throws -> FileMonitorEvent?
}

public final class FakeFileMonitorClient: FileMonitorClient, @unchecked Sendable {
    private var events: [FileMonitorEvent]
    private let lock = NSLock()

    public init(events: [FileMonitorEvent] = []) {
        self.events = events
    }

    public func nextEvent() throws -> FileMonitorEvent? {
        lock.lock()
        defer { lock.unlock() }

        guard !events.isEmpty else {
            return nil
        }
        return events.removeFirst()
    }
}

public struct ArtifactMonitoringResult: Equatable, Sendable {
    public var updatedArtifacts: [ArtifactRecord]
    public var skippedReason: String?

    public init(updatedArtifacts: [ArtifactRecord] = [], skippedReason: String? = nil) {
        self.updatedArtifacts = updatedArtifacts
        self.skippedReason = skippedReason
    }
}

public final class ArtifactMonitoringService: @unchecked Sendable {
    private let artifactStore: SQLiteArtifactStore
    private let fileMonitorClient: any FileMonitorClient
    private let workspacePath: String
    private let dateProvider: any DateProvider

    public init(
        artifactStore: SQLiteArtifactStore,
        fileMonitorClient: any FileMonitorClient,
        workspacePath: String,
        dateProvider: any DateProvider = SystemDateProvider()
    ) {
        self.artifactStore = artifactStore
        self.fileMonitorClient = fileMonitorClient
        self.workspacePath = workspacePath
        self.dateProvider = dateProvider
    }

    public func applyNextEvent() throws -> ArtifactMonitoringResult {
        guard let event = try fileMonitorClient.nextEvent() else {
            return ArtifactMonitoringResult(skippedReason: "no_event")
        }

        guard WorkspacePathPolicy.isPath(event.path, inside: workspacePath) else {
            return ArtifactMonitoringResult(skippedReason: "outside_workspace")
        }

        switch event.kind {
        case .created, .modified:
            let modifiedAt = event.modifiedAt ?? dateProvider.now
            let updated = try artifactStore.updateFromFileEvent(
                workspacePath: workspacePath,
                path: event.path,
                modifiedAt: modifiedAt
            )
            return ArtifactMonitoringResult(updatedArtifacts: updated)
        case .deleted:
            return ArtifactMonitoringResult(skippedReason: "deleted_event")
        }
    }

    public func staleArtifacts(olderThan interval: TimeInterval) throws -> [ArtifactRecord] {
        let cutoff = dateProvider.now.addingTimeInterval(-interval)
        return try artifactStore.listStale(workspacePath: workspacePath, modifiedBefore: cutoff)
    }
}

public enum ArtifactProgressIssueKind: String, Equatable, Sendable {
    case missingFile
    case staleFile
    case incompleteBeforeDeadline
}

public struct ArtifactProgressIssue: Equatable, Sendable {
    public var artifact: ArtifactRecord
    public var kind: ArtifactProgressIssueKind
    public var deadlineRuleTarget: DeadlineRuleTarget?
    public var referenceDate: Date?

    public init(
        artifact: ArtifactRecord,
        kind: ArtifactProgressIssueKind,
        deadlineRuleTarget: DeadlineRuleTarget? = nil,
        referenceDate: Date? = nil
    ) {
        self.artifact = artifact
        self.kind = kind
        self.deadlineRuleTarget = deadlineRuleTarget
        self.referenceDate = referenceDate
    }
}

public final class ArtifactProgressDetector: @unchecked Sendable {
    private let artifactStore: SQLiteArtifactStore
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let dateProvider: any DateProvider

    public init(
        artifactStore: SQLiteArtifactStore,
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        dateProvider: any DateProvider = SystemDateProvider()
    ) {
        self.artifactStore = artifactStore
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.dateProvider = dateProvider
    }

    public func detectIssues(staleAfter: TimeInterval, deadlineLeadTime: TimeInterval) throws -> [ArtifactProgressIssue] {
        let now = dateProvider.now
        let staleCutoff = now.addingTimeInterval(-staleAfter)
        let deadlineCutoff = now.addingTimeInterval(deadlineLeadTime)

        var issues: [ArtifactProgressIssue] = []
        for artifact in try artifactStore.list() {
            let target = deadlineRuleTarget(for: artifact)
            let dueAt = try deadlineDate(for: artifact)

            if artifact.createdState != .created {
                issues.append(
                    ArtifactProgressIssue(
                        artifact: artifact,
                        kind: .missingFile,
                        deadlineRuleTarget: target
                    )
                )
            } else if let lastModifiedAt = artifact.lastModifiedAt,
                      lastModifiedAt < staleCutoff {
                issues.append(
                    ArtifactProgressIssue(
                        artifact: artifact,
                        kind: .staleFile,
                        deadlineRuleTarget: target,
                        referenceDate: lastModifiedAt
                    )
                )
            }

            if artifact.createdState != .created,
               let dueAt,
               dueAt >= now,
               dueAt <= deadlineCutoff {
                issues.append(
                    ArtifactProgressIssue(
                        artifact: artifact,
                        kind: .incompleteBeforeDeadline,
                        deadlineRuleTarget: target,
                        referenceDate: dueAt
                    )
                )
            }
        }

        return issues
    }

    private func deadlineRuleTarget(for artifact: ArtifactRecord) -> DeadlineRuleTarget? {
        if let taskID = artifact.taskID {
            return .task(taskID)
        }
        if let projectID = artifact.projectID {
            return .project(projectID)
        }
        return nil
    }

    private func deadlineDate(for artifact: ArtifactRecord) throws -> Date? {
        if let taskID = artifact.taskID {
            return try taskStore.get(id: taskID).dueAt.flatMap(DeadlineDateParser.date(from:))
        }
        if let projectID = artifact.projectID {
            return try projectStore.get(id: projectID).deadline.flatMap(DeadlineDateParser.date(from:))
        }
        return nil
    }
}

public enum WorkspacePathPolicy {
    public static func isPath(_ path: String, inside workspacePath: String) -> Bool {
        let normalizedPath = normalize(path)
        let normalizedWorkspace = normalize(workspacePath)
        if normalizedWorkspace == "/" {
            return normalizedPath.hasPrefix("/")
        }
        return normalizedPath == normalizedWorkspace || normalizedPath.hasPrefix(normalizedWorkspace + "/")
    }

    private static func normalize(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardized.path
        guard standardized != "/" else {
            return standardized
        }
        return standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }
}

private extension ArtifactRecord {
    init(row: [String: String]) {
        self.init(
            id: Int64(row["id"] ?? "") ?? 0,
            projectID: Int64(row["project_id"] ?? ""),
            taskID: Int64(row["task_id"] ?? ""),
            workspacePath: row["workspace_path"] ?? "",
            expectedPath: row["expected_path"] ?? "",
            createdState: ArtifactCreatedState(rawValue: row["created_state"] ?? "") ?? .expected,
            lastModifiedAt: row["last_modified_at"].flatMap(DeadlineDateParser.date(from:))
        )
    }
}

private enum ArtifactSQL {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    static func optionalInt(_ value: Int64?) -> String {
        value.map(String.init) ?? "NULL"
    }

    static func optionalDate(_ value: Date?) -> String {
        guard let value else {
            return "NULL"
        }
        return "'\(DeadlineDateParser.string(from: value))'"
    }
}
