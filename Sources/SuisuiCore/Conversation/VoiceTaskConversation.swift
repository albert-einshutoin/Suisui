import Foundation

public enum VoiceTaskConversationDomainError: Error, Equatable, Sendable {
    case invalidStateTransition
    case blankConfirmedText
    case confirmedTextRequiresUserAuthor
    case invalidConfidence
    case cyclicSupersession
    case expiredReference
    case nonMonotonicTimestamp
    case blankFactValue
    case blankFingerprint
    case blankActionIdentifier
    case missingActionTarget
    case invalidReferenceOrdinal
    case invalidReferenceTarget
    case invalidReferenceExpiration
    case duplicateFactIdentifier
    case invalidFactEvidenceDigest
    case invalidFactExpiration
    case invalidFactScope
    case incompatibleFactTransition
    case unauthorizedFactPersistence
}

public enum VoiceTaskConversationSessionState: String, Codable, Equatable, Hashable, Sendable {
    case active
    case paused
    case archived
}

public enum VoiceTaskConversationEntryPoint: String, Codable, Equatable, Hashable, Sendable {
    case voiceCommand = "voice_command"
    case inboxVoice = "inbox_voice"
    case taskInspector = "task_inspector"
    case projectWorkspace = "project_workspace"
}

public struct VoiceTaskConversationSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public private(set) var state: VoiceTaskConversationSessionState
    public private(set) var title: String
    public let entryPoint: VoiceTaskConversationEntryPoint
    public private(set) var activeProjectID: Int64?
    public private(set) var activeTaskID: Int64?
    public private(set) var resumeSummary: String?
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var lastTurnAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        entryPoint: VoiceTaskConversationEntryPoint,
        activeProjectID: Int64? = nil,
        activeTaskID: Int64? = nil,
        resumeSummary: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        state = .active
        self.title = title
        self.entryPoint = entryPoint
        self.activeProjectID = activeProjectID
        self.activeTaskID = activeTaskID
        self.resumeSummary = resumeSummary
        self.createdAt = createdAt
        updatedAt = createdAt
        lastTurnAt = nil
    }

    /// Rehydrates a validated persisted session without making lifecycle fields
    /// publicly writable. SQLite corruption must cross the same timestamp
    /// boundary as Codable restoration instead of creating an impossible state.
    public init(
        restoringID id: UUID,
        state: VoiceTaskConversationSessionState,
        title: String,
        entryPoint: VoiceTaskConversationEntryPoint,
        activeProjectID: Int64?,
        activeTaskID: Int64?,
        resumeSummary: String?,
        createdAt: Date,
        updatedAt: Date,
        lastTurnAt: Date?
    ) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              lastTurnAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              updatedAt >= createdAt,
              lastTurnAt.map({ $0 >= createdAt && $0 <= updatedAt }) ?? true
        else {
            throw VoiceTaskConversationDomainError.nonMonotonicTimestamp
        }

        self.id = id
        self.state = state
        self.title = title
        self.entryPoint = entryPoint
        self.activeProjectID = activeProjectID
        self.activeTaskID = activeTaskID
        self.resumeSummary = resumeSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastTurnAt = lastTurnAt
    }

    public mutating func pause(at date: Date = Date()) throws {
        guard state == .active else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        try advance(to: .paused, at: date)
    }

    public mutating func resume(at date: Date = Date()) throws {
        guard state == .paused else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        try advance(to: .active, at: date)
    }

    public mutating func archive(at date: Date = Date()) throws {
        guard state == .paused else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        try advance(to: .archived, at: date)
    }

    public mutating func recordTurn(at date: Date = Date()) throws {
        guard state == .active else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        let previousTurnAt = lastTurnAt ?? createdAt
        guard date >= previousTurnAt else {
            throw VoiceTaskConversationDomainError.nonMonotonicTimestamp
        }
        let previousUpdateValue = updatedAt.timeIntervalSinceReferenceDate
        let turnValue = date.timeIntervalSinceReferenceDate
        guard previousUpdateValue.isFinite, turnValue.isFinite else {
            throw VoiceTaskConversationDomainError.nonMonotonicTimestamp
        }
        lastTurnAt = date
        let nextVersion = previousUpdateValue.nextUp
        guard nextVersion.isFinite else {
            throw VoiceTaskConversationDomainError.nonMonotonicTimestamp
        }
        // `updatedAt` is also the persisted optimistic-lock version. Turn
        // chronology follows `lastTurnAt`, while every write advances the version
        // even when multiple Turns share one clock instant.
        updatedAt = max(date, Date(timeIntervalSinceReferenceDate: nextVersion))
    }

    public mutating func updateTitle(
        _ title: String,
        at date: Date = Date()
    ) throws {
        guard state != .archived else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        try requireMonotonic(date)
        self.title = title
        updatedAt = date
    }

    public mutating func setActiveContext(
        projectID: Int64?,
        taskID: Int64?,
        resumeSummary: String?,
        at date: Date = Date()
    ) throws {
        guard state != .archived else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        try requireMonotonic(date)
        activeProjectID = projectID
        self.activeTaskID = taskID
        self.resumeSummary = resumeSummary
        updatedAt = date
    }

    private mutating func advance(
        to newState: VoiceTaskConversationSessionState,
        at date: Date
    ) throws {
        try requireMonotonic(date)
        state = newState
        updatedAt = date
    }

    private func requireMonotonic(_ date: Date) throws {
        guard date >= updatedAt else {
            throw VoiceTaskConversationDomainError.nonMonotonicTimestamp
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case state
        case title
        case entryPoint
        case activeProjectID
        case activeTaskID
        case resumeSummary
        case createdAt
        case updatedAt
        case lastTurnAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            restoringID: values.decode(UUID.self, forKey: .id),
            state: values.decode(VoiceTaskConversationSessionState.self, forKey: .state),
            title: values.decode(String.self, forKey: .title),
            entryPoint: values.decode(VoiceTaskConversationEntryPoint.self, forKey: .entryPoint),
            activeProjectID: values.decodeIfPresent(Int64.self, forKey: .activeProjectID),
            activeTaskID: values.decodeIfPresent(Int64.self, forKey: .activeTaskID),
            resumeSummary: values.decodeIfPresent(String.self, forKey: .resumeSummary),
            createdAt: values.decode(Date.self, forKey: .createdAt),
            updatedAt: values.decode(Date.self, forKey: .updatedAt),
            lastTurnAt: values.decodeIfPresent(Date.self, forKey: .lastTurnAt)
        )
    }
}

