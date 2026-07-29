import Foundation

public enum VoiceTaskConversationRawAudioRetentionDisposition: String, Equatable, Sendable {
    /// #321 owns attachment/file lifecycle. This planner intentionally cannot
    /// enumerate paths or issue filesystem deletes from a conversation preview.
    case delegatedToAttachmentRetention
}

/// Retention is intentionally modelled separately from the conversation Store.
/// The planner never receives raw transcript/audio values, so previews cannot
/// accidentally turn a retention audit into another sensitive-content store.
public struct VoiceTaskConversationRetentionPolicy: Equatable, Sendable {
    public let transcriptRetention: TimeInterval
    public let referenceRetention: TimeInterval
    public let rawAudioDisposition: VoiceTaskConversationRawAudioRetentionDisposition

    public init(
        transcriptRetention: TimeInterval = 30 * 86_400,
        referenceRetention: TimeInterval = 24 * 86_400,
        rawAudioDisposition: VoiceTaskConversationRawAudioRetentionDisposition =
            .delegatedToAttachmentRetention
    ) {
        self.transcriptRetention = transcriptRetention
        self.referenceRetention = referenceRetention
        self.rawAudioDisposition = rawAudioDisposition
    }
}

public struct VoiceTaskConversationRetentionTranscript: Equatable, Sendable {
    public let turnID: UUID
    public let sessionID: UUID
    public let createdAt: Date
    /// `nil` means the storage adapter could not cheaply establish a size. It
    /// must remain unknown rather than being presented as reclaimed zero bytes.
    public let byteCount: Int64?

    public init(
        turnID: UUID,
        sessionID: UUID,
        createdAt: Date,
        byteCount: Int64?
    ) {
        self.turnID = turnID
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.byteCount = byteCount.map { max(0, $0) }
    }
}

public struct VoiceTaskConversationRetentionSession: Equatable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct VoiceTaskConversationRetentionReference: Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let createdAt: Date
    public let expiresAt: Date

    public init(
        id: UUID,
        sessionID: UUID,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct VoiceTaskConversationRetentionFact: Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    /// Facts are Task/Project-scoped and therefore do not become session-delete
    /// targets unless the caller has explicitly classified them as eligible.
    public let isEligibleForSessionDeletion: Bool

    public init(
        id: UUID,
        sessionID: UUID,
        isEligibleForSessionDeletion: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.isEligibleForSessionDeletion = isEligibleForSessionDeletion
    }
}

public struct VoiceTaskConversationRetentionActionLink: Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID

    public init(id: UUID, sessionID: UUID) {
        self.id = id
        self.sessionID = sessionID
    }
}

public enum VoiceTaskConversationRetentionRequest: Equatable, Sendable {
    case expiredTranscripts
    case transcriptOnly(sessionID: UUID?)
    case expiredReferences
    case session(sessionID: UUID, includeEligibleFacts: Bool)
    case forgetFact(id: UUID)
}

public struct VoiceTaskConversationRetentionSnapshot: Equatable, Sendable {
    public let request: VoiceTaskConversationRetentionRequest
    public let sessions: [VoiceTaskConversationRetentionSession]
    public let transcripts: [VoiceTaskConversationRetentionTranscript]
    public let references: [VoiceTaskConversationRetentionReference]
    public let facts: [VoiceTaskConversationRetentionFact]
    public let actionLinks: [VoiceTaskConversationRetentionActionLink]

    public init(
        request: VoiceTaskConversationRetentionRequest,
        sessions: [VoiceTaskConversationRetentionSession] = [],
        transcripts: [VoiceTaskConversationRetentionTranscript] = [],
        references: [VoiceTaskConversationRetentionReference] = [],
        facts: [VoiceTaskConversationRetentionFact] = [],
        actionLinks: [VoiceTaskConversationRetentionActionLink] = []
    ) {
        self.request = request
        self.sessions = sessions
        self.transcripts = transcripts
        self.references = references
        self.facts = facts
        self.actionLinks = actionLinks
    }
}

public struct VoiceTaskConversationRetentionTargets: Equatable, Sendable {
    public let sessionIDs: [UUID]
    public let transcriptTurnIDs: [UUID]
    public let referenceIDs: [UUID]
    public let factIDs: [UUID]
    public let actionLinkIDs: [UUID]

