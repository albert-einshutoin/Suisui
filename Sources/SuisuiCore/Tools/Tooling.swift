import CryptoKit
import Foundation

public struct ToolInputSchema: Equatable, Sendable {
    public var required: [String]
    public var properties: [String: String]
    public var nonBlank: [String]
    public var arrayItems: [String: ToolInputSchema]
    public var additionalProperties: Bool

    public init(
        required: [String] = [],
        properties: [String: String] = [:],
        nonBlank: [String] = [],
        arrayItems: [String: ToolInputSchema] = [:],
        additionalProperties: Bool = false
    ) {
        self.required = required
        self.properties = properties
        self.nonBlank = nonBlank
        self.arrayItems = arrayItems
        self.additionalProperties = additionalProperties
    }
}

public struct ToolInputValidationIssue: Equatable, Sendable {
    public var actionID: String?
    public var field: String
    public var message: String

    public init(actionID: String? = nil, field: String, message: String) {
        self.actionID = actionID
        self.field = field
        self.message = message
    }
}

public extension ToolInputSchema {
    func validate(arguments: [String: JSONValue], tool: ActionTool, actionID: String? = nil) -> [ToolInputValidationIssue] {
        validate(arguments: arguments, tool: tool, actionID: actionID, fieldPrefix: nil)
    }

    private func validate(
        arguments: [String: JSONValue],
        tool: ActionTool,
        actionID: String?,
        fieldPrefix: String?
    ) -> [ToolInputValidationIssue] {
        var issues: [ToolInputValidationIssue] = []

        for key in required {
            guard let value = arguments[key], !value.isBlankString else {
                issues.append(
                    ToolInputValidationIssue(
                        actionID: actionID,
                        field: path(key, prefix: fieldPrefix),
                        message: "Missing required argument '\(path(key, prefix: fieldPrefix))' for \(tool.rawValue)."
                    )
                )
                continue
            }
        }

        for key in nonBlank where !required.contains(key) {
            guard let value = arguments[key], value.isBlankString else {
                continue
            }
            issues.append(
                ToolInputValidationIssue(
                    actionID: actionID,
                    field: path(key, prefix: fieldPrefix),
                    message: "Argument '\(path(key, prefix: fieldPrefix))' cannot be blank for \(tool.rawValue)."
                )
            )
        }

        if !additionalProperties {
            let knownKeys = Set(properties.keys).union(required).union(nonBlank).union(arrayItems.keys)
            for key in arguments.keys.sorted() where !knownKeys.contains(key) {
                issues.append(
                    ToolInputValidationIssue(
                        actionID: actionID,
                        field: path(key, prefix: fieldPrefix),
                        message: "Unknown argument '\(path(key, prefix: fieldPrefix))' for \(tool.rawValue)."
                    )
                )
            }
        }

        for (key, value) in arguments {
            guard let expectedType = properties[key], !value.matchesSchemaType(expectedType) else {
                continue
            }

            issues.append(
                ToolInputValidationIssue(
                    actionID: actionID,
                    field: path(key, prefix: fieldPrefix),
                    message: "Argument '\(path(key, prefix: fieldPrefix))' must be \(expectedType) for \(tool.rawValue)."
                )
            )
        }

        for (arrayKey, itemSchema) in arrayItems {
            guard case .array(let values)? = arguments[arrayKey] else {
                continue
            }

            for (index, value) in values.enumerated() {
                let itemPrefix = "\(path(arrayKey, prefix: fieldPrefix))[\(index)]"
                guard case .object(let object) = value else {
                    issues.append(
                        ToolInputValidationIssue(
                            actionID: actionID,
                            field: itemPrefix,
                            message: "Argument '\(itemPrefix)' must be object for \(tool.rawValue)."
                        )
                    )
                    continue
                }

                issues.append(contentsOf: itemSchema.validate(
                    arguments: object,
                    tool: tool,
                    actionID: actionID,
                    fieldPrefix: itemPrefix
                ))
            }
        }

        return issues
    }

    private func path(_ key: String, prefix: String?) -> String {
        guard let prefix else {
            return key
        }

        return "\(prefix).\(key)"
    }
}

public enum ToolPermissionLevel: String, Equatable, Sendable {
    case read
    case draft
    case writeWithApproval
    case dangerous
}

public struct ToolActionAuthorization: Equatable, Sendable {
    public let approval: ApprovedExecution
    public let actionID: String
    public let tool: ActionTool
    public let resolvedArgumentsDigest: Data

