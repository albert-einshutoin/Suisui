import Foundation

public enum ExternalSideEffectState: String, Codable, Equatable, Sendable {
    case prepared
    case started
    case succeeded
    case unknown
    case failedBeforeSideEffect = "failed_before_side_effect"
    case compensated
}

public struct ExternalSideEffectRequest: Equatable, Sendable {
    public var executionID: String
    public var reviewSessionID: String
    public var actionID: String
    public var itemIndex: Int?
    public var tool: ActionTool
    public var canonicalArgumentsDigest: Data
    public var idempotencyKey: String

    public init(
        executionID: String,
        reviewSessionID: String,
        actionID: String,
        itemIndex: Int? = nil,
        tool: ActionTool,
        canonicalArgumentsDigest: Data,
        idempotencyKey: String
    ) {
        self.executionID = executionID
        self.reviewSessionID = reviewSessionID
        self.actionID = actionID
        self.itemIndex = itemIndex
        self.tool = tool
        self.canonicalArgumentsDigest = canonicalArgumentsDigest
        self.idempotencyKey = idempotencyKey
    }
}

public struct ExternalSideEffectRecord: Equatable, Sendable {
    public var id: String
    public var executionID: String
    public var reviewSessionID: String
    public var actionID: String
    public var itemIndex: Int?
    public var tool: ActionTool
    public var canonicalArgumentsDigest: Data
    public var idempotencyKey: String
    public var attempt: Int
    public var state: ExternalSideEffectState
    public var externalResourceID: String?
    public var preparedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var updatedAt: Date
    public var failureCategory: String?
    public var reconciliationResult: String?
    public var result: ToolResult?
}

public enum ExternalSideEffectClaim: Equatable, Sendable {
    case execute(ExternalSideEffectRecord)
    case returnSucceeded(ToolResult)
    case inProgress(ExternalSideEffectRecord)
    case requiresReconciliation(ExternalSideEffectRecord)
}

public enum ExternalSideEffectJournalError: Error, Equatable, Sendable {
    case invalidArgumentsDigest
    case idempotencyKeyConflict(String)
    case recordNotFound(String)
    case invalidTransition(id: String, from: ExternalSideEffectState, to: ExternalSideEffectState)
    case corruptedRecord(String)
}

public protocol ExternalSideEffectJournal: Sendable {
    func claim(_ request: ExternalSideEffectRequest, at: Date) throws -> ExternalSideEffectClaim
    func markStarted(id: String, at: Date) throws
    func markSucceeded(
        id: String,
        externalResourceID: String?,
        result: ToolResult,
        at: Date
    ) throws
    func markUnknown(
        id: String,
        externalResourceID: String?,
        failureCategory: String,
        at: Date
    ) throws
    func markFailedBeforeSideEffect(id: String, failureCategory: String, at: Date) throws
    func markCompensated(id: String, reconciliationResult: String, at: Date) throws
    func reconcileSucceeded(
        id: String,
        externalResourceID: String,
        result: ToolResult,
        reconciliationResult: String,
        at: Date
    ) throws
    func record(id: String) throws -> ExternalSideEffectRecord?
    func records(executionID: String) throws -> [ExternalSideEffectRecord]
    func recordsRequiringReconciliation() throws -> [ExternalSideEffectRecord]
    @discardableResult
    func recoverStartedAsUnknown(at: Date) throws -> Int
}

