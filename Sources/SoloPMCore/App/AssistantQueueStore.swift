import Foundation

public enum AssistantQueueStoreError: Error, Equatable, Sendable {
    case notFound(String)
    case saveFailed
    case encodingFailed(column: String)
    case decodingFailed(column: String)
    case invalidStoredValue(column: String, value: String)

    public static func userMessage(for error: Error) -> String {
        if let storeError = error as? AssistantQueueStoreError {
            switch storeError {
            case .notFound:
                return "Assistant Queue item is no longer available."
            case .saveFailed:
                return "Assistant Queue could not save generated work. Confirm local data storage is available, then try again."
            case .encodingFailed, .decodingFailed, .invalidStoredValue:
                return "Local Assistant Queue data needs repair. Restore from backup or repair the local database, then reopen SoloPM."
            }
        }
        return "Assistant Queue could not save generated work. Confirm local data storage is available, then try again."
    }
}

public struct AssistantQueueFilter: Equatable, Sendable {
    public var states: Set<AssistantQueueState>?
    public var limit: Int

    public init(states: Set<AssistantQueueState>? = nil, limit: Int = 100) {
        self.states = states
        self.limit = min(max(limit, 1), 500)
    }

    public static func all(limit: Int = 100) -> AssistantQueueFilter {
        AssistantQueueFilter(limit: limit)
    }

    public static func states(_ states: Set<AssistantQueueState>, limit: Int = 100) -> AssistantQueueFilter {
        AssistantQueueFilter(states: states, limit: limit)
    }

    public func includes(_ state: AssistantQueueState) -> Bool {
        states?.contains(state) ?? true
    }
}

public protocol AssistantQueueStore {
    @discardableResult
    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem
    func get(id: String) throws -> AssistantQueueItem
    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem]

    @discardableResult
    func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem
}

public struct AssistantQueueReadModelRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var state: AssistantQueueState
    public var stateLabel: String
    public var riskLabel: String
    public var title: String
    public var sourcePreview: String?
    public var reviewReason: String
    public var capabilityLabels: [String]
    public var blockingReason: String?
    public var canApprove: Bool
    public var canDefer: Bool
    public var canReject: Bool

    public init(
        id: String,
        state: AssistantQueueState,
        stateLabel: String,
        riskLabel: String,
        title: String,
        sourcePreview: String?,
        reviewReason: String,
        capabilityLabels: [String],
        blockingReason: String?,
        canApprove: Bool,
        canDefer: Bool,
        canReject: Bool
    ) {
        self.id = id
        self.state = state
        self.stateLabel = stateLabel
        self.riskLabel = riskLabel
        self.title = title
        self.sourcePreview = sourcePreview
        self.reviewReason = reviewReason
        self.capabilityLabels = capabilityLabels
        self.blockingReason = blockingReason
        self.canApprove = canApprove
        self.canDefer = canDefer
        self.canReject = canReject
    }
}

public struct AssistantQueueSnapshot: Equatable, Sendable {
    public var rows: [AssistantQueueReadModelRow]
    public var waitingReviewCount: Int
    public var blockedCount: Int

    public static let empty = AssistantQueueSnapshot(rows: [], waitingReviewCount: 0, blockedCount: 0)

    public init(
        rows: [AssistantQueueReadModelRow],
        waitingReviewCount: Int,
        blockedCount: Int
    ) {
        self.rows = rows
        self.waitingReviewCount = waitingReviewCount
        self.blockedCount = blockedCount
    }

    public var reviewableCount: Int {
        waitingReviewCount + blockedCount
    }
}

public enum AssistantQueueReadModel {
    public static func snapshot(from items: [AssistantQueueItem]) -> AssistantQueueSnapshot {
        let rows = items
            .sorted(by: sortForReview)
            .map(row)
        return AssistantQueueSnapshot(
            rows: rows,
            waitingReviewCount: items.filter { $0.state == .waitingReview }.count,
            blockedCount: items.filter { $0.state == .blocked }.count
        )
    }