    init(
        approval: ApprovedExecution,
        actionID: String,
        tool: ActionTool,
        arguments: [String: JSONValue]
    ) throws {
        self.approval = approval
        self.actionID = actionID
        self.tool = tool
        self.resolvedArgumentsDigest = try Self.digest(arguments: arguments)
    }

    public func validate(
        tool expectedTool: ActionTool,
        arguments: [String: JSONValue],
        now: Date
    ) throws {
        guard approval.enabledActionIDs.contains(actionID),
              tool == expectedTool,
              now >= approval.issuedAt,
              now < approval.expiresAt,
              resolvedArgumentsDigest == (try Self.digest(arguments: arguments)) else {
            throw ToolExecutionError.approvalBindingInvalid(expectedTool)
        }
    }

    private static func digest(arguments: [String: JSONValue]) throws -> Data {
        Data(SHA256.hash(data: try CanonicalJSONEncoder.encode(.object(arguments))))
    }
}

public struct ToolExecutionContext: Sendable {
    public var authorization: ToolActionAuthorization?
    public var now: Date
    public var source: ToolExecutionSource
    public var executionID: String?
    public var reviewSessionID: String?
    public var actionID: String?
    public var idempotencyKey: String?
#if DEBUG
    // Existing unit checks exercise individual tools without constructing a
    // review session. This internal-only bridge is absent from release builds.
    internal var debugApprovalToken: ApprovalToken?
#endif

    public init(
        authorization: ToolActionAuthorization? = nil,
        now: Date = Date(),
        source: ToolExecutionSource,
        executionID: String? = nil,
        reviewSessionID: String? = nil,
        actionID: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.authorization = authorization
        self.now = now
        self.source = source
        self.executionID = executionID
        self.reviewSessionID = reviewSessionID
        self.actionID = actionID
        self.idempotencyKey = idempotencyKey
#if DEBUG
        self.debugApprovalToken = nil
#endif
    }

    public var approvalToken: ApprovalToken? {
#if DEBUG
        authorization?.approval ?? debugApprovalToken
#else
        authorization?.approval
#endif
    }

#if DEBUG
    internal init(
        approvalToken: ApprovalToken,
        now: Date = Date(),
        source: ToolExecutionSource,
        executionID: String? = nil,
        reviewSessionID: String? = nil,
        actionID: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.authorization = nil
        self.now = now
        self.source = source
        self.executionID = executionID
        self.reviewSessionID = reviewSessionID
        self.actionID = actionID
        self.idempotencyKey = idempotencyKey
        self.debugApprovalToken = approvalToken
    }
#endif

    public func externalSideEffectRequest(
        tool: ActionTool,
        arguments: [String: JSONValue],
        sideEffectArguments: [String: JSONValue]? = nil,
        itemIndex: Int? = nil,
        itemIdentity: String? = nil
    ) throws -> ExternalSideEffectRequest {
        guard let executionID,
              let reviewSessionID,
              let actionID,
              let idempotencyKey else {
            throw ToolExecutionError.sideEffectIdentityMissing(tool)
        }
        let canonicalArguments = sideEffectArguments ?? arguments
        let itemKey: String
        if itemIndex != nil {
            guard let itemIdentity, !itemIdentity.isEmpty else {
                throw ToolExecutionError.sideEffectIdentityMissing(tool)
            }
            // Bulk items must not inherit the action-level arguments digest or
            // their current array position. The adapter supplies a stable
            // content-occurrence identity so sibling edits and reordering do
            // not duplicate already-succeeded external writes.
            itemKey = try Self.externalSideEffectIdempotencyKey(
                reviewSessionID: reviewSessionID,
                actionID: "\(actionID):item:\(itemIdentity)",
                tool: tool,
                arguments: canonicalArguments
            )
        } else if sideEffectArguments != nil {
            // Some actions carry local linkage metadata in addition to the
            // external payload. Re-approval after changing only that metadata
            // must still claim the original external side effect.
            itemKey = try Self.externalSideEffectIdempotencyKey(
                reviewSessionID: reviewSessionID,
                actionID: actionID,
                tool: tool,
                arguments: canonicalArguments
            )
        } else {
            itemKey = idempotencyKey
        }
        return ExternalSideEffectRequest(
            executionID: executionID,
            reviewSessionID: reviewSessionID,
            actionID: actionID,
            itemIndex: itemIndex,
            tool: tool,
            canonicalArgumentsDigest: try CanonicalJSONEncoder.digest(.object(canonicalArguments)),
            idempotencyKey: itemKey
        )
    }

