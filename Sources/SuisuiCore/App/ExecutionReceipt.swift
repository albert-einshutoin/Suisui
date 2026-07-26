import CryptoKit
import Foundation

public enum ExecutionReceiptStatus: String, Codable, Equatable, Hashable, Sendable {
    case notStarted = "not_started"
    case running
    case succeeded
    case failed
    case skipped
    case canceled
}

public enum ExecutionReceiptUsageState: String, Codable, Equatable, Sendable {
    case measured
    case estimated
    case unknown
    case unavailable
}

public enum ExecutionReceiptReferenceKind: String, Codable, Equatable, Hashable, Sendable {
    case unknown
    case assistantQueue = "assistant_queue"
    case actionPlan = "action_plan"
    case reviewSession = "review_session"
    case task
    case project
    case document
    case calendarEvent = "calendar_event"
    case notification
    case reminder
    case developmentBranch = "development_branch"
    case developmentBaseBranch = "development_base_branch"
    case developmentCommit = "development_commit"
    case file
    case pullRequest = "pull_request"
    case externalMCP = "external_mcp"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ExecutionReceiptSurface: String, Codable, Equatable, Hashable, Sendable {
    case assistantQueue = "assistant_queue"
    case doneList = "done_list"
    case taskDetail = "task_detail"
    case projectDetail = "project_detail"
    case auditLog = "audit_log"
}

public struct ExecutionReceiptModel: Codable, Equatable, Sendable {
    public var provider: String
    public var name: String

    public init(provider: String, name: String) {
        self.provider = provider
        self.name = name
    }
}

public struct ExecutionReceiptUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var estimatedCostCents: Double?
    public var currencyCode: String?
    public var state: ExecutionReceiptUsageState
    public var isEstimated: Bool { state == .estimated }

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        estimatedCostCents: Double? = nil,
        currencyCode: String? = nil,
        isEstimated: Bool = true,
        state: ExecutionReceiptUsageState? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCostCents = estimatedCostCents
        self.currencyCode = currencyCode
        self.state = state ?? Self.defaultState(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostCents: estimatedCostCents,
            isEstimated: isEstimated
        )
    }

    public static var unknown: ExecutionReceiptUsage {
        ExecutionReceiptUsage(state: .unknown)
    }

    public static var unavailable: ExecutionReceiptUsage {
        ExecutionReceiptUsage(isEstimated: false, state: .unavailable)
    }

    public var totalTokens: Int? {
        switch (inputTokens, outputTokens) {
        case (.some(let input), .some(let output)):
            input + output
        case (.some(let input), .none):
            input
        case (.none, .some(let output)):
            output
        case (.none, .none):
            nil
        }
    }

    private static func defaultState(
        inputTokens: Int?,
        outputTokens: Int?,
        estimatedCostCents: Double?,
        isEstimated: Bool
    ) -> ExecutionReceiptUsageState {
        guard inputTokens != nil || outputTokens != nil || estimatedCostCents != nil else {
            return .unknown
        }
        return isEstimated ? .estimated : .measured
    }
}

public struct ExecutionReceiptReference: Codable, Equatable, Sendable {
    public var kind: ExecutionReceiptReferenceKind
    public var id: String
    public var label: String?

    public init(kind: ExecutionReceiptReferenceKind, id: String, label: String? = nil) {
        self.kind = kind
        self.id = id
        self.label = label
    }
}

public struct ExecutionReceiptSourceLink: Codable, Equatable, Sendable {
    public var kind: ExecutionReceiptReferenceKind
    public var title: String
    public var url: String

    public init(kind: ExecutionReceiptReferenceKind, title: String, url: String) {
        self.kind = kind
        self.title = title
        self.url = url
    }
}

public struct ExecutionReceiptActionSummary: Codable, Equatable, Sendable {
    public var id: String
    public var toolName: String
    public var status: ExecutionReceiptStatus
    public var inputPreview: String
    public var outputSummary: String?
    public var errorSummary: String?
    public var failureRecovery: ExecutionReceiptFailureRecovery?
    public var externalSideEffectEvidence: ExecutionReceiptExternalSideEffectEvidence?

    public init(
        id: String,
        toolName: String,
        status: ExecutionReceiptStatus,
        inputPreview: String,
        outputSummary: String? = nil,
        errorSummary: String? = nil,
        failureRecovery: ExecutionReceiptFailureRecovery? = nil,
        externalSideEffectEvidence: ExecutionReceiptExternalSideEffectEvidence? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.status = status
        self.inputPreview = inputPreview
        self.outputSummary = outputSummary
        self.errorSummary = errorSummary
        self.failureRecovery = failureRecovery
        self.externalSideEffectEvidence = externalSideEffectEvidence
    }
}

public struct ExecutionReceiptExternalSideEffectEvidence: Codable, Equatable, Sendable {
    public var idempotencyKeys: [String]
    public var externalResourceIDs: [String]
    public var journalRecordIDs: [String]
    public var journalState: ExternalSideEffectState

    public init(
        idempotencyKeys: [String],
        externalResourceIDs: [String],
        journalRecordIDs: [String],
        journalState: ExternalSideEffectState
    ) {
        self.idempotencyKeys = idempotencyKeys
        self.externalResourceIDs = externalResourceIDs
        self.journalRecordIDs = journalRecordIDs
        self.journalState = journalState
    }
}

public enum ExecutionReceiptFailureRecovery: String, Codable, Equatable, Sendable {
    case retryable
    case notRetryable
}

public struct ExecutionReceiptQueueApproval: Codable, Equatable, Sendable {
    public var approvalID: String?
    public var reviewerID: String
    public var note: String?
    public private(set) var reviewedContentDigest: String

    public init(
        approvalID: String? = nil,
        reviewerID: String,
        note: String? = nil,
        reviewedContentFingerprint: String
    ) {
        self.approvalID = approvalID
        self.reviewerID = reviewerID
        self.note = note
        self.reviewedContentDigest = ExecutionReceiptDigest.normalizedDigest(reviewedContentFingerprint)
    }

    init(
        approvalID: String? = nil,
        reviewerID: String,
        note: String? = nil,
        reviewedContentDigest: String
    ) {
        self.approvalID = approvalID
        self.reviewerID = reviewerID
        self.note = note
        self.reviewedContentDigest = reviewedContentDigest
    }
}

public struct ExecutionReceiptApprovalEvidence: Codable, Equatable, Sendable {
    public let approvalID: String
    public let sessionID: String
    public let planID: String
    public let canonicalPlanDigest: String
    public let enabledActionIDs: [String]
    public let issuedAt: Date
    public let expiresAt: Date
    public let nonce: String

    public init(_ approval: ApprovedExecution) {
        self.approvalID = approval.approvalID.uuidString
        self.sessionID = approval.sessionID
        self.planID = approval.planID
        self.canonicalPlanDigest = approval.canonicalPlanDigest.lowercaseHexString
        self.enabledActionIDs = approval.enabledActionIDs.sorted()
        self.issuedAt = approval.issuedAt
        self.expiresAt = approval.expiresAt
        self.nonce = approval.nonce.uuidString
    }
}

public struct ExecutionReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public private(set) var id: String
    public private(set) var runID: String
    public private(set) var approvalID: String?
    public private(set) var assistantQueueItemID: String?
    public private(set) var queueApproval: ExecutionReceiptQueueApproval?
    public private(set) var approvalEvidence: ExecutionReceiptApprovalEvidence?
    public private(set) var resolvedActionEvidence: [ResolvedActionEvidence]?
    public private(set) var createdAt: Date
    public private(set) var startedAt: Date?
    public private(set) var finishedAt: Date?
    public private(set) var status: ExecutionReceiptStatus
    public private(set) var inputPreview: String
    public private(set) var outputSummary: String
    public private(set) var model: ExecutionReceiptModel?
    public private(set) var primaryToolName: String?
    public private(set) var usage: ExecutionReceiptUsage
    public private(set) var references: [ExecutionReceiptReference]
    public private(set) var sourceLinks: [ExecutionReceiptSourceLink]
    public private(set) var actions: [ExecutionReceiptActionSummary]
    public private(set) var visibleSurfaces: [ExecutionReceiptSurface]

    public init(
        id: String,
        runID: String,
        approvalID: String? = nil,
        assistantQueueItemID: String? = nil,
        queueApproval: ExecutionReceiptQueueApproval? = nil,
        approvalEvidence: ExecutionReceiptApprovalEvidence? = nil,
        resolvedActionEvidence: [ResolvedActionEvidence]? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        status: ExecutionReceiptStatus,
        inputPreview: String,
        outputSummary: String,
        model: ExecutionReceiptModel? = nil,
        primaryToolName: String? = nil,
        usage: ExecutionReceiptUsage = .unknown,
        references: [ExecutionReceiptReference] = [],
        sourceLinks: [ExecutionReceiptSourceLink] = [],
        actions: [ExecutionReceiptActionSummary] = [],
        visibleSurfaces: [ExecutionReceiptSurface] = [],
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        self.schemaVersion = 1
        self.id = id
        self.runID = runID
        self.approvalID = approvalID
        self.assistantQueueItemID = assistantQueueItemID
        self.queueApproval = queueApproval.map { approval in
            ExecutionReceiptQueueApproval(
                approvalID: approval.approvalID,
                reviewerID: redactor.redact(approval.reviewerID, maxLength: 180),
                note: approval.note.map { redactor.redact($0, maxLength: 600) },
                reviewedContentDigest: approval.reviewedContentDigest
            )
        }
        self.approvalEvidence = approvalEvidence
        self.resolvedActionEvidence = resolvedActionEvidence
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.inputPreview = redactor.redact(inputPreview)
        self.outputSummary = redactor.redact(outputSummary)
        self.model = model
        self.primaryToolName = primaryToolName
        self.usage = usage
        self.references = references.map { reference in
            ExecutionReceiptReference(
                kind: reference.kind,
                id: redactor.redact(reference.id, maxLength: 240),
                label: reference.label.map { redactor.redact($0, maxLength: 300) }
            )
        }
        self.sourceLinks = sourceLinks.map { link in
            ExecutionReceiptSourceLink(
                kind: link.kind,
                title: redactor.redact(link.title, maxLength: 240),
                url: redactor.redact(link.url, maxLength: 600)
            )
        }
        self.actions = actions.map { action in
            ExecutionReceiptActionSummary(
                id: redactor.redact(action.id, maxLength: 240),
                toolName: action.toolName,
                status: action.status,
                inputPreview: redactor.redact(action.inputPreview),
                outputSummary: action.outputSummary.map { redactor.redact($0) },
                errorSummary: action.errorSummary.map { redactor.redact($0) },
                failureRecovery: action.failureRecovery,
                externalSideEffectEvidence: action.externalSideEffectEvidence.map { evidence in
                    ExecutionReceiptExternalSideEffectEvidence(
                        idempotencyKeys: evidence.idempotencyKeys.map {
                            redactor.redact($0, maxLength: 240)
                        },
                        externalResourceIDs: evidence.externalResourceIDs.map {
                            redactor.redact($0, maxLength: 240)
                        },
                        journalRecordIDs: evidence.journalRecordIDs.map {
                            redactor.redact($0, maxLength: 240)
                        },
                        journalState: evidence.journalState
                    )
                }
            )
        }
        self.visibleSurfaces = visibleSurfaces
    }
}

