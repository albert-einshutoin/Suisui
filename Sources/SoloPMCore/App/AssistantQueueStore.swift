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

public enum AssistantQueueViewFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case needsAttention
    case waiting
    case approved
    case failed
    case deferred
    case done
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsAttention:
            return "Needs attention"
        case .waiting:
            return "Waiting"
        case .approved:
            return "Approved"
        case .failed:
            return "Failed"
        case .deferred:
            return "Deferred"
        case .done:
            return "Done"
        case .all:
            return "All"
        }
    }

    public var states: Set<AssistantQueueState> {
        switch self {
        case .needsAttention:
            return [.blocked, .captured, .interpreted, .drafted, .waitingReview, .approved, .failed]
        case .waiting:
            return [.captured, .interpreted, .drafted, .waitingReview, .blocked]
        case .approved:
            return [.approved, .running]
        case .failed:
            return [.failed]
        case .deferred:
            return [.deferred]
        case .done:
            return [.done]
        case .all:
            return Set(AssistantQueueState.allCases)
        }
    }

    public func storeFilter(limit: Int = 100) -> AssistantQueueFilter {
        self == .all ? .all(limit: limit) : .states(states, limit: limit)
    }
}

public enum AssistantQueueSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case needsActionFirst
    case riskHighFirst
    case titleAscending

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsActionFirst:
            return "Needs action first"
        case .riskHighFirst:
            return "Risk high first"
        case .titleAscending:
            return "Title A-Z"
        }
    }
}

public struct AssistantQueueStateCounts: Equatable, Sendable {
    public var total: Int
    public var byState: [AssistantQueueState: Int]

    public static let empty = AssistantQueueStateCounts(total: 0, byState: [:])

    public init(total: Int, byState: [AssistantQueueState: Int]) {
        self.total = total
        self.byState = byState
    }

    public init(items: [AssistantQueueItem]) {
        self.total = items.count
        self.byState = items.reduce(into: [:]) { counts, item in
            counts[item.state, default: 0] += 1
        }
    }

    public func count(for state: AssistantQueueState) -> Int {
        byState[state, default: 0]
    }

    public func count(in states: Set<AssistantQueueState>) -> Int {
        states.reduce(0) { partialResult, state in
            partialResult + count(for: state)
        }
    }
}

public protocol AssistantQueueStore {
    @discardableResult
    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem
    @discardableResult
    func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem?
    func get(id: String) throws -> AssistantQueueItem
    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem]
    func stateCounts() throws -> AssistantQueueStateCounts

    @discardableResult
    func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem
}

public extension AssistantQueueStore {
    @discardableResult
    func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem? {
        // Default stores are used by in-memory tests and lightweight adapters. Durable
        // sync-facing stores should override this with a conflict-safe insert.
        do {
            _ = try get(id: item.id)
            return nil
        } catch AssistantQueueStoreError.notFound {
            return try save(item)
        }
    }
}

public struct AssistantQueueReadModelRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var state: AssistantQueueState
    public var stateLabel: String
    public var riskLabel: String
    public var title: String
    public var redactedSummary: String
    public var sourcePreview: String?
    public var reviewReason: String
    public var capabilityLabels: [String]
    public var costPreviewLabel: String?
    public var blockingReason: String?
    public var latestReceipt: AssistantQueueReceiptSummary?
    public var canApprove: Bool
    public var canRun: Bool
    public var canDefer: Bool
    public var canEdit: Bool
    public var canRetry: Bool
    public var canReject: Bool

    public init(
        id: String,
        state: AssistantQueueState,
        stateLabel: String,
        riskLabel: String,
        title: String,
        redactedSummary: String,
        sourcePreview: String?,
        reviewReason: String,
        capabilityLabels: [String],
        costPreviewLabel: String? = nil,
        blockingReason: String?,
        latestReceipt: AssistantQueueReceiptSummary? = nil,
        canApprove: Bool,
        canRun: Bool,
        canDefer: Bool,
        canEdit: Bool,
        canRetry: Bool,
        canReject: Bool
    ) {
        self.id = id
        self.state = state
        self.stateLabel = stateLabel
        self.riskLabel = riskLabel
        self.title = title
        self.redactedSummary = redactedSummary
        self.sourcePreview = sourcePreview
        self.reviewReason = reviewReason
        self.capabilityLabels = capabilityLabels
        self.costPreviewLabel = costPreviewLabel
        self.blockingReason = blockingReason
        self.latestReceipt = latestReceipt
        self.canApprove = canApprove
        self.canRun = canRun
        self.canDefer = canDefer
        self.canEdit = canEdit
        self.canRetry = canRetry
        self.canReject = canReject
    }
}