    public static func externalSideEffectIdempotencyKey(
        reviewSessionID: String,
        actionID: String,
        tool: ActionTool,
        arguments: [String: JSONValue]
    ) throws -> String {
        let argumentsDigest = try CanonicalJSONEncoder.digest(.object(arguments)).lowercaseHexString
        let material = "\(reviewSessionID)\u{0}\(actionID)\u{0}\(tool.rawValue)\u{0}\(argumentsDigest)"
        // Google Calendar accepts caller-provided event IDs only in base32hex.
        // A `suisui` prefix plus a 64-character hexadecimal SHA-256 digest is
        // valid there and remains suitable for every other adapter.
        return "suisui\(Data(SHA256.hash(data: Data(material.utf8))).lowercaseHexString)"
    }
}

public enum ToolExecutionSource: String, Equatable, Sendable {
    case developerTool
    case reviewUI
}

public enum ToolExecutionStatus: String, Equatable, Sendable {
    case succeeded
    case failed
    case skipped
}

public struct ToolResult: Equatable, Sendable {
    public var tool: ActionTool
    public var status: ToolExecutionStatus
    public var summary: String
    public var output: [String: JSONValue]
    public var rollbackMetadata: [String: JSONValue]
    public var compensationHint: String?

    public init(
        tool: ActionTool,
        status: ToolExecutionStatus,
        summary: String,
        output: [String: JSONValue] = [:],
        rollbackMetadata: [String: JSONValue] = [:],
        compensationHint: String? = nil
    ) {
        self.tool = tool
        self.status = status
        self.summary = summary
        self.output = output
        self.rollbackMetadata = rollbackMetadata
        self.compensationHint = compensationHint
    }
}

public struct ExternalSideEffectFailureEvidence: Equatable, Sendable {
    public var tool: ActionTool
    public var idempotencyKey: String
    public var journalRecordID: String
    public var externalResourceID: String?
    public var state: ExternalSideEffectState

    public init(
        tool: ActionTool,
        idempotencyKey: String,
        journalRecordID: String,
        externalResourceID: String?,
        state: ExternalSideEffectState
    ) {
        self.tool = tool
        self.idempotencyKey = idempotencyKey
        self.journalRecordID = journalRecordID
        self.externalResourceID = externalResourceID
        self.state = state
    }

    public init(record: ExternalSideEffectRecord) {
        self.init(
            tool: record.tool,
            idempotencyKey: record.idempotencyKey,
            journalRecordID: record.id,
            externalResourceID: record.externalResourceID,
            state: record.state
        )
    }
}

public enum ExternalSideEffectBatchFailureReason: Equatable, Sendable {
    case executionFailed(String)
    case inProgress
    case requiresReconciliation
}

public struct ExternalSideEffectBatchFailureEvidence: Equatable, Sendable {
    public var tool: ActionTool
    public var reason: ExternalSideEffectBatchFailureReason
    public var records: [ExternalSideEffectFailureEvidence]

    public init(
        tool: ActionTool,
        reason: ExternalSideEffectBatchFailureReason,
        records: [ExternalSideEffectFailureEvidence]
    ) {
        self.tool = tool
        self.reason = reason
        self.records = records
    }
}

public enum ToolExecutionError: Error, Equatable, Sendable {
    case duplicateTool(ActionTool)
    case unknownTool(ActionTool)
    case approvalRequired(ActionTool)
    case approvalBindingInvalid(ActionTool)
    case dangerousToolBlocked(ActionTool)
    case sideEffectIdentityMissing(ActionTool)
    case externalSideEffectInProgress(ExternalSideEffectFailureEvidence)
    case externalSideEffectRequiresReconciliation(ExternalSideEffectFailureEvidence)
    case externalSideEffectBatchFailed(ExternalSideEffectBatchFailureEvidence)
    case validationFailed(ActionTool, String)
    case executionFailed(ActionTool, String)
}

public extension ToolExecutionError {
    static func validationFailed(_ tool: ActionTool, issues: [ToolInputValidationIssue]) -> ToolExecutionError {
        let message = issues.map(\.message).joined(separator: " ")
        return .validationFailed(tool, message.isEmpty ? "Invalid tool arguments." : message)
    }

    var externalSideEffectFailureEvidence: ExternalSideEffectFailureEvidence? {
        switch self {
        case .externalSideEffectInProgress(let evidence),
             .externalSideEffectRequiresReconciliation(let evidence):
            evidence
        default:
            nil
        }
    }

    var externalSideEffectBatchFailureEvidence: ExternalSideEffectBatchFailureEvidence? {
        guard case .externalSideEffectBatchFailed(let evidence) = self else {
            return nil
        }
        return evidence
    }
}

public protocol Tool: Sendable {
    var name: ActionTool { get }
    var description: String { get }
    var inputSchema: ToolInputSchema { get }
    var permissionLevel: ToolPermissionLevel { get }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult
}