public final class SQLiteExternalSideEffectJournal: ExternalSideEffectJournal, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(connection: SQLiteConnection) {
        self.connection = connection
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = formatter
    }

    public func claim(
        _ request: ExternalSideEffectRequest,
        at: Date
    ) throws -> ExternalSideEffectClaim {
        guard request.canonicalArgumentsDigest.count == 32 else {
            throw ExternalSideEffectJournalError.invalidArgumentsDigest
        }
        lock.lock()
        defer { lock.unlock() }

        if let existing = try recordLocked(idempotencyKey: request.idempotencyKey) {
            guard existing.tool == request.tool,
                  existing.canonicalArgumentsDigest == request.canonicalArgumentsDigest else {
                throw ExternalSideEffectJournalError.idempotencyKeyConflict(request.idempotencyKey)
            }
            switch existing.state {
            case .succeeded:
                guard let result = existing.result else {
                    throw ExternalSideEffectJournalError.corruptedRecord(existing.id)
                }
                return .returnSucceeded(result)
            case .unknown, .compensated:
                return .requiresReconciliation(existing)
            case .prepared, .started:
                return .inProgress(existing)
            case .failedBeforeSideEffect:
                let timestamp = dateFormatter.string(from: at)
                try connection.execute(
                    """
                    UPDATE external_side_effect_journal
                    SET execution_id = ?,
                        review_session_id = ?,
                        action_id = ?,
                        item_index = ?,
                        attempt = attempt + 1,
                        state = 'prepared',
                        prepared_at = ?,
                        started_at = NULL,
                        completed_at = NULL,
                        updated_at = ?,
                        external_resource_id = NULL,
                        failure_category = NULL,
                        reconciliation_result = NULL,
                        result_json = NULL
                    WHERE id = ? AND state = 'failed_before_side_effect';
                    """,
                    parameters: [
                        .text(request.executionID),
                        .text(request.reviewSessionID),
                        .text(request.actionID),
                        .init(request.itemIndex),
                        .text(timestamp),
                        .text(timestamp),
                        .text(existing.id)
                    ]
                )
                return .execute(try requiredRecordLocked(id: existing.id))
            }
        }

        let id = "side-effect-\(UUID().uuidString)"
        let timestamp = dateFormatter.string(from: at)
        try connection.execute(
            """
            INSERT INTO external_side_effect_journal (
                id,
                execution_id,
                review_session_id,
                action_id,
                item_index,
                tool,
                canonical_arguments_digest,
                idempotency_key,
                attempt,
                state,
                prepared_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 'prepared', ?, ?);
            """,
            parameters: [
                .text(id),
                .text(request.executionID),
                .text(request.reviewSessionID),
                .text(request.actionID),
                .init(request.itemIndex),
                .text(request.tool.rawValue),
                .blob(request.canonicalArgumentsDigest),
                .text(request.idempotencyKey),
                .text(timestamp),
                .text(timestamp)
            ]
        )
        return .execute(try requiredRecordLocked(id: id))
    }

    public func markStarted(id: String, at: Date) throws {
        try transition(
            id: id,
            allowedFrom: [.prepared],
            to: .started,
            at: at,
            assignments: "started_at = ?, completed_at = NULL",
            values: [.text(dateFormatter.string(from: at))]
        )
    }

    public func markSucceeded(
        id: String,
        externalResourceID: String?,
        result: ToolResult,
        at: Date
    ) throws {
        let payload = try encoder.encode(ExternalSideEffectResultPayload(result))
        try transition(
            id: id,
            allowedFrom: [.started],
            to: .succeeded,
            at: at,
            assignments: "external_resource_id = ?, completed_at = ?, result_json = ?, failure_category = NULL",
            values: [
                .init(externalResourceID),
                .text(dateFormatter.string(from: at)),
                .blob(payload)
            ]
        )
    }

    public func markUnknown(
        id: String,
        externalResourceID: String?,
        failureCategory: String,
        at: Date
    ) throws {
        try transition(
            id: id,
            allowedFrom: [.started],
            to: .unknown,
            at: at,
            assignments: "external_resource_id = ?, completed_at = ?, failure_category = ?",
            values: [
                .init(externalResourceID),
                .text(dateFormatter.string(from: at)),
                .text(failureCategory)
            ]
        )
    }

    public func markFailedBeforeSideEffect(id: String, failureCategory: String, at: Date) throws {
        try transition(
            id: id,
            allowedFrom: [.started],
            to: .failedBeforeSideEffect,
            at: at,
            assignments: "completed_at = ?, failure_category = ?",
            values: [
                .text(dateFormatter.string(from: at)),
                .text(failureCategory)
            ]
        )
    }

    public func markCompensated(id: String, reconciliationResult: String, at: Date) throws {
        try transition(
            id: id,
            allowedFrom: [.unknown, .succeeded],
            to: .compensated,
            at: at,
            assignments: "completed_at = ?, reconciliation_result = ?",
            values: [
                .text(dateFormatter.string(from: at)),
                .text(reconciliationResult)
            ]
        )
    }

    public func reconcileSucceeded(
        id: String,
        externalResourceID: String,
        result: ToolResult,
        reconciliationResult: String,
        at: Date
    ) throws {
        let payload = try encoder.encode(ExternalSideEffectResultPayload(result))
        try transition(
            id: id,
            allowedFrom: [.unknown],
            to: .succeeded,
            at: at,
            assignments: """
            external_resource_id = ?,
            completed_at = ?,
            reconciliation_result = ?,
            result_json = ?,
            failure_category = NULL
            """,
            values: [
                .text(externalResourceID),
                .text(dateFormatter.string(from: at)),
                .text(reconciliationResult),
                .blob(payload)
            ]
        )
    }

    public func record(id: String) throws -> ExternalSideEffectRecord? {
        lock.lock()
        defer { lock.unlock() }
        return try recordLocked(id: id)
    }

    public func records(executionID: String) throws -> [ExternalSideEffectRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try queryRecordsLocked(
            """
            SELECT * FROM external_side_effect_journal
            WHERE execution_id = ?
            ORDER BY item_index IS NULL, item_index, prepared_at, id;
            """,
            parameters: [.text(executionID)]
        )
    }

    public func recordsRequiringReconciliation() throws -> [ExternalSideEffectRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try queryRecordsLocked(
            """
            SELECT * FROM external_side_effect_journal
            WHERE state = 'unknown'
            ORDER BY updated_at, id;
            """
        )
    }

    @discardableResult
    public func recoverStartedAsUnknown(at: Date) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = dateFormatter.string(from: at)
        try connection.execute(
            """
            UPDATE external_side_effect_journal
            SET state = 'unknown',
                completed_at = ?,
                updated_at = ?,
                failure_category = 'process_interrupted_after_start'
            WHERE state = 'started';
            """,
            parameters: [.text(timestamp), .text(timestamp)]
        )
        return connection.numberOfChanges
    }

    private func transition(
        id: String,
        allowedFrom: Set<ExternalSideEffectState>,
        to state: ExternalSideEffectState,
        at: Date,
        assignments: String,
        values: [SQLiteValue]
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let existing = try requiredRecordLocked(id: id)
        guard allowedFrom.contains(existing.state) else {
            throw ExternalSideEffectJournalError.invalidTransition(
                id: id,
                from: existing.state,
                to: state
            )
        }
        let placeholders = allowedFrom.map { _ in "?" }.joined(separator: ", ")
        let fromValues = allowedFrom.map { SQLiteValue.text($0.rawValue) }
        try connection.execute(
            """
            UPDATE external_side_effect_journal
            SET state = ?, \(assignments), updated_at = ?
            WHERE id = ? AND state IN (\(placeholders));
            """,
            parameters: [.text(state.rawValue)]
                + values
                + [.text(dateFormatter.string(from: at)), .text(id)]
                + fromValues
        )
        guard connection.numberOfChanges == 1 else {
            throw ExternalSideEffectJournalError.invalidTransition(
                id: id,
                from: existing.state,
                to: state
            )
        }
    }

    private func recordLocked(id: String) throws -> ExternalSideEffectRecord? {
        try queryRecordsLocked(
            "SELECT * FROM external_side_effect_journal WHERE id = ? LIMIT 1;",
            parameters: [.text(id)]
        ).first
    }

    private func recordLocked(idempotencyKey: String) throws -> ExternalSideEffectRecord? {
        try queryRecordsLocked(
            "SELECT * FROM external_side_effect_journal WHERE idempotency_key = ? LIMIT 1;",
            parameters: [.text(idempotencyKey)]
        ).first
    }

    private func requiredRecordLocked(id: String) throws -> ExternalSideEffectRecord {
        guard let record = try recordLocked(id: id) else {
            throw ExternalSideEffectJournalError.recordNotFound(id)
        }
        return record
    }

    private func queryRecordsLocked(
        _ sql: String,
        parameters: [SQLiteValue] = []
    ) throws -> [ExternalSideEffectRecord] {
        try connection.query(sql, parameters: parameters) { row in
            let stateRaw = try row.string("state")
            let toolRaw = try row.string("tool")
            guard let state = ExternalSideEffectState(rawValue: stateRaw),
                  let tool = ActionTool(rawValue: toolRaw),
                  let preparedAt = self.dateFormatter.date(from: try row.string("prepared_at")),
                  let updatedAt = self.dateFormatter.date(from: try row.string("updated_at")) else {
                throw ExternalSideEffectJournalError.corruptedRecord(try row.string("id"))
            }
            let result: ToolResult?
            if let data = try row.optionalData("result_json") {
                result = try self.decoder.decode(ExternalSideEffectResultPayload.self, from: data).toolResult
            } else {
                result = nil
            }
            return ExternalSideEffectRecord(
                id: try row.string("id"),
                executionID: try row.string("execution_id"),
                reviewSessionID: try row.string("review_session_id"),
                actionID: try row.string("action_id"),
                itemIndex: try row.optionalInt64("item_index").map(Int.init),
                tool: tool,
                canonicalArgumentsDigest: try row.data("canonical_arguments_digest"),
                idempotencyKey: try row.string("idempotency_key"),
                attempt: Int(try row.int64("attempt")),
                state: state,
                externalResourceID: try row.optionalString("external_resource_id"),
                preparedAt: preparedAt,
                startedAt: try row.optionalString("started_at").flatMap(self.dateFormatter.date(from:)),
                completedAt: try row.optionalString("completed_at").flatMap(self.dateFormatter.date(from:)),
                updatedAt: updatedAt,
                failureCategory: try row.optionalString("failure_category"),
                reconciliationResult: try row.optionalString("reconciliation_result"),
                result: result
            )
        }
    }
}

