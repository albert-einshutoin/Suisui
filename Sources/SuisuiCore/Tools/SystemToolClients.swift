import Foundation

public enum ToolClientAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
}

public enum ToolClientError: Error, Equatable, Sendable {
    case permissionDenied(String)
    case invalidRequest(String)
    case notFound(String)
    case conflict(String)

    public var message: String {
        switch self {
        case .permissionDenied(let message),
             .invalidRequest(let message),
             .notFound(let message),
             .conflict(let message):
            message
        }
    }
}

public struct NotificationDraft: Equatable, Sendable {
    public var title: String
    public var body: String?
    public var scheduledAt: String
    public var identifierHint: String?
    public var categoryIdentifier: String?
    public var userInfo: [String: String]

    public init(
        title: String,
        body: String? = nil,
        scheduledAt: String,
        identifierHint: String? = nil,
        categoryIdentifier: String? = nil,
        userInfo: [String: String] = [:]
    ) {
        self.title = title
        self.body = body
        self.scheduledAt = scheduledAt
        self.identifierHint = identifierHint
        self.categoryIdentifier = categoryIdentifier
        self.userInfo = userInfo
    }
}

public struct NotificationRecord: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String?
    public var scheduledAt: String

    public init(id: String, title: String, body: String? = nil, scheduledAt: String) {
        self.id = id
        self.title = title
        self.body = body
        self.scheduledAt = scheduledAt
    }
}

public protocol NotificationClient: Sendable {
    func schedule(_ draft: NotificationDraft) throws -> NotificationRecord
    func cancel(id: String) throws
    func listScheduled() throws -> [NotificationRecord]
}

public struct CalendarEventDraft: Equatable, Sendable {
    public var title: String
    public var startAt: String
    public var endAt: String
    public var isAllDay: Bool
    public var notes: String?
    public var idempotencyKey: String?

    public init(
        title: String,
        startAt: String,
        endAt: String,
        isAllDay: Bool = false,
        notes: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.notes = notes
        self.idempotencyKey = idempotencyKey
    }
}

public struct CalendarEventRecord: Equatable, Sendable {
    public var id: String
    public var draft: CalendarEventDraft

    public init(id: String, draft: CalendarEventDraft) {
        self.id = id
        self.draft = draft
    }
}

public protocol CalendarClient: Sendable {
    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventRecord
    func listEvents() throws -> [CalendarEventRecord]
}

public struct ExternalScheduleEvent: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var isAllDay: Bool
    public var blocksAvailability: Bool
    public var location: String?
    public var allDayStartDateKey: String?
    public var allDayEndDateKey: String?

    public init(
        id: String,
        title: String,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool,
        blocksAvailability: Bool = true,
        location: String? = nil,
        allDayStartDateKey: String? = nil,
        allDayEndDateKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.blocksAvailability = blocksAvailability
        self.location = location
        self.allDayStartDateKey = allDayStartDateKey
        self.allDayEndDateKey = allDayEndDateKey
    }
}

public protocol ExternalScheduleEventSource: Sendable {
    func listEvents(in interval: DateInterval) throws -> [ExternalScheduleEvent]
}

public enum ExternalScheduleEventLoadState: Equatable, Sendable {
    case unavailable
    case loading
    case loaded
    case failed
}

public struct ReminderDraft: Equatable, Sendable {
    public var title: String
    public var dueAt: String?
    public var listName: String?

    public init(title: String, dueAt: String? = nil, listName: String? = nil) {
        self.title = title
        self.dueAt = dueAt
        self.listName = listName
    }
}

public struct ReminderRecord: Equatable, Sendable {
    public var id: String
    public var title: String
    public var dueAt: String?
    public var listName: String?
    public var isCompleted: Bool

    public init(id: String, title: String, dueAt: String? = nil, listName: String? = nil, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.listName = listName
        self.isCompleted = isCompleted
    }
}

public protocol ReminderClient: Sendable {
    func create(_ draft: ReminderDraft) throws -> ReminderRecord
    func markComplete(id: String) throws -> ReminderRecord
    func list() throws -> [ReminderRecord]
}

public struct FileArtifact: Equatable, Sendable {
    public var relativePath: String
    public var kind: String
    public var absolutePath: String?
    public var workspacePath: String?

    public init(
        relativePath: String,
        kind: String,
        absolutePath: String? = nil,
        workspacePath: String? = nil
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.absolutePath = absolutePath
        self.workspacePath = workspacePath
    }
}

public protocol FileAccessClient: Sendable {
    func createDirectory(relativePath: String) throws -> FileArtifact
    func createMarkdownFile(relativePath: String, contents: String) throws -> FileArtifact
    func scan(relativePath: String) throws -> [FileArtifact]
}

