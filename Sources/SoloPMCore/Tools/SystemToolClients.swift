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

    public init(title: String, body: String? = nil, scheduledAt: String, identifierHint: String? = nil) {
        self.title = title
        self.body = body
        self.scheduledAt = scheduledAt
        self.identifierHint = identifierHint
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

public final class InMemoryNotificationClient: NotificationClient, @unchecked Sendable {
    private let authorizationStatus: ToolClientAuthorizationStatus
    private var records: [NotificationRecord]
    private var nextID: Int
    private let lock = NSLock()

    public init(authorizationStatus: ToolClientAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        self.records = []
        self.nextID = 1
    }

    public func schedule(_ draft: NotificationDraft) throws -> NotificationRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        let id = draft.identifierHint ?? "notification-\(nextID)"
        nextID += 1
        let record = NotificationRecord(id: id, title: draft.title, body: draft.body, scheduledAt: draft.scheduledAt)
        records.append(record)
        return record
    }

    public func cancel(id: String) throws {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw ToolClientError.notFound("Notification \(id) was not found.")
        }
        records.remove(at: index)
    }

    public func listScheduled() throws -> [NotificationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    private func ensureAuthorized() throws {
        guard authorizationStatus == .authorized else {
            throw ToolClientError.permissionDenied("Notification permission is denied.")
        }
    }
}

public struct CalendarEventDraft: Equatable, Sendable {
    public var title: String
    public var startAt: String
    public var endAt: String
    public var isAllDay: Bool
    public var notes: String?

    public init(title: String, startAt: String, endAt: String, isAllDay: Bool = false, notes: String? = nil) {
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.notes = notes
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

public final class InMemoryCalendarClient: CalendarClient, @unchecked Sendable {
    private let authorizationStatus: ToolClientAuthorizationStatus
    private var records: [CalendarEventRecord]
    private var nextID: Int
    private let lock = NSLock()

    public init(authorizationStatus: ToolClientAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        self.records = []
        self.nextID = 1
    }

    public func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        let record = CalendarEventRecord(id: "calendar-event-\(nextID)", draft: draft)
        nextID += 1
        records.append(record)
        return record
    }

    public func listEvents() throws -> [CalendarEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    private func ensureAuthorized() throws {
        guard authorizationStatus == .authorized else {
            throw ToolClientError.permissionDenied("Calendar permission is denied.")
        }
    }
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

public final class InMemoryReminderClient: ReminderClient, @unchecked Sendable {
    private let authorizationStatus: ToolClientAuthorizationStatus
    private var records: [ReminderRecord]
    private var nextID: Int
    private let lock = NSLock()

    public init(authorizationStatus: ToolClientAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        self.records = []
        self.nextID = 1
    }

    public func create(_ draft: ReminderDraft) throws -> ReminderRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        let record = ReminderRecord(
            id: "reminder-\(nextID)",
            title: draft.title,
            dueAt: draft.dueAt,
            listName: draft.listName,
            isCompleted: false
        )
        nextID += 1
        records.append(record)
        return record
    }

    public func markComplete(id: String) throws -> ReminderRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw ToolClientError.notFound("Reminder \(id) was not found.")
        }
        records[index].isCompleted = true
        return records[index]
    }

    public func list() throws -> [ReminderRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    private func ensureAuthorized() throws {
        guard authorizationStatus == .authorized else {
            throw ToolClientError.permissionDenied("Reminder permission is denied.")
        }
    }
}

public struct FileArtifact: Equatable, Sendable {
    public var relativePath: String
    public var kind: String
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
        return FileArtifact(relativePath: normalizedRelativePath(for: target), kind: "directory")
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
        try contents.write(to: target, atomically: true, encoding: .utf8)
        return FileArtifact(relativePath: normalizedRelativePath(for: target), kind: "markdown")
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
                return FileArtifact(relativePath: normalizedRelativePath(for: url), kind: isDirectory.boolValue ? "directory" : "file")
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

        return target
    }

    private func normalizedRelativePath(for url: URL) -> String {
        let rootPath = workspaceRoot.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return "."
        }
        return String(path.dropFirst(rootPath.count + 1))
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
    func listDrafts() throws -> [MailDraftRecord]
}

public final class InMemoryMailDraftClient: MailDraftClient, @unchecked Sendable {
    private var records: [MailDraftRecord]
    private var nextID: Int
    private let lock = NSLock()

    public init() {
        self.records = []
        self.nextID = 1
    }

    public func createTextDraft(to: String?, subject: String, body: String) throws -> MailDraftRecord {
        lock.lock()
        defer { lock.unlock() }

        let record = MailDraftRecord(id: "mail-draft-\(nextID)", to: to, subject: subject, body: body)
        nextID += 1
        records.append(record)
        return record
    }

    public func listDrafts() throws -> [MailDraftRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}