public struct AssistantQueueReceiptSummary: Identifiable, Equatable, Sendable {
    public var id: String
    public var runID: String
    public var status: ExecutionReceiptStatus
    public var statusLabel: String
    public var outputSummary: String
    public var usageLabel: String
    public var actionCount: Int
    public var finishedAt: Date?

    public init(
        id: String,
        runID: String,
        status: ExecutionReceiptStatus,
        statusLabel: String,
        outputSummary: String,
        usageLabel: String,
        actionCount: Int,
        finishedAt: Date?
    ) {
        self.id = id
        self.runID = runID
        self.status = status
        self.statusLabel = statusLabel
        self.outputSummary = outputSummary
        self.usageLabel = usageLabel
        self.actionCount = actionCount
        self.finishedAt = finishedAt
    }
}

public struct AssistantQueueSnapshot: Equatable, Sendable {
    public var rows: [AssistantQueueReadModelRow]
    public var totalCount: Int
    public var needsAttentionCount: Int
    public var waitingReviewCount: Int
    public var blockedCount: Int
    public var approvedCount: Int
    public var failedCount: Int
    public var deferredCount: Int
    public var doneCount: Int

    public static let empty = AssistantQueueSnapshot(
        rows: [],
        totalCount: 0,
        needsAttentionCount: 0,
        waitingReviewCount: 0,
        blockedCount: 0
    )

    public init(
        rows: [AssistantQueueReadModelRow],
        totalCount: Int? = nil,
        needsAttentionCount: Int? = nil,
        waitingReviewCount: Int,
        blockedCount: Int,
        approvedCount: Int = 0,
        failedCount: Int = 0,
        deferredCount: Int = 0,
        doneCount: Int = 0
    ) {
        self.rows = rows
        self.totalCount = totalCount ?? rows.count
        self.needsAttentionCount = needsAttentionCount
            ?? rows.filter { AssistantQueueViewFilter.needsAttention.states.contains($0.state) }.count
        self.waitingReviewCount = waitingReviewCount
        self.blockedCount = blockedCount
        self.approvedCount = approvedCount
        self.failedCount = failedCount
        self.deferredCount = deferredCount
        self.doneCount = doneCount
    }

    public var reviewableCount: Int {
        needsAttentionCount
    }
}

public enum AssistantQueueReadModel {
    public static func snapshot(
        from items: [AssistantQueueItem],
        receipts: [ExecutionReceipt] = [],
        viewFilter: AssistantQueueViewFilter = .all,
        sort: AssistantQueueSort = .needsActionFirst,
        allItemsForCounts: [AssistantQueueItem]? = nil,
        stateCounts: AssistantQueueStateCounts? = nil
    ) -> AssistantQueueSnapshot {
        let latestReceipts = latestAssistantQueueReceiptsByItemID(receipts)
        let counts = stateCounts ?? AssistantQueueStateCounts(items: allItemsForCounts ?? items)
        let rows = items
            .filter { viewFilter.states.contains($0.state) }
            .sorted { sortItems($0, $1, sort: sort) }
            .map { item in row(from: item, receipt: latestReceipts[item.id]) }
        return AssistantQueueSnapshot(
            rows: rows,
            totalCount: counts.total,
            needsAttentionCount: counts.count(in: AssistantQueueViewFilter.needsAttention.states),
            waitingReviewCount: counts.count(for: .waitingReview),
            blockedCount: counts.count(for: .blocked),
            approvedCount: counts.count(for: .approved) + counts.count(for: .running),
            failedCount: counts.count(for: .failed),
            deferredCount: counts.count(for: .deferred),
            doneCount: counts.count(for: .done)
        )
    }

    private static func row(
        from item: AssistantQueueItem,
        receipt: ExecutionReceipt? = nil
    ) -> AssistantQueueReadModelRow {
        let redactedSummary = redactedText(item.redactedSummary)
        return AssistantQueueReadModelRow(
            id: item.id,
            state: item.state,
            stateLabel: label(for: item.state),
            riskLabel: item.riskLevel.rawValue.capitalized,
            title: redactedSummary.assistantQueuePreview(maxLength: 160),
            redactedSummary: redactedSummary,
            sourcePreview: item.sourceTranscript.map(redactedPreview),
            reviewReason: item.reviewReason,
            capabilityLabels: item.requiredCapabilities.map { redactedPreview(label(for: $0)) },
            costPreviewLabel: item.costPreview.map { redactedPreview($0.reviewLabel) },
            blockingReason: item.blockingReason,
            latestReceipt: receipt.map(receiptSummary),
            canApprove: canApprove(item),
            canRun: canRun(item),
            canDefer: canDefer(item),
            canEdit: canEdit(item),
            canRetry: canRetry(item),
            canReject: canReject(item)
        )
    }

