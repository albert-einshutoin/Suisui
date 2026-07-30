import Foundation

public enum VoiceTaskConversationAutomaticRetentionScope:
    String,
    Equatable,
    Sendable
{
    case expiredTranscripts = "expired_transcripts"
    case expiredReferences = "expired_references"
}

public enum VoiceTaskConversationAutomaticRetentionStatus:
    String,
    Equatable,
    Sendable
{
    case completed
    case alreadyCompleted = "already_completed"
    case skipped
    case failed
}

public struct VoiceTaskConversationAutomaticRetentionResult:
    Equatable,
    Sendable
{
    public let scope: VoiceTaskConversationAutomaticRetentionScope
    public let status: VoiceTaskConversationAutomaticRetentionStatus
    public let targetCount: Int
    public let reviewedFingerprint: String?
    public let failureCategory: String?

    public init(
        scope: VoiceTaskConversationAutomaticRetentionScope,
        status: VoiceTaskConversationAutomaticRetentionStatus,
        targetCount: Int,
        reviewedFingerprint: String?,
        failureCategory: String?
    ) {
        self.scope = scope
        self.status = status
        self.targetCount = targetCount
        self.reviewedFingerprint = reviewedFingerprint
        self.failureCategory = failureCategory
    }
}

public struct VoiceTaskConversationAutomaticRetentionReport:
    Equatable,
    Sendable
{
    public let results: [VoiceTaskConversationAutomaticRetentionResult]

    public init(
        results: [VoiceTaskConversationAutomaticRetentionResult]
    ) {
        self.results = results
    }

    public var completedCount: Int {
        results.filter {
            $0.status == .completed || $0.status == .alreadyCompleted
        }.count
    }

    public var skippedCount: Int {
        results.filter { $0.status == .skipped }.count
    }

    public var failureCount: Int {
        results.filter { $0.status == .failed }.count
    }
}

/// Applies only time-based policy scopes. Interactive Session and Fact
/// forgetting remain explicit user operations with their own preview.
public struct VoiceTaskConversationAutomaticRetentionRunner: Sendable {
    private let planner: VoiceTaskConversationRetentionPlanner

    public init(
        planner: VoiceTaskConversationRetentionPlanner = .init()
    ) {
        self.planner = planner
    }

    public func run(
        at now: Date,
        policy: VoiceTaskConversationRetentionPolicy,
        store: any VoiceTaskConversationRetentionStore
    ) -> VoiceTaskConversationAutomaticRetentionReport {
        let scopes: [
            (
                VoiceTaskConversationAutomaticRetentionScope,
                VoiceTaskConversationRetentionRequest
            )
        ] = [
            (.expiredTranscripts, .expiredTranscripts),
            (.expiredReferences, .expiredReferences),
        ]
        let results = scopes.map { scope, request in
            run(
                scope: scope,
                request: request,
                at: now,
                policy: policy,
                store: store
            )
        }
        return VoiceTaskConversationAutomaticRetentionReport(
            results: results
        )
    }

    private func run(
        scope: VoiceTaskConversationAutomaticRetentionScope,
        request: VoiceTaskConversationRetentionRequest,
        at now: Date,
        policy: VoiceTaskConversationRetentionPolicy,
        store: any VoiceTaskConversationRetentionStore
    ) -> VoiceTaskConversationAutomaticRetentionResult {
        var reviewedPlan: VoiceTaskConversationRetentionPlan?
        do {
            // Planning and execution remain separate reads. The Store repeats
            // the snapshot inside its transaction and rejects fingerprint
            // drift before any destructive operation.
            let snapshot = try store.retentionSnapshot(for: request)
            let plan = planner.plan(
                at: now,
                policy: policy,
                snapshot: snapshot
            )
            reviewedPlan = plan
            let targetCount = targetCount(
                plan.targets
            )
            guard !plan.operations.isEmpty else {
                return .init(
                    scope: scope,
                    status: .skipped,
                    targetCount: 0,
                    reviewedFingerprint:
                        plan.reviewedFingerprint,
                    failureCategory: nil
                )
            }
            let execution = try store.executeRetention(
                reviewedPlan: plan,
                at: now,
                policy: policy
            )
            let status:
                VoiceTaskConversationAutomaticRetentionStatus
            switch execution {
            case .completed:
                status = .completed
            case .alreadyCompleted:
                status = .alreadyCompleted
            }
            return .init(
                scope: scope,
                status: status,
                targetCount: targetCount,
                reviewedFingerprint:
                    plan.reviewedFingerprint,
                failureCategory: nil
            )
        } catch {
            return .init(
                scope: scope,
                status: .failed,
                targetCount: reviewedPlan.map {
                    targetCount($0.targets)
                } ?? 0,
                reviewedFingerprint:
                    reviewedPlan?.reviewedFingerprint,
                failureCategory: failureCategory(for: error)
            )
        }
    }

    private func targetCount(
        _ targets: VoiceTaskConversationRetentionTargets
    ) -> Int {
        targets.sessionIDs.count
            + targets.transcriptTurnIDs.count
            + targets.referenceIDs.count
            + targets.factIDs.count
            + targets.actionLinkIDs.count
            + targets.orchestrationStateSessionIDs.count
    }

    private func failureCategory(for error: Error) -> String {
        switch error {
        case VoiceTaskConversationRetentionError.requiresReview:
            "requires_review"
        case VoiceTaskConversationRetentionError.invalidExecutionResult:
            "invalid_execution_result"
        case is DatabaseError:
            "database_error"
        default:
            "retention_error"
        }
    }
}