public protocol ExecutionReceiptStore: Sendable {
    func save(_ receipt: ExecutionReceipt) throws
    func list(limit: Int) throws -> [ExecutionReceipt]
    func list(matching filter: ExecutionReceiptSearchFilter, limit: Int) throws -> [ExecutionReceipt]
    func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int
    ) throws -> [ExecutionReceipt]
}

public enum ExecutionReceiptStoreError: Error, Equatable, Sendable {
    case duplicateReceiptID(String)
}

fileprivate func executionReceiptNormalizedSearchText(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

fileprivate func executionReceiptSearchTokens(in query: String) -> [String] {
    executionReceiptNormalizedSearchText(query)
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
}

fileprivate struct ExecutionReceiptIndexReference: Codable, Equatable, Sendable {
    var kind: ExecutionReceiptReferenceKind
    var id: String

    init(kind: ExecutionReceiptReferenceKind, id: String) {
        self.kind = kind
        self.id = id
    }
}

fileprivate struct ExecutionReceiptIndexEntry: Codable, Equatable, Sendable {
    var id: String
    var runID: String
    var assistantQueueItemID: String?
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var status: ExecutionReceiptStatus
    var primaryToolName: String?
    var usageState: ExecutionReceiptUsageState
    var modelProvider: String?
    var modelName: String?
    var referenceKinds: [ExecutionReceiptReferenceKind]
    var references: [ExecutionReceiptIndexReference]
    var sourceLinkKinds: [ExecutionReceiptReferenceKind]
    var actionToolNames: [String]
    var actionStatuses: [ExecutionReceiptStatus]
    var visibleSurfaces: [ExecutionReceiptSurface]
    var outputSummary: String
    var searchableText: String
    var receiptPath: String
    var digest: String

    var occurrenceDate: Date {
        finishedAt ?? startedAt ?? createdAt
    }

    var toolNames: Set<String> {
        Set(([primaryToolName].compactMap { $0 } + actionToolNames)
            .map(executionReceiptNormalizedSearchText)
            .filter { !$0.isEmpty })
    }

    init(receipt: ExecutionReceipt, receiptPath: String, digest: String) {
        self.id = receipt.id
        self.runID = receipt.runID
        self.assistantQueueItemID = receipt.assistantQueueItemID
        self.createdAt = receipt.createdAt
        self.startedAt = receipt.startedAt
        self.finishedAt = receipt.finishedAt
        self.status = receipt.status
        self.primaryToolName = receipt.primaryToolName
        self.usageState = receipt.usage.state
        self.modelProvider = receipt.model?.provider
        self.modelName = receipt.model?.name
        self.referenceKinds = receipt.references.map(\.kind)
        self.references = receipt.references.map { reference in
            ExecutionReceiptIndexReference(kind: reference.kind, id: reference.id)
        }
        self.sourceLinkKinds = receipt.sourceLinks.map(\.kind)
        self.actionToolNames = receipt.actions.map(\.toolName)
        self.actionStatuses = receipt.actions.map(\.status)
        self.visibleSurfaces = receipt.visibleSurfaces
        self.outputSummary = receipt.outputSummary
        self.searchableText = executionReceiptSearchableText(
            status: receipt.status,
            outputSummary: receipt.outputSummary,
            usageState: receipt.usage.state,
            primaryToolName: receipt.primaryToolName,
            modelProvider: receipt.model?.provider,
            modelName: receipt.model?.name,
            referenceKinds: receipt.references.map(\.kind),
            sourceLinkKinds: receipt.sourceLinks.map(\.kind),
            visibleSurfaces: receipt.visibleSurfaces,
            actionToolNames: receipt.actions.map(\.toolName),
            actionStatuses: receipt.actions.map(\.status)
        )
        self.receiptPath = receiptPath
        self.digest = digest
    }
}

fileprivate struct ExecutionReceiptIndexFileSnapshot: Equatable, Sendable {
    var modificationDate: Date?
    var byteCount: Int?
}

fileprivate struct ExecutionReceiptDirectorySnapshot: Equatable, Sendable {
    var modificationDate: Date?
}

fileprivate func executionReceiptSearchableText(
    status: ExecutionReceiptStatus,
    outputSummary: String,
    usageState: ExecutionReceiptUsageState,
    primaryToolName: String?,
    modelProvider: String?,
    modelName: String?,
    referenceKinds: [ExecutionReceiptReferenceKind],
    sourceLinkKinds: [ExecutionReceiptReferenceKind],
    visibleSurfaces: [ExecutionReceiptSurface],
    actionToolNames: [String],
    actionStatuses: [ExecutionReceiptStatus]
) -> String {
    var parts: [String] = [
        status.rawValue,
        outputSummary,
        usageState.rawValue,
        primaryToolName ?? "",
        modelProvider ?? "",
        modelName ?? ""
    ]
    parts.append(contentsOf: referenceKinds.map(\.rawValue))
    parts.append(contentsOf: sourceLinkKinds.map(\.rawValue))
    parts.append(contentsOf: visibleSurfaces.map(\.rawValue))
    parts.append(contentsOf: actionToolNames)
    parts.append(contentsOf: actionStatuses.map(\.rawValue))

    // This index stores the redacted, query-safe vocabulary so recent history
    // and scoped search can stay fast without decoding every receipt JSON file.
    return executionReceiptNormalizedSearchText(parts.joined(separator: " "))
}

public struct ExecutionReceiptSearchFilter: Equatable, Sendable {
    public var query: String
    public var statuses: Set<ExecutionReceiptStatus>
    public var toolNames: Set<String>
    public var referenceKinds: Set<ExecutionReceiptReferenceKind>
    public var visibleSurface: ExecutionReceiptSurface?

    public init(
        query: String = "",
        statuses: Set<ExecutionReceiptStatus> = [],
        toolNames: Set<String> = [],
        referenceKinds: Set<ExecutionReceiptReferenceKind> = [],
        visibleSurface: ExecutionReceiptSurface? = nil
    ) {
        self.query = query
        self.statuses = statuses
        self.toolNames = Set(toolNames.map(Self.normalizedIdentifier).filter { !$0.isEmpty })
        self.referenceKinds = referenceKinds
        self.visibleSurface = visibleSurface
    }

    public var isEmpty: Bool {
        Self.searchTokens(in: query).isEmpty
            && statuses.isEmpty
            && toolNames.isEmpty
            && referenceKinds.isEmpty
            && visibleSurface == nil
    }

    public func matches(_ receipt: ExecutionReceipt) -> Bool {
        if !statuses.isEmpty && !statuses.contains(receipt.status) {
            return false
        }
        if let visibleSurface, !receipt.visibleSurfaces.contains(visibleSurface) {
            return false
        }
        if !toolNames.isEmpty && toolNames.isDisjoint(with: toolNames(in: receipt)) {
            return false
        }
        if !referenceKinds.isEmpty && referenceKinds.isDisjoint(with: Set(receipt.references.map(\.kind))) {
            return false
        }

        let tokens = Self.searchTokens(in: query)
        guard !tokens.isEmpty else {
            return true
        }
        let searchableText = Self.normalizedSearchText(safeSearchParts(in: receipt).joined(separator: " "))
        return tokens.allSatisfy { searchableText.contains($0) }
    }

    private func toolNames(in receipt: ExecutionReceipt) -> Set<String> {
        Set(([receipt.primaryToolName].compactMap { $0 } + receipt.actions.map(\.toolName))
            .map(Self.normalizedIdentifier)
            .filter { !$0.isEmpty })
    }

    private func safeSearchParts(in receipt: ExecutionReceipt) -> [String] {
        // Search deliberately uses the redacted audit row vocabulary instead of
        // prompt/action inputs so querying cannot become a side channel for secrets.
        var parts = [
            receipt.status.rawValue,
            receipt.outputSummary,
            receipt.usage.state.rawValue
        ]
        if let primaryToolName = receipt.primaryToolName {
            parts.append(primaryToolName)
        }
        if let model = receipt.model {
            parts.append(model.provider)
            parts.append(model.name)
        }
        parts.append(contentsOf: receipt.references.map { $0.kind.rawValue })
        parts.append(contentsOf: receipt.sourceLinks.map { $0.kind.rawValue })
        parts.append(contentsOf: receipt.visibleSurfaces.map(\.rawValue))
        parts.append(contentsOf: receipt.actions.map(\.toolName))
        parts.append(contentsOf: receipt.actions.map { $0.status.rawValue })
        return parts
    }

    private static func searchTokens(in query: String) -> [String] {
        executionReceiptSearchTokens(in: query)
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        executionReceiptNormalizedSearchText(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func normalizedSearchText(_ value: String) -> String {
        executionReceiptNormalizedSearchText(value)
    }

    fileprivate func matches(_ entry: ExecutionReceiptIndexEntry) -> Bool {
        if !statuses.isEmpty && !statuses.contains(entry.status) {
            return false
        }
        if let visibleSurface, !entry.visibleSurfaces.contains(visibleSurface) {
            return false
        }
        if !toolNames.isEmpty && toolNames.isDisjoint(with: entry.toolNames) {
            return false
        }
        if !referenceKinds.isEmpty && referenceKinds.isDisjoint(with: Set(entry.referenceKinds)) {
            return false
        }

        let tokens = Self.searchTokens(in: query)
        guard !tokens.isEmpty else {
            return true
        }
        return tokens.allSatisfy { entry.searchableText.contains($0) }
    }
}

public final class VolatileExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ExecutionReceipt]

    public init(receipts: [ExecutionReceipt] = []) {
        self.storage = receipts
    }

    public var receipts: [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func save(_ receipt: ExecutionReceipt) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.append(receipt)
    }

    public func list(limit: Int = 100) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        return Array(storage.suffix(boundedLimit).reversed())
    }

    public func list(matching filter: ExecutionReceiptSearchFilter, limit: Int = 100) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        // Filter before limiting so an admin search can still find older
        // relevant receipts even when recent automation generated many rows.
        return Array(storage.reversed())
            .filter { filter.matches($0) }
            .prefix(boundedLimit)
            .map { $0 }
    }

    public func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int = 100
    ) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        // Scope before limiting so a busy global receipt stream cannot hide
        // older task/project evidence from the detail inspector.
        return Array(storage.reversed())
            .filter { receipt in
                receipt.visibleSurfaces.contains(visibleSurface)
                    && receipt.references.contains { reference in
                        reference.kind == referenceKind && reference.id == referenceID
                    }
            }
            .prefix(boundedLimit)
            .map { $0 }
    }
}

