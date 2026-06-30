import CryptoKit
import Foundation

public enum ExecutionReceiptStatus: String, Codable, Equatable, Sendable {
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

public enum ExecutionReceiptReferenceKind: String, Codable, Equatable, Sendable {
    case assistantQueue = "assistant_queue"
    case actionPlan = "action_plan"
    case reviewSession = "review_session"
    case task
    case project
    case document
    case calendarEvent = "calendar_event"
    case notification
    case file
    case pullRequest = "pull_request"
}

public enum ExecutionReceiptSurface: String, Codable, Equatable, Sendable {
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

    public init(
        id: String,
        toolName: String,
        status: ExecutionReceiptStatus,
        inputPreview: String,
        outputSummary: String? = nil,
        errorSummary: String? = nil,
        failureRecovery: ExecutionReceiptFailureRecovery? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.status = status
        self.inputPreview = inputPreview
        self.outputSummary = outputSummary
        self.errorSummary = errorSummary
        self.failureRecovery = failureRecovery
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

public struct ExecutionReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public private(set) var id: String
    public private(set) var runID: String
    public private(set) var approvalID: String?
    public private(set) var assistantQueueItemID: String?
    public private(set) var queueApproval: ExecutionReceiptQueueApproval?
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
                failureRecovery: action.failureRecovery
            )
        }
        self.visibleSurfaces = visibleSurfaces
    }
}

