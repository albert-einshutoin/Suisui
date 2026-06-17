import Foundation
@testable import SoloPMCore

final class FakeFileMonitorClient: FileMonitorClient, @unchecked Sendable {
    private var events: [FileMonitorEvent]
    private let lock = NSLock()

    init(events: [FileMonitorEvent] = []) {
        self.events = events
    }

    func nextEvent() throws -> FileMonitorEvent? {
        lock.lock()
        defer { lock.unlock() }

        guard !events.isEmpty else {
            return nil
        }
        return events.removeFirst()
    }
}

struct StaticPermissionManager: PermissionManager {
    private var currentSnapshot: PermissionSnapshot

    init(snapshot: PermissionSnapshot = .empty) {
        self.currentSnapshot = snapshot
    }

    func snapshot() -> PermissionSnapshot {
        currentSnapshot
    }

    func status(for permission: AppPermission) -> PermissionStatus {
        currentSnapshot.status(for: permission)
    }
}

struct StaticMenuBarSummaryProvider: MenuBarSummaryProviding {
    var summary: MenuBarSummary

    init(summary: MenuBarSummary) {
        self.summary = summary
    }

    func loadMenuBarSummary() throws -> MenuBarSummary {
        summary
    }
}

struct StaticTool: Tool {
    var name: ActionTool
    var description: String
    var inputSchema: ToolInputSchema
    var permissionLevel: ToolPermissionLevel
    private var handler: @Sendable ([String: JSONValue], ToolExecutionContext) throws -> ToolResult

    init(
        name: ActionTool,
        description: String,
        inputSchema: ToolInputSchema,
        permissionLevel: ToolPermissionLevel,
        handler: @escaping @Sendable ([String: JSONValue], ToolExecutionContext) throws -> ToolResult
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.permissionLevel = permissionLevel
        self.handler = handler
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)
        return try handler(arguments, context)
    }
}