    private static func row(from item: AssistantQueueItem) -> AssistantQueueReadModelRow {
        AssistantQueueReadModelRow(
            id: item.id,
            state: item.state,
            stateLabel: label(for: item.state),
            riskLabel: item.riskLevel.rawValue.capitalized,
            title: redactedPreview(item.redactedSummary),
            sourcePreview: item.sourceTranscript.map(redactedPreview),
            reviewReason: item.reviewReason,
            capabilityLabels: item.requiredCapabilities.map { redactedPreview(label(for: $0)) },
            blockingReason: item.blockingReason,
            canApprove: canApprove(item),
            canDefer: canDefer(item),
            canReject: canReject(item)
        )
    }

    private static func sortForReview(_ lhs: AssistantQueueItem, _ rhs: AssistantQueueItem) -> Bool {
        let leftRank = reviewRank(lhs.state)
        let rightRank = reviewRank(rhs.state)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.id < rhs.id
    }

    private static func reviewRank(_ state: AssistantQueueState) -> Int {
        switch state {
        case .blocked:
            return 0
        case .waitingReview:
            return 1
        case .captured, .interpreted, .drafted:
            return 2
        case .approved:
            return 3
        case .running:
            return 4
        case .deferred:
            return 5
        case .rejected:
            return 6
        case .done:
            return 7
        }
    }

    private static func canApprove(_ item: AssistantQueueItem) -> Bool {
        switch item.state {
        case .waitingReview, .captured, .interpreted, .drafted, .deferred:
            return item.riskLevel != .danger
        case .approved, .running, .blocked, .done, .rejected:
            return false
        }
    }

    private static func canDefer(_ item: AssistantQueueItem) -> Bool {
        switch item.state {
        case .waitingReview, .captured, .interpreted, .drafted, .approved:
            return true
        case .running, .blocked, .done, .rejected, .deferred:
            return false
        }
    }

    private static func canReject(_ item: AssistantQueueItem) -> Bool {
        switch item.state {
        case .done, .rejected:
            return false
        case .captured, .interpreted, .drafted, .waitingReview, .approved, .running, .blocked, .deferred:
            return true
        }
    }

    private static func redactedPreview(_ value: String) -> String {
        DeveloperSecretRedactor().redact(value).text.assistantQueuePreview(maxLength: 160)
    }

    private static func label(for state: AssistantQueueState) -> String {
        switch state {
        case .captured:
            return "Captured"
        case .interpreted:
            return "Interpreted"
        case .drafted:
            return "Drafted"
        case .waitingReview:
            return "Waiting Review"
        case .approved:
            return "Approved"
        case .running:
            return "Running"
        case .blocked:
            return "Blocked"
        case .done:
            return "Done"
        case .rejected:
            return "Rejected"
        case .deferred:
            return "Deferred"
        }
    }

    private static func label(for capability: AssistantQueueRequiredCapability) -> String {
        switch capability {
        case .tool(let tool):
            return tool.rawValue
        case .appPermission(let permission):
            return "permission.\(permission.rawValue)"
        case .connectedMacRequired:
            return "connected_mac_required"
        case .providerExecutionApproval:
            return "provider_execution_approval"
        case .externalMCP(let serverID, let toolName):
            return "mcp.\(serverID).\(toolName)"
        }
    }
}