public final class LocalFileAccessClient: FileAccessClient, @unchecked Sendable {
    private let workspaceRoot: URL
    private let fileManager: FileManager

    public init(workspaceRoot: URL, fileManager: FileManager = .default) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.fileManager = fileManager
    }

    public func createDirectory(relativePath: String) throws -> FileArtifact {
        let target = try resolve(relativePath: relativePath)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw ToolClientError.conflict("Path already exists: \(relativePath)")
        }

        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        return makeArtifact(for: target, kind: "directory")
    }

    public func createMarkdownFile(relativePath: String, contents: String) throws -> FileArtifact {
        let target = try resolve(relativePath: relativePath)
        guard target.pathExtension.lowercased() == "md" else {
            throw ToolClientError.invalidRequest("Markdown artifact path must end with .md.")
        }
        guard !fileManager.fileExists(atPath: target.path) else {
            throw ToolClientError.conflict("File already exists: \(relativePath)")
        }

        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            // `.withoutOverwriting` maps the final create to O_EXCL semantics.
            // The earlier existence check improves the error message, while this
            // option closes the check-then-write race between concurrent actions.
            try Data(contents.utf8).write(to: target, options: .withoutOverwriting)
        } catch {
            if fileManager.fileExists(atPath: target.path) {
                throw ToolClientError.conflict("File already exists: \(relativePath)")
            }
            throw error
        }
        return makeArtifact(for: target, kind: "markdown")
    }

    public func scan(relativePath: String) throws -> [FileArtifact] {
        let directory = try resolve(relativePath: relativePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolClientError.notFound("Directory was not found: \(relativePath)")
        }

        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.path < $1.path }
            .map { url in
                var isDirectory: ObjCBool = false
                _ = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return makeArtifact(for: url, kind: isDirectory.boolValue ? "directory" : "file")
            }
    }

    private func resolve(relativePath: String) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else {
            throw ToolClientError.invalidRequest("Path must be relative to the workspace.")
        }

        let target = workspaceRoot.appendingPathComponent(trimmed).standardizedFileURL
        let rootPath = workspaceRoot.path
        guard target.path == rootPath || target.path.hasPrefix(rootPath + "/") else {
            throw ToolClientError.invalidRequest("Path escapes the workspace: \(relativePath)")
        }

        try validateSymlinkResolvedPathStaysInsideWorkspace(target, relativePath: relativePath)
        return target
    }

    private func validateSymlinkResolvedPathStaysInsideWorkspace(_ target: URL, relativePath: String) throws {
        let resolvedRoot = workspaceRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRootPath = resolvedRoot.path
        var nearestExistingAncestor = target.standardizedFileURL
        var unresolvedComponents: [String] = []

        while !fileManager.fileExists(atPath: nearestExistingAncestor.path),
              nearestExistingAncestor.path != workspaceRoot.path,
              nearestExistingAncestor.path != "/" {
            unresolvedComponents.insert(nearestExistingAncestor.lastPathComponent, at: 0)
            nearestExistingAncestor.deleteLastPathComponent()
        }

        let resolvedAncestor = nearestExistingAncestor.resolvingSymlinksInPath().standardizedFileURL
        guard isPathInsideWorkspace(resolvedAncestor.path, rootPath: resolvedRootPath) else {
            throw ToolClientError.invalidRequest("Path escapes the workspace: \(relativePath)")
        }

        var resolvedTarget = resolvedAncestor
        for component in unresolvedComponents {
            resolvedTarget.appendPathComponent(component)
        }

        guard isPathInsideWorkspace(resolvedTarget.standardizedFileURL.path, rootPath: resolvedRootPath) else {
            throw ToolClientError.invalidRequest("Path escapes the workspace: \(relativePath)")
        }
    }

    private func isPathInsideWorkspace(_ path: String, rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func normalizedRelativePath(for url: URL) -> String {
        let rootPath = workspaceRoot.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return "."
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func makeArtifact(for url: URL, kind: String) -> FileArtifact {
        FileArtifact(
            relativePath: normalizedRelativePath(for: url),
            kind: kind,
            absolutePath: url.standardizedFileURL.path,
            workspacePath: workspaceRoot.path
        )
    }
}

public final class SecurityScopedBookmarkFileAccessClient: FileAccessClient, @unchecked Sendable {
    private let bookmarkData: Data
    private let fileManager: FileManager

    public init(bookmarkData: Data, fileManager: FileManager = .default) {
        self.bookmarkData = bookmarkData
        self.fileManager = fileManager
    }

    public func createDirectory(relativePath: String) throws -> FileArtifact {
        try withSecurityScopedAccess { client in
            try client.createDirectory(relativePath: relativePath)
        }
    }

    public func createMarkdownFile(relativePath: String, contents: String) throws -> FileArtifact {
        try withSecurityScopedAccess { client in
            try client.createMarkdownFile(relativePath: relativePath, contents: contents)
        }
    }

    public func scan(relativePath: String) throws -> [FileArtifact] {
        try withSecurityScopedAccess { client in
            try client.scan(relativePath: relativePath)
        }
    }

    private func withSecurityScopedAccess<T>(_ body: (LocalFileAccessClient) throws -> T) throws -> T {
        var isStale = false
        let workspaceRoot = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard !isStale else {
            throw ToolClientError.invalidRequest("Workspace access bookmark is stale and must be renewed.")
        }

        let didStartAccessing = workspaceRoot.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                workspaceRoot.stopAccessingSecurityScopedResource()
            }
        }

        return try body(LocalFileAccessClient(workspaceRoot: workspaceRoot, fileManager: fileManager))
    }
}