public enum VoiceTaskConversationTurnAuthor: String, Codable, Equatable, Hashable, Sendable {
    case user
    case assistant
    case system
}

public struct VoiceTaskConversationTurn: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let author: VoiceTaskConversationTurnAuthor
    /// Raw recognition output remains independent so retention can delete it
    /// without deleting the text the user explicitly confirmed.
    public let rawTranscript: String?
    public let userConfirmedText: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        author: VoiceTaskConversationTurnAuthor,
        rawTranscript: String? = nil,
        userConfirmedText: String? = nil,
        createdAt: Date = Date()
    ) throws {
        if let userConfirmedText,
           userConfirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw VoiceTaskConversationDomainError.blankConfirmedText
        }
        guard userConfirmedText == nil || author == .user else {
            throw VoiceTaskConversationDomainError.confirmedTextRequiresUserAuthor
        }

        self.id = id
        self.sessionID = sessionID
        self.author = author
        self.rawTranscript = rawTranscript
        self.userConfirmedText = userConfirmedText
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case author
        case rawTranscript
        case userConfirmedText
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            sessionID: values.decode(UUID.self, forKey: .sessionID),
            author: values.decode(VoiceTaskConversationTurnAuthor.self, forKey: .author),
            rawTranscript: values.decodeIfPresent(String.self, forKey: .rawTranscript),
            userConfirmedText: values.decodeIfPresent(String.self, forKey: .userConfirmedText),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

