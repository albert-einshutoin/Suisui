import XCTest
@testable import SuisuiCore

final class VoiceTaskConversationOrchestrationStateStoreTests: XCTestCase {
    func testSaveThenReopenRestoresOriginalIntentAndClarificationTrail() throws {
        let fixture = try TemporaryOrchestrationDatabase()
        let sessionID = UUID()
        let initial = makeState(sessionID: sessionID)
        let firstStore = try SQLiteVoiceTaskConversationOrchestrationStateStore(
            path: fixture.url.path
        )
        try firstStore.save(initial)

        var answered = initial
        XCTAssertEqual(answered.clarification.answer("Launch"), .needsClarification)
        try firstStore.save(answered)

        let reopened = try SQLiteVoiceTaskConversationOrchestrationStateStore(
            path: fixture.url.path
        )
        let restored = try XCTUnwrap(reopened.load(sessionID: sessionID))

        XCTAssertEqual(restored, answered)
        XCTAssertEqual(restored.route.originalTranscript, "リリースタスクを作成して")
        XCTAssertEqual(restored.clarification.turns.map(\.response), ["Launch"])
    }

    func testRemoveIsIdempotent() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let store = SQLiteVoiceTaskConversationOrchestrationStateStore(
            connection: connection
        )
        let state = makeState()
        try store.save(state)

        try store.remove(sessionID: state.sessionID)
        try store.remove(sessionID: state.sessionID)

        XCTAssertNil(try store.load(sessionID: state.sessionID))
    }

    func testCorruptPayloadFailsClosed() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let sessionID = UUID()
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_orchestration_states (
                session_id, payload, updated_at
            )
            VALUES (?, ?, ?);
            """,
            parameters: [
                .text(sessionID.uuidString),
                .blob(Data("not-json".utf8)),
                .real(1),
            ]
        )
        let store = SQLiteVoiceTaskConversationOrchestrationStateStore(
            connection: connection
        )

        XCTAssertThrowsError(try store.load(sessionID: sessionID)) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationOrchestrationStateStoreError,
                .corruptState(sessionID)
            )
        }
    }

    private func makeState(
        sessionID: UUID = UUID()
    ) -> VoiceTaskConversationOrchestrationState {
        let route = VoiceCommandRoutingResult(
            originalTranscript: "リリースタスクを作成して",
            normalizedTranscript: "リリースタスクを作成して",
            intent: .taskCreate,
            interpretationSummary: "Create a task",
            confidence: 0.9,
            decision: .reviewOnly
        )
        return VoiceTaskConversationOrchestrationState(
            sessionID: sessionID,
            originalSourceTurnID: UUID(),
            route: route,
            intents: [
                ConversationTaskIntent(
                    utterance: route.originalTranscript,
                    operation: .create,
                    tool: .taskCreate,
                    arguments: ["title": .string("Release")],
                    summary: "Create release task"
                )
            ],
            clarification: ClarificationSession(
                route: route,
                requiredSlots: [.project, .dueDate]
            )
        )
    }
}

private final class TemporaryOrchestrationDatabase {
    let directory: URL
    let url: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appendingPathComponent("suisui.sqlite")
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
