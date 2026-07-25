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
    func saveReference(_ reference: ConversationReference) throws
    func saveFact(_ write: TaskContextFactWrite) throws
    func saveSupersession(_ write: TaskContextFactSupersessionWrite) throws
    func saveActionLink(_ link: ConversationActionLink) throws
    func deleteSession(
        id: UUID,
        scope: VoiceTaskConversationDeleteScope
    ) throws -> VoiceTaskConversationDeleteResult
}