public enum ConversationStableTargetID: Codable, Equatable, Hashable, Sendable {
    case project(Int64)
    case task(Int64)
    case actionPlan(String)
    case assistantQueueItem(String)
    case executionReceipt(String)

    fileprivate var hasValidIdentifier: Bool {
        switch self {
        case .project(let id), .task(let id):
            id > 0
        case .actionPlan(let id), .assistantQueueItem(let id), .executionReceipt(let id):
            !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct ConversationReference: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let target: ConversationStableTargetID
    public let sourceTurnID: UUID
    public let ordinal: Int
    public let orderingFingerprint: String
    public let expiresAt: Date
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        target: ConversationStableTargetID,
        sourceTurnID: UUID,
        ordinal: Int,
        orderingFingerprint: String,
        expiresAt: Date,
        createdAt: Date = Date()
    ) throws {
        guard ordinal >= 0 else {
            throw VoiceTaskConversationDomainError.invalidReferenceOrdinal
        }
        guard target.hasValidIdentifier else {
            throw VoiceTaskConversationDomainError.invalidReferenceTarget
        }
        guard !orderingFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceTaskConversationDomainError.blankFingerprint
        }
        guard expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > createdAt
        else {
            throw VoiceTaskConversationDomainError.invalidReferenceExpiration
        }
        self.id = id
        self.sessionID = sessionID
        self.target = target
        self.sourceTurnID = sourceTurnID
        self.ordinal = ordinal
        self.orderingFingerprint = orderingFingerprint
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    public func requireEligible(at date: Date = Date()) throws {
        // An expired ordinal must never be reinterpreted against a newer candidate
        // list; callers have to ask the user to clarify instead.
        guard date < expiresAt else {
            throw VoiceTaskConversationDomainError.expiredReference
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case target
        case sourceTurnID
        case ordinal
        case orderingFingerprint
        case expiresAt
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            sessionID: values.decode(UUID.self, forKey: .sessionID),
            target: values.decode(ConversationStableTargetID.self, forKey: .target),
            sourceTurnID: values.decode(UUID.self, forKey: .sourceTurnID),
            ordinal: values.decode(Int.self, forKey: .ordinal),
            orderingFingerprint: values.decode(String.self, forKey: .orderingFingerprint),
            expiresAt: values.decode(Date.self, forKey: .expiresAt),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

public enum TaskContextFactKind: String, Codable, Equatable, Hashable, Sendable {
    case goal
    case constraint
    case acceptanceCriterion = "acceptance_criterion"
    case decision
    case openQuestion = "open_question"
    case followUp = "follow_up"
    case dueDate = "due_date"
    case dueDateReason = "due_date_reason"
    case priorityReason = "priority_reason"
    case project
    case task
    case preference
}

public enum TaskContextFactScope: Codable, Equatable, Hashable, Sendable {
    case session
    case project(Int64)
    case task(Int64)
}

public enum TaskContextFactState: String, Codable, Equatable, Hashable, Sendable {
    case proposed
    case confirmed
    case superseded
    case retracted
    case rejected
    case expired
}

public enum TaskContextFactAuthor: Equatable, Hashable, Sendable {
    case userExplicit
    case providerInferred
    case deterministic

    public var rawValue: String {
        switch self {
        case .userExplicit:
            "user_explicit"
        case .providerInferred:
            "provider_inferred"
        case .deterministic:
            "deterministic"
        }
    }
}

extension TaskContextFactAuthor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "user_explicit":
            self = .userExplicit
        case "provider_inferred":
            self = .providerInferred
        case "deterministic", "system_derived":
            // Decode the legacy spelling so persisted pre-policy payloads remain readable.
            self = .deterministic
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Task Context fact author."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct TaskContextFact: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let kind: TaskContextFactKind
    public let scope: TaskContextFactScope
    public let state: TaskContextFactState
    /// This value is created by an explicit confirmation/inference step. The
    /// model deliberately has no API that derives it from a raw transcript.
    public let value: String
    public let sourceTurnID: UUID
    /// SHA-256 of the minimal user-visible source excerpt. Keeping the digest
    /// instead of raw audio/transcript evidence prevents Task Context from
    /// becoming a second transcript store.
    public let sourceExcerptDigest: String
    /// Legacy payloads without an excerpt digest remain readable for migration
    /// but can never become long-term context or an authorized Store write.
    public let sourceEvidenceVerified: Bool
    public let confidence: Double
    public let author: TaskContextFactAuthor
    public let supersedesFactID: UUID?
    public let expiresAt: Date?
    public let createdAt: Date
    let persistenceAuthorized: Bool
    let requiresAtomicSupersession: Bool

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        kind: TaskContextFactKind,
        scope: TaskContextFactScope,
        state: TaskContextFactState,
        value: String,
        sourceTurnID: UUID,
        sourceExcerptDigest: String,
        confidence: Double,
        author: TaskContextFactAuthor,
        supersedesFactID: UUID? = nil,
        expiresAt: Date? = nil,
        createdAt: Date = Date()
    ) throws {
        guard confidence.isFinite, (0 ... 1).contains(confidence) else {
            throw VoiceTaskConversationDomainError.invalidConfidence
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceTaskConversationDomainError.blankFactValue
        }
        guard supersedesFactID != id else {
            throw VoiceTaskConversationDomainError.cyclicSupersession
        }
        // Session-wide memory is deliberately excluded: every durable Fact
        // must stay anchored to one persisted Task or Project identifier.
        switch scope {
        case .session:
            throw VoiceTaskConversationDomainError.invalidFactScope
        case .project(let id), .task(let id):
            guard id > 0 else {
                throw VoiceTaskConversationDomainError.invalidFactScope
            }
        }
        let normalizedDigest = sourceExcerptDigest.lowercased()
        guard normalizedDigest.count == 64,
              normalizedDigest.unicodeScalars.allSatisfy({
                  ("0" ... "9").contains(Character($0))
                      || ("a" ... "f").contains(Character($0))
              })
        else {
            throw VoiceTaskConversationDomainError.invalidFactEvidenceDigest
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              expiresAt.map({ $0 > createdAt }) ?? true
        else {
            throw VoiceTaskConversationDomainError.invalidFactExpiration
        }

        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.scope = scope
        self.state = state
        self.value = value
        self.sourceTurnID = sourceTurnID
        self.sourceExcerptDigest = normalizedDigest
        sourceEvidenceVerified = true
        self.confidence = confidence
        self.author = author
        self.supersedesFactID = supersedesFactID
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        persistenceAuthorized = false
        requiresAtomicSupersession = false
    }

    public func isEligibleForLongTermContext(at date: Date = Date()) -> Bool {
        sourceEvidenceVerified
            && scope != .session
            && state == .confirmed
            && (expiresAt.map { date < $0 } ?? true)
    }

    func authorizingPersistence(
        using _: TaskContextFactAuthorizationToken,
        requiresAtomicSupersession: Bool = false
    ) -> TaskContextFact {
        TaskContextFact(
            validated: self,
            sourceEvidenceVerified: sourceEvidenceVerified,
            persistenceAuthorized: true,
            requiresAtomicSupersession: requiresAtomicSupersession
        )
    }

    private init(
        validated fact: TaskContextFact,
        scope: TaskContextFactScope? = nil,
        sourceEvidenceVerified: Bool,
        persistenceAuthorized: Bool,
        requiresAtomicSupersession: Bool = false
    ) {
        id = fact.id
        sessionID = fact.sessionID
        kind = fact.kind
        self.scope = scope ?? fact.scope
        state = fact.state
        value = fact.value
        sourceTurnID = fact.sourceTurnID
        sourceExcerptDigest = fact.sourceExcerptDigest
        self.sourceEvidenceVerified = sourceEvidenceVerified
        confidence = fact.confidence
        author = fact.author
        supersedesFactID = fact.supersedesFactID
        expiresAt = fact.expiresAt
        createdAt = fact.createdAt
        self.persistenceAuthorized = persistenceAuthorized
        self.requiresAtomicSupersession = requiresAtomicSupersession
    }

    public static func == (lhs: TaskContextFact, rhs: TaskContextFact) -> Bool {
        lhs.id == rhs.id
            && lhs.sessionID == rhs.sessionID
            && lhs.kind == rhs.kind
            && lhs.scope == rhs.scope
            && lhs.state == rhs.state
            && lhs.value == rhs.value
            && lhs.sourceTurnID == rhs.sourceTurnID
            && lhs.sourceExcerptDigest == rhs.sourceExcerptDigest
            && lhs.sourceEvidenceVerified == rhs.sourceEvidenceVerified
            && lhs.confidence == rhs.confidence
            && lhs.author == rhs.author
            && lhs.supersedesFactID == rhs.supersedesFactID
            && lhs.expiresAt == rhs.expiresAt
            && lhs.createdAt == rhs.createdAt
    }

    public static func validateSupersessionGraph(_ facts: [TaskContextFact]) throws {
        var supersededByID: [UUID: UUID?] = [:]
        for fact in facts {
            guard supersededByID.updateValue(fact.supersedesFactID, forKey: fact.id) == nil else {
                throw VoiceTaskConversationDomainError.duplicateFactIdentifier
            }
        }
        var fullyVisited = Set<UUID>()

        for fact in facts where !fullyVisited.contains(fact.id) {
            var currentID: UUID? = fact.id
            var currentPath = Set<UUID>()

            // Facts may reference an older record outside the loaded window. Only a
            // repeated ID in this in-memory path proves a cycle; a missing node does not.
            while let id = currentID, let next = supersededByID[id] {
                guard currentPath.insert(id).inserted else {
                    throw VoiceTaskConversationDomainError.cyclicSupersession
                }
                currentID = next
            }
            fullyVisited.formUnion(currentPath)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case kind
        case scope
        case state
        case value
        case sourceTurnID
        case sourceExcerptDigest
        case sourceEvidenceVerified
        case confidence
        case author
        case supersedesFactID
        case expiresAt
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDigest = try values.decodeIfPresent(
            String.self,
            forKey: .sourceExcerptDigest
        )
        let decodedScope = try values.decode(
            TaskContextFactScope.self,
            forKey: .scope
        )
        let base = try TaskContextFact(
            id: values.decode(UUID.self, forKey: .id),
            sessionID: values.decode(UUID.self, forKey: .sessionID),
            kind: values.decode(TaskContextFactKind.self, forKey: .kind),
            // Legacy session-scoped Facts are reconstructed below as
            // read-only, unverified records. A temporary valid scope lets the
            // common initializer continue validating every other field.
            scope: decodedScope == .session ? .task(1) : decodedScope,
            state: values.decode(TaskContextFactState.self, forKey: .state),
            value: values.decode(String.self, forKey: .value),
            sourceTurnID: values.decode(UUID.self, forKey: .sourceTurnID),
            sourceExcerptDigest: decodedDigest ?? String(repeating: "0", count: 64),
            confidence: values.decode(Double.self, forKey: .confidence),
            author: values.decode(TaskContextFactAuthor.self, forKey: .author),
            supersedesFactID: values.decodeIfPresent(UUID.self, forKey: .supersedesFactID),
            expiresAt: values.decodeIfPresent(Date.self, forKey: .expiresAt),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
        let declaredEvidenceState = try values.decodeIfPresent(
            Bool.self,
            forKey: .sourceEvidenceVerified
        )
        self = TaskContextFact(
            validated: base,
            scope: decodedScope,
            sourceEvidenceVerified: decodedScope != .session
                && decodedDigest != nil
                && (declaredEvidenceState ?? true),
            persistenceAuthorized: false,
            requiresAtomicSupersession: false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(kind, forKey: .kind)
        try values.encode(scope, forKey: .scope)
        try values.encode(state, forKey: .state)
        try values.encode(value, forKey: .value)
        try values.encode(sourceTurnID, forKey: .sourceTurnID)
        if sourceEvidenceVerified {
            try values.encode(sourceExcerptDigest, forKey: .sourceExcerptDigest)
        }
        try values.encode(sourceEvidenceVerified, forKey: .sourceEvidenceVerified)
        try values.encode(confidence, forKey: .confidence)
        try values.encode(author, forKey: .author)
        try values.encodeIfPresent(supersedesFactID, forKey: .supersedesFactID)
        try values.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try values.encode(createdAt, forKey: .createdAt)
    }
}

public enum ConversationActionLinkOperation: String, Codable, Equatable, Sendable {
    case unspecified
    case taskCreated = "task_created"
    case taskUpdated = "task_updated"
    case taskCompleted = "task_completed"
    case taskDeleted = "task_deleted"
}

public struct ConversationActionLink: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let sourceTurnID: UUID
    public let actionPlanID: String?
    public let assistantQueueItemID: String?
    public let taskID: Int64?
    public let executionReceiptID: String?
    public let operation: ConversationActionLinkOperation
    public let reviewedFingerprint: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        sourceTurnID: UUID,
        actionPlanID: String? = nil,
        assistantQueueItemID: String? = nil,
        taskID: Int64? = nil,
        executionReceiptID: String? = nil,
        operation: ConversationActionLinkOperation = .unspecified,
        reviewedFingerprint: String,
        createdAt: Date = Date()
    ) throws {
        guard actionPlanID != nil
            || assistantQueueItemID != nil
            || taskID != nil
            || executionReceiptID != nil
        else {
            throw VoiceTaskConversationDomainError.missingActionTarget
        }
        guard !reviewedFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceTaskConversationDomainError.blankFingerprint
        }
        let identifiers = [actionPlanID, assistantQueueItemID, executionReceiptID].compactMap { $0 }
        guard identifiers.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw VoiceTaskConversationDomainError.blankActionIdentifier
        }
        guard taskID.map({ $0 > 0 }) ?? true else {
            throw VoiceTaskConversationDomainError.blankActionIdentifier
        }

        self.id = id
        self.sessionID = sessionID
        self.sourceTurnID = sourceTurnID
        self.actionPlanID = actionPlanID
        self.assistantQueueItemID = assistantQueueItemID
        self.taskID = taskID
        self.executionReceiptID = executionReceiptID
        self.operation = operation
        self.reviewedFingerprint = reviewedFingerprint
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case sourceTurnID
        case actionPlanID
        case assistantQueueItemID
        case taskID
        case executionReceiptID
        case operation
        case reviewedFingerprint
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            sessionID: values.decode(UUID.self, forKey: .sessionID),
            sourceTurnID: values.decode(UUID.self, forKey: .sourceTurnID),
            actionPlanID: values.decodeIfPresent(String.self, forKey: .actionPlanID),
            assistantQueueItemID: values.decodeIfPresent(String.self, forKey: .assistantQueueItemID),
            taskID: values.decodeIfPresent(Int64.self, forKey: .taskID),
            executionReceiptID: values.decodeIfPresent(String.self, forKey: .executionReceiptID),
            operation: try values.decodeIfPresent(
                ConversationActionLinkOperation.self,
                forKey: .operation
            ) ?? .unspecified,
            reviewedFingerprint: values.decode(String.self, forKey: .reviewedFingerprint),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}
