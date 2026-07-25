import Foundation

public enum VoiceTaskConversationDomainError: Error, Equatable, Sendable {
    case invalidStateTransition
    case blankConfirmedText
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
        guard state == .active || state == .paused else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        try advance(to: .archived, at: date)
    }

    public mutating func recordTurn(at date: Date = Date()) throws {
        guard state == .active else {
            throw VoiceTaskConversationDomainError.invalidStateTransition
        }
        try requireMonotonic(date)
        lastTurnAt = date
        updatedAt = date
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
        let createdAt = try values.decode(Date.self, forKey: .createdAt)
        let updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        let lastTurnAt = try values.decodeIfPresent(Date.self, forKey: .lastTurnAt)
        guard updatedAt >= createdAt,
              lastTurnAt.map({ $0 >= createdAt && $0 <= updatedAt }) ?? true
        else {
            throw VoiceTaskConversationDomainError.nonMonotonicTimestamp
        }

        id = try values.decode(UUID.self, forKey: .id)
        state = try values.decode(VoiceTaskConversationSessionState.self, forKey: .state)
        title = try values.decode(String.self, forKey: .title)
        entryPoint = try values.decode(VoiceTaskConversationEntryPoint.self, forKey: .entryPoint)
        activeProjectID = try values.decodeIfPresent(Int64.self, forKey: .activeProjectID)
        activeTaskID = try values.decodeIfPresent(Int64.self, forKey: .activeTaskID)
        resumeSummary = try values.decodeIfPresent(String.self, forKey: .resumeSummary)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastTurnAt = lastTurnAt
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
    public let expiresAt: Date?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        target: ConversationStableTargetID,
        sourceTurnID: UUID,
        ordinal: Int,
        orderingFingerprint: String,
        expiresAt: Date?,
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
        guard expiresAt.map({ $0 > createdAt }) ?? true else {
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
        guard expiresAt.map({ date < $0 }) ?? true else {
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
            expiresAt: values.decodeIfPresent(Date.self, forKey: .expiresAt),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

public enum TaskContextFactKind: String, Codable, Equatable, Hashable, Sendable {
    case goal
    case constraint
    case dueDate = "due_date"
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
}

public enum TaskContextFactAuthor: String, Codable, Equatable, Hashable, Sendable {
    case userExplicit = "user_explicit"
    case providerInferred = "provider_inferred"
    case systemDerived = "system_derived"
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
    public let confidence: Double
    public let author: TaskContextFactAuthor
    public let supersedesFactID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        kind: TaskContextFactKind,
        scope: TaskContextFactScope,
        state: TaskContextFactState,
        value: String,
        sourceTurnID: UUID,
        confidence: Double,
        author: TaskContextFactAuthor,
        supersedesFactID: UUID? = nil,
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

        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.scope = scope
        self.state = state
        self.value = value
        self.sourceTurnID = sourceTurnID
        self.confidence = confidence
        self.author = author
        self.supersedesFactID = supersedesFactID
        self.createdAt = createdAt
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
        case confidence
        case author
        case supersedesFactID
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            sessionID: values.decode(UUID.self, forKey: .sessionID),
            kind: values.decode(TaskContextFactKind.self, forKey: .kind),
            scope: values.decode(TaskContextFactScope.self, forKey: .scope),
            state: values.decode(TaskContextFactState.self, forKey: .state),
            value: values.decode(String.self, forKey: .value),
            sourceTurnID: values.decode(UUID.self, forKey: .sourceTurnID),
            confidence: values.decode(Double.self, forKey: .confidence),
            author: values.decode(TaskContextFactAuthor.self, forKey: .author),
            supersedesFactID: values.decodeIfPresent(UUID.self, forKey: .supersedesFactID),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

public struct ConversationActionLink: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let sourceTurnID: UUID
    public let actionPlanID: String?
    public let assistantQueueItemID: String?
    public let taskID: Int64?
    public let executionReceiptID: String?
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
            reviewedFingerprint: values.decode(String.self, forKey: .reviewedFingerprint),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}