public protocol ExecutionReceiptStore: Sendable {
    func save(_ receipt: ExecutionReceipt) throws
    func list(limit: Int) throws -> [ExecutionReceipt]
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

public final class InMemoryExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
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
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public func save(_ receipt: ExecutionReceipt) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try encoder.encode(receipt)
        let destinationURL = fileURL(for: receipt.id)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw ExecutionReceiptStoreError.duplicateReceiptID(receipt.id)
        }
        try data.write(to: destinationURL, options: [.atomic])
    }

    public func list(limit: Int = 100) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        return try sortedReceiptURLs()
            .prefix(boundedLimit)
            .map { url in
                try loadReceipt(from: url)
            }
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
        var matches: [ExecutionReceipt] = []
        // Scope before limiting so a busy global receipt stream cannot hide
        // older task/project evidence from the detail inspector.
        for url in try sortedReceiptURLs() {
            let receipt = try loadReceipt(from: url)
            guard receipt.visibleSurfaces.contains(visibleSurface),
                  receipt.references.contains(where: { reference in
                      reference.kind == referenceKind && reference.id == referenceID
                  }) else {
                continue
            }
            matches.append(receipt)
            if matches.count >= boundedLimit {
                break
            }
        }
        return matches
    }

    private func sortedReceiptURLs() throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension == "json" }
            .map { url -> (URL, Date) in
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                return (url, values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func loadReceipt(from url: URL) throws -> ExecutionReceipt {
        let data = try Data(contentsOf: url)
        return try decoder.decode(ExecutionReceipt.self, from: data)
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

public struct ExecutionReceiptRedactionPolicy: Equatable, Sendable {
    public var allowedLocalPathPrefixes: [String]

    public init(allowedLocalPathPrefixes: [String] = []) {
        self.allowedLocalPathPrefixes = allowedLocalPathPrefixes.map(Self.canonicalPath)
    }

    fileprivate static func canonicalPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }
        var path = URL(fileURLWithPath: trimmed).standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

public struct ExecutionReceiptRedactor: Sendable {
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
        return redactDisallowedLocalPaths(in: secretRedacted).receiptPreview(maxLength: maxLength)
    }

    private func redactDisallowedLocalPaths(in value: String) -> String {
        guard !value.isEmpty else {
            return value
        }

        let ranges = localPathRanges(in: value)
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

    private func localPathRanges(in value: String) -> [Range<String.Index>] {
        let starts = localPathStartIndexes(in: value)
        guard !starts.isEmpty else {
            return []
        }

        return starts.enumerated().compactMap { index, start in
            let searchEnd = index + 1 < starts.count
                ? starts[index + 1]
                : value.endIndex
            var end = firstLocalPathTerminator(in: value, from: start, upperBound: searchEnd) ?? searchEnd
            end = pathExtensionEnd(in: value[start..<end]) ?? end
            return start < end ? start..<end : nil
        }
    }

    private func localPathStartIndexes(in value: String) -> [String.Index] {
        var indexes: [String.Index] = []
        var searchStart = value.startIndex
        let prefixes = ["/Users/", "/Volumes/", "/private/", "/tmp/"]

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
        let terminators = CharacterSet(charactersIn: "\n\r,;\")'")
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
        let actions = session.items.map { item in
            ExecutionReceiptActionSummary(
                id: item.id,
                toolName: item.editedAction.tool.rawValue,
                status: executionReceiptStatus(for: item.executionStatus),
                inputPreview: redactor.redact(item.argumentDisplaySummary(maxFields: 12, maxValueLength: 300).fullText),
                outputSummary: item.result.map { redactor.redact($0.summary) },
                errorSummary: item.errorMessage.map { redactor.redact($0) },
                failureRecovery: executionReceiptFailureRecovery(for: item.failureRecovery)
            )
        }
        let sanitizedSourceLinks = sourceLinks.map { link in
            ExecutionReceiptSourceLink(
                kind: link.kind,
                title: redactor.redact(link.title, maxLength: 240),
                url: redactor.redact(link.url, maxLength: 600)
            )
        }

        // Receipts are user-facing accountability records, so they carry a
        // compact redacted view instead of raw prompts or document bodies.
        return ExecutionReceipt(
            id: "receipt:\(runID):\(session.id)",
            runID: runID,
            approvalID: session.approvalToken?.id,
            createdAt: finishedAt ?? startedAt ?? Date(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: executionReceiptStatus(for: session.executionStatus),
            inputPreview: redactor.redact("\(session.originalPlan.userInput)\n\(session.originalPlan.summary)"),
            outputSummary: redactor.redact(outcomeSummary(for: actions)),
            model: model,
            primaryToolName: actions.first?.toolName,
            usage: usage,
            references: references(for: session),
            sourceLinks: sanitizedSourceLinks,
            actions: actions,
            redactionPolicy: redactionPolicy
        )
    }

    public static func makeApprovedAutomationReceipt(
        _ receipt: ApprovedAutomationExecutionReceipt,
        runID: String,
        approvalID: String?,
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
        let outputSummary = "Moved task \(receipt.taskID) from \(receipt.statusBefore.rawValue) to \(receipt.statusAfter.rawValue)."

        return ExecutionReceipt(
            id: "receipt:\(runID):approved-automation:\(receipt.taskID)",
            runID: runID,
            approvalID: approvalID,
            createdAt: createdAt,
            startedAt: createdAt,
            finishedAt: createdAt,
            status: .succeeded,
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
                    status: .succeeded,
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
            finishedAt: createdAt,
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
        let actions = session.items.map { item in
            ExecutionReceiptActionSummary(
                id: item.id,
                toolName: item.editedAction.tool.rawValue,
                status: executionReceiptStatus(for: item.executionStatus),
                inputPreview: redactor.redact(item.argumentDisplaySummary(maxFields: 12, maxValueLength: 300).fullText),
                outputSummary: item.result.map { redactor.redact($0.summary) },
                errorSummary: item.errorMessage.map { redactor.redact($0) },
                failureRecovery: executionReceiptFailureRecovery(for: item.failureRecovery)
            )
        }
        let queueReference = ExecutionReceiptReference(
            kind: .assistantQueue,
            id: item.id,
            label: redactor.redact(item.redactedSummary, maxLength: 300)
        )
        let references = [queueReference] + references(for: session)

        return ExecutionReceipt(
            id: "receipt:\(runID):\(item.id):\(session.id)",
            runID: runID,
            approvalID: session.approvalToken?.id,
            assistantQueueItemID: item.id,
            queueApproval: item.approval.map { approval in
                ExecutionReceiptQueueApproval(
                    approvalID: approval.approvalID,
                    reviewerID: approval.reviewerID,
                    note: approval.note,
                    reviewedContentFingerprint: approval.reviewedContentFingerprint
                )
            },
            createdAt: finishedAt ?? startedAt ?? Date(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: executionReceiptStatus(for: session.executionStatus),
            inputPreview: redactor.redact(inputPreview),
            outputSummary: redactor.redact(outcomeSummary(for: actions)),
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
            outputSummary: redactor.redact(outputSummary),
            model: model,
            usage: usage,
            references: [
                ExecutionReceiptReference(kind: .assistantQueue, id: item.id, label: redactor.redact(item.redactedSummary, maxLength: 300))
            ],
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
            guard let output = item.result?.output else {
                continue
            }
            appendReference(kind: .task, keys: ["taskId", "taskID"], output: output, references: &references)
            appendReference(kind: .project, keys: ["projectId", "projectID"], output: output, references: &references)
            appendReference(kind: .notification, keys: ["notificationId", "notificationID"], output: output, references: &references)
        }
        return references
    }

    private static func appendReference(
        kind: ExecutionReceiptReferenceKind,
        keys: [String],
        output: [String: JSONValue],
        references: inout [ExecutionReceiptReference]
    ) {
        for key in keys {
            guard let id = output[key]?.receiptIDValue else {
                continue
            }
            let reference = ExecutionReceiptReference(kind: kind, id: id)
            if !references.contains(reference) {
                references.append(reference)
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
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONValue {
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
        case .object, .array, .null:
            nil
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
