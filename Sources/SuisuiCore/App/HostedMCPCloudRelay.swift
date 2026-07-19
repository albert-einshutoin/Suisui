import Foundation

public enum HostedMCPTaskToolName: String, Codable, CaseIterable, Equatable, Sendable {
    case taskCreate = "task_create"
    case taskUpdate = "task_update"
    case taskComplete = "task_complete"
    case taskDueDateUpdate = "task_due_date_update"
    case taskProjectMove = "task_project_move"
}

public struct HostedMCPTaskToolSchema: Codable, Equatable, Sendable {
    public var name: String
    public var requiredArgumentKeys: [String]
    public var optionalArgumentKeys: [String]
    public var approvalState: SyncApprovalState

    public init(
        name: String,
        requiredArgumentKeys: [String],
        optionalArgumentKeys: [String],
        approvalState: SyncApprovalState
    ) {
        self.name = name
        self.requiredArgumentKeys = requiredArgumentKeys
        self.optionalArgumentKeys = optionalArgumentKeys
        self.approvalState = approvalState
    }

    public static let all: [HostedMCPTaskToolSchema] = HostedMCPTaskToolName.allCases.map { toolName in
        switch toolName {
        case .taskCreate:
            HostedMCPTaskToolSchema(
                name: toolName.rawValue,
                requiredArgumentKeys: ["title"],
                optionalArgumentKeys: ["detail", "projectID", "dueAt", "priority"],
                approvalState: .notRequired
            )
        case .taskUpdate:
            HostedMCPTaskToolSchema(
                name: toolName.rawValue,
                requiredArgumentKeys: ["taskID"],
                optionalArgumentKeys: ["title", "detail", "status", "projectID", "dueAt", "priority"],
                approvalState: .pendingApproval
            )
        case .taskComplete:
            HostedMCPTaskToolSchema(
                name: toolName.rawValue,
                requiredArgumentKeys: ["taskID"],
                optionalArgumentKeys: [],
                approvalState: .pendingApproval
            )
        case .taskDueDateUpdate:
            HostedMCPTaskToolSchema(
                name: toolName.rawValue,
                requiredArgumentKeys: ["taskID", "dueAt"],
                optionalArgumentKeys: [],
                approvalState: .pendingApproval
            )
        case .taskProjectMove:
            HostedMCPTaskToolSchema(
                name: toolName.rawValue,
                requiredArgumentKeys: ["taskID", "projectID"],
                optionalArgumentKeys: [],
                approvalState: .pendingApproval
            )
        }
    }
}

public struct CloudRelayTaskApprovalPolicy: Equatable, Sendable {
    public var autoCreatePlainTasks: Bool

    public init(autoCreatePlainTasks: Bool) {
        self.autoCreatePlainTasks = autoCreatePlainTasks
    }

    public static let defaultPersonal = CloudRelayTaskApprovalPolicy(autoCreatePlainTasks: true)

    public func approvalState(for toolName: HostedMCPTaskToolName) -> SyncApprovalState {
        if toolName == .taskCreate, autoCreatePlainTasks {
            return .notRequired
        }

        // Remote changes beyond plain creation can rewrite existing work, so keep
        // them reviewable even when they arrive through a trusted relay client.
        return .pendingApproval
    }
}

public enum CloudRelayTaskRequestError: Error, Equatable, Sendable {
    case missingArgument(String)
    case invalidArgument(String)
}

public struct CloudRelayTaskRequest: Codable, Equatable, Sendable {
    public var id: String
    public var source: SyncMutationSource
    public var sourceClientID: String
    public var toolName: HostedMCPTaskToolName
    public var arguments: [String: JSONValue]
    public var receivedAt: String

    public init(
        id: String,
        source: SyncMutationSource,
        sourceClientID: String,
        toolName: HostedMCPTaskToolName,
        arguments: [String: JSONValue],
        receivedAt: String
    ) {
        self.id = id
        self.source = source
        self.sourceClientID = sourceClientID
        self.toolName = toolName
        self.arguments = arguments
        self.receivedAt = receivedAt
    }