    public init(
        sessionIDs: [UUID] = [],
        transcriptTurnIDs: [UUID] = [],
        referenceIDs: [UUID] = [],
        factIDs: [UUID] = [],
        actionLinkIDs: [UUID] = []
    ) {
        self.sessionIDs = sessionIDs
        self.transcriptTurnIDs = transcriptTurnIDs
        self.referenceIDs = referenceIDs
        self.factIDs = factIDs
        self.actionLinkIDs = actionLinkIDs
    }
}

public struct VoiceTaskConversationRetentionPreview: Equatable, Sendable {
    public let transcriptCount: Int
    public let referenceCount: Int
    public let sessionCount: Int
    public let factCount: Int
    public let actionLinkCount: Int
    public let estimatedBytes: Int64?
    public let hasUnknownBytes: Bool

    public init(
        transcriptCount: Int,
        referenceCount: Int,
        sessionCount: Int,
        factCount: Int,
        actionLinkCount: Int,
        estimatedBytes: Int64?,
        hasUnknownBytes: Bool
    ) {
        self.transcriptCount = transcriptCount
        self.referenceCount = referenceCount
        self.sessionCount = sessionCount
        self.factCount = factCount
        self.actionLinkCount = actionLinkCount
        self.estimatedBytes = estimatedBytes
        self.hasUnknownBytes = hasUnknownBytes
    }

    /// UI can localize this label, but its semantic distinction is fixed:
    /// unknown capacity is never equivalent to a measured 0 bytes.
    public var estimatedBytesDescription: String {
        estimatedBytes.map(String.init) ?? "Unknown"
    }
}

public enum VoiceTaskConversationRetentionOperation: String, Equatable, Sendable {
    case deleteTranscript
    case deleteReference
    case deleteSession
    case deleteActionLink
    case forgetFact
}

public enum VoiceTaskConversationRetentionRecoveryImpact: String, Equatable, Sendable {
    case irreversibleTranscriptDeletion
    case expiredReferenceCleanup
    case irreversibleSessionDeletion
    case factMarkedRejected
}

public struct VoiceTaskConversationRetentionSafetyAssertion: Equatable, Sendable {
    /// A retention plan has no Task, Project, Action Plan, or Receipt deletion
    /// operation. Store adapters must enforce this boundary transactionally.
    public let preservesTasksAndReceipts: Bool

    public init(preservesTasksAndReceipts: Bool = true) {
        self.preservesTasksAndReceipts = preservesTasksAndReceipts
    }
}

public struct VoiceTaskConversationRetentionPlan: Equatable, Sendable {
    /// The deterministic identity lets an adapter treat an already committed
    /// request as a retry instead of executing a destructive operation twice.
    public let id: String
    public let request: VoiceTaskConversationRetentionRequest
    public let reviewedFingerprint: String
    public let targets: VoiceTaskConversationRetentionTargets
    public let preview: VoiceTaskConversationRetentionPreview
    public let operations: [VoiceTaskConversationRetentionOperation]
    public let recoveryImpact: VoiceTaskConversationRetentionRecoveryImpact
    public let safetyAssertion: VoiceTaskConversationRetentionSafetyAssertion

    public init(
        id: String,
        request: VoiceTaskConversationRetentionRequest,
        reviewedFingerprint: String,
        targets: VoiceTaskConversationRetentionTargets,
        preview: VoiceTaskConversationRetentionPreview,
        operations: [VoiceTaskConversationRetentionOperation],
        recoveryImpact: VoiceTaskConversationRetentionRecoveryImpact,
        safetyAssertion: VoiceTaskConversationRetentionSafetyAssertion = .init()
    ) {
        self.id = id
        self.request = request
        self.reviewedFingerprint = reviewedFingerprint
        self.targets = targets
        self.preview = preview
        self.operations = operations
        self.recoveryImpact = recoveryImpact
        self.safetyAssertion = safetyAssertion
    }
}

public struct VoiceTaskConversationRetentionPlanner: Sendable {
    public init() {}

