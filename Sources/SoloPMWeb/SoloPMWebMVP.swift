import Foundation
import SoloPMCore

public enum WebAppSurface: String, Codable, CaseIterable, Equatable, Sendable {
    case taskBoard
    case taskList
    case projectDocs
    case conversation
    case automationReview
    case account
    case billing
    case devices
    case relayTokens
    case hostedMCPEndpoints
    case harnessRuns
}

public enum WebReadModelBoundary: String, Codable, Equatable, Sendable {
    case syncDomainPayload
}

public enum WebMutationEndpointBoundary: String, Codable, Equatable, Sendable {
    case cloudRelayTaskMutation
}

public enum WebAdminEndpointBoundary: String, Codable, Equatable, Sendable {
    case accountBillingDevicesRelayTokens
}

public enum WebExecutionBoundary: String, Codable, Equatable, Sendable {
    case cloudSafeActionsOnly
}

public struct WebBackendBoundary: Codable, Equatable, Sendable {
    public var readModel: WebReadModelBoundary
    public var mutationEndpoint: WebMutationEndpointBoundary
    public var adminEndpoint: WebAdminEndpointBoundary
    public var executionBoundary: WebExecutionBoundary

    public init(
        readModel: WebReadModelBoundary,
        mutationEndpoint: WebMutationEndpointBoundary,
        adminEndpoint: WebAdminEndpointBoundary,
        executionBoundary: WebExecutionBoundary
    ) {
        self.readModel = readModel
        self.mutationEndpoint = mutationEndpoint
        self.adminEndpoint = adminEndpoint
        self.executionBoundary = executionBoundary
    }
}

public struct WebAppMVPConfiguration: Codable, Equatable, Sendable {
    public var surfaces: [WebAppSurface]
    public var backendBoundary: WebBackendBoundary

    public init(surfaces: [WebAppSurface], backendBoundary: WebBackendBoundary) {
        self.surfaces = surfaces
        self.backendBoundary = backendBoundary
    }

    public static let `default` = WebAppMVPConfiguration(
        surfaces: [
            .taskBoard,
            .taskList,
            .projectDocs,
            .conversation,
            .automationReview,
            .account,
            .billing,
            .devices,
            .relayTokens,
            .hostedMCPEndpoints,
            .harnessRuns
        ],
        backendBoundary: WebBackendBoundary(
            readModel: .syncDomainPayload,
            mutationEndpoint: .cloudRelayTaskMutation,
            adminEndpoint: .accountBillingDevicesRelayTokens,
            executionBoundary: .cloudSafeActionsOnly
        )
    )
}

public enum WebTaskActionError: Error, Equatable, Sendable {
    case blankTitle
    case blankStatus
    case blankDueDate
}

public enum WebTaskAction: Equatable, Sendable {
    case create(title: String, projectID: Int64?)
    case complete(taskID: Int64)
    case changeStatus(taskID: Int64, status: String)
    case changeDueDate(taskID: Int64, dueAt: String)
    case moveToProject(taskID: Int64, projectID: Int64)

    public func mutationPayload(source: SyncMutationSource) throws -> SyncTaskMutationPayload {
        switch self {
        case let .create(title, projectID):
            let normalizedTitle = try trimmedRequired(title, error: .blankTitle)
            return SyncTaskMutationPayload(
                operation: .create,
                title: normalizedTitle,
                projectID: projectID,
                source: source,
                approvalState: .notRequired
            )
        case let .complete(taskID):
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .complete,
                status: "completed",
                source: source,
                approvalState: .pendingApproval
            )
        case let .changeStatus(taskID, status):
            let normalizedStatus = try trimmedRequired(status, error: .blankStatus)
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .update,
                status: normalizedStatus,
                source: source,
                approvalState: .pendingApproval
            )
        case let .changeDueDate(taskID, dueAt):
            let normalizedDueAt = try trimmedRequired(dueAt, error: .blankDueDate)
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .updateDueDate,
                dueAt: normalizedDueAt,
                source: source,
                approvalState: .pendingApproval
            )
        case let .moveToProject(taskID, projectID):
            return SyncTaskMutationPayload(
                taskID: taskID,
                operation: .moveProject,
                projectID: projectID,
                source: source,
                approvalState: .pendingApproval
            )
        }
    }

    private func trimmedRequired(_ value: String, error: WebTaskActionError) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw error
        }
        return trimmed
    }
}

public struct WebBoardColumn: Codable, Equatable, Sendable {
    public var status: String
    public var tasks: [SyncTaskPayload]

    public init(status: String, tasks: [SyncTaskPayload]) {
        self.status = status
        self.tasks = tasks
    }
}

public struct WebAccountState: Codable, Equatable, Sendable {
    public var userEmail: String
    public var billingPlan: String

