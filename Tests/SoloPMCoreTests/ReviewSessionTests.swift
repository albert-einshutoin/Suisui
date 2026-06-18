import XCTest
@testable import SoloPMCore

final class ReviewSessionTests: XCTestCase {
    func testReviewSessionSupportsDisableEditResetAndApproval() throws {
        let plan = ActionPlan.reviewFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("Alpha")]),
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ])
        var session = ReviewSession(plan: plan)

        session.setActionEnabled(id: "task", false)
        session.editActionArguments(id: "project", arguments: ["title": .string("Beta")])

        XCTAssertEqual(session.items.first(where: { $0.id == "task" })?.isEnabled, false)
        XCTAssertEqual(session.items.first(where: { $0.id == "project" })?.editedAction.arguments["title"], .string("Beta"))

        session.resetAction(id: "project")
        XCTAssertEqual(session.items.first(where: { $0.id == "project" })?.editedAction.arguments["title"], .string("Alpha"))

        let token = ApprovalToken(id: "approval-1", sessionID: session.id)
        try session.approve(token: token)

        XCTAssertEqual(session.approvalState, .approved(token))
        XCTAssertTrue(session.canExecute)
    }

    func testDangerousReviewSessionIsBlocked() {
        let plan = ActionPlan.reviewFixture(actions: [
            PlanAction(id: "danger", tool: .filesystemCreateMarkdownFile, arguments: ["relativePath": .string("a.md"), "contents": .string("")], riskLevel: .danger)
        ])
        let session = ReviewSession(plan: plan)

        XCTAssertEqual(session.approvalState, .blocked("Dangerous actions cannot be executed."))
        XCTAssertFalse(session.canExecute)
    }

    func testReviewActionArgumentSummaryTruncatesLongValuesAndExtraFields() throws {
        let plan = ActionPlan.reviewFixture(actions: [
            PlanAction(
                id: "task",
                tool: .taskCreate,
                arguments: [
                    "title": .string(String(repeating: "Release readiness ", count: 8)),
                    "detail": .string("Prepare final investor review notes"),
                    "priority": .string("high"),
                    "dueAt": .string("2026-06-21"),
                    "source": .string("voice")
                ]
            )
        ])
        let session = ReviewSession(plan: plan)
        let item = try XCTUnwrap(session.items.first)

        let summary = item.argumentDisplaySummary(maxFields: 3, maxValueLength: 36)

        XCTAssertTrue(summary.isTruncated)
        XCTAssertTrue(summary.preview.hasPrefix("title: Release readiness Release readiness"))
        XCTAssertTrue(summary.preview.contains("..."))
        XCTAssertTrue(summary.preview.contains("+2 more"))
        XCTAssertTrue(summary.fullText.contains("source: voice"))
    }
}