public struct MailDraftRecord: Equatable, Sendable {
    public var id: String
    public var to: String?
    public var subject: String
    public var body: String
}

public protocol MailDraftClient: Sendable {
    func createTextDraft(to: String?, subject: String, body: String) throws -> MailDraftRecord
}

public final class LocalFileMailDraftClient: MailDraftClient, @unchecked Sendable {
    public static let defaultRetentionInterval: TimeInterval = 60 * 60 * 24 * 30

    private let draftsDirectoryURL: URL
    private let fileManager: FileManager
    private let retentionInterval: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        draftsDirectoryURL: URL,
        fileManager: FileManager = .default,
        retentionInterval: TimeInterval = LocalFileMailDraftClient.defaultRetentionInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.draftsDirectoryURL = draftsDirectoryURL.standardizedFileURL
        self.fileManager = fileManager
        self.retentionInterval = retentionInterval
        self.now = now
    }

    public func createTextDraft(to: String?, subject: String, body: String) throws -> MailDraftRecord {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBodyForValidation = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient = try normalizedRecipient(to)
        guard !trimmedSubject.isEmpty else {
            throw ToolClientError.invalidRequest("Mail draft subject is required.")
        }
        guard !trimmedBodyForValidation.isEmpty else {
            throw ToolClientError.invalidRequest("Mail draft body is required.")
        }

        // Draft contents are persisted locally only; external send/list surfaces stay in separate approved connectors.
        try prepareDraftsDirectory()
        try pruneExpiredDrafts(referenceDate: now())
        let id = "mail-draft-\(UUID().uuidString.lowercased())"
        let record = MailDraftRecord(id: id, to: recipient, subject: trimmedSubject, body: body)
        let snapshot = LocalFileMailDraftSnapshot(record: record, createdAt: ISO8601DateFormatter().string(from: now()))
        let data = try JSONEncoder.localMailDraftEncoder.encode(snapshot)
        let fileURL = draftsDirectoryURL.appendingPathComponent("\(id).json", isDirectory: false)
        guard fileManager.createFile(atPath: fileURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw ToolClientError.conflict("Mail draft file already exists.")
        }
        try excludeFromBackup(fileURL)
        return record
    }

    private func normalizedRecipient(_ value: String?) throws -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n,;:")) == nil else {
            throw ToolClientError.invalidRequest("Mail draft recipient must be a single address or contact name.")
        }
        return trimmed
    }

    private func prepareDraftsDirectory() throws {
        try fileManager.createDirectory(
            at: draftsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: draftsDirectoryURL.path)
        try excludeFromBackup(draftsDirectoryURL)
    }

    private func pruneExpiredDrafts(referenceDate: Date) throws {
        guard retentionInterval > 0 else {
            return
        }
        let files = try fileManager.contentsOfDirectory(
            at: draftsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for fileURL in files where fileURL.pathExtension == "json" {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modifiedAt = values.contentModificationDate,
                  referenceDate.timeIntervalSince(modifiedAt) > retentionInterval else {
                continue
            }
            // Business/customer text should not live forever just because a review draft was never opened.
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }
}

private struct LocalFileMailDraftSnapshot: Encodable {
    var id: String
    var to: String?
    var subject: String
    var body: String
    var createdAt: String

    init(record: MailDraftRecord, createdAt: String) {
        id = record.id
        to = record.to
        subject = record.subject
        body = record.body
        self.createdAt = createdAt
    }
}

private extension JSONEncoder {
    static var localMailDraftEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
