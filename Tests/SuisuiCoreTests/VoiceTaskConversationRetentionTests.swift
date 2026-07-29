import XCTest
@testable import SuisuiCore

final class VoiceTaskConversationRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testGivenTranscriptAtThirtyDayBoundaryWhenPlanThenUsesExactExpiryRule() {
        let atBoundary = makeTranscript(createdAt: now.addingTimeInterval(-30 * 86_400))
        let justInside = makeTranscript(createdAt: now.addingTimeInterval(-30 * 86_400 + 1))

        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: .init(
                request: .expiredTranscripts,
                transcripts: [atBoundary, justInside]
            )
        )

        XCTAssertEqual(plan.targets.transcriptTurnIDs, [atBoundary.turnID])
        XCTAssertEqual(plan.preview.estimatedBytes, 42)
    }

    func testGivenReferenceAtTwentyFourHourBoundaryWhenPlanThenExpires() {
        let expired = makeReference(
            createdAt: now.addingTimeInterval(-24 * 3_600),
            expiresAt: now.addingTimeInterval(3_600)
        )
        let active = makeReference(
            createdAt: now.addingTimeInterval(-24 * 3_600 + 1),
            expiresAt: now.addingTimeInterval(3_600)
        )

        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: .init(request: .expiredReferences, references: [expired, active])
        )

        XCTAssertEqual(plan.targets.referenceIDs, [expired.id])
        XCTAssertEqual(plan.preview.estimatedBytes, 0)
    }

    func testGivenUnknownBytesWhenPreviewThenShowsUnknownNotZero() {
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: .init(
                request: .expiredTranscripts,
                transcripts: [makeTranscript(createdAt: now.addingTimeInterval(-31 * 86_400), bytes: nil)]
            )
        )

        XCTAssertNil(plan.preview.estimatedBytes)
        XCTAssertTrue(plan.preview.hasUnknownBytes)
        XCTAssertEqual(plan.preview.estimatedBytesDescription, "Unknown")
    }

    func testGivenTranscriptOnlyDeleteWhenPlanThenFactTaskReceiptRemain() {
        let transcript = makeTranscript(createdAt: now)
        let factID = UUID()
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: .init(
                request: .transcriptOnly(sessionID: transcript.sessionID),
                transcripts: [transcript],
                facts: [.init(id: factID, sessionID: transcript.sessionID)]
            )
        )

        XCTAssertEqual(plan.targets.transcriptTurnIDs, [transcript.turnID])
        XCTAssertTrue(plan.targets.factIDs.isEmpty)
        XCTAssertTrue(plan.safetyAssertion.preservesTasksAndReceipts)
        XCTAssertEqual(plan.recoveryImpact, .irreversibleTranscriptDeletion)
    }

    func testGivenDeleteSetChangesAfterReviewWhenExecuteThenRequiresReview() throws {
        let original = VoiceTaskConversationRetentionSnapshot(
            request: .expiredTranscripts,
            transcripts: [makeTranscript(createdAt: now.addingTimeInterval(-31 * 86_400))]
        )
        let reviewedPlan = planner.plan(at: now, policy: .init(), snapshot: original)
        let changed = VoiceTaskConversationRetentionSnapshot(
            request: .expiredTranscripts,
            transcripts: original.transcripts + [makeTranscript(createdAt: now.addingTimeInterval(-31 * 86_400))]
        )
        let executor = RecordingRetentionExecutor()
        let coordinator = VoiceTaskConversationRetentionCoordinator()

        XCTAssertThrowsError(
            try coordinator.execute(
                reviewedPlan: reviewedPlan,
                at: now,
                policy: .init(),
                currentSnapshot: changed,
                executor: executor
            )
        ) { error in
            XCTAssertEqual(error as? VoiceTaskConversationRetentionError, .requiresReview)
        }
        XCTAssertEqual(executor.executeCount, 0)
    }

    func testGivenSamePlanWhenRetriedThenKeepsIdempotentPlanIdentity() {
        let snapshot = VoiceTaskConversationRetentionSnapshot(
            request: .expiredTranscripts,
            transcripts: [makeTranscript(createdAt: now.addingTimeInterval(-31 * 86_400))]
        )

        let first = planner.plan(at: now, policy: .init(), snapshot: snapshot)
        let retry = planner.plan(at: now, policy: .init(), snapshot: snapshot)

        XCTAssertEqual(first.id, retry.id)
        XCTAssertEqual(first.reviewedFingerprint, retry.reviewedFingerprint)
    }

    func testGivenTranscriptOnlyDeleteWhenExecuteThenFactTaskReceiptRemain()
        throws
    {
        let fixture = try makeSQLiteFixture()
        let fact = try saveConfirmedFact(in: fixture)
        let link = try saveActionLink(in: fixture)
        let snapshot = try fixture.store.retentionSnapshot(
            for: .transcriptOnly(sessionID: fixture.session.id)
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )

        let result = try fixture.store.executeRetention(
            reviewedPlan: plan,
            at: now,
            policy: .init()
        )

        XCTAssertEqual(result, .completed(planID: plan.id))
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT COUNT(*) FROM voice_task_conversation_turns
                WHERE id = ? AND raw_transcript IS NOT NULL;
                """,
                parameters: [.text(fixture.turn.id.uuidString)]
            ),
            ["0"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT confirmed_text FROM voice_task_conversation_turns
                WHERE id = ?;
                """,
                parameters: [.text(fixture.turn.id.uuidString)]
            ),
            ["Sign the release"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                "SELECT COUNT(*) FROM task_context_facts WHERE id = ?;",
                parameters: [.text(fact.id.uuidString)]
            ),
            ["1"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                "SELECT COUNT(*) FROM tasks WHERE id = 11;"
            ),
            ["1"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT execution_receipt_id
                FROM conversation_action_links
                WHERE id = ?;
                """,
                parameters: [.text(link.id.uuidString)]
            ),
            ["receipt-retained"]
        )
    }

    func testGivenExpiredTranscriptWhenExecuteThenSensitiveOrchestrationStateIsRemovedButConfirmedDisplayTextRemains()
        throws
    {
        let fixture = try makeSQLiteFixture()
        let stateStore = SQLiteVoiceTaskConversationOrchestrationStateStore(
            connection: fixture.connection
        )
        try stateStore.save(makeOrchestrationState(in: fixture))
        let snapshot = try fixture.store.retentionSnapshot(
            for: .expiredTranscripts
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )

        XCTAssertEqual(
            plan.targets.orchestrationStateSessionIDs,
            [fixture.session.id]
        )
        XCTAssertEqual(plan.preview.orchestrationStateCount, 1)
        XCTAssertTrue(
            plan.operations.contains(.deleteOrchestrationState)
        )
        _ = try fixture.store.executeRetention(
            reviewedPlan: plan,
            at: now,
            policy: .init()
        )

        XCTAssertNil(try stateStore.load(sessionID: fixture.session.id))
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT COUNT(*)
                FROM voice_task_conversation_turns
                WHERE id = ? AND raw_transcript IS NOT NULL;
                """,
                parameters: [.text(fixture.turn.id.uuidString)]
            ),
            ["0"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT confirmed_text
                FROM voice_task_conversation_turns
                WHERE id = ?;
                """,
                parameters: [.text(fixture.turn.id.uuidString)]
            ),
            ["Sign the release"]
        )
    }

    func testGivenOrchestrationStateAddedAfterReviewWhenExecuteThenRequiresReview()
        throws
    {
        let fixture = try makeSQLiteFixture()
        let snapshot = try fixture.store.retentionSnapshot(
            for: .expiredTranscripts
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )
        let stateStore = SQLiteVoiceTaskConversationOrchestrationStateStore(
            connection: fixture.connection
        )
        try stateStore.save(makeOrchestrationState(in: fixture))

        XCTAssertThrowsError(
            try fixture.store.executeRetention(
                reviewedPlan: plan,
                at: now,
                policy: .init()
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationRetentionError,
                .requiresReview
            )
        }
        XCTAssertNotNil(try stateStore.load(sessionID: fixture.session.id))
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT COUNT(*)
                FROM voice_task_conversation_turns
                WHERE id = ? AND raw_transcript IS NOT NULL;
                """,
                parameters: [.text(fixture.turn.id.uuidString)]
            ),
            ["1"]
        )
    }

    func testGivenForgetFactWhenExecuteThenTaskAndReceiptRemain() throws {
        let fixture = try makeSQLiteFixture()
        let fact = try saveConfirmedFact(in: fixture)
        _ = try saveActionLink(in: fixture)
        let snapshot = try fixture.store.retentionSnapshot(
            for: .forgetFact(id: fact.id)
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )

        _ = try fixture.store.executeRetention(
            reviewedPlan: plan,
            at: now,
            policy: .init()
        )

        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT state FROM task_context_facts
                WHERE supersedes_fact_id = ?;
                """,
                parameters: [.text(fact.id.uuidString)]
            ),
            ["retracted"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                "SELECT COUNT(*) FROM tasks WHERE id = 11;"
            ),
            ["1"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT execution_receipt_id
                FROM conversation_action_links;
                """
            ),
            ["receipt-retained"]
        )
    }

    func testGivenRetractedFactHistoryWhenSessionPlanThenDoesNotTargetItAgain()
        throws
    {
        let fixture = try makeSQLiteFixture()
        let confirmed = try saveConfirmedFact(in: fixture)
        let retracted = try fixture.store.retractFact(
            factID: confirmed.id,
            at: now
        )

        let snapshot = try fixture.store.retentionSnapshot(
            for: .session(
                sessionID: fixture.session.id,
                includeEligibleFacts: true
            )
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )

        XCTAssertFalse(plan.targets.factIDs.contains(retracted.id))
    }

    func testGivenSessionDeleteWhenExecuteThenConversationRowsAreRemoved()
        throws
    {
        let fixture = try makeSQLiteFixture()
        let stateStore = SQLiteVoiceTaskConversationOrchestrationStateStore(
            connection: fixture.connection
        )
        try stateStore.save(makeOrchestrationState(in: fixture))
        let reference = try saveReference(
            in: fixture,
            id: UUID(
                uuidString: "20000000-0000-0000-0000-000000000001"
            )!
        )
        let link = try saveActionLink(in: fixture)
        let snapshot = try fixture.store.retentionSnapshot(
            for: .session(
                sessionID: fixture.session.id,
                includeEligibleFacts: false
            )
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )

        XCTAssertEqual(
            plan.targets.orchestrationStateSessionIDs,
            [fixture.session.id]
        )
        _ = try fixture.store.executeRetention(
            reviewedPlan: plan,
            at: now,
            policy: .init()
        )

        for (table, identifierColumn, id) in [
            ("voice_task_conversation_sessions", "id", fixture.session.id),
            ("voice_task_conversation_turns", "id", fixture.turn.id),
            ("voice_task_conversation_references", "id", reference.id),
            ("conversation_action_links", "id", link.id),
            (
                "voice_task_conversation_orchestration_states",
                "session_id",
                fixture.session.id
            ),
        ] {
            XCTAssertEqual(
                try fixture.connection.queryStrings(
                    """
                    SELECT COUNT(*) FROM \(table)
                    WHERE \(identifierColumn) = ?;
                    """,
                    parameters: [.text(id.uuidString)]
                ),
                ["0"]
            )
        }
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                "SELECT COUNT(*) FROM tasks WHERE id = 11;"
            ),
            ["1"]
        )
    }

    func testGivenSecondDeleteFailsWhenTransactionThenRollsBackAll()
        throws
    {
        let fixture = try makeSQLiteFixture()
        let stateStore = SQLiteVoiceTaskConversationOrchestrationStateStore(
            connection: fixture.connection
        )
        try stateStore.save(makeOrchestrationState(in: fixture))
        let first = try saveReference(
            in: fixture,
            id: UUID(
                uuidString: "20000000-0000-0000-0000-000000000001"
            )!
        )
        let second = try saveReference(
            in: fixture,
            id: UUID(
                uuidString: "20000000-0000-0000-0000-000000000002"
            )!
        )
        let snapshot = try fixture.store.retentionSnapshot(
            for: .session(
                sessionID: fixture.session.id,
                includeEligibleFacts: false
            )
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )
        try fixture.connection.execute(
            """
            CREATE TRIGGER fail_second_retention_reference
            BEFORE DELETE ON voice_task_conversation_references
            WHEN OLD.id = '\(second.id.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'injected retention failure');
            END;
            """
        )

        XCTAssertThrowsError(
            try fixture.store.executeRetention(
                reviewedPlan: plan,
                at: now,
                policy: .init()
            )
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT id FROM voice_task_conversation_references
                ORDER BY id;
                """
            ),
            [first.id.uuidString, second.id.uuidString]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT COUNT(*) FROM voice_task_conversation_sessions
                WHERE id = ?;
                """,
                parameters: [.text(fixture.session.id.uuidString)]
            ),
            ["1"]
        )
        XCTAssertNotNil(try stateStore.load(sessionID: fixture.session.id))
    }

    func testGivenCompletedPlanWhenRetriedThenIsIdempotent() throws {
        let fixture = try makeSQLiteFixture()
        let snapshot = try fixture.store.retentionSnapshot(
            for: .transcriptOnly(sessionID: fixture.session.id)
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )

        XCTAssertEqual(
            try fixture.store.executeRetention(
                reviewedPlan: plan,
                at: now,
                policy: .init()
            ),
            .completed(planID: plan.id)
        )
        XCTAssertEqual(
            try fixture.store.executeRetention(
                reviewedPlan: plan,
                at: now,
                policy: .init()
            ),
            .alreadyCompleted(planID: plan.id)
        )
    }

    func testGivenDeleteSetChangesAfterReviewWhenSQLiteExecutesThenRequiresReview()
        throws
    {
        let fixture = try makeSQLiteFixture()
        let snapshot = try fixture.store.retentionSnapshot(
            for: .expiredTranscripts
        )
        let plan = planner.plan(
            at: now,
            policy: .init(),
            snapshot: snapshot
        )
        try fixture.store.saveTurn(
            VoiceTaskConversationTurn(
                sessionID: fixture.session.id,
                author: .user,
                rawTranscript: "new expired raw transcript",
                userConfirmedText: "Second confirmed request",
                createdAt: now.addingTimeInterval(-30 * 86_400)
            )
        )

        XCTAssertThrowsError(
            try fixture.store.executeRetention(
                reviewedPlan: plan,
                at: now,
                policy: .init()
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationRetentionError,
                .requiresReview
            )
        }
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                """
                SELECT COUNT(*) FROM voice_task_conversation_turns
                WHERE raw_transcript IS NOT NULL;
                """
            ),
            ["2"]
        )
    }

    private var planner: VoiceTaskConversationRetentionPlanner {
        VoiceTaskConversationRetentionPlanner()
    }

    private struct SQLiteFixture {
        let connection: SQLiteConnection
        let store: SQLiteVoiceTaskConversationStore
        let session: VoiceTaskConversationSession
        let turn: VoiceTaskConversationTurn
    }

    private func makeSQLiteFixture() throws -> SQLiteFixture {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        try connection.execute(
            """
            INSERT INTO projects (id, title, status)
            VALUES (7, 'Release', 'active');
            INSERT INTO tasks (id, project_id, title, status)
            VALUES (11, 7, 'Sign build', 'planned');
            """
        )
        let store = SQLiteVoiceTaskConversationStore(
            connection: connection
        )
        let session = VoiceTaskConversationSession(
            title: "Release preparation",
            entryPoint: .taskInspector,
            activeProjectID: 7,
            activeTaskID: 11,
            createdAt: now.addingTimeInterval(-40 * 86_400)
        )
        try store.createSession(session)
        let turn = try VoiceTaskConversationTurn(
            sessionID: session.id,
            author: .user,
            rawTranscript: "raw sign the release",
            userConfirmedText: "Sign the release",
            createdAt: now.addingTimeInterval(-31 * 86_400)
        )
        try store.saveTurn(turn)
        return .init(
            connection: connection,
            store: store,
            session: session,
            turn: turn
        )
    }

    private func saveReference(
        in fixture: SQLiteFixture,
        id: UUID
    ) throws -> ConversationReference {
        let reference = try ConversationReference(
            id: id,
            sessionID: fixture.session.id,
            target: .task(11),
            sourceTurnID: fixture.turn.id,
            ordinal: 0,
            orderingFingerprint: "task-11",
            expiresAt: now.addingTimeInterval(86_400),
            createdAt: fixture.turn.createdAt
        )
        try fixture.store.saveReference(reference)
        return reference
    }

    private func saveActionLink(
        in fixture: SQLiteFixture
    ) throws -> ConversationActionLink {
        let link = try ConversationActionLink(
            sessionID: fixture.session.id,
            sourceTurnID: fixture.turn.id,
            actionPlanID: "plan-retained",
            assistantQueueItemID: "queue-retained",
            taskID: 11,
            executionReceiptID: "receipt-retained",
            operation: .taskUpdated,
            reviewedFingerprint: "reviewed-retained",
            createdAt: fixture.turn.createdAt
        )
        try fixture.store.saveActionLink(link)
        return link
    }

    private func saveConfirmedFact(
        in fixture: SQLiteFixture
    ) throws -> TaskContextFact {
        let evidence = try fixture.store.verifyFactSourceEvidence(
            sessionID: fixture.session.id,
            turnID: fixture.turn.id,
            sourceExcerpt: "Sign the release"
        )
        let candidate = TaskContextFactCandidate(
            sessionID: fixture.session.id,
            kind: .constraint,
            scope: .task(11),
            scopeAssessment: .unique,
            value: "Sign before distribution",
            sourceEvidence: evidence,
            confidence: 1,
            author: .userExplicit,
            conflictingConfirmedFactIDs: [],
            contentCategory: .taskContext,
            createdAt: fixture.turn.createdAt
        )
        let policy = TaskContextFactPolicy()
        let proposed: TaskContextFact
        switch policy.evaluate(candidate) {
        case .saveCandidate(let fact),
             .requireConfirmation(let fact, _):
            proposed = fact
        case .prohibit:
            throw VoiceTaskConversationDomainError
                .unauthorizedFactPersistence
        }
        let confirmed = try policy.confirm(
            proposed,
            at: fixture.turn.createdAt.addingTimeInterval(1)
        )
        try fixture.store.saveFact(
            try policy.persistenceWrite(for: proposed)
        )
        try fixture.store.saveFact(
            try policy.persistenceWrite(for: confirmed)
        )
        return confirmed
    }

    private func makeOrchestrationState(
        in fixture: SQLiteFixture
    ) -> VoiceTaskConversationOrchestrationState {
        let route = VoiceCommandRoutingResult(
            originalTranscript: "raw sign the release",
            normalizedTranscript: "raw sign the release",
            intent: .taskCreate,
            interpretationSummary: "Create a release task",
            confidence: 0.9,
            decision: .reviewOnly
        )
        return VoiceTaskConversationOrchestrationState(
            sessionID: fixture.session.id,
            originalSourceTurnID: fixture.turn.id,
            route: route,
            intents: [],
            clarification: ClarificationSession(
                route: route,
                requiredSlots: [.project]
            )
        )
    }

    private func makeTranscript(
        createdAt: Date,
        bytes: Int64? = 42,
        sessionID: UUID = UUID()
    ) -> VoiceTaskConversationRetentionTranscript {
        .init(turnID: UUID(), sessionID: sessionID, createdAt: createdAt, byteCount: bytes)
    }

    private func makeReference(
        createdAt: Date,
        expiresAt: Date
    ) -> VoiceTaskConversationRetentionReference {
        .init(
            id: UUID(),
            sessionID: UUID(),
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }
}

private final class RecordingRetentionExecutor: VoiceTaskConversationRetentionPlanExecutor, @unchecked Sendable {
    private(set) var executeCount = 0

    func execute(_ plan: VoiceTaskConversationRetentionPlan) throws -> VoiceTaskConversationRetentionExecutionResult {
        executeCount += 1
        return .completed(planID: plan.id)
    }
}