final class ActionExecutorTests: XCTestCase {
    func testExecutorRunsEnabledActionsAndInjectsProjectIDIntoFollowingTasks() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let registry = try ToolRegistry.phase2Core(
            projectStore: projectStore,
            taskStore: taskStore,
            knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("Alpha")]),
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        try session.approve(token: ApprovalToken(id: "approval-1", sessionID: session.id))

        let executed = try ActionExecutor(registry: registry).execute(session)

        XCTAssertEqual(executed.executionStatus, .completed)
        XCTAssertEqual(executed.items.map(\.executionStatus), [.succeeded, .succeeded])
        let taskRows = try connection.queryRows("SELECT project_id FROM tasks ORDER BY id;")
        XCTAssertEqual(taskRows.first?["project_id"], "1")
    }

    func testExecutorInjectsProjectIDIntoFollowingBulkTasks() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let registry = try ToolRegistry.phase2Core(
            projectStore: projectStore,
            taskStore: taskStore,
            knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("Alpha")]),
            PlanAction(
                id: "bulk",
                tool: .taskBulkCreate,
                arguments: [
                    "tasks": .array([
                        .object(["title": .string("Draft")]),
                        .object(["title": .string("Review")])
                    ])
                ]
            )
        ]))
        try session.approve(token: ApprovalToken(id: "approval-1", sessionID: session.id))

        let executed = try ActionExecutor(registry: registry).execute(session)

        XCTAssertEqual(executed.executionStatus, .completed)
        XCTAssertEqual(executed.items.map(\.executionStatus), [.succeeded, .succeeded])
        let taskRows = try connection.queryRows("SELECT title, project_id FROM tasks ORDER BY id;")
        XCTAssertEqual(taskRows.map { $0["title"] }, ["Draft", "Review"])
        XCTAssertEqual(taskRows.map { $0["project_id"] }, ["1", "1"])
    }

    func testExecutorStopsOnPartialFailureAndSkipsRemainingActions() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "success", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "ok")
            },
            StaticTool(name: .frameSearch, description: "failure", inputSchema: ToolInputSchema(required: ["query"]), permissionLevel: .read) { _, _ in
                throw ToolExecutionError.executionFailed(.frameSearch, "boom")
            },
            StaticTool(name: .taskListDue, description: "after", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .taskListDue, status: .succeeded, summary: "should not run")
            }
        ])
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "first", tool: .projectList),
            PlanAction(id: "second", tool: .frameSearch, arguments: ["query": .string("q")]),
            PlanAction(id: "third", tool: .taskListDue)
        ]))

        let executed = try ActionExecutor(registry: registry).execute(session)

        XCTAssertEqual(executed.executionStatus, .failed)
        XCTAssertEqual(executed.items.map(\.executionStatus), [.succeeded, .failed, .skipped])
        XCTAssertEqual(executed.items[1].failureRecovery, .retryable)
    }

    func testExecutorClassifiesValidationFailureAsNotRetryable() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "write", inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]), permissionLevel: .writeWithApproval) { _, _ in
                throw ToolExecutionError.validationFailed(.taskCreate, "Invalid title.")
            }
        ])
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        try session.approve(token: ApprovalToken(id: "approval-1", sessionID: session.id))

        let executed = try ActionExecutor(registry: registry).execute(session)

        XCTAssertEqual(executed.items.first?.executionStatus, .failed)
        XCTAssertEqual(executed.items.first?.failureRecovery, .notRetryable)
    }

    func testExecutorRejectsWriteSessionWithoutApproval() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "write", inputSchema: ToolInputSchema(required: ["title"]), permissionLevel: .writeWithApproval) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))

        XCTAssertThrowsError(try ActionExecutor(registry: registry).execute(session))
    }

    func testExecutorRejectsInvalidEditedArgumentsBeforeCallingTool() throws {
        let callTracker = ToolCallTracker()
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "write", inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]), permissionLevel: .writeWithApproval) { _, _ in
                callTracker.markCalled()
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        session.editActionArguments(id: "task", arguments: ["title": .string(" ")])
        try session.approve(token: ApprovalToken(id: "approval-1", sessionID: session.id))

        XCTAssertThrowsError(try ActionExecutor(registry: registry).execute(session))
        XCTAssertFalse(callTracker.wasCalled)
    }

    func testExecutorMarksUnknownToolAsFailure() throws {
        let registry = ToolRegistry()
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "missing", tool: .projectList)
        ]))

        let executed = try ActionExecutor(registry: registry).execute(session)

        XCTAssertEqual(executed.executionStatus, .failed)
        XCTAssertEqual(executed.items.first?.executionStatus, .failed)
        XCTAssertTrue(executed.items.first?.errorMessage?.contains("unknownTool") == true)
    }

    func testExecutorRecordsSkippedDisabledActionInAuditLog() throws {
        let logger = InMemoryAuditLogger()
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "success", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "ok")
            },
            StaticTool(name: .taskListDue, description: "success", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .taskListDue, status: .succeeded, summary: "ok")
            }
        ])
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "first", tool: .projectList),
            PlanAction(id: "second", tool: .taskListDue)
        ]))
        session.setActionEnabled(id: "first", false)

        let executed = try ActionExecutor(registry: registry, auditLogger: logger).execute(session)

        XCTAssertEqual(executed.items.first?.executionStatus, .skipped)
        XCTAssertTrue(logger.recordedEvents.contains { $0.status == .skipped && $0.action == "project.list" })
    }
}

private final class ToolCallTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var isCalled = false

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCalled
    }

    func markCalled() {
        lock.lock()
        defer { lock.unlock() }
        isCalled = true
    }
}

private extension ActionPlan {
    static func reviewFixture(actions: [PlanAction]) -> ActionPlan {
        ActionPlan(
            id: "plan-review",
            userInput: "Review fixture",
            summary: "Review fixture",
            actions: actions,
            riskLevel: actions.map(\.riskLevel).max() ?? .read,
            requiresApproval: actions.contains { $0.riskLevel >= .write }
        )
    }
}

private enum TestMigrationRunner {
    static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try migration.apply(connection)
            try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(migration.id)');")
        }
    }
}