public extension Tool {
    func enforcePermission(arguments: [String: JSONValue], context: ToolExecutionContext) throws {
        switch permissionLevel {
        case .read, .draft:
            return
        case .writeWithApproval:
#if DEBUG
            if context.debugApprovalToken != nil {
                return
            }
#endif
            guard let authorization = context.authorization else {
                throw ToolExecutionError.approvalRequired(name)
            }
            try authorization.validate(tool: name, arguments: arguments, now: context.now)
        case .dangerous:
            throw ToolExecutionError.dangerousToolBlocked(name)
        }
    }

    func validateRequiredArguments(_ arguments: [String: JSONValue]) throws {
        for key in inputSchema.required where arguments[key] == nil {
            throw ToolExecutionError.validationFailed(name, "Missing required argument '\(key)'.")
        }
    }
}

public final class ToolRegistry: @unchecked Sendable {
    private var tools: [ActionTool: any Tool]
    private let lock = NSLock()

    public init() {
        self.tools = [:]
    }

    public init(tools: [any Tool]) throws {
        self.tools = [:]
        for tool in tools {
            try register(tool)
        }
    }

    public func register(_ tool: any Tool) throws {
        lock.lock()
        defer { lock.unlock() }

        guard tools[tool.name] == nil else {
            throw ToolExecutionError.duplicateTool(tool.name)
        }

        tools[tool.name] = tool
    }

    public func registerTools(
        from registry: ToolRegistry,
        transform: (any Tool) -> any Tool = { $0 }
    ) throws {
        for tool in registry.snapshotTools() {
            try register(transform(tool))
        }
    }

    public func tool(named name: ActionTool) throws -> any Tool {
        lock.lock()
        defer { lock.unlock() }

        guard let tool = tools[name] else {
            throw ToolExecutionError.unknownTool(name)
        }

        return tool
    }

    public func contains(_ name: ActionTool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tools[name] != nil
    }

    public func schema(for name: ActionTool) -> ToolInputSchema? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]?.inputSchema
    }

    public func validate(action: PlanAction) -> [ToolInputValidationIssue] {
        lock.lock()
        defer { lock.unlock() }

        guard let schema = tools[action.tool]?.inputSchema else {
            return [
                ToolInputValidationIssue(
                    actionID: action.id,
                    field: "tool",
                    message: "Tool \(action.tool.rawValue) is not available in the active registry."
                )
            ]
        }

        return schema.validate(arguments: action.arguments, tool: action.tool, actionID: action.id)
    }

    private func snapshotTools() -> [any Tool] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values.sorted { $0.name.rawValue < $1.name.rawValue }
    }

    public var registeredTools: [ActionTool] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public var schemaList: [ToolSchemaExport] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values
            .map {
                ToolSchemaExport(
                    name: $0.name,
                    description: $0.description,
                    inputSchema: $0.inputSchema,
                    permissionLevel: $0.permissionLevel
                )
            }
            .sorted { $0.name.rawValue < $1.name.rawValue }
    }
}

public struct ToolSchemaExport: Equatable, Sendable {
    public var name: ActionTool
    public var description: String
    public var inputSchema: ToolInputSchema
    public var permissionLevel: ToolPermissionLevel

    public init(
        name: ActionTool,
        description: String,
        inputSchema: ToolInputSchema,
        permissionLevel: ToolPermissionLevel
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.permissionLevel = permissionLevel
    }
}

private extension JSONValue {
    var isBlankString: Bool {
        guard case .string(let value) = self else {
            return false
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matchesSchemaType(_ expectedType: String) -> Bool {
        // Typed references are validated against the target schema immediately
        // after resolution, when their concrete value is available.
        if case .actionOutput = self {
            return true
        }
        let alternatives = expectedType
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if alternatives.count > 1 {
            return alternatives.contains { matchesSchemaType($0) }
        }

        switch expectedType {
        case "string":
            if case .string = self {
                return true
            }
            return false
        case "number":
            switch self {
            case .number:
                return true
            case .string(let value):
                return Double(value) != nil
            default:
                return false
            }
        case "integer":
            switch self {
            case .number(let value):
                return Int64(exactly: value) != nil
            case .string(let value):
                return Int64(value) != nil
            default:
                return false
            }
        case "array":
            if case .array = self {
                return true
            }
            return false
        case "object":
            if case .object = self {
                return true
            }
            return false
        case "bool", "boolean":
            if case .bool = self {
                return true
            }
            return false
        case "null":
            if case .null = self {
                return true
            }
            return false
        default:
            return true
        }
    }
}
