import Foundation

public enum VoiceTaskConversationStoreError: Error, Equatable, Sendable {
    case invalidLimit
    case invalidDate
    case missingSession(UUID)
    case nonEmptyNewSession(UUID)
    case staleSession(UUID)
    case turnCursorRequiresSaveTurn(UUID)
    case missingTurn(UUID)
    case missingFact(UUID)
    case invalidFactSourceEvidence(UUID)
    case corruptRow(entity: String, identifier: String)
}

public struct VoiceTaskConversationTurnCursor: Equatable, Sendable {
    public let createdAt: Date
    public let turnID: UUID

    public init(createdAt: Date, turnID: UUID) {
        self.createdAt = createdAt
        self.turnID = turnID
    }
}

public struct VoiceTaskConversationTurnPage: Equatable, Sendable {
    public let turns: [VoiceTaskConversationTurn]
    public let nextCursor: VoiceTaskConversationTurnCursor?

    public init(
        turns: [VoiceTaskConversationTurn],
        nextCursor: VoiceTaskConversationTurnCursor?
    ) {
        self.turns = turns
        self.nextCursor = nextCursor
    }
}

public struct VoiceTaskConversationReviewBundleConflictError:
    Error,
    Equatable,
    Sendable
{
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public enum VoiceTaskConversationDeleteScope: Equatable, Sendable {
    case rawTranscripts
    case conversation
}

public struct VoiceTaskConversationDeleteResult: Equatable, Sendable {
    public let sessionsDeleted: Int
    public let turnsDeleted: Int
    public let referencesDeleted: Int
    public let actionLinksDeleted: Int
    public let rawTranscriptsDeleted: Int

    public init(
        sessionsDeleted: Int = 0,
        turnsDeleted: Int = 0,
        referencesDeleted: Int = 0,
        actionLinksDeleted: Int = 0,
        rawTranscriptsDeleted: Int = 0
    ) {
        self.sessionsDeleted = sessionsDeleted
        self.turnsDeleted = turnsDeleted
        self.referencesDeleted = referencesDeleted
        self.actionLinksDeleted = actionLinksDeleted
        self.rawTranscriptsDeleted = rawTranscriptsDeleted
    }
}

public protocol VoiceTaskConversationStore: Sendable {
    func createSession(_ session: VoiceTaskConversationSession) throws
    func updateSession(
        _ session: VoiceTaskConversationSession,
        expectedUpdatedAt: Date
    ) throws
    func loadSession(id: UUID) throws -> VoiceTaskConversationSession?
    func saveTurn(_ turn: VoiceTaskConversationTurn) throws
    func listTurns(
        sessionID: UUID,
        before: Date?,
        limit: Int
    ) throws -> [VoiceTaskConversationTurn]
    func listTurnPage(
        sessionID: UUID,
        before: VoiceTaskConversationTurnCursor?,
        limit: Int
    ) throws -> VoiceTaskConversationTurnPage
    func verifyFactSourceEvidence(
        sessionID: UUID,
        turnID: UUID,
        sourceExcerpt: String
    ) throws -> TaskContextFactSourceEvidence
    func retractFact(
        factID: UUID,
        at date: Date
    ) throws -> TaskContextFact
    func saveReference(_ reference: ConversationReference) throws
    func saveFact(_ write: TaskContextFactWrite) throws
    func saveSupersession(_ write: TaskContextFactSupersessionWrite) throws
    func saveActionLink(_ link: ConversationActionLink) throws
    func deleteSession(
        id: UUID,
        scope: VoiceTaskConversationDeleteScope
    ) throws -> VoiceTaskConversationDeleteResult
}

public protocol AtomicVoiceTaskConversationReviewBundleStore: Sendable {
    func saveReviewBundleAtomically(
        turns: [VoiceTaskConversationTurn],
        actionLink: ConversationActionLink
    ) throws
}

public extension VoiceTaskConversationStore {
    /// Compatibility implementation for custom stores.
    ///
    /// Production SQLite overrides this with one transaction. Existing custom
    /// stores retain source compatibility and preserve ordering: every Turn is
    /// written before the ActionLink can become visible.
    func saveReviewBundle(
        turns: [VoiceTaskConversationTurn],
        actionLink: ConversationActionLink
    ) throws {
        if let atomicStore =
            self as? any AtomicVoiceTaskConversationReviewBundleStore
        {
            try atomicStore.saveReviewBundleAtomically(
                turns: turns,
                actionLink: actionLink
            )
            return
        }
        for turn in turns {
            try saveTurn(turn)
        }
        try saveActionLink(actionLink)
    }
}

public protocol ConversationActionLinkStore: Sendable {
    func saveActionLink(_ link: ConversationActionLink) throws
    func latestActionLink(
        assistantQueueItemID: String
    ) throws -> ConversationActionLink?
}

public protocol VoiceTaskConversationRetentionStore: Sendable {
    func retentionSnapshot(
        for request: VoiceTaskConversationRetentionRequest
    ) throws -> VoiceTaskConversationRetentionSnapshot
    func executeRetention(
        reviewedPlan: VoiceTaskConversationRetentionPlan,
        at now: Date,
        policy: VoiceTaskConversationRetentionPolicy
    ) throws -> VoiceTaskConversationRetentionExecutionResult
}