public final class SQLiteAssistantQueueStore: AssistantQueueStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(connection: SQLiteConnection) {
        self.connection = connection
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    public convenience init(path: String, migrations: [DatabaseMigration] = CoreMigrations.current) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection)
    }

    @discardableResult
    public func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        lock.lock()
        defer { lock.unlock() }
        try saveLocked(item)
        return item
    }

    public func get(id: String) throws -> AssistantQueueItem {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    public func list(filter: AssistantQueueFilter = .all()) throws -> [AssistantQueueItem] {
        lock.lock()
        defer { lock.unlock() }

        if filter.states?.isEmpty == true {
            return []
        }
        let whereClause = filter.states.map { states in
            let values = states.map { "'\(Self.escape($0.rawValue))'" }.sorted().joined(separator: ", ")
            return "WHERE state IN (\(values))"
        } ?? ""
        return try connection.queryRows(
            """
            SELECT * FROM assistant_queue_items
            \(whereClause)
            ORDER BY updated_at DESC, id ASC
            LIMIT \(filter.limit);
            """
        ).map(item(row:))
    }

    @discardableResult
    public func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem {
        lock.lock()
        defer { lock.unlock() }

        return try connection.transaction {
            let current = try getLocked(id: id)
            let updated = try transform(current)
            try saveLocked(updated)
            return updated
        }
    }

    private func getLocked(id: String) throws -> AssistantQueueItem {
        guard let row = try connection.queryRows(
            "SELECT * FROM assistant_queue_items WHERE id = '\(Self.escape(id))' LIMIT 1;"
        ).first else {
            throw AssistantQueueStoreError.notFound(id)
        }
        return try item(row: row)
    }

    private func saveLocked(_ item: AssistantQueueItem) throws {
        let existing = try connection.queryStrings(
            "SELECT id FROM assistant_queue_items WHERE id = '\(Self.escape(item.id))' LIMIT 1;"
        ).first != nil
        let payloadJSON = try encode(item.payload, column: "assistant_queue_items.payload_json")
        let requiredCapabilitiesJSON = try encode(item.requiredCapabilities, column: "assistant_queue_items.required_capabilities_json")
        let approvalJSON = try item.approval.map { try encode($0, column: "assistant_queue_items.approval_json") }
        let now = Self.timestamp()

        if existing {
            try connection.execute(
                """
                UPDATE assistant_queue_items
                SET schema_version = 1,
                    payload_kind = '\(Self.escape(payloadKind(for: item.payload)))',
                    payload_json = '\(Self.escape(payloadJSON))',
                    state = '\(Self.escape(item.state.rawValue))',
                    risk_level = '\(Self.escape(item.riskLevel.rawValue))',
                    source_transcript = \(Self.optional(item.sourceTranscript)),
                    interpretation_summary = \(Self.optional(item.interpretationSummary)),
                    review_reason = '\(Self.escape(item.reviewReason))',
                    redacted_summary = '\(Self.escape(item.redactedSummary))',
                    required_capabilities_json = '\(Self.escape(requiredCapabilitiesJSON))',
                    approval_json = \(Self.optional(approvalJSON)),
                    blocking_reason = \(Self.optional(item.blockingReason)),
                    updated_at = '\(Self.escape(now))'
                WHERE id = '\(Self.escape(item.id))';
                """
            )
        } else {
            try connection.execute(
                """
                INSERT INTO assistant_queue_items (
                    id,
                    schema_version,
                    payload_kind,
                    payload_json,
                    state,
                    risk_level,
                    source_transcript,
                    interpretation_summary,
                    review_reason,
                    redacted_summary,
                    required_capabilities_json,
                    approval_json,
                    blocking_reason,
                    created_at,
                    updated_at
                )
                VALUES (
                    '\(Self.escape(item.id))',
                    1,
                    '\(Self.escape(payloadKind(for: item.payload)))',
                    '\(Self.escape(payloadJSON))',
                    '\(Self.escape(item.state.rawValue))',
                    '\(Self.escape(item.riskLevel.rawValue))',
                    \(Self.optional(item.sourceTranscript)),
                    \(Self.optional(item.interpretationSummary)),
                    '\(Self.escape(item.reviewReason))',
                    '\(Self.escape(item.redactedSummary))',
                    '\(Self.escape(requiredCapabilitiesJSON))',
                    \(Self.optional(approvalJSON)),
                    \(Self.optional(item.blockingReason)),
                    '\(Self.escape(now))',
                    '\(Self.escape(now))'
                );
                """
            )
        }
    }

    private func item(row: [String: String]) throws -> AssistantQueueItem {
        let state = try enumValue(
            AssistantQueueState.self,
            rawValue: requiredString(row["state"], column: "assistant_queue_items.state"),
            column: "assistant_queue_items.state"
        )
        let riskLevel = try enumValue(
            RiskLevel.self,
            rawValue: requiredString(row["risk_level"], column: "assistant_queue_items.risk_level"),
            column: "assistant_queue_items.risk_level"
        )
        let payload = try decode(
            AssistantQueuePayload.self,
            from: requiredString(row["payload_json"], column: "assistant_queue_items.payload_json"),
            column: "assistant_queue_items.payload_json"
        )
        let payloadKind = try requiredString(row["payload_kind"], column: "assistant_queue_items.payload_kind")
        guard payloadKind == self.payloadKind(for: payload) else {
            throw AssistantQueueStoreError.invalidStoredValue(
                column: "assistant_queue_items.payload_kind",
                value: payloadKind
            )
        }
        let capabilities = try decode(
            [AssistantQueueRequiredCapability].self,
            from: requiredString(
                row["required_capabilities_json"],
                column: "assistant_queue_items.required_capabilities_json"
            ),
            column: "assistant_queue_items.required_capabilities_json"
        )
        let approval = try decodeOptional(
            AssistantQueueApprovalRecord.self,
            from: row["approval_json"],
            column: "assistant_queue_items.approval_json"
        )

        return AssistantQueueItem(
            id: try requiredString(row["id"], column: "assistant_queue_items.id"),
            state: state,
            payload: payload,
            riskLevel: riskLevel,
            sourceTranscript: nilIfEmpty(row["source_transcript"]),
            interpretationSummary: nilIfEmpty(row["interpretation_summary"]),
            reviewReason: try requiredString(row["review_reason"], column: "assistant_queue_items.review_reason"),
            redactedSummary: try requiredString(row["redacted_summary"], column: "assistant_queue_items.redacted_summary"),
            requiredCapabilities: capabilities,
            approval: approval,
            blockingReason: nilIfEmpty(row["blocking_reason"])
        )
    }

    private func payloadKind(for payload: AssistantQueuePayload) -> String {
        switch payload {
        case .actionPlan:
            return "action_plan"
        case .automationRequest:
            return "automation_request"
        }
    }

    private func encode<Value: Encodable>(_ value: Value, column: String) throws -> String {
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            throw AssistantQueueStoreError.encodingFailed(column: column)
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from value: String, column: String) throws -> Value {
        do {
            return try decoder.decode(type, from: Data(value.utf8))
        } catch {
            throw AssistantQueueStoreError.decodingFailed(column: column)
        }
    }

    private func decodeOptional<Value: Decodable>(_ type: Value.Type, from value: String?, column: String) throws -> Value? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return try decode(type, from: value, column: column)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func optional(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }
        return "'\(escape(value))'"
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private func nilIfEmpty(_ value: String?) -> String? {
        Self.nilIfEmpty(value)
    }

    private func requiredString(_ value: String?, column: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantQueueStoreError.invalidStoredValue(column: column, value: "")
        }
        return value
    }

    private func enumValue<Value: RawRepresentable>(
        _ type: Value.Type,
        rawValue: String,
        column: String
    ) throws -> Value where Value.RawValue == String {
        guard let value = Value(rawValue: rawValue) else {
            throw AssistantQueueStoreError.invalidStoredValue(column: column, value: rawValue)
        }
        return value
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

private extension String {
    func assistantQueuePreview(maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }
        let endIndex = index(startIndex, offsetBy: maxLength)
        return String(self[..<endIndex]) + "..."
    }
}
