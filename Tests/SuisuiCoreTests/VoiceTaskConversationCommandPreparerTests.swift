import XCTest
@testable import SuisuiCore

final class VoiceTaskConversationCommandPreparerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_930_000_000)

    func testGivenTaskListThenSecondTaskUpdateWhenClarifiedThenBuildsReview()
        async throws
    {
        let fixture = try makeFixture()
        let listTurnID = UUID()
        let listed = try fixture.preparer.prepare(
            transcript: "List tasks",
            sessionID: fixture.sessionID,
            sourceTurnID: listTurnID,
            selectedProjectID: nil,
            selectedTaskID: nil,
            at: now
        )

        XCTAssertEqual(
            listed?.localAnswerItems.map(\.label),
            ["Prepare review", "Submit summary"]
        )
        XCTAssertEqual(
            try fixture.store.listReferences(
                sessionID: fixture.sessionID,
                limit: 10
            ).map(\.ordinal),
            [0, 1]
        )

        let prepared = try XCTUnwrap(
            fixture.preparer.prepare(
                transcript:
                    "Update the second task due date and priority high",
                sessionID: fixture.sessionID,
                sourceTurnID: UUID(),
                selectedProjectID: nil,
                selectedTaskID: nil,
                at: now.addingTimeInterval(60)
            )
        )
        let referenceRequest = try XCTUnwrap(
            prepared.referenceRequest
        )
        XCTAssertNotNil(referenceRequest.ordinalReference)
        let resolutionDate = now.addingTimeInterval(60)
        XCTAssertEqual(
            VoiceTaskReferenceResolver(
                now: { resolutionDate }
            ).resolve(referenceRequest),
            .resolved(.task(id: 22, projectID: 7), reason: .stableOrdinal)
        )
        let orchestrator = VoiceTaskConversationOrchestrator(
            stateStore:
                SQLiteVoiceTaskConversationOrchestrationStateStore(
                    connection: fixture.connection
                )
        )
        let route = VoiceCommandRouter().route(
            transcript:
                "Update the second task due date and priority high"
        )
        let first = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: fixture.sessionID,
                sourceTurnID: UUID(),
                event: .begin(
                    route: route,
                    requiredSlots: prepared.requiredSlots,
                    intents: prepared.intents,
                    referenceRequest: prepared.referenceRequest,
                    localAnswerItems: prepared.localAnswerItems
                )
            )
        )
        guard case .clarification(let question) = first else {
            return XCTFail("Expected one due-date clarification")
        }
        XCTAssertEqual(question.slot, .dueDate)

        let outcome = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: fixture.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("2031-03-08")
            )
        )
        guard case .review(let plan) = outcome else {
            return XCTFail("Expected approval-gated review")
        }
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions[0].arguments["id"], .number(22))
        XCTAssertEqual(
            plan.actions[0].arguments["dueAt"],
            .string("2031-03-08")
        )
        XCTAssertEqual(
            plan.actions[0].arguments["priority"],
            .string("high")
        )
        XCTAssertTrue(plan.requiresApproval)
    }

    func testGivenTaskSetDriftAfterListWhenUseOrdinalThenFailsClosed()
        async throws
    {
        let fixture = try makeFixture()
        _ = try fixture.preparer.prepare(
            transcript: "List tasks",
            sessionID: fixture.sessionID,
            sourceTurnID: UUID(),
            selectedProjectID: nil,
            selectedTaskID: nil,
            at: now
        )
        _ = try SQLiteTaskStore(connection: fixture.connection).create(
            title: "Newly inserted task",
            projectID: 7
        )
        let prepared = try XCTUnwrap(
            fixture.preparer.prepare(
                transcript:
                    "Update the second task due 2031-03-08 priority high",
                sessionID: fixture.sessionID,
                sourceTurnID: UUID(),
                selectedProjectID: nil,
                selectedTaskID: nil,
                at: now.addingTimeInterval(60)
            )
        )

        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore:
                SQLiteVoiceTaskConversationOrchestrationStateStore(
                    connection: fixture.connection
                )
        ).handle(
            VoiceTaskConversationInput(
                sessionID: fixture.sessionID,
                sourceTurnID: UUID(),
                event: .begin(
                    route: VoiceCommandRouter().route(
                        transcript:
                            "Update the second task due 2031-03-08 priority high"
                    ),
                    requiredSlots: prepared.requiredSlots,
                    intents: prepared.intents,
                    referenceRequest: prepared.referenceRequest,
                    localAnswerItems: []
                )
            )
        )

        XCTAssertEqual(outcome, .blocked(.referenceUnavailable))
    }

    func testGivenTwoListsAtSameInstantWhenReloadReferencesThenUsesLatestSet()
        throws
    {
        let fixture = try makeFixture()
        let firstTurnID = UUID(
            uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff"
        )!
        _ = try fixture.preparer.prepare(
            transcript: "List tasks",
            sessionID: fixture.sessionID,
            sourceTurnID: firstTurnID,
            selectedProjectID: nil,
            selectedTaskID: nil,
            at: now
        )
        _ = try SQLiteTaskStore(connection: fixture.connection).create(
            title: "Third task",
            projectID: 7
        )
        let latestTurnID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        _ = try fixture.preparer.prepare(
            transcript: "List tasks",
            sessionID: fixture.sessionID,
            sourceTurnID: latestTurnID,
            selectedProjectID: nil,
            selectedTaskID: nil,
            at: now
        )

        let references = try fixture.store.listReferences(
            sessionID: fixture.sessionID,
            limit: 10
        )
        XCTAssertEqual(references.count, 3)
        XCTAssertTrue(
            references.allSatisfy {
                $0.sourceTurnID == latestTurnID
            }
        )
    }

    func testGivenReferenceInsertFailureWhenListThenRollsBackTurnAndReferences()
        throws
    {
        let fixture = try makeFixture()
        try fixture.connection.execute(
            """
            CREATE TRIGGER fail_second_list_reference
            BEFORE INSERT ON voice_task_conversation_references
            WHEN NEW.ordinal = 1
            BEGIN
                SELECT RAISE(ABORT, 'injected reference failure');
            END;
            """
        )

        XCTAssertThrowsError(
            try fixture.preparer.prepare(
                transcript: "List tasks",
                sessionID: fixture.sessionID,
                sourceTurnID: UUID(),
                selectedProjectID: nil,
                selectedTaskID: nil,
                at: now
            )
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                "SELECT COUNT(*) FROM voice_task_conversation_turns;"
            ),
            ["0"]
        )
        XCTAssertEqual(
            try fixture.connection.queryStrings(
                "SELECT COUNT(*) FROM voice_task_conversation_references;"
            ),
            ["0"]
        )
    }

    private struct Fixture {
        let connection: SQLiteConnection
        let store: SQLiteVoiceTaskConversationStore
        let preparer: SQLiteVoiceTaskConversationCommandPreparer
        let sessionID: UUID
    }

    private func makeFixture() throws -> Fixture {
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
            VALUES
                (11, 7, 'Prepare review', 'planned'),
                (22, 7, 'Submit summary', 'planned');
            """
        )
        let sessionID = UUID()
        let store = SQLiteVoiceTaskConversationStore(
            connection: connection
        )
        try store.createSession(
            VoiceTaskConversationSession(
                id: sessionID,
                title: "Continuity",
                entryPoint: .voiceCommand,
                createdAt: now
            )
        )
        return Fixture(
            connection: connection,
            store: store,
            preparer: SQLiteVoiceTaskConversationCommandPreparer(
                taskStore: SQLiteTaskStore(connection: connection),
                projectStore: SQLiteProjectStore(connection: connection),
                conversationStore: store
            ),
            sessionID: sessionID
        )
    }
}
