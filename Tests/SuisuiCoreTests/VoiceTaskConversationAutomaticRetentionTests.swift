import XCTest
@testable import SuisuiCore

final class VoiceTaskConversationAutomaticRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testRunReviewsThenExecutesTranscriptAndReferencePlans() {
        let transcript = VoiceTaskConversationRetentionTranscript(
            turnID: UUID(),
            sessionID: UUID(),
            createdAt: now.addingTimeInterval(-31 * 86_400),
            byteCount: 42
        )
        let reference = VoiceTaskConversationRetentionReference(
            id: UUID(),
            sessionID: UUID(),
            createdAt: now.addingTimeInterval(-25 * 3_600),
            expiresAt: now.addingTimeInterval(3_600)
        )
        let store = RecordingAutomaticRetentionStore(
            transcriptSnapshot: .init(
                request: .expiredTranscripts,
                transcripts: [transcript]
            ),
            referenceSnapshot: .init(
                request: .expiredReferences,
                references: [reference]
            )
        )
        XCTAssertFalse(
            VoiceTaskConversationRetentionPlanner().plan(
                at: now,
                policy: .init(),
                snapshot: store.referenceSnapshot
            ).operations.isEmpty
        )

        let report = VoiceTaskConversationAutomaticRetentionRunner().run(
            at: now,
            policy: .init(),
            store: store
        )

        XCTAssertEqual(
            store.reviewedRequests,
            [.expiredTranscripts, .expiredReferences]
        )
        XCTAssertEqual(
            store.executedPlans.map(\.request),
            [.expiredTranscripts, .expiredReferences]
        )
        XCTAssertEqual(report.completedCount, 2)
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.failureCount, 0)
    }

    func testRunContinuesWithReferenceCleanupAfterTranscriptFailure() {
        let transcript = VoiceTaskConversationRetentionTranscript(
            turnID: UUID(),
            sessionID: UUID(),
            createdAt: now.addingTimeInterval(-31 * 86_400),
            byteCount: 42
        )
        let reference = VoiceTaskConversationRetentionReference(
            id: UUID(),
            sessionID: UUID(),
            createdAt: now.addingTimeInterval(-25 * 3_600),
            expiresAt: now.addingTimeInterval(3_600)
        )
        let store = RecordingAutomaticRetentionStore(
            transcriptSnapshot: .init(
                request: .expiredTranscripts,
                transcripts: [transcript]
            ),
            referenceSnapshot: .init(
                request: .expiredReferences,
                references: [reference]
            ),
            failingExecutionRequest: .expiredTranscripts
        )

        let report = VoiceTaskConversationAutomaticRetentionRunner().run(
            at: now,
            policy: .init(),
            store: store
        )

        XCTAssertEqual(
            store.executedPlans.map(\.request),
            [.expiredTranscripts, .expiredReferences]
        )
        XCTAssertEqual(report.completedCount, 1)
        XCTAssertEqual(report.failureCount, 1)
        XCTAssertEqual(
            report.results.first?.failureCategory,
            "requires_review"
        )
        XCTAssertEqual(report.results.first?.targetCount, 1)
        XCTAssertNotNil(
            report.results.first?.reviewedFingerprint
        )
    }

    func testRunSkipsExecutionWhenReviewFindsNoExpiredTargets() {
        let store = RecordingAutomaticRetentionStore(
            transcriptSnapshot: .init(request: .expiredTranscripts),
            referenceSnapshot: .init(request: .expiredReferences)
        )

        let report = VoiceTaskConversationAutomaticRetentionRunner().run(
            at: now,
            policy: .init(),
            store: store
        )

        XCTAssertTrue(store.executedPlans.isEmpty)
        XCTAssertEqual(report.completedCount, 0)
        XCTAssertEqual(report.skippedCount, 2)
        XCTAssertEqual(report.failureCount, 0)
    }
}

private final class RecordingAutomaticRetentionStore:
    VoiceTaskConversationRetentionStore,
    @unchecked Sendable
{
    let transcriptSnapshot: VoiceTaskConversationRetentionSnapshot
    let referenceSnapshot: VoiceTaskConversationRetentionSnapshot
    let failingExecutionRequest: VoiceTaskConversationRetentionRequest?
    private(set) var reviewedRequests:
        [VoiceTaskConversationRetentionRequest] = []
    private(set) var executedPlans:
        [VoiceTaskConversationRetentionPlan] = []

    init(
        transcriptSnapshot: VoiceTaskConversationRetentionSnapshot,
        referenceSnapshot: VoiceTaskConversationRetentionSnapshot,
        failingExecutionRequest:
            VoiceTaskConversationRetentionRequest? = nil
    ) {
        self.transcriptSnapshot = transcriptSnapshot
        self.referenceSnapshot = referenceSnapshot
        self.failingExecutionRequest = failingExecutionRequest
    }

    func retentionSnapshot(
        for request: VoiceTaskConversationRetentionRequest
    ) throws -> VoiceTaskConversationRetentionSnapshot {
        reviewedRequests.append(request)
        switch request {
        case .expiredTranscripts:
            return transcriptSnapshot
        case .expiredReferences:
            return referenceSnapshot
        case .transcriptOnly, .session, .forgetFact:
            XCTFail("Automatic retention requested an interactive scope.")
            return .init(request: request)
        }
    }

    func executeRetention(
        reviewedPlan: VoiceTaskConversationRetentionPlan,
        at now: Date,
        policy: VoiceTaskConversationRetentionPolicy
    ) throws -> VoiceTaskConversationRetentionExecutionResult {
        executedPlans.append(reviewedPlan)
        if reviewedPlan.request == failingExecutionRequest {
            throw VoiceTaskConversationRetentionError.requiresReview
        }
        return .completed(planID: reviewedPlan.id)
    }
}