    public func plan(
        at now: Date,
        policy: VoiceTaskConversationRetentionPolicy,
        snapshot: VoiceTaskConversationRetentionSnapshot
    ) -> VoiceTaskConversationRetentionPlan {
        let targets = targets(at: now, policy: policy, snapshot: snapshot)
        let selectedTranscriptIDs = Set(targets.transcriptTurnIDs)
        let selectedTranscripts = snapshot.transcripts.filter {
            selectedTranscriptIDs.contains($0.turnID)
        }
        var hasUnknownBytes = false
        var totalBytes: Int64 = 0
        for transcript in selectedTranscripts {
            guard let byteCount = transcript.byteCount else {
                hasUnknownBytes = true
                continue
            }
            let addition = totalBytes.addingReportingOverflow(byteCount)
            // A saturated preview would claim a false, precise reclaimable
            // capacity. Overflow is therefore another form of unknown size.
            guard !addition.overflow else {
                hasUnknownBytes = true
                continue
            }
            totalBytes = addition.partialValue
        }
        let estimatedBytes: Int64? = hasUnknownBytes ? nil : totalBytes
        let preview = VoiceTaskConversationRetentionPreview(
            transcriptCount: targets.transcriptTurnIDs.count,
            referenceCount: targets.referenceIDs.count,
            sessionCount: targets.sessionIDs.count,
            factCount: targets.factIDs.count,
            actionLinkCount: targets.actionLinkIDs.count,
            estimatedBytes: estimatedBytes,
            hasUnknownBytes: hasUnknownBytes
        )
        let operations = operations(for: targets, request: snapshot.request)
        let fingerprint = fingerprint(
            request: snapshot.request,
            policy: policy,
            targets: targets
        )
        return VoiceTaskConversationRetentionPlan(
            id: "retention:" + fingerprint,
            request: snapshot.request,
            reviewedFingerprint: fingerprint,
            targets: targets,
            preview: preview,
            operations: operations,
            recoveryImpact: recoveryImpact(for: snapshot.request),
            safetyAssertion: .init()
        )
    }

    private func targets(
        at now: Date,
        policy: VoiceTaskConversationRetentionPolicy,
        snapshot: VoiceTaskConversationRetentionSnapshot
    ) -> VoiceTaskConversationRetentionTargets {
        // Date compares absolute instants; this gives the same boundary result
        // for every locale/time zone and makes fixed-clock tests reproducible.
        let transcriptExpiry = now.addingTimeInterval(-policy.transcriptRetention)
        let referenceExpiry = now.addingTimeInterval(-policy.referenceRetention)
        switch snapshot.request {
        case .expiredTranscripts:
            return .init(transcriptTurnIDs: sortedIDs(snapshot.transcripts.filter {
                $0.createdAt <= transcriptExpiry
            }.map(\.turnID)))
        case .transcriptOnly(let sessionID):
            return .init(transcriptTurnIDs: sortedIDs(snapshot.transcripts.filter { transcript in
                sessionID.map { transcript.sessionID == $0 } ?? true
            }.map(\.turnID)))
        case .expiredReferences:
            return .init(referenceIDs: sortedIDs(snapshot.references.filter {
                // Existing ordinal References can carry a shorter expiry, but
                // retention never lets one outlive the policy's 24-hour cap.
                $0.expiresAt <= now || $0.createdAt <= referenceExpiry
            }.map(\.id)))
        case .session(let sessionID, let includeEligibleFacts):
            let sessionExists = snapshot.sessions.contains { $0.id == sessionID }
            return .init(
                sessionIDs: sessionExists ? [sessionID] : [],
                transcriptTurnIDs: sortedIDs(snapshot.transcripts.filter {
                    $0.sessionID == sessionID
                }.map(\.turnID)),
                referenceIDs: sortedIDs(snapshot.references.filter {
                    $0.sessionID == sessionID
                }.map(\.id)),
                factIDs: includeEligibleFacts ? sortedIDs(snapshot.facts.filter {
                    $0.sessionID == sessionID && $0.isEligibleForSessionDeletion
                }.map(\.id)) : [],
                actionLinkIDs: sortedIDs(snapshot.actionLinks.filter {
                    $0.sessionID == sessionID
                }.map(\.id))
            )
        case .forgetFact(let factID):
            return .init(factIDs: snapshot.facts.contains { $0.id == factID } ? [factID] : [])
        }
    }