    private static func latestAssistantQueueReceiptsByItemID(_ receipts: [ExecutionReceipt]) -> [String: ExecutionReceipt] {
        receipts.reduce(into: [:]) { partialResult, receipt in
            guard let itemID = receipt.assistantQueueItemID else {
                return
            }
            guard receipt.visibleSurfaces.contains(.assistantQueue) else {
                return
            }
            guard let existing = partialResult[itemID] else {
                partialResult[itemID] = receipt
                return
            }
            if receiptSortDate(receipt) > receiptSortDate(existing) {
                partialResult[itemID] = receipt
            }
        }
    }

    private static func receiptSummary(_ receipt: ExecutionReceipt) -> AssistantQueueReceiptSummary {
        AssistantQueueReceiptSummary(
            id: receipt.id,
            runID: receipt.runID,
            status: receipt.status,
            statusLabel: label(for: receipt.status),
            outputSummary: redactedPreview(receipt.outputSummary),
            usageLabel: usageLabel(for: receipt.usage),
            actionCount: receipt.actions.count,
            finishedAt: receipt.finishedAt
        )
    }

    private static func receiptSortDate(_ receipt: ExecutionReceipt) -> Date {
        receipt.finishedAt ?? receipt.startedAt ?? receipt.createdAt
    }

    private static func sortForReview(_ lhs: AssistantQueueItem, _ rhs: AssistantQueueItem) -> Bool {
        let leftRank = reviewRank(lhs.state)
        let rightRank = reviewRank(rhs.state)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.id < rhs.id
    }