    public init(userEmail: String, billingPlan: String) {
        self.userEmail = userEmail
        self.billingPlan = billingPlan
    }
}

public struct WebDeviceState: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var platform: String
    public var lastSeenAt: String

    public init(id: String, displayName: String, platform: String, lastSeenAt: String) {
        self.id = id
        self.displayName = displayName
        self.platform = platform
        self.lastSeenAt = lastSeenAt
    }
}

public struct WebRelayTokenState: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var lastFour: String
    public var revoked: Bool

    public init(id: String, displayName: String, lastFour: String, revoked: Bool) {
        self.id = id
        self.displayName = displayName
        self.lastFour = lastFour
        self.revoked = revoked
    }
}

public struct WebHostedMCPEndpointState: Codable, Equatable, Sendable {
    public var url: String
    public var toolNames: [String]

    public init(url: String, toolNames: [String]) {
        self.url = url
        self.toolNames = toolNames
    }
}

public struct WebWorkspaceState: Codable, Equatable, Sendable {
    public var boardColumns: [WebBoardColumn]
    public var taskList: [SyncTaskPayload]
    public var projectDocuments: [SyncDocumentPayload]
    public var conversations: [SyncConversationPayload]
    public var automationReviews: [SyncAutomationRequestPayload]
    public var account: WebAccountState
    public var devices: [WebDeviceState]
    public var relayTokens: [WebRelayTokenState]
    public var hostedMCPEndpoints: [WebHostedMCPEndpointState]
    public var harnessRuns: [SyncHarnessRunPayload]

    public init(
        boardColumns: [WebBoardColumn],
        taskList: [SyncTaskPayload],
        projectDocuments: [SyncDocumentPayload],
        conversations: [SyncConversationPayload],
        automationReviews: [SyncAutomationRequestPayload],
        account: WebAccountState,
        devices: [WebDeviceState],
        relayTokens: [WebRelayTokenState],
        hostedMCPEndpoints: [WebHostedMCPEndpointState],
        harnessRuns: [SyncHarnessRunPayload]
    ) {
        self.boardColumns = boardColumns
        self.taskList = taskList
        self.projectDocuments = projectDocuments
        self.conversations = conversations
        self.automationReviews = automationReviews
        self.account = account
        self.devices = devices
        self.relayTokens = relayTokens
        self.hostedMCPEndpoints = hostedMCPEndpoints
        self.harnessRuns = harnessRuns
    }

    public static func fixture() -> WebWorkspaceState {
        let tasks = [
            SyncTaskPayload(
                id: 1,
                projectID: 13,
                title: "Prepare hosted MCP docs",
                detail: "Document relay token setup.",
                status: "todo",
                dueAt: "2026-06-23",
                priority: "high",
                sourceCommand: "web-fixture",
                auditMetadata: SyncTaskAuditMetadata(source: .cloudRelay, sourceCommand: "web-fixture")
            ),
            SyncTaskPayload(
                id: 2,
                projectID: 13,
                title: "Review sync ledger",
                detail: "Confirm pending automation entries.",
                status: "in_progress",
                dueAt: nil,
                priority: "medium",
                sourceCommand: "web-fixture",
                auditMetadata: SyncTaskAuditMetadata(source: .cloudRelay, sourceCommand: "web-fixture")
            )
        ]

        return WebWorkspaceState(
            boardColumns: [
                WebBoardColumn(status: "todo", tasks: [tasks[0]]),
                WebBoardColumn(status: "in_progress", tasks: [tasks[1]]),
                WebBoardColumn(status: "done", tasks: [])
            ],
            taskList: tasks,
            projectDocuments: [
                SyncDocumentPayload(
                    id: "phase13",
                    title: "Phase13 plan",
                    scope: "projectDocs",
                    redactedSummary: "Multiplatform automation scope"
                )
            ],
            conversations: [
                SyncConversationPayload(id: "conversation-1", title: "Launch prep", createdAt: "2026-06-21T10:00:00Z")
            ],
            automationReviews: [
                SyncAutomationRequestPayload(
                    id: "auto-1",
                    source: .cloudRelay,
                    approvalState: .pendingApproval,
                    sourceClientID: "web",
                    toolName: "task_update",
                    redactedArgumentSummary: "taskID=2, status=done",
                    taskMutation: SyncTaskMutationPayload(
                        taskID: 2,
                        operation: .update,
                        status: "done",
                        source: .cloudRelay,
                        approvalState: .pendingApproval
                    )
                )
            ],
            account: WebAccountState(userEmail: "owner@example.com", billingPlan: "Pro"),
            devices: [
                WebDeviceState(id: "mac-1", displayName: "Desk Mac", platform: "macOS", lastSeenAt: "2026-06-21T09:58:00Z"),
                WebDeviceState(id: "ios-1", displayName: "iPhone", platform: "iOS", lastSeenAt: "2026-06-21T09:59:00Z")
            ],
            relayTokens: [
                WebRelayTokenState(id: "relay-token-1", displayName: "Gemini task capture", lastFour: "A19F", revoked: false)
            ],
            hostedMCPEndpoints: [
                WebHostedMCPEndpointState(
                    url: "https://relay.solopm.example/mcp",
                    toolNames: ["task_create", "task_update", "task_complete"]
                )
            ],
            harnessRuns: [
                SyncHarnessRunPayload(id: "harness-1", scenario: "web-task-mutation", status: "passed", scenarioKind: "taskMutation")
            ]
        )
    }
}