    private func operations(
        for targets: VoiceTaskConversationRetentionTargets,
        request: VoiceTaskConversationRetentionRequest
    ) -> [VoiceTaskConversationRetentionOperation] {
        var result: [VoiceTaskConversationRetentionOperation] = []
        if !targets.transcriptTurnIDs.isEmpty { result.append(.deleteTranscript) }
        if !targets.referenceIDs.isEmpty { result.append(.deleteReference) }
        if !targets.actionLinkIDs.isEmpty { result.append(.deleteActionLink) }
        if !targets.sessionIDs.isEmpty { result.append(.deleteSession) }
        if !targets.factIDs.isEmpty {
            // Forgetting records a rejected/retracted state; it is not a cascade
            // delete into the Task, Project, or receipt that once used the Fact.
            result.append(.forgetFact)
        }
        return result
    }

    private func recoveryImpact(
        for request: VoiceTaskConversationRetentionRequest
    ) -> VoiceTaskConversationRetentionRecoveryImpact {
        switch request {
        case .expiredTranscripts, .transcriptOnly:
            .irreversibleTranscriptDeletion
        case .expiredReferences:
            .expiredReferenceCleanup
        case .session:
            .irreversibleSessionDeletion
        case .forgetFact:
            .factMarkedRejected
        }
    }

    private func fingerprint(
        request: VoiceTaskConversationRetentionRequest,
        policy: VoiceTaskConversationRetentionPolicy,
        targets: VoiceTaskConversationRetentionTargets
    ) -> String {
        AssistantQueueMutationRevision.canonicalDigest(
            [requestKey(request), String(policy.transcriptRetention), String(policy.referenceRetention)]
                + targets.sessionIDs.map { "session:" + $0.uuidString }
                + targets.transcriptTurnIDs.map { "transcript:" + $0.uuidString }
                + targets.referenceIDs.map { "reference:" + $0.uuidString }
                + targets.factIDs.map { "fact:" + $0.uuidString }
                + targets.actionLinkIDs.map { "action-link:" + $0.uuidString }
        )
    }

    private func requestKey(_ request: VoiceTaskConversationRetentionRequest) -> String {
        switch request {
        case .expiredTranscripts: "expired-transcripts"
        case .transcriptOnly(let sessionID): "transcript-only:" + (sessionID?.uuidString ?? "all")
        case .expiredReferences: "expired-references"
        case .session(let sessionID, let includeEligibleFacts):
            "session:" + sessionID.uuidString + ":" + String(includeEligibleFacts)
        case .forgetFact(let id): "forget-fact:" + id.uuidString
        }
    }

    private func sortedIDs(_ identifiers: [UUID]) -> [UUID] {
        Array(Set(identifiers)).sorted { $0.uuidString < $1.uuidString }
    }
}

public enum VoiceTaskConversationRetentionError: Error, Equatable, Sendable {
    case requiresReview
    case invalidExecutionResult
}

public enum VoiceTaskConversationRetentionExecutionResult: Equatable, Sendable {
    case completed(planID: String)
    case alreadyCompleted(planID: String)
}

/// The Store layer supplies the transaction. Keeping it injected lets Core
/// verify review drift before any SQLite/file operation begins.
public protocol VoiceTaskConversationRetentionPlanExecutor: Sendable {
    func execute(
        _ plan: VoiceTaskConversationRetentionPlan
    ) throws -> VoiceTaskConversationRetentionExecutionResult
}

public struct VoiceTaskConversationRetentionCoordinator: Sendable {
    private let planner: VoiceTaskConversationRetentionPlanner

    public init(planner: VoiceTaskConversationRetentionPlanner = .init()) {
        self.planner = planner
    }

    public func execute(
        reviewedPlan: VoiceTaskConversationRetentionPlan,
        at now: Date,
        policy: VoiceTaskConversationRetentionPolicy,
        currentSnapshot: VoiceTaskConversationRetentionSnapshot,
        executor: any VoiceTaskConversationRetentionPlanExecutor
    ) throws -> VoiceTaskConversationRetentionExecutionResult {
        let currentPlan = planner.plan(at: now, policy: policy, snapshot: currentSnapshot)
        guard currentPlan.reviewedFingerprint == reviewedPlan.reviewedFingerprint,
              currentPlan.targets == reviewedPlan.targets
        else {
            throw VoiceTaskConversationRetentionError.requiresReview
        }
        let result = try executor.execute(reviewedPlan)
        guard result.planID == reviewedPlan.id else {
            throw VoiceTaskConversationRetentionError.invalidExecutionResult
        }
        return result
    }
}

private extension VoiceTaskConversationRetentionExecutionResult {
    var planID: String {
        switch self {
        case .completed(let planID), .alreadyCompleted(let planID): planID
        }
    }
}