public final class FileExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
    private static let receiptIndexFileName = "execution-receipt-index.jsonl"
    private let directoryURL: URL
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let receiptDecodeObserver: ((URL) -> Void)?
    private let lock = NSLock()
    private var indexEntriesByID: [String: ExecutionReceiptIndexEntry]
    private var orderedIndexEntries: [ExecutionReceiptIndexEntry]
    private var loadedIndexSnapshot: ExecutionReceiptIndexFileSnapshot?
    private var loadedReceiptDirectorySnapshot: ExecutionReceiptDirectorySnapshot?

    public convenience init(directoryURL: URL) throws {
        try self.init(directoryURL: directoryURL, receiptDecodeObserver: nil)
    }

    init(directoryURL: URL, receiptDecodeObserver: ((URL) -> Void)? = nil) throws {
        self.directoryURL = directoryURL
        self.indexURL = directoryURL.appendingPathComponent(Self.receiptIndexFileName)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.receiptDecodeObserver = receiptDecodeObserver
        self.indexEntriesByID = [:]
        self.orderedIndexEntries = []
        self.loadedIndexSnapshot = nil
        self.loadedReceiptDirectorySnapshot = nil
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try loadOrRepairIndex()
    }

    public func save(_ receipt: ExecutionReceipt) throws {
        lock.lock()
        defer { lock.unlock() }
        try refreshIndexIfNeeded()
        let data = try encoder.encode(receipt)
        let destinationURL = fileURL(for: receipt.id)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw ExecutionReceiptStoreError.duplicateReceiptID(receipt.id)
        }
        try data.write(to: destinationURL, options: [.atomic])
        let entry = ExecutionReceiptIndexEntry(
            receipt: receipt,
            receiptPath: destinationURL.lastPathComponent,
            digest: ExecutionReceiptDigest.sha256(data)
        )
        upsertIndexEntry(entry)
        do {
            try appendIndexEntry(entry)
            updateLoadedFileSystemSnapshots()
        } catch {
            // The receipt JSON is the durable evidence. The index is a repairable
            // cache, so rebuild it if an incremental append fails.
            try rebuildIndexFromReceiptDirectory()
        }
    }

    public func list(limit: Int = 100) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        try refreshIndexIfNeeded()
        return try loadedReceipts(from: orderedIndexEntries, limit: boundedLimit)
    }

    public func list(matching filter: ExecutionReceiptSearchFilter, limit: Int = 100) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        try refreshIndexIfNeeded()
        return try loadedReceipts(
            from: orderedIndexEntries.filter { filter.matches($0) },
            limit: boundedLimit
        )
    }

    public func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int = 100
    ) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        try refreshIndexIfNeeded()
        let matchingEntries = orderedIndexEntries.filter { entry in
            entry.visibleSurfaces.contains(visibleSurface)
                && entry.references.contains { reference in
                    reference.kind == referenceKind && reference.id == referenceID
                }
        }
        return try loadedReceipts(from: matchingEntries, limit: boundedLimit)
    }

    private func loadOrRepairIndex() throws {
        if let loadedEntries = try loadIndexEntriesFromManifest() {
            let receiptURLs = try receiptURLsInDirectory()
            if indexIsMissingReceiptFiles(loadedEntries, receiptURLs: receiptURLs) {
                try rebuildIndexFromReceiptDirectory()
                return
            }
            indexEntriesByID = Dictionary(uniqueKeysWithValues: loadedEntries.map { ($0.id, $0) })
            orderedIndexEntries = sortIndexEntries(Array(indexEntriesByID.values))
            updateLoadedFileSystemSnapshots()
            return
        }
        try rebuildIndexFromReceiptDirectory()
    }

    private func refreshIndexIfNeeded() throws {
        let currentIndexSnapshot = currentIndexFileSnapshot()
        let currentDirectorySnapshot = currentReceiptDirectorySnapshot()
        guard currentIndexSnapshot != loadedIndexSnapshot
            || currentDirectorySnapshot != loadedReceiptDirectorySnapshot else {
            return
        }
        // Multiple runtime surfaces can hold their own receipt store instance.
        // Refreshing on lightweight filesystem snapshots preserves cross-store
        // visibility without returning to a full JSON directory scan per query.
        try loadOrRepairIndex()
    }

    private func indexIsMissingReceiptFiles(
        _ entries: [ExecutionReceiptIndexEntry],
        receiptURLs: [URL]
    ) -> Bool {
        let indexedPaths = Set(entries.map(\.receiptPath))
        let indexedFileNames = Set(entries.map { URL(fileURLWithPath: $0.receiptPath).lastPathComponent })
        return receiptURLs.contains { url in
            let path = url.path
            let fileName = url.lastPathComponent
            return !indexedPaths.contains(path) && !indexedFileNames.contains(fileName)
        }
    }

    private func loadIndexEntriesFromManifest() throws -> [ExecutionReceiptIndexEntry]? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: indexURL)
        guard !data.isEmpty else {
            return []
        }

        let contents = String(decoding: data, as: UTF8.self)
        var entriesByID: [String: ExecutionReceiptIndexEntry] = [:]
        var didEncounterInvalidLine = false

        for line in contents.split(whereSeparator: \.isNewline) {
            guard !line.isEmpty else {
                continue
            }
            do {
                let entry = try JSONDecoder.executionReceiptIndexDecoder.decode(
                    ExecutionReceiptIndexEntry.self,
                    from: Data(line.utf8)
                )
                entriesByID[entry.id] = entry
            } catch {
                didEncounterInvalidLine = true
            }
        }

        if didEncounterInvalidLine {
            return nil
        }
        return sortIndexEntries(Array(entriesByID.values))
    }

    private func rebuildIndexFromReceiptDirectory() throws {
        let receiptURLs = try receiptURLsInDirectory()
        var entriesByID: [String: ExecutionReceiptIndexEntry] = [:]
        entriesByID.reserveCapacity(receiptURLs.count)

        for url in receiptURLs {
            guard let loaded = try loadReceiptAndData(from: url) else {
                continue
            }
            let entry = ExecutionReceiptIndexEntry(
                receipt: loaded.receipt,
                receiptPath: url.lastPathComponent,
                digest: ExecutionReceiptDigest.sha256(loaded.data)
            )
            entriesByID[entry.id] = entry
        }

        indexEntriesByID = entriesByID
        orderedIndexEntries = sortIndexEntries(Array(entriesByID.values))
        try writeIndexManifest(orderedIndexEntries)
        updateLoadedFileSystemSnapshots()
    }

    private func appendIndexEntry(_ entry: ExecutionReceiptIndexEntry) throws {
        let data = try JSONEncoder.executionReceiptIndexEncoder.encode(entry)
        try appendLine(data)
    }

    private func writeIndexManifest(_ entries: [ExecutionReceiptIndexEntry]) throws {
        var data = Data()
        for entry in entries {
            let encoded = try JSONEncoder.executionReceiptIndexEncoder.encode(entry)
            data.append(encoded)
            data.append(0x0A)
        }
        try data.write(to: indexURL, options: [.atomic])
    }

    private func appendLine(_ data: Data) throws {
        let line = data + Data([0x0A])
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let handle = try FileHandle(forWritingTo: indexURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: indexURL, options: [.atomic])
        }
    }

    private func loadedReceipts(from entries: [ExecutionReceiptIndexEntry], limit: Int) throws -> [ExecutionReceipt] {
        var receipts: [ExecutionReceipt] = []
        receipts.reserveCapacity(limit)

        for entry in entries {
            guard let receipt = try loadReceipt(from: entry) else {
                continue
            }
            receipts.append(receipt)
            if receipts.count >= limit {
                break
            }
        }

        return receipts
    }

    private func loadReceipt(from entry: ExecutionReceiptIndexEntry) throws -> ExecutionReceipt? {
        try loadReceipt(from: receiptURL(for: entry), expectedDigest: entry.digest)
    }

    private func loadReceipt(from url: URL) throws -> ExecutionReceipt? {
        try loadReceipt(from: url, expectedDigest: nil)
    }

    private func loadReceipt(from url: URL, expectedDigest: String?) throws -> ExecutionReceipt? {
        guard let loaded = try loadReceiptAndData(from: url, expectedDigest: expectedDigest) else {
            return nil
        }
        return loaded.receipt
    }

    private func loadReceiptAndData(
        from url: URL,
        expectedDigest: String? = nil
    ) throws -> (receipt: ExecutionReceipt, data: Data)? {
        do {
            let data = try Data(contentsOf: url)
            if let expectedDigest, expectedDigest != ExecutionReceiptDigest.sha256(data) {
                return nil
            }
            receiptDecodeObserver?(url)
            return (try decoder.decode(ExecutionReceipt.self, from: data), data)
        } catch {
            return nil
        }
    }

    private func receiptURLsInDirectory() throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.filter { $0.pathExtension == "json" }
    }

    private func upsertIndexEntry(_ entry: ExecutionReceiptIndexEntry) {
        indexEntriesByID[entry.id] = entry
        orderedIndexEntries = sortIndexEntries(Array(indexEntriesByID.values))
    }

    private func sortIndexEntries(_ entries: [ExecutionReceiptIndexEntry]) -> [ExecutionReceiptIndexEntry] {
        entries.sorted { lhs, rhs in
            if lhs.occurrenceDate != rhs.occurrenceDate {
                return lhs.occurrenceDate > rhs.occurrenceDate
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id > rhs.id
        }
    }

    private func receiptURL(for entry: ExecutionReceiptIndexEntry) -> URL {
        // The index is a repairable cache, so do not trust cached paths to read
        // outside the receipt directory if a stale or hand-edited manifest exists.
        let fileName = URL(fileURLWithPath: entry.receiptPath).lastPathComponent
        return directoryURL.appendingPathComponent(fileName)
    }

    private func updateLoadedFileSystemSnapshots() {
        loadedIndexSnapshot = currentIndexFileSnapshot()
        loadedReceiptDirectorySnapshot = currentReceiptDirectorySnapshot()
    }

    private func currentIndexFileSnapshot() -> ExecutionReceiptIndexFileSnapshot? {
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: indexURL.path) else {
            return nil
        }
        return ExecutionReceiptIndexFileSnapshot(
            modificationDate: attributes[.modificationDate] as? Date,
            byteCount: (attributes[.size] as? NSNumber)?.intValue
        )
    }

    private func currentReceiptDirectorySnapshot() -> ExecutionReceiptDirectorySnapshot {
        let values = try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey])
        return ExecutionReceiptDirectorySnapshot(modificationDate: values?.contentModificationDate)
    }

    private func fileURL(for id: String) -> URL {
        let safeName = id
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
            }
            .reduce(into: "") { $0.append($1) }
        return directoryURL.appendingPathComponent("\(safeName).json")
    }
}