    private static func sortItems(
        _ lhs: AssistantQueueItem,
        _ rhs: AssistantQueueItem,
        sort: AssistantQueueSort
    ) -> Bool {
        switch sort {
        case .needsActionFirst:
            return sortForReview(lhs, rhs)
        case .riskHighFirst:
            if lhs.riskLevel != rhs.riskLevel {
                return lhs.riskLevel > rhs.riskLevel
            }
            return sortForReview(lhs, rhs)
        case .titleAscending:
            let leftTitle = redactedText(lhs.redactedSummary).localizedCaseInsensitiveCompare(redactedText(rhs.redactedSummary))
            if leftTitle != .orderedSame {
                return leftTitle == .orderedAscending
            }
            return sortForReview(lhs, rhs)
        }
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
        case .failed:
            return 5
        case .deferred:
            return 6
        case .rejected:
            return 7
        case .done:
            return 8
        }
    }

    private static func canApprove(_ item: AssistantQueueItem) -> Bool {
        switch item.state {
        case .waitingReview, .captured, .interpreted, .drafted, .deferred:
            return item.riskLevel != .danger && (item.costPreview?.allowsApprovalAndRun ?? false)
        case .approved, .running, .blocked, .done, .failed, .rejected:
            return false
        }
    }

    private static func canRun(_ item: AssistantQueueItem) -> Bool {
        guard item.state == .approved else {
            return false
        }
        guard item.costPreview?.allowsApprovalAndRun == true else {
            return false
        }
        return AssistantQueueExecutableActionPlanFactory.actionPlan(for: item.payload) != nil
    }

    private static func canDefer(_ item: AssistantQueueItem) -> Bool {
        switch item.state {
        case .waitingReview, .captured, .interpreted, .drafted, .approved:
            return true
        case .running, .blocked, .done, .failed, .rejected, .deferred:
            return false
        }
    }

    private static func canRetry(_ item: AssistantQueueItem) -> Bool {
        guard item.state == .failed else {
            return false
        }
        guard case .actionPlan(let plan) = item.payload else {
            return false
        }
        return item.riskLevel != .danger
            && plan.riskLevel != .danger
            && !plan.actions.contains { $0.riskLevel == .danger }
    }

    private static func canEdit(_ item: AssistantQueueItem) -> Bool {
        item.isEditableForReview
    }

    private static func canReject(_ item: AssistantQueueItem) -> Bool {
        switch item.state {
        case .done, .failed, .rejected:
            return false
        case .captured, .interpreted, .drafted, .waitingReview, .approved, .running, .blocked, .deferred:
            return true
        }
    }

    private static func redactedPreview(_ value: String) -> String {
        redactedText(value).assistantQueuePreview(maxLength: 160)
    }

    private static func redactedText(_ value: String) -> String {
        DeveloperSecretRedactor().redact(value).text
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
        case .failed:
            return "Failed"
        case .rejected:
            return "Rejected"
        case .deferred:
            return "Deferred"
        }
    }

    private static func label(for status: ExecutionReceiptStatus) -> String {
        switch status {
        case .notStarted:
            return "Not Started"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        case .canceled:
            return "Canceled"
        }
    }

    private static func usageLabel(for usage: ExecutionReceiptUsage) -> String {
        switch usage.state {
        case .measured:
            return tokenUsageLabel(prefix: "Measured", usage: usage)
        case .estimated:
            return tokenUsageLabel(prefix: "Estimated", usage: usage)
        case .unknown:
            return "Usage unknown"
        case .unavailable:
            return "Usage unavailable"
        }
    }

    private static func tokenUsageLabel(prefix: String, usage: ExecutionReceiptUsage) -> String {
        var parts: [String] = []
        if let totalTokens = usage.totalTokens {
            parts.append("\(formattedInteger(totalTokens)) tokens")
        } else {
            parts.append("usage")
        }
        if let estimatedCostCents = usage.estimatedCostCents,
           let currencyCode = usage.currencyCode,
           !currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\(currencyCode) \(formattedMajorCurrency(fromCents: estimatedCostCents))")
        }
        return "\(prefix): \(parts.joined(separator: ", "))"
    }

    private static func formattedMajorCurrency(fromCents cents: Double) -> String {
        let value = cents / 100
        let format = value > 0 && value < 0.01 ? "%.4f" : "%.2f"
        return String(format: format, value)
    }

    private static func formattedInteger(_ value: Int) -> String {
        let digits = Array(String(abs(value)).reversed())
        let grouped = stride(from: 0, to: digits.count, by: 3)
            .map { start -> String in
                let end = min(start + 3, digits.count)
                return String(digits[start..<end].reversed())
            }
            .reversed()
            .joined(separator: ",")
        return value < 0 ? "-\(grouped)" : grouped
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

    @discardableResult
    public func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem? {
        lock.lock()
        defer { lock.unlock() }

        // Sync ingest replays remote facts, while queue rows hold local review state.
        // Conflict-safe insert preserves approvals, edits, and receipts on duplicates.
        let inserted = try insertLocked(item, onIDConflict: "ON CONFLICT(id) DO NOTHING")
        return inserted ? item : nil
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

    public func stateCounts() throws -> AssistantQueueStateCounts {
        lock.lock()
        defer { lock.unlock() }

        let rows = try connection.queryRows(
            """
            SELECT state, COUNT(*) AS count
            FROM assistant_queue_items
            GROUP BY state;
            """
        )
        var byState: [AssistantQueueState: Int] = [:]
        var total = 0
        for row in rows {
            guard let rawState = row["state"], let state = AssistantQueueState(rawValue: rawState) else {
                throw AssistantQueueStoreError.invalidStoredValue(
                    column: "assistant_queue_items.state",
                    value: row["state"] ?? ""
                )
            }
            guard let rawCount = row["count"], let count = Int(rawCount) else {
                throw AssistantQueueStoreError.invalidStoredValue(
                    column: "assistant_queue_items.count",
                    value: row["count"] ?? ""
                )
            }
            byState[state] = count
            total += count
        }
        return AssistantQueueStateCounts(total: total, byState: byState)
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
        let costPreviewJSON = try item.costPreview.map { try encode($0, column: "assistant_queue_items.cost_preview_json") }
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
                    cost_preview_json = \(Self.optional(costPreviewJSON)),
                    updated_at = '\(Self.escape(now))'
                WHERE id = '\(Self.escape(item.id))';
                """
            )
        } else {
            _ = try insertLocked(item)
        }
    }

    @discardableResult
    private func insertLocked(
        _ item: AssistantQueueItem,
        onIDConflict conflictClause: String = ""
    ) throws -> Bool {
        let payloadJSON = try encode(item.payload, column: "assistant_queue_items.payload_json")
        let requiredCapabilitiesJSON = try encode(item.requiredCapabilities, column: "assistant_queue_items.required_capabilities_json")
        let approvalJSON = try item.approval.map { try encode($0, column: "assistant_queue_items.approval_json") }
        let costPreviewJSON = try item.costPreview.map { try encode($0, column: "assistant_queue_items.cost_preview_json") }
        let now = Self.timestamp()
        let normalizedConflictClause = conflictClause.trimmingCharacters(in: .whitespacesAndNewlines)
        let conflictSQL = normalizedConflictClause.isEmpty ? "" : "\n\(normalizedConflictClause)"
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
                cost_preview_json,
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
                \(Self.optional(costPreviewJSON)),
                '\(Self.escape(now))',
                '\(Self.escape(now))'
            )\(conflictSQL);
            """
        )
        return try connection.queryStrings("SELECT changes();").first == "1"
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
        let costPreview = try decodeOptional(
            AssistantQueueCostPreview.self,
            from: row["cost_preview_json"],
            column: "assistant_queue_items.cost_preview_json"
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
            blockingReason: nilIfEmpty(row["blocking_reason"]),
            costPreview: costPreview
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
