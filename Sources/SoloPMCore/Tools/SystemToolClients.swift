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
        try contents.write(to: target, atomically: true, encoding: .utf8)
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
