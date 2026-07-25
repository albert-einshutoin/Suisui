import Foundation

public enum TaskContextFactScopeAssessment: Equatable, Sendable {
    case unique
    case ambiguous
    case outsideAllowedScope
}

public enum TaskContextFactContentCategory: Equatable, Sendable {
    case taskContext
    case secret
    case authentication
    case payment
    case health
    case familyProfile
    case rawAudio
    case localPath
    case binary
}

public struct TaskContextFactCandidate: Equatable, Sendable {
    public let sessionID: UUID
    public let kind: TaskContextFactKind
    public let scope: TaskContextFactScope
    public let scopeAssessment: TaskContextFactScopeAssessment
    public let value: String
    public let sourceTurnID: UUID?
    public let sourceExcerptDigest: String?
    public let confidence: Double
    public let author: TaskContextFactAuthor
    public let conflictingConfirmedFactIDs: [UUID]
    public let contentCategory: TaskContextFactContentCategory
    public let createdAt: Date

    public init(
        sessionID: UUID,
        kind: TaskContextFactKind,
        scope: TaskContextFactScope,
        scopeAssessment: TaskContextFactScopeAssessment,
        value: String,
        sourceTurnID: UUID?,
        sourceExcerptDigest: String?,
        confidence: Double,
        author: TaskContextFactAuthor,
        conflictingConfirmedFactIDs: [UUID],
        contentCategory: TaskContextFactContentCategory,
        createdAt: Date
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.scope = scope
        self.scopeAssessment = scopeAssessment
        self.value = value
        self.sourceTurnID = sourceTurnID
        self.sourceExcerptDigest = sourceExcerptDigest
        self.confidence = confidence
        self.author = author
        self.conflictingConfirmedFactIDs = conflictingConfirmedFactIDs
        self.contentCategory = contentCategory
        self.createdAt = createdAt
    }
}

public enum TaskContextFactStorageDecision: Equatable, Sendable {
    case saveCandidate(TaskContextFact)
    case requireConfirmation(TaskContextFact, reason: String)
    case prohibit(reason: String)
}

public struct TaskContextFactPolicy: Sendable {
    public init() {}

    public func evaluate(
        _ candidate: TaskContextFactCandidate
    ) -> TaskContextFactStorageDecision {
        // Prohibitions are checked before confirmation rules so sensitive input
        // can never be reflected in a prompt or persisted as a proposal.
        if candidate.scopeAssessment == .outsideAllowedScope {
            return .prohibit(reason: "outside allowed Task Context scope")
        }
        if case .session = candidate.scope {
            return .prohibit(reason: "Task Context requires task or project scope")
        }
        guard candidate.contentCategory == .taskContext else {
            return .prohibit(reason: "content category is prohibited from Task Context")
        }
        guard !Self.containsSecretOrRawPath(candidate.value) else {
            return .prohibit(reason: "secret or local data is prohibited from Task Context")
        }
        guard let sourceTurnID = candidate.sourceTurnID,
              let sourceExcerptDigest = candidate.sourceExcerptDigest
        else {
            return .prohibit(reason: "source evidence is required")
        }

        let fact: TaskContextFact
        do {
            fact = try TaskContextFact(
                sessionID: candidate.sessionID,
                kind: candidate.kind,
                scope: candidate.scope,
                state: .proposed,
                value: candidate.value,
                sourceTurnID: sourceTurnID,
                sourceExcerptDigest: sourceExcerptDigest,
                confidence: candidate.confidence,
                author: candidate.author,
                createdAt: candidate.createdAt
            )
        } catch {
            return .prohibit(reason: "candidate failed Task Context validation")
        }

        if candidate.scopeAssessment == .ambiguous {
            return .requireConfirmation(fact, reason: "scope requires confirmation")
        }
        if !candidate.conflictingConfirmedFactIDs.isEmpty {
            return .requireConfirmation(fact, reason: "conflict requires confirmation")
        }
        if candidate.author == .providerInferred {
            return .requireConfirmation(fact, reason: "provider inference requires confirmation")
        }
        if candidate.kind == .decision {
            return .requireConfirmation(fact, reason: "long-term decision requires confirmation")
        }
        if [.dueDateReason, .priorityReason].contains(candidate.kind),
           candidate.author != .userExplicit
        {
            return .requireConfirmation(fact, reason: "inferred scheduling reason requires confirmation")
        }
        guard [
            .goal,
            .constraint,
            .acceptanceCriterion,
            .openQuestion,
            .followUp,
        ].contains(candidate.kind) else {
            return .requireConfirmation(fact, reason: "fact kind requires confirmation")
        }
        return .saveCandidate(fact)
    }

    public func confirm(
        _ fact: TaskContextFact,
        at date: Date
    ) throws -> TaskContextFact {
        guard fact.state == .proposed, date >= fact.createdAt else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        guard fact.expiresAt.map({ date < $0 }) ?? true else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        return try transition(fact, to: .confirmed, at: date)
    }

    public func reject(
        _ fact: TaskContextFact,
        at date: Date
    ) throws -> TaskContextFact {
        guard fact.state == .proposed, date >= fact.createdAt else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        return try transition(fact, to: .rejected, at: date)
    }

    public func expire(
        _ fact: TaskContextFact,
        at date: Date
    ) throws -> TaskContextFact {
        guard fact.state == .confirmed,
              let expiresAt = fact.expiresAt,
              date >= expiresAt
        else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }
        return try transition(fact, to: .expired, at: date, preserveExpiration: false)
    }

    public func supersede(
        _ old: TaskContextFact,
        with replacement: TaskContextFact,
        at date: Date
    ) throws -> (TaskContextFact, TaskContextFact) {
        guard old.state == .confirmed,
              replacement.state == .proposed,
              old.sessionID == replacement.sessionID,
              old.kind == replacement.kind,
              old.scope == replacement.scope,
              date >= old.createdAt,
              date >= replacement.createdAt
        else {
            throw VoiceTaskConversationDomainError.incompatibleFactTransition
        }

        let supersession = try transition(old, to: .superseded, at: date)
        let corrected = try TaskContextFact(
            sessionID: replacement.sessionID,
            kind: replacement.kind,
            scope: replacement.scope,
            state: .confirmed,
            value: replacement.value,
            sourceTurnID: replacement.sourceTurnID,
            sourceExcerptDigest: replacement.sourceExcerptDigest,
            confidence: replacement.confidence,
            author: replacement.author,
            supersedesFactID: old.id,
            expiresAt: replacement.expiresAt,
            createdAt: date
        )
        return (supersession, corrected)
    }

    private func transition(
        _ fact: TaskContextFact,
        to state: TaskContextFactState,
        at date: Date,
        preserveExpiration: Bool = true
    ) throws -> TaskContextFact {
        let expiration = preserveExpiration
            ? fact.expiresAt.flatMap { $0 > date ? $0 : nil }
            : nil
        return try TaskContextFact(
            sessionID: fact.sessionID,
            kind: fact.kind,
            scope: fact.scope,
            state: state,
            value: fact.value,
            sourceTurnID: fact.sourceTurnID,
            sourceExcerptDigest: fact.sourceExcerptDigest,
            confidence: fact.confidence,
            author: fact.author,
            supersedesFactID: fact.id,
            expiresAt: expiration,
            createdAt: date
        )
    }

    private static func containsSecretOrRawPath(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let highSignalMarkers = [
            "sk-", "ghp_", "github_pat_", "akia", "bearer ",
            "api_key=", "apikey=", "password=", "authorization:",
            "file://", "/users/", "/private/", "/volumes/",
        ]
        return highSignalMarkers.contains { lowered.contains($0) }
    }
}