    public func taskMutationPayload(policy: CloudRelayTaskApprovalPolicy) throws -> SyncTaskMutationPayload {
        let approvalState = policy.approvalState(for: toolName)
        switch toolName {
        case .taskCreate:
            return SyncTaskMutationPayload(
                operation: .create,
                title: try requiredString("title"),
                detail: optionalString("detail"),
                status: optionalString("status"),
                projectID: try optionalPositiveInt64("projectID"),
                dueAt: optionalString("dueAt"),
                priority: optionalString("priority"),
                source: source,
                approvalState: approvalState
            )
        case .taskUpdate:
            return SyncTaskMutationPayload(
                taskID: try requiredPositiveInt64("taskID"),
                operation: .update,
                title: optionalString("title"),
                detail: optionalString("detail"),
                status: optionalString("status"),
                projectID: try optionalPositiveInt64("projectID"),
                dueAt: optionalString("dueAt"),
                priority: optionalString("priority"),
                source: source,
                approvalState: approvalState
            )
        case .taskComplete:
            return SyncTaskMutationPayload(
                taskID: try requiredPositiveInt64("taskID"),
                operation: .complete,
                status: "completed",
                source: source,
                approvalState: approvalState
            )
        case .taskDueDateUpdate:
            return SyncTaskMutationPayload(
                taskID: try requiredPositiveInt64("taskID"),
                operation: .updateDueDate,
                dueAt: try requiredString("dueAt"),
                source: source,
                approvalState: approvalState
            )
        case .taskProjectMove:
            return SyncTaskMutationPayload(
                taskID: try requiredPositiveInt64("taskID"),
                operation: .moveProject,
                projectID: try requiredPositiveInt64("projectID"),
                source: source,
                approvalState: approvalState
            )
        }
    }

    public func automationRequestPayload(policy: CloudRelayTaskApprovalPolicy) throws -> SyncAutomationRequestPayload {
        let mutation = try taskMutationPayload(policy: policy)
        return SyncAutomationRequestPayload(
            id: id,
            source: source,
            approvalState: mutation.approvalState,
            sourceClientID: sourceClientID,
            toolName: toolName.rawValue,
            redactedArgumentSummary: redactedArgumentSummary,
            taskMutation: mutation
        )
    }

    public func ledgerEntry(
        deviceID: String,
        sequence: Int64,
        encryptedPayload: EncryptedSyncPayload
    ) throws -> SyncLedgerEntry {
        SyncLedgerEntry(
            id: "ledger-\(id)",
            deviceID: deviceID,
            sequence: sequence,
            entity: SyncLedgerEntity(kind: .automationRequest, id: id),
            operation: .create,
            encryptedPayload: encryptedPayload,
            parentEntryID: nil,
            createdAt: receivedAt,
            mergePolicy: .appendLedgerEntry,
            redactedAuditSummary: "\(sourceClientID) \(toolName.rawValue) \(redactedArgumentSummary)"
        )
    }

    public var redactedArgumentSummary: String {
        let summary = arguments
            .keys
            .sorted()
            .map { "\($0)=\(arguments[$0]?.summaryValue ?? "null")" }
            .joined(separator: ", ")
        return DeveloperSecretRedactor().redact(summary).text
    }

    private func requiredString(_ key: String) throws -> String {
        guard let value = arguments[key] else {
            throw CloudRelayTaskRequestError.missingArgument(key)
        }
        guard case let .string(string) = value else {
            throw CloudRelayTaskRequestError.invalidArgument(key)
        }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CloudRelayTaskRequestError.invalidArgument(key)
        }
        return normalized
    }

    private func optionalString(_ key: String) -> String? {
        guard case let .string(string) = arguments[key] else {
            return nil
        }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func requiredPositiveInt64(_ key: String) throws -> Int64 {
        guard let value = try optionalPositiveInt64(key) else {
            throw arguments[key] == nil
                ? CloudRelayTaskRequestError.missingArgument(key)
                : CloudRelayTaskRequestError.invalidArgument(key)
        }
        return value
    }

    private func optionalPositiveInt64(_ key: String) throws -> Int64? {
        guard let value = try optionalInt64(key) else {
            return nil
        }
        // Hosted requests encode existing SQLite identifiers; zero or negative
        // IDs cannot identify a task/project and should not enter approval queues.
        guard value > 0 else {
            throw CloudRelayTaskRequestError.invalidArgument(key)
        }
        return value
    }

    private func optionalInt64(_ key: String) throws -> Int64? {
        guard let value = arguments[key] else {
            return nil
        }
        guard case let .number(number) = value,
              number.rounded(.towardZero) == number,
              number >= Double(Int64.min),
              number <= Double(Int64.max) else {
            throw CloudRelayTaskRequestError.invalidArgument(key)
        }
        return Int64(number)
    }
}

private extension JSONValue {
    var summaryValue: String {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            value.rounded(.towardZero) == value ? String(Int64(value)) : String(value)
        case let .bool(value):
            String(value)
        case .object:
            "{...}"
        case .array:
            "[...]"
        case .null:
            "null"
        }
    }
}