public enum WebOSBoundAction: String, Codable, Equatable, Sendable {
    case localFilesystemWrite
    case calendarWrite
    case remindersWrite
    case localMCPStdioExecution
}

public enum WebActionAvailability: String, Codable, Equatable, Sendable {
    case availableInWeb
    case requiresConnectedMac
}

public enum RequiredExecutionSurface: String, Codable, Equatable, Sendable {
    case web
    case macOSApp
}

public struct WebOSBoundActionNotice: Codable, Equatable, Sendable {
    public var action: WebOSBoundAction
    public var webAvailability: WebActionAvailability
    public var requiredSurface: RequiredExecutionSurface
    public var userMessage: String

    public init(
        action: WebOSBoundAction,
        webAvailability: WebActionAvailability,
        requiredSurface: RequiredExecutionSurface,
        userMessage: String
    ) {
        self.action = action
        self.webAvailability = webAvailability
        self.requiredSurface = requiredSurface
        self.userMessage = userMessage
    }

    public static let defaultNotices: [WebOSBoundActionNotice] = [
        WebOSBoundActionNotice(
            action: .localFilesystemWrite,
            webAvailability: .requiresConnectedMac,
            requiredSurface: .macOSApp,
            userMessage: "Local file writes require a connected Mac."
        ),
        WebOSBoundActionNotice(
            action: .calendarWrite,
            webAvailability: .requiresConnectedMac,
            requiredSurface: .macOSApp,
            userMessage: "Calendar writes require the macOS app approval surface."
        ),
        WebOSBoundActionNotice(
            action: .remindersWrite,
            webAvailability: .requiresConnectedMac,
            requiredSurface: .macOSApp,
            userMessage: "Reminders writes require a connected Mac."
        ),
        WebOSBoundActionNotice(
            action: .localMCPStdioExecution,
            webAvailability: .requiresConnectedMac,
            requiredSurface: .macOSApp,
            userMessage: "Local stdio MCP execution is not available from Web."
        )
    ]
}

public enum WebAppRenderer {
    public static func render(workspace: WebWorkspaceState) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>SoloPM Web</title>
        </head>
        <body>
          \(section("task-board", boardHTML(workspace.boardColumns)))
          \(section("task-list", listHTML(workspace.taskList.map(\.title))))
          \(section("project-docs", listHTML(workspace.projectDocuments.map(\.title))))
          \(section("conversation", listHTML(workspace.conversations.map(\.title))))
          \(section("automation-review", listHTML(workspace.automationReviews.map(\.id))))
          \(section("relay-tokens", listHTML(workspace.relayTokens.map { "\($0.displayName) ...\($0.lastFour)" })))
          \(section("devices", listHTML(workspace.devices.map { "\($0.displayName) \($0.platform)" })))
          \(section("hosted-mcp", listHTML(workspace.hostedMCPEndpoints.flatMap(\.toolNames))))
          \(section("harness-runs", listHTML(workspace.harnessRuns.map(\.scenario))))
          \(section("os-bound-actions", listHTML(WebOSBoundActionNotice.defaultNotices.map(\.userMessage))))
        </body>
        </html>
        """
    }

    private static func section(_ region: String, _ body: String) -> String {
        "<section data-region=\"\(escape(region))\">\(body)</section>"
    }

    private static func boardHTML(_ columns: [WebBoardColumn]) -> String {
        columns
            .map { column in
                "<article data-status=\"\(escape(column.status))\"><h2>\(escape(column.status))</h2>\(listHTML(column.tasks.map(\.title)))</article>"
            }
            .joined()
    }

    private static func listHTML(_ values: [String]) -> String {
        "<ul>\(values.map { "<li>\(escape($0))</li>" }.joined())</ul>"
    }

    private static func escape(_ value: String) -> String {
        // Web MVP renders synced/user-owned text, so minimal escaping is kept
        // close to the renderer to prevent test fixtures and future previews
        // from accidentally normalizing unsafe HTML into the UI contract.
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