public struct ExternalSideEffectReconciliationRow: Equatable, Sendable {
    public var id: String
    public var tool: ActionTool
    public var actionID: String
    public var itemIndex: Int?
    public var idempotencyKey: String
    public var externalResourceID: String?
    public var state: ExternalSideEffectState
    public var updatedAt: Date
    public var guidance: String

    public init(record: ExternalSideEffectRecord) {
        id = record.id
        tool = record.tool
        actionID = record.actionID
        itemIndex = record.itemIndex
        idempotencyKey = record.idempotencyKey
        externalResourceID = record.externalResourceID
        state = record.state
        updatedAt = record.updatedAt
        guidance = record.externalResourceID == nil
            ? "Check the external service before choosing a result. Automatic retry is blocked."
            : "Verify external resource \(record.externalResourceID ?? "") before retrying or compensating."
    }
}

public struct ExternalSideEffectReconciliationReadModel: Sendable {
    private let journal: any ExternalSideEffectJournal

    public init(journal: any ExternalSideEffectJournal) {
        self.journal = journal
    }

    public func load() throws -> [ExternalSideEffectReconciliationRow] {
        try journal.recordsRequiringReconciliation().map(ExternalSideEffectReconciliationRow.init)
    }
}

private struct ExternalSideEffectResultPayload: Codable {
    var tool: ActionTool
    var status: String
    var summary: String
    var output: [String: JSONValue]
    var rollbackMetadata: [String: JSONValue]
    var compensationHint: String?

    init(_ result: ToolResult) {
        tool = result.tool
        status = result.status.rawValue
        summary = result.summary
        output = result.output
        rollbackMetadata = result.rollbackMetadata
        compensationHint = result.compensationHint
    }

    var toolResult: ToolResult {
        ToolResult(
            tool: tool,
            status: ToolExecutionStatus(rawValue: status) ?? .failed,
            summary: summary,
            output: output,
            rollbackMetadata: rollbackMetadata,
            compensationHint: compensationHint
        )
    }
}