private extension JSONEncoder {
    static var executionReceiptIndexEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var executionReceiptIndexDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct ExecutionReceiptRedactionPolicy: Equatable, Sendable {
    public var allowedLocalPathPrefixes: [String]

    public init(allowedLocalPathPrefixes: [String] = []) {
        self.allowedLocalPathPrefixes = allowedLocalPathPrefixes.map(Self.canonicalPath)
    }

    fileprivate static func canonicalPath(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }
        if let url = URL(string: trimmed), url.isFileURL {
            trimmed = url.path
        } else if trimmed == "~" || trimmed.hasPrefix("~/") {
            trimmed = NSString(string: trimmed).expandingTildeInPath
        }
        var path = URL(fileURLWithPath: trimmed).standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

public struct ExecutionReceiptRedactor: Sendable {
    private static let unquotedProseBoundaryWords: Set<String> = [
        "after",
        "before",
        "then",
        "and",
        "or",
        "but"
    ]

    private let secretRedactor: DeveloperSecretRedactor
    private let policy: ExecutionReceiptRedactionPolicy

    public init(
        secretRedactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        policy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) {
        self.secretRedactor = secretRedactor
        self.policy = policy
    }

    public func redact(_ value: String, maxLength: Int = 1_200) -> String {
        let secretRedacted = secretRedactor.redact(value).text
        return redactDisallowedLocalPaths(
            in: secretRedacted,
            preserveTrailingProse: false
        )
        .receiptPreview(maxLength: maxLength)
    }

    /// Redacts the same secret and local-path classes without rewriting layout.
    /// Provider context can contain Markdown or code where whitespace carries
    /// meaning, so its separate aggregate budget owns any later truncation.
    public func redactPreservingWhitespace(_ value: String) -> String {
        let secretRedacted = secretRedactor.redact(value).text
        return redactDisallowedLocalPaths(
            in: secretRedacted,
            preserveTrailingProse: true
        )
    }

    private func redactDisallowedLocalPaths(
        in value: String,
        preserveTrailingProse: Bool
    ) -> String {
        guard !value.isEmpty else {
            return value
        }

        let ranges = localPathRanges(
            in: value,
            preserveTrailingProse: preserveTrailingProse
        )
        guard !ranges.isEmpty else {
            return value
        }

        var result = value
        for range in ranges.reversed() {
            let path = String(result[range])
            // Project-scoped automation may display paths inside the user-approved
            // project root, but unrelated local paths are private machine context.
            guard !isAllowedLocalPath(path) else {
                continue
            }
            result.replaceSubrange(range, with: "[REDACTED_LOCAL_PATH]")
        }
        return result
    }

    private func isAllowedLocalPath(_ path: String) -> Bool {
        let canonicalPath = ExecutionReceiptRedactionPolicy.canonicalPath(path)
        return policy.allowedLocalPathPrefixes.contains { prefix in
            canonicalPath == prefix || canonicalPath.hasPrefix("\(prefix)/")
        }
    }

    private func localPathRanges(
        in value: String,
        preserveTrailingProse: Bool
    ) -> [Range<String.Index>] {
        let starts = localPathStartIndexes(in: value)
        guard !starts.isEmpty else {
            return []
        }

        return starts.enumerated().compactMap { index, start in
            let searchEnd = index + 1 < starts.count
                ? starts[index + 1]
                : value.endIndex
            var end = firstLocalPathTerminator(in: value, from: start, upperBound: searchEnd) ?? searchEnd
            let candidate = value[start..<end]
            if let extensionEnd = pathExtensionEnd(in: candidate) {
                // A recognized extension lets us safely retain spaces that are
                // part of a path while preserving any prose that follows it.
                end = extensionEnd
            } else if preserveTrailingProse,
                      let proseBoundary = unquotedProseBoundary(in: candidate) {
                // Only a small set of explicit connective words is accepted as
                // prose evidence. Ambiguous whitespace otherwise fails closed,
                // because exposing a path suffix is worse than over-redaction.
                end = proseBoundary
            }
            return start < end ? start..<end : nil
        }
    }

    private func unquotedProseBoundary(in candidate: Substring) -> String.Index? {
        var searchStart = candidate.startIndex

        while let whitespaceStart = candidate[searchStart...].firstIndex(where: \.isWhitespace) {
            var wordStart = whitespaceStart
            while wordStart < candidate.endIndex, candidate[wordStart].isWhitespace {
                wordStart = candidate.index(after: wordStart)
            }
            guard wordStart < candidate.endIndex else {
                return nil
            }

            var wordEnd = wordStart
            while wordEnd < candidate.endIndex, candidate[wordEnd].isLetter {
                wordEnd = candidate.index(after: wordEnd)
            }
            let word = candidate[wordStart..<wordEnd].lowercased()
            if Self.unquotedProseBoundaryWords.contains(word) {
                return whitespaceStart
            }
            searchStart = wordEnd > wordStart
                ? wordEnd
                : candidate.index(after: wordStart)
        }

        return nil
    }

    private func localPathStartIndexes(in value: String) -> [String.Index] {
        var indexes: [String.Index] = []
        var searchStart = value.startIndex
        let prefixes = [
            "file:///Users/",
            "file:///Volumes/",
            "file:///private/",
            "file:///tmp/",
            "file:///var/",
            "~/",
            "/Users/",
            "/Volumes/",
            "/private/",
            "/tmp/",
            "/var/"
        ]

        while searchStart < value.endIndex {
            let matches = prefixes.compactMap { prefix -> String.Index? in
                value.range(of: prefix, range: searchStart..<value.endIndex)?.lowerBound
            }
            guard let next = matches.min() else {
                break
            }
            indexes.append(next)
            searchStart = value.index(after: next)
        }

        return indexes
    }

    private func firstLocalPathTerminator(
        in value: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> String.Index? {
        var index = start
        // Backticks delimit Markdown code spans. Treating them as path content
        // would redact unrelated prose after an extensionless path.
        let terminators = CharacterSet(charactersIn: "\n\r,;\")'`")
        while index < upperBound {
            let scalar = value[index].unicodeScalars.first
            if let scalar, terminators.contains(scalar) {
                return index
            }
            index = value.index(after: index)
        }
        return nil
    }

    private func pathExtensionEnd(in candidate: Substring) -> String.Index? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\.(?:md|markdown|txt|json|yaml|yml|swift|pdf|docx?|xlsx?|pptx?|html|htm|csv|sqlite|db|log|png|jpe?g|heic)(?=$|[\s,;:)\]"'])"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let text = String(candidate)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let textRange = Range(match.range, in: text) else {
            return nil
        }
        let offset = text.distance(from: text.startIndex, to: textRange.upperBound)
        return candidate.index(candidate.startIndex, offsetBy: offset)
    }
}

public struct ScheduleDraftApplyWriteCandidate: Equatable, Sendable {
    public var taskID: Int64
    public var projectID: Int64
    public var taskTitle: String
    public var startAt: String
    public var endAt: String

    public init(taskID: Int64, projectID: Int64, taskTitle: String, startAt: String, endAt: String) {
        self.taskID = taskID
        self.projectID = projectID
        self.taskTitle = taskTitle
        self.startAt = startAt
        self.endAt = endAt
    }

    public init?(block: TodayTimeBlock) {
        guard let startAt = block.startAt, let endAt = block.endAt else {
            return nil
        }
        self.init(
            taskID: block.task.id,
            projectID: block.task.projectID,
            taskTitle: block.task.title,
            startAt: startAt,
            endAt: endAt
        )
    }
}

public struct ScheduleDraftApplyCreatedEvent: Equatable, Sendable {
    public var candidate: ScheduleDraftApplyWriteCandidate
    public var calendarEventID: String
    public var calendarEventTitle: String

    public init(
        candidate: ScheduleDraftApplyWriteCandidate,
        calendarEventID: String,
        calendarEventTitle: String
    ) {
        self.candidate = candidate
        self.calendarEventID = calendarEventID
        self.calendarEventTitle = calendarEventTitle
    }

    public init(candidate: ScheduleDraftApplyWriteCandidate, record: CalendarEventRecord) {
        self.init(
            candidate: candidate,
            calendarEventID: record.id,
            calendarEventTitle: record.draft.title
        )
    }
}

public enum ExecutionReceiptFactory {
    public static func makeReviewReceipt(
        session: ReviewSession,
        runID: String,
        model: ExecutionReceiptModel?,
        usage: ExecutionReceiptUsage,
        startedAt: Date?,
        finishedAt: Date?,
        sourceLinks: [ExecutionReceiptSourceLink] = [],
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) -> ExecutionReceipt {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        let actions = session.items.map { actionSummary(for: $0, redactor: redactor) }
        let sanitizedSourceLinks = sourceLinks.map { link in
            ExecutionReceiptSourceLink(
                kind: link.kind,
                title: redactor.redact(link.title, maxLength: 240),
                url: redactor.redact(link.url, maxLength: 600)
            )
        }
        let references = references(for: session)

        // Receipts are user-facing accountability records, so they carry a
        // compact redacted view instead of raw prompts or document bodies.
        return ExecutionReceipt(
            id: "receipt:\(runID):\(session.id)",
            runID: runID,
            approvalID: session.approvalToken?.approvalID.uuidString,
            approvalEvidence: session.approvalToken.map(ExecutionReceiptApprovalEvidence.init),
            resolvedActionEvidence: session.resolvedActionEvidence,
            createdAt: finishedAt ?? startedAt ?? Date(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: executionReceiptStatus(for: session.executionStatus),
            inputPreview: redactor.redact("\(session.originalPlan.userInput)\n\(session.originalPlan.summary)"),
            outputSummary: redactor.redact(outcomeSummary(for: actions)),
            model: model,
            primaryToolName: actions.first?.toolName,
            usage: usage,
            references: references,
            sourceLinks: sanitizedSourceLinks,
            actions: actions,
            visibleSurfaces: reviewVisibleSurfaces(for: references),
            redactionPolicy: redactionPolicy
        )
    }

    public static func makeApprovedAutomationReceipt(
        _ receipt: ApprovedAutomationExecutionReceipt,
        runID: String,
        approvalID: String?,
        status: ExecutionReceiptStatus = .succeeded,
        createdAt: Date = Date(),
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) -> ExecutionReceipt {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        let redactedTitle = redactor.redact(receipt.redactedTaskTitle, maxLength: 300)
        let redactedDetail = redactor.redact(receipt.redactedTaskDetail)
        let redactedReviewReason = redactor.redact(receipt.reviewReason)
        let inputPreview = [
            "title: \(redactedTitle)",
            "detail: \(redactedDetail)",
            "statusBefore: \(receipt.statusBefore.rawValue)",
            "statusAfter: \(receipt.statusAfter.rawValue)",
            "priority: \(receipt.priority.rawValue)",
            "dueAt: \(receipt.dueAt ?? "none")",
            "reviewReason: \(redactedReviewReason)"
        ].joined(separator: ", ")
        let outputSummary = approvedAutomationOutputSummary(
            status: status,
            taskID: receipt.taskID,
            statusBefore: receipt.statusBefore,
            statusAfter: receipt.statusAfter
        )
        let finishedAt: Date? = (status == .running || status == .notStarted) ? nil : createdAt

        return ExecutionReceipt(
            id: "receipt:\(runID):approved-automation:\(receipt.taskID)",
            runID: runID,
            approvalID: approvalID,
            createdAt: createdAt,
            startedAt: createdAt,
            finishedAt: finishedAt,
            status: status,
            inputPreview: inputPreview,
            outputSummary: outputSummary,
            primaryToolName: ActionTool.taskUpdate.rawValue,
            usage: .unavailable,
            references: [
                ExecutionReceiptReference(kind: .task, id: String(receipt.taskID), label: redactedTitle),
                ExecutionReceiptReference(kind: .project, id: String(receipt.projectID))
            ],
            actions: [
                ExecutionReceiptActionSummary(
                    id: "approved-automation:\(receipt.taskID)",
                    toolName: ActionTool.taskUpdate.rawValue,
                    status: status,
                    inputPreview: inputPreview,
                    outputSummary: outputSummary
                )
            ],
            visibleSurfaces: [.doneList, .taskDetail, .projectDetail, .auditLog],
            redactionPolicy: redactionPolicy
        )
    }

    public static func makeScheduleDraftApplyReceipt(
        writeCandidates: [ScheduleDraftApplyWriteCandidate],
        unscheduledTaskCount: Int,
        createdEvents: [ScheduleDraftApplyCreatedEvent],
        projectTitlesByID: [Int64: String] = [:],
        runID: String,
        approvalID: String? = nil,
        status: ExecutionReceiptStatus,
        errorSummary: String? = nil,
        createdAt: Date = Date(),
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) -> ExecutionReceipt {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        // The approval token comes from a SecureField, so the receipt proves the
        // reviewed write outcome using a separate non-secret approval ID.
        let inputPreview = [
            "calendarWriteCandidates: \(writeCandidates.count)",
            "unscheduledTasks: \(unscheduledTaskCount)"
        ].joined(separator: ", ")
        let outputSummary = scheduleDraftApplyOutputSummary(
            status: status,
            createdEventCount: createdEvents.count
        )
        let references = scheduleDraftApplyReferences(
            writeCandidates: writeCandidates,
            createdEvents: createdEvents,
            projectTitlesByID: projectTitlesByID,
            redactor: redactor
        )
        var actions = createdEvents.map { event in
            ExecutionReceiptActionSummary(
                id: "calendar-event:\(event.calendarEventID)",
                toolName: ActionTool.calendarCreateWorkBlock.rawValue,
                status: .succeeded,
                inputPreview: redactor.redact(scheduleDraftApplyActionInput(for: event.candidate)),
                outputSummary: redactor.redact("Created Calendar event \(event.calendarEventID).")
            )
        }
        if status == .failed || actions.isEmpty {
            actions.append(ExecutionReceiptActionSummary(
                id: "schedule-draft-apply",
                toolName: ActionTool.calendarCreateWorkBlock.rawValue,
                status: status,
                inputPreview: inputPreview,
                outputSummary: status == .failed ? nil : outputSummary,
                errorSummary: errorSummary.map { redactor.redact($0) }
            ))
        }

        return ExecutionReceipt(
            id: "receipt:\(runID):schedule-draft-apply",
            runID: runID,
            approvalID: approvalID,
            createdAt: createdAt,
            startedAt: createdAt,
            finishedAt: (status == .running || status == .notStarted) ? nil : createdAt,
            status: status,
            inputPreview: inputPreview,
            outputSummary: outputSummary,
            primaryToolName: ActionTool.calendarCreateWorkBlock.rawValue,
            usage: .unavailable,
            references: references,
            actions: actions,
            visibleSurfaces: [.taskDetail, .projectDetail, .auditLog],
            redactionPolicy: redactionPolicy
        )
    }

    public static func makeDocumentDeliverableReceipt(
        deliverables: [TaskAutomationDocumentDeliverableReview],
        selectedTasks: [ProjectBoardTask],
        runID: String,
        approvalID: String? = nil,
        status: ExecutionReceiptStatus = .succeeded,
        errorSummary: String? = nil,
        createdAt: Date = Date(),
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) -> ExecutionReceipt {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        let references = documentDeliverableReferences(
            deliverables: deliverables,
            selectedTasks: selectedTasks,
            redactor: redactor
        )
        let sourceLinks = documentDeliverableSourceLinks(deliverables: deliverables, redactor: redactor)
        let inputPreview = documentDeliverableInputPreview(
            deliverables: deliverables,
            selectedTasks: selectedTasks
        )
        let outputSummary = documentDeliverableOutputSummary(status: status, deliverableCount: deliverables.count)
        let actions = documentDeliverableActions(
            deliverables: deliverables,
            status: status,
            errorSummary: errorSummary,
            redactor: redactor
        )

        // Document deliverable planning produces review evidence, not files.
        // Keeping a separate tool name prevents audit surfaces from implying
        // filesystem write permission was granted before explicit approval.
        return ExecutionReceipt(
            id: "receipt:\(runID):document-deliverables",
            runID: runID,
            approvalID: approvalID,
            createdAt: createdAt,
            startedAt: createdAt,
            finishedAt: (status == .running || status == .notStarted) ? nil : createdAt,
            status: status,
            inputPreview: inputPreview,
            outputSummary: outputSummary,
            primaryToolName: documentDeliverablePrepareToolName,
            usage: .unavailable,
            references: references,
            sourceLinks: sourceLinks,
            actions: actions,
            visibleSurfaces: documentDeliverableVisibleSurfaces(selectedTasks: selectedTasks),
            redactionPolicy: redactionPolicy
        )
    }

    public static func makeAssistantQueueReceipt(
        item: AssistantQueueItem,
        session: ReviewSession,
        runID: String,
        model: ExecutionReceiptModel? = nil,
        usage: ExecutionReceiptUsage = .unknown,
        startedAt: Date?,
        finishedAt: Date?,
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) -> ExecutionReceipt {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        let inputPreview = [
            item.sourceTranscript,
            item.interpretationSummary,
            item.reviewReason,
            item.redactedSummary,
            session.originalPlan.userInput,
            session.originalPlan.summary
        ].compactMap { $0 }.joined(separator: "\n")
        let actions = session.items.map { actionSummary(for: $0, redactor: redactor) }
        let queueReference = ExecutionReceiptReference(
            kind: .assistantQueue,
            id: item.id,
            label: redactor.redact(item.redactedSummary, maxLength: 300)
        )
        let references = [queueReference] + references(for: session)

        return ExecutionReceipt(
            id: "receipt:\(runID):\(item.id):\(session.id)",
            runID: runID,
            approvalID: session.approvalToken?.approvalID.uuidString,
            assistantQueueItemID: item.id,
            queueApproval: item.approval.map { approval in
                ExecutionReceiptQueueApproval(
                    approvalID: approval.approvalID,
                    reviewerID: approval.reviewerID,
                    note: approval.note,
                    reviewedContentFingerprint: approval.reviewedContentFingerprint
                )
            },
            approvalEvidence: session.approvalToken.map(ExecutionReceiptApprovalEvidence.init),
            resolvedActionEvidence: session.resolvedActionEvidence,
            createdAt: finishedAt ?? startedAt ?? Date(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: executionReceiptStatus(for: session.executionStatus),
            inputPreview: redactor.redact(inputPreview),
            outputSummary: redactor.redact(assistantQueueOutputSummary(
                base: outcomeSummary(for: actions),
                costPreview: item.costPreview
            )),
            model: model,
            primaryToolName: actions.first?.toolName,
            usage: usage,
            references: references,
            actions: actions,
            visibleSurfaces: assistantQueueVisibleSurfaces(for: references),
            redactionPolicy: redactionPolicy
        )
    }

    public static func makeAssistantQueueReceipt(
        item: AssistantQueueItem,
        runID: String,
        executionApprovalID: String?,
        status: ExecutionReceiptStatus,
        outputSummary: String,
        model: ExecutionReceiptModel? = nil,
        usage: ExecutionReceiptUsage = .unknown,
        createdAt: Date = Date(),
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) -> ExecutionReceipt {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        let inputPreview = [
            item.sourceTranscript,
            item.interpretationSummary,
            item.reviewReason,
            item.redactedSummary
        ].compactMap { $0 }.joined(separator: "\n")

        return ExecutionReceipt(
            id: "receipt:\(runID):\(item.id)",
            runID: runID,
            approvalID: executionApprovalID,
            assistantQueueItemID: item.id,
            queueApproval: item.approval.map { approval in
                ExecutionReceiptQueueApproval(
                    approvalID: approval.approvalID,
                    reviewerID: approval.reviewerID,
                    note: approval.note,
                    reviewedContentFingerprint: approval.reviewedContentFingerprint
                )
            },
            createdAt: createdAt,
            startedAt: createdAt,
            finishedAt: createdAt,
            status: status,
            inputPreview: redactor.redact(inputPreview),
            outputSummary: redactor.redact(assistantQueueOutputSummary(
                base: outputSummary,
                costPreview: item.costPreview
            )),
            model: model,
            usage: usage,
            references: [
                ExecutionReceiptReference(kind: .assistantQueue, id: item.id, label: redactor.redact(item.redactedSummary, maxLength: 300))
            ],
            redactionPolicy: redactionPolicy
        )
    }

    public static func makeExternalMCPReceipt(
        serverID: String,
        serverName: String,
        toolName: String,
        permissionLevel: ExternalMCPToolPermission,
        redactedArgumentSummary: String,
        approvalID: String?,
        source: ToolExecutionSource,
        result: MCPToolCallResult?,
        error: Error?,
        runID: String,
        startedAt: Date,
        finishedAt: Date,
        redactionPolicy: ExecutionReceiptRedactionPolicy = ExecutionReceiptRedactionPolicy()
    ) -> ExecutionReceipt {
        let redactor = ExecutionReceiptRedactor(policy: redactionPolicy)
        let primaryToolName = externalMCPToolName(toolName)
        let status = externalMCPStatus(result: result, error: error)
        let inputPreview = [
            "server: \(serverName)",
            "tool: \(toolName)",
            "permission: \(permissionLevel.rawValueForAudit)",
            "source: \(source.rawValue)",
            "approval: \(approvalID == nil ? "missing" : "present")",
            "arguments: \(redactedArgumentSummary)"
        ].joined(separator: ", ")
        let outputSummary = externalMCPOutputSummary(
            serverName: serverName,
            toolName: toolName,
            result: result,
            error: error
        )
        let actionErrorSummary = externalMCPActionErrorSummary(result: result, error: error, redactor: redactor)
        // Server IDs are user-configured and can accidentally include local
        // paths or customer names, so durable receipt identifiers use a digest.
        let externalMCPDigest = ExecutionReceiptDigest.normalizedDigest("\(serverID):\(toolName)")

        return ExecutionReceipt(
            id: "receipt:\(runID):external-mcp:\(externalMCPDigest)",
            runID: runID,
            approvalID: approvalID,
            createdAt: finishedAt,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: status,
            inputPreview: inputPreview,
            outputSummary: outputSummary,
            primaryToolName: primaryToolName,
            usage: .unavailable,
            references: [
                ExecutionReceiptReference(
                    kind: .externalMCP,
                    id: externalMCPDigest,
                    label: redactor.redact("\(serverName) / \(toolName)", maxLength: 300)
                )
            ],
            actions: [
                ExecutionReceiptActionSummary(
                    id: "external-mcp:\(externalMCPDigest)",
                    toolName: primaryToolName,
                    status: status,
                    inputPreview: inputPreview,
                    outputSummary: outputSummary,
                    errorSummary: actionErrorSummary
                )
            ],
            visibleSurfaces: [.auditLog],
            redactionPolicy: redactionPolicy
        )
    }

    private static func executionReceiptStatus(for status: ReviewExecutionStatus) -> ExecutionReceiptStatus {
        switch status {
        case .notStarted:
            .notStarted
        case .executing:
            .running
        case .completed:
            .succeeded
        case .failed:
            .failed
        case .canceled:
            .canceled
        }
    }

    private static func executionReceiptStatus(for status: ReviewActionExecutionStatus) -> ExecutionReceiptStatus {
        switch status {
        case .pending:
            .notStarted
        case .executing:
            .running
        case .succeeded:
            .succeeded
        case .failed:
            .failed
        case .skipped:
            .skipped
        }
    }

    private static func outcomeSummary(for actions: [ExecutionReceiptActionSummary]) -> String {
        let succeeded = actions.filter { $0.status == .succeeded }.count
        let failed = actions.filter { $0.status == .failed }.count
        let skipped = actions.filter { $0.status == .skipped }.count
        if failed > 0 {
            return "\(failed) failed, \(succeeded) succeeded, \(skipped) skipped."
        }
        return "\(succeeded) succeeded, \(skipped) skipped."
    }

    private static func assistantQueueOutputSummary(
        base: String,
        costPreview: AssistantQueueCostPreview?
    ) -> String {
        guard let costPreview else {
            return base
        }
        switch costPreview.billingMode {
        case .userProviderBilled:
            return "\(base) provider-billed usage recorded; Suisui managed charge unavailable."
        case .localOnly:
            return "\(base) Local-only execution; Suisui managed charge unavailable."
        case .suisuiManaged:
            return base
        }
    }

    private static let documentDeliverablePrepareToolName = "document.deliverable.prepare"

    private static func externalMCPToolName(_ toolName: String) -> String {
        "external_mcp.\(toolName)"
    }

    private static func externalMCPStatus(
        result: MCPToolCallResult?,
        error: Error?
    ) -> ExecutionReceiptStatus {
        if error is CancellationError {
            return .canceled
        }
        if error != nil || result?.isError == true {
            return .failed
        }
        return .succeeded
    }

    private static func externalMCPOutputSummary(
        serverName: String,
        toolName: String,
        result: MCPToolCallResult?,
        error: Error?
    ) -> String {
        if error is CancellationError {
            return "External MCP tool \(toolName) was canceled on \(serverName)."
        }
        if error != nil {
            return "External MCP tool \(toolName) failed on \(serverName)."
        }
        guard let result else {
            return "External MCP tool \(toolName) did not return a result on \(serverName)."
        }
        let contentItemLabel = result.content.count == 1 ? "content item" : "content items"
        let structuredLabel = result.structuredContent == nil ? "" : " with structured output"
        // MCP servers can echo credentials, files, or customer data in results, so
        // receipts record result shape and outcome instead of raw response bodies.
        if result.isError {
            return "External MCP tool \(toolName) returned a tool error on \(serverName) with \(result.content.count) \(contentItemLabel)\(structuredLabel)."
        }
        return "External MCP tool \(toolName) succeeded on \(serverName) with \(result.content.count) \(contentItemLabel)\(structuredLabel)."
    }

    private static func externalMCPActionErrorSummary(
        result: MCPToolCallResult?,
        error: Error?,
        redactor: ExecutionReceiptRedactor
    ) -> String? {
        if let error {
            return redactor.redact(String(describing: error))
        }
        guard result?.isError == true else {
            return nil
        }
        return "MCP tool returned an error result. Raw tool output is omitted from the receipt."
    }

    private static func documentDeliverableInputPreview(
        deliverables: [TaskAutomationDocumentDeliverableReview],
        selectedTasks: [ProjectBoardTask]
    ) -> String {
        let sourceCount = documentDeliverableUniqueSources(deliverables).count
        let approvalRequired = deliverables.contains(where: \.requiresApproval)
        let taskPreview = selectedTasks.map { task in
            "task \(task.id): \(task.title), priority: \(task.priority.rawValue), dueAt: \(task.dueAt ?? "none")"
        }
        let draftPreview = deliverables.map { deliverable in
            [
                "draft \(deliverable.kind.rawValue)",
                "title: \(deliverable.title)",
                "suggestedPath: \(deliverable.suggestedPath)",
                "sources: \(deliverable.sourceDocuments.count)",
                "rationale: \(deliverable.rationale)",
                "requiresApproval: \(deliverable.requiresApproval)"
            ].joined(separator: ", ")
        }
        return ([
            "documentDeliverables: \(deliverables.count)",
            "selectedTasks: \(selectedTasks.count)",
            "sourceDocuments: \(sourceCount)",
            "approvalRequired: \(approvalRequired)",
            "noFilesWritten: true"
        ] + taskPreview + draftPreview).joined(separator: "\n")
    }

    private static func documentDeliverableOutputSummary(
        status: ExecutionReceiptStatus,
        deliverableCount: Int
    ) -> String {
        let draftLabel = deliverableCount == 1 ? "draft" : "drafts"
        switch status {
        case .succeeded:
            return "Prepared \(deliverableCount) approval-gated document deliverable \(draftLabel) for review. No files were written."
        case .failed:
            return "Document deliverable draft preparation failed before files were written."
        case .canceled:
            return "Document deliverable draft preparation was canceled before files were written."
        case .skipped:
            return "Document deliverable draft preparation was skipped. No files were written."
        case .running:
            return "Document deliverable draft preparation is running. No files have been written."
        case .notStarted:
            return "Document deliverable draft preparation has not started. No files have been written."
        }
    }

    private static func documentDeliverableActions(
        deliverables: [TaskAutomationDocumentDeliverableReview],
        status: ExecutionReceiptStatus,
        errorSummary: String?,
        redactor: ExecutionReceiptRedactor
    ) -> [ExecutionReceiptActionSummary] {
        guard !deliverables.isEmpty else {
            return [
                ExecutionReceiptActionSummary(
                    id: "document-deliverable:none",
                    toolName: documentDeliverablePrepareToolName,
                    status: status,
                    inputPreview: "documentDeliverables: 0",
                    outputSummary: documentDeliverableOutputSummary(status: status, deliverableCount: 0),
                    errorSummary: errorSummary.map { redactor.redact($0) }
                )
            ]
        }
        return deliverables.map { deliverable in
            let draftDigest = ExecutionReceiptDigest.normalizedDigest(deliverable.id)
            let inputPreview = [
                "kind: \(deliverable.kind.rawValue)",
                "title: \(deliverable.title)",
                "suggestedPath: \(deliverable.suggestedPath)",
                "sourceDocuments: \(deliverable.sourceDocuments.count)",
                "requiresApproval: \(deliverable.requiresApproval)"
            ].joined(separator: ", ")
            let outputSummary = documentDeliverableActionOutputSummary(
                status: status,
                kind: deliverable.kind
            )
            return ExecutionReceiptActionSummary(
                id: "document-deliverable:\(draftDigest)",
                toolName: documentDeliverablePrepareToolName,
                status: status,
                inputPreview: inputPreview,
                outputSummary: outputSummary,
                errorSummary: errorSummary.map { redactor.redact($0) }
            )
        }
    }

    private static func documentDeliverableActionOutputSummary(
        status: ExecutionReceiptStatus,
        kind: DocumentAutomationOutputKind
    ) -> String {
        switch status {
        case .succeeded:
            return "Prepared \(kind.rawValue) document deliverable draft for approval. No file was written."
        case .failed:
            return "\(kind.rawValue) document deliverable draft preparation failed before a file was written."
        case .canceled:
            return "\(kind.rawValue) document deliverable draft preparation was canceled before a file was written."
        case .skipped:
            return "\(kind.rawValue) document deliverable draft preparation was skipped. No file was written."
        case .running:
            return "\(kind.rawValue) document deliverable draft preparation is running. No file has been written."
        case .notStarted:
            return "\(kind.rawValue) document deliverable draft preparation has not started. No file has been written."
        }
    }

    private static func documentDeliverableReferences(
        deliverables: [TaskAutomationDocumentDeliverableReview],
        selectedTasks: [ProjectBoardTask],
        redactor: ExecutionReceiptRedactor
    ) -> [ExecutionReceiptReference] {
        var references: [ExecutionReceiptReference] = []
        for task in selectedTasks {
            appendReference(
                kind: .task,
                id: String(task.id),
                label: redactor.redact(task.title, maxLength: 300),
                references: &references
            )
        }
        for projectID in Set(selectedTasks.map(\.projectID)).sorted() {
            appendReference(kind: .project, id: String(projectID), references: &references)
        }
        for source in documentDeliverableUniqueSources(deliverables) {
            appendReference(
                kind: .document,
                id: "document-source:\(ExecutionReceiptDigest.normalizedDigest(source.id))",
                label: redactor.redact(source.title, maxLength: 300),
                references: &references
            )
        }
        for deliverable in deliverables {
            appendReference(
                kind: .file,
                id: deliverable.suggestedPath,
                label: redactor.redact(deliverable.title, maxLength: 300),
                references: &references
            )
        }
        return references
    }

    private static func documentDeliverableSourceLinks(
        deliverables: [TaskAutomationDocumentDeliverableReview],
        redactor: ExecutionReceiptRedactor
    ) -> [ExecutionReceiptSourceLink] {
        documentDeliverableUniqueSources(deliverables).map { source in
            ExecutionReceiptSourceLink(
                kind: .document,
                title: redactor.redact(source.title, maxLength: 240),
                url: "suisui://document-source/\(ExecutionReceiptDigest.normalizedDigest(source.id))"
            )
        }
    }

    private static func documentDeliverableUniqueSources(
        _ deliverables: [TaskAutomationDocumentDeliverableReview]
    ) -> [TaskAutomationDocumentSourceReview] {
        var seen = Set<String>()
        var sources: [TaskAutomationDocumentSourceReview] = []
        for source in deliverables.flatMap(\.sourceDocuments) {
            guard seen.insert(source.id).inserted else {
                continue
            }
            sources.append(source)
        }
        return sources
    }

    private static func documentDeliverableVisibleSurfaces(
        selectedTasks: [ProjectBoardTask]
    ) -> [ExecutionReceiptSurface] {
        var surfaces: [ExecutionReceiptSurface] = []
        if !selectedTasks.isEmpty {
            surfaces.append(.taskDetail)
        }
        if !Set(selectedTasks.map(\.projectID)).isEmpty {
            surfaces.append(.projectDetail)
        }
        surfaces.append(.auditLog)
        return surfaces
    }

    private static func assistantQueueVisibleSurfaces(
        for references: [ExecutionReceiptReference]
    ) -> [ExecutionReceiptSurface] {
        var surfaces: [ExecutionReceiptSurface] = [.assistantQueue]
        // Derive scoped visibility from receipt references so task/project
        // detail screens only show queue executions that have redacted proof of
        // touching that entity.
        if references.contains(where: { $0.kind == .task }) {
            surfaces.append(.taskDetail)
        }
        if references.contains(where: { $0.kind == .project }) {
            surfaces.append(.projectDetail)
        }
        if surfaces.count > 1 {
            surfaces.append(.auditLog)
        }
        return surfaces
    }

    private static func reviewVisibleSurfaces(
        for references: [ExecutionReceiptReference]
    ) -> [ExecutionReceiptSurface] {
        guard references.contains(where: { $0.kind == .developmentBranch }) else {
            return []
        }
        var surfaces: [ExecutionReceiptSurface] = []
        if references.contains(where: { $0.kind == .task }) {
            surfaces.append(.taskDetail)
        }
        if references.contains(where: { $0.kind == .project }) {
            surfaces.append(.projectDetail)
        }
        surfaces.append(.auditLog)
        return surfaces
    }

    private static func actionSummary(
        for item: ReviewActionItem,
        redactor: ExecutionReceiptRedactor
    ) -> ExecutionReceiptActionSummary {
        ExecutionReceiptActionSummary(
            id: item.id,
            toolName: item.editedAction.tool.rawValue,
            status: executionReceiptStatus(for: item.executionStatus),
            inputPreview: actionInputPreview(for: item, redactor: redactor),
            outputSummary: actionOutputSummary(for: item, redactor: redactor),
            errorSummary: item.errorMessage.map { redactor.redact($0) },
            failureRecovery: executionReceiptFailureRecovery(for: item.failureRecovery),
            externalSideEffectEvidence: externalSideEffectEvidence(for: item.result)
        )
    }

    private static func externalSideEffectEvidence(
        for result: ToolResult?
    ) -> ExecutionReceiptExternalSideEffectEvidence? {
        guard let result,
              let stateRaw = result.output["journalState"]?.receiptStringValue,
              let state = ExternalSideEffectState(rawValue: stateRaw) else {
            return nil
        }
        return ExecutionReceiptExternalSideEffectEvidence(
            idempotencyKeys: result.output["idempotencyKeys"]?.receiptIDValues
                ?? result.output["idempotencyKey"]?.receiptStringValue.map { [$0] }
                ?? [],
            externalResourceIDs: result.output["externalResourceIds"]?.receiptIDValues
                ?? result.output["externalResourceId"]?.receiptStringValue.map { [$0] }
                ?? [],
            journalRecordIDs: result.output["journalRecordIds"]?.receiptIDValues
                ?? result.output["journalRecordId"]?.receiptStringValue.map { [$0] }
                ?? [],
            journalState: state
        )
    }

    private static func actionInputPreview(
        for item: ReviewActionItem,
        redactor: ExecutionReceiptRedactor
    ) -> String {
        switch item.editedAction.tool {
        case .mailDraftCreateText:
            return redactor.redact(mailDraftActionInputPreview(arguments: item.editedAction.arguments))
        case .developmentRepositoryCreateFile, .developmentRepositoryUpdateFile:
            return redactor.redact(developmentRepositoryFileWriteInputPreview(arguments: item.editedAction.arguments))
        default:
            return redactor.redact(item.argumentDisplaySummary(maxFields: 12, maxValueLength: 300).fullText)
        }
    }

    private static func mailDraftActionInputPreview(arguments: [String: JSONValue]) -> String {
        let subject = arguments["subject"]?.receiptStringValue?.receiptPreview(maxLength: 300)
        let hasRecipient = arguments["to"]?.receiptStringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let subjectPreview = subject?.isEmpty == false ? subject ?? "none" : "none"
        return [
            "subject: \(subjectPreview)",
            "to: \(hasRecipient ? "[REDACTED_RECIPIENT]" : "none")",
            "body: [REDACTED_DRAFT_BODY]"
        ].joined(separator: ", ")
    }

    private static func developmentRepositoryFileWriteInputPreview(arguments: [String: JSONValue]) -> String {
        var parts: [String] = []
        if let projectID = arguments["projectId"]?.receiptIDValue {
            parts.append("projectId: \(projectID)")
        }
        if let relativePath = arguments["relativePath"]?.receiptStringValue?.receiptPreview(maxLength: 300) {
            parts.append("relativePath: \(relativePath)")
        }
        if let expectedSHA256 = arguments["expectedSHA256"]?.receiptStringValue?.receiptPreview(maxLength: 120) {
            parts.append("expectedSHA256: \(expectedSHA256)")
        }
        if let contents = arguments["contents"]?.receiptStringValue {
            parts.append("contentBytes: \(contents.utf8.count)")
        }
        // Repository writes can contain source code, customer content, or generated
        // documents. Receipts should prove what was targeted without persisting the
        // edited body; the resulting digest/artifact id is captured in tool output.
        parts.append("contents: [REDACTED_REPOSITORY_FILE_CONTENT]")
        return parts.joined(separator: ", ")
    }

    private static func actionOutputSummary(
        for item: ReviewActionItem,
        redactor: ExecutionReceiptRedactor
    ) -> String? {
        guard let result = item.result else {
            return nil
        }
        switch item.editedAction.tool {
        case .developmentPreparePullRequestWorkflow:
            return developmentPRWorkflowOutputSummary(for: result, redactor: redactor)
                ?? redactor.redact(result.summary)
        case .developmentPushBranch:
            return developmentPushOutputSummary(for: result, redactor: redactor)
                ?? redactor.redact(result.summary)
        case .developmentCreatePullRequest:
            return developmentPullRequestOutputSummary(for: result, redactor: redactor)
                ?? redactor.redact(result.summary)
        case .developmentReviewPullRequestGate:
            return developmentPullRequestGateOutputSummary(for: result, redactor: redactor)
                ?? redactor.redact(result.summary)
        case .developmentMergePullRequest:
            return developmentPullRequestMergeOutputSummary(for: result, redactor: redactor)
                ?? redactor.redact(result.summary)
        default:
            return redactor.redact(result.summary)
        }
    }

    private static func developmentPRWorkflowOutputSummary(
        for result: ToolResult,
        redactor: ExecutionReceiptRedactor
    ) -> String? {
        guard let branchName = result.output["branchName"]?.receiptIDValue else {
            return nil
        }
        var parts = [
            "Prepared development branch \(redactor.redact(branchName, maxLength: 240))."
        ]
        if result.output["requiresPushApproval"]?.receiptBoolValue == true {
            parts.append("Push approval required.")
        }
        if result.output["requiresPullRequestApproval"]?.receiptBoolValue == true {
            parts.append("Pull request approval required.")
        }
        // Git status/diff-stat can include local paths or file names, so the
        // receipt records their presence without copying the raw command output.
        if result.output["status"]?.receiptNonEmptyString == nil,
           result.output["diffStat"]?.receiptNonEmptyString == nil {
            parts.append("No git status or diff-stat evidence was returned.")
        } else {
            parts.append("Git evidence captured.")
        }
        return parts.joined(separator: " ")
    }

    private static func developmentPushOutputSummary(
        for result: ToolResult,
        redactor: ExecutionReceiptRedactor
    ) -> String? {
        guard let branchName = result.output["branchName"]?.receiptIDValue else {
            return nil
        }
        guard result.status == .succeeded else {
            return "Push did not run for development branch \(redactor.redact(branchName, maxLength: 240)). \(redactor.redact(result.summary))"
        }
        var parts = [
            "Pushed development branch \(redactor.redact(branchName, maxLength: 240))."
        ]
        if let remoteRepository = result.output["remoteRepository"]?.receiptNonEmptyString {
            parts.append("Remote repository \(redactor.redact(remoteRepository, maxLength: 240)).")
        }
        if result.output["requiresPullRequestApproval"]?.receiptBoolValue == true {
            parts.append("Pull request approval required.")
        }
        return parts.joined(separator: " ")
    }

    private static func developmentPullRequestOutputSummary(
        for result: ToolResult,
        redactor: ExecutionReceiptRedactor
    ) -> String? {
        guard let pullRequestURL = result.output["pullRequestURL"]?.receiptIDValue else {
            return nil
        }
        var parts = [
            "Created pull request \(redactor.redact(pullRequestURL, maxLength: 300))."
        ]
        if let branchName = result.output["branchName"]?.receiptIDValue {
            parts.append("Head \(redactor.redact(branchName, maxLength: 240)).")
        }
        if let baseBranch = result.output["baseBranch"]?.receiptIDValue {
            parts.append("Base \(redactor.redact(baseBranch, maxLength: 240)).")
        }
        return parts.joined(separator: " ")
    }

    private static func developmentPullRequestGateOutputSummary(
        for result: ToolResult,
        redactor: ExecutionReceiptRedactor
    ) -> String? {
        guard let pullRequestURL = result.output["pullRequestURL"]?.receiptIDValue else {
            return nil
        }
        var parts = [
            "Checked pull request gate \(redactor.redact(pullRequestURL, maxLength: 300))."
        ]
        if result.output["readyToMerge"]?.receiptBoolValue == true {
            parts.append("Review, CI, and mergeability gates passed.")
        } else {
            parts.append("Merge gate blocked.")
        }
        if let statusCheckCount = result.output["statusCheckCount"]?.receiptNumberValue {
            parts.append("\(Int(statusCheckCount)) status check(s) evaluated.")
        }
        return parts.joined(separator: " ")
    }

    private static func developmentPullRequestMergeOutputSummary(
        for result: ToolResult,
        redactor: ExecutionReceiptRedactor
    ) -> String? {
        guard let pullRequestURL = result.output["pullRequestURL"]?.receiptIDValue else {
            return nil
        }
        if result.status != .succeeded {
            if result.output["merged"]?.receiptBoolValue == false {
                return "Pull request merge failed for \(redactor.redact(pullRequestURL, maxLength: 300)). \(redactor.redact(result.summary))"
            }
            return "Pull request merge did not run for \(redactor.redact(pullRequestURL, maxLength: 300)). \(redactor.redact(result.summary))"
        }
        var parts = [
            "Merged pull request \(redactor.redact(pullRequestURL, maxLength: 300))."
        ]
        if result.output["deletedRemoteBranch"]?.receiptBoolValue == true {
            parts.append("Remote feature branch deletion requested.")
        }
        return parts.joined(separator: " ")
    }

    private static func executionReceiptFailureRecovery(
        for recovery: ReviewActionFailureRecovery?
    ) -> ExecutionReceiptFailureRecovery? {
        switch recovery {
        case .retryable:
            .retryable
        case .notRetryable:
            .notRetryable
        case nil:
            nil
        }
    }

    private static func approvedAutomationOutputSummary(
        status: ExecutionReceiptStatus,
        taskID: Int64,
        statusBefore: ProjectTaskStatus,
        statusAfter: ProjectTaskStatus
    ) -> String {
        switch status {
        case .succeeded:
            return "Moved task \(taskID) from \(statusBefore.rawValue) to \(statusAfter.rawValue)."
        case .running:
            return "Reserved approved task update \(taskID) from \(statusBefore.rawValue) to \(statusAfter.rawValue)."
        case .failed:
            return "Approved task update \(taskID) failed before completion."
        case .skipped:
            return "Approved task update \(taskID) was skipped."
        case .canceled:
            return "Approved task update \(taskID) was canceled."
        case .notStarted:
            return "Approved task update \(taskID) has not started."
        }
    }

    private static func scheduleDraftApplyOutputSummary(
        status: ExecutionReceiptStatus,
        createdEventCount: Int
    ) -> String {
        let eventLabel = createdEventCount == 1 ? "Calendar event" : "Calendar events"
        switch status {
        case .succeeded:
            return "Created \(createdEventCount) \(eventLabel) from a reviewed schedule draft."
        case .failed:
            return "Calendar schedule apply failed after creating \(createdEventCount) \(eventLabel)."
        case .running:
            return "Calendar schedule apply is running."
        case .notStarted:
            return "Calendar schedule apply has not started."
        case .skipped:
            return "Calendar schedule apply was skipped."
        case .canceled:
            return "Calendar schedule apply was canceled."
        }
    }

    private static func scheduleDraftApplyActionInput(for candidate: ScheduleDraftApplyWriteCandidate) -> String {
        [
            "taskID: \(candidate.taskID)",
            "startAt: \(candidate.startAt)",
            "endAt: \(candidate.endAt)"
        ].joined(separator: ", ")
    }

    private static func scheduleDraftApplyReferences(
        writeCandidates: [ScheduleDraftApplyWriteCandidate],
        createdEvents: [ScheduleDraftApplyCreatedEvent],
        projectTitlesByID: [Int64: String],
        redactor: ExecutionReceiptRedactor
    ) -> [ExecutionReceiptReference] {
        var references: [ExecutionReceiptReference] = []
        for candidate in writeCandidates {
            appendReference(
                kind: .task,
                id: String(candidate.taskID),
                label: redactor.redact(candidate.taskTitle, maxLength: 300),
                references: &references
            )
        }
        for projectID in Set(writeCandidates.map(\.projectID)).sorted() {
            appendReference(
                kind: .project,
                id: String(projectID),
                label: projectTitlesByID[projectID].map { redactor.redact($0, maxLength: 300) },
                references: &references
            )
        }
        for event in createdEvents {
            appendReference(
                kind: .calendarEvent,
                id: event.calendarEventID,
                label: redactor.redact(event.calendarEventTitle, maxLength: 300),
                references: &references
            )
        }
        return references
    }

    private static func appendReference(
        kind: ExecutionReceiptReferenceKind,
        id: String,
        label: String? = nil,
        references: inout [ExecutionReceiptReference]
    ) {
        guard !references.contains(where: { $0.kind == kind && $0.id == id }) else {
            return
        }
        references.append(ExecutionReceiptReference(kind: kind, id: id, label: label))
    }

    private static func references(for session: ReviewSession) -> [ExecutionReceiptReference] {
        var references = [
            ExecutionReceiptReference(kind: .reviewSession, id: session.id),
            ExecutionReceiptReference(kind: .actionPlan, id: session.originalPlan.id)
        ]
        for item in session.items {
            if let output = item.result?.output {
                appendReference(kind: .task, keys: ["taskId", "taskID"], output: output, references: &references)
                appendReference(kind: .project, keys: ["projectId", "projectID"], output: output, references: &references)
                appendReference(kind: .calendarEvent, keys: ["calendarEventId", "calendarEventID", "eventId", "eventID"], output: output, references: &references)
                appendReference(kind: .notification, keys: ["notificationId", "notificationID"], output: output, references: &references)
                // Keep connector references stable and low-disclosure; reminder titles stay in redacted summaries.
                appendReference(
                    kind: .reminder,
                    keys: ["reminderId", "reminderID", "reminderIds", "reminderIDs"],
                    output: output,
                    references: &references
                )
                appendDevelopmentReferences(for: item.editedAction, values: output, references: &references)
            }
            // Developer PR tools may fail before producing ToolResult output
            // (for example invalid GitHub JSON). Preserve the reviewed branch,
            // PR, and project IDs from the approved action arguments so audit
            // surfaces still show what external object was attempted.
            appendDevelopmentReferences(for: item.editedAction, values: item.editedAction.arguments, references: &references)
        }
        return references
    }

    private static func appendDevelopmentReferences(
        for action: PlanAction,
        values: [String: JSONValue],
        references: inout [ExecutionReceiptReference]
    ) {
        switch action.tool {
        case .developmentPreparePullRequestWorkflow:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
            appendReference(kind: .developmentCommit, keys: ["headRefOid", "headRefOID"], output: values, references: &references)
        case .developmentPushBranch:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
            appendReference(kind: .developmentCommit, keys: ["headRefOid", "headRefOID"], output: values, references: &references)
        case .developmentRunVerification:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
        case .developmentRepositoryCreateFile, .developmentRepositoryUpdateFile:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .task, keys: ["taskId", "taskID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
        case .developmentCommitChanges:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
            appendReference(kind: .developmentCommit, keys: ["headRefOid", "headRefOID", "headOid", "headOID"], output: values, references: &references)
        case .developmentCreatePullRequest:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
            appendReference(kind: .developmentBaseBranch, keys: ["baseBranch"], output: values, references: &references)
            appendReference(kind: .developmentCommit, keys: ["headRefOid", "headRefOID", "headOid", "headOID", "expectedHeadOID"], output: values, references: &references)
            appendReference(kind: .pullRequest, keys: ["pullRequestURL"], output: values, references: &references)
        case .developmentReviewPullRequestGate:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
            appendReference(kind: .developmentBaseBranch, keys: ["baseBranch"], output: values, references: &references)
            appendReference(kind: .developmentCommit, keys: ["headRefOid", "headRefOID", "headOid", "headOID"], output: values, references: &references)
            appendReference(kind: .pullRequest, keys: ["pullRequestURL"], output: values, references: &references)
        case .developmentMergePullRequest:
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: values, references: &references)
            appendReference(kind: .developmentBranch, keys: ["branchName"], output: values, references: &references)
            appendReference(kind: .developmentBaseBranch, keys: ["baseBranch"], output: values, references: &references)
            appendReference(kind: .developmentCommit, keys: ["headRefOid", "headRefOID", "headOid", "headOID"], output: values, references: &references)
            appendReference(kind: .pullRequest, keys: ["pullRequestURL"], output: values, references: &references)
        default:
            return
        }
    }

    private static func appendReference(
        kind: ExecutionReceiptReferenceKind,
        keys: [String],
        output: [String: JSONValue],
        references: inout [ExecutionReceiptReference]
    ) {
        for key in keys {
            guard let ids = output[key]?.receiptIDValues, !ids.isEmpty else {
                continue
            }
            for id in ids {
                appendReference(kind: kind, id: id, references: &references)
            }
            return
        }
    }
}

private enum ExecutionReceiptDigest {
    static func normalizedDigest(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.count == 64 && normalized.allSatisfy(\.isHexDigit) {
            return normalized
        }
        return sha256(value)
    }

    static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONValue {
    var receiptStringValue: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            String(value)
        case .bool(let value):
            value ? "true" : "false"
        case .object, .array, .null, .actionOutput:
            nil
        }
    }

    var receiptIDValue: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            if value.rounded() == value {
                String(Int64(value))
            } else {
                String(value)
            }
        case .bool(let value):
            String(value)
        case .object, .array, .null, .actionOutput:
            nil
        }
    }

    var receiptIDValues: [String]? {
        switch self {
        case .array(let values):
            let ids = values.compactMap(\.receiptIDValue)
            return ids.isEmpty ? nil : ids
        default:
            return receiptIDValue.map { [$0] }
        }
    }

    var receiptBoolValue: Bool? {
        switch self {
        case .bool(let value):
            value
        default:
            nil
        }
    }

    var receiptNumberValue: Double? {
        switch self {
        case .number(let value):
            value
        default:
            nil
        }
    }

    var receiptNonEmptyString: String? {
        switch self {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }
}

private extension String {
    func receiptPreview(maxLength: Int) -> String {
        let normalized = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > maxLength else {
            return normalized
        }
        return "\(normalized.prefix(maxLength))..."
    }
}
