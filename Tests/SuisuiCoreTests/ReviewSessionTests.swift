import XCTest
@testable import SuisuiCore

final class ReviewSessionTests: XCTestCase {
    func testReviewSessionMakesImplicitProjectDependencyExplicitBeforeApproval() throws {
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("Alpha")]),
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))

        XCTAssertEqual(
            session.items[1].editedAction.arguments["projectId"],
            .actionOutput(ActionOutputReference(actionID: "project", key: "projectId"))
        )
        XCTAssertEqual(
            session.originalPlan.actions[1].arguments["projectId"],
            .actionOutput(ActionOutputReference(actionID: "project", key: "projectId"))
        )
    }

    func testReviewSessionIssuesPlanBoundExpiringApproval() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let approvalID = UUID()
        let nonce = UUID()
        var session = ReviewSession(id: "session-1", plan: .reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))

        let approved = try session.approve(
            approvalID: approvalID,
            issuedAt: issuedAt,
            validity: 120,
            nonce: nonce
        )

        XCTAssertEqual(approved.approvalID, approvalID)
        XCTAssertEqual(approved.sessionID, session.id)
        XCTAssertEqual(approved.planID, session.originalPlan.id)
        XCTAssertEqual(approved.enabledActionIDs, ["task"])
        XCTAssertEqual(approved.issuedAt, issuedAt)
        XCTAssertEqual(approved.expiresAt, issuedAt.addingTimeInterval(120))
        XCTAssertEqual(approved.nonce, nonce)
        XCTAssertEqual(approved.canonicalPlanDigest, try session.approvalBinding.digest())
        XCTAssertEqual(session.approvalState, .approved(approved))
    }

    func testReviewSessionRejectsCallerTokenForAnotherSession() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(id: "session-1", plan: .reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))

        XCTAssertThrowsError(
            try session.approve(token: ApprovalToken(id: "approval", sessionID: "session-2", approvedAt: issuedAt))
        ) { error in
            XCTAssertEqual(error as? ReviewSessionError, .approvalSessionMismatch)
        }
    }

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

        XCTAssertEqual(session.approvalToken?.approvalID, token.approvalID)
        XCTAssertEqual(session.approvalToken?.sessionID, token.sessionID)
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

    func testEditingApprovedWriteActionInvalidatesApprovalBeforeExecution() throws {
        let plan = ActionPlan.reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ])
        var session = ReviewSession(plan: plan)
        try session.approve(token: ApprovalToken(id: "approval-1", sessionID: session.id))

        session.updateStringArgument(id: "task", key: "title", value: "Edited")

        XCTAssertEqual(session.approvalState, .pending)
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

    /// The approval surface must describe a proposal in words, not dump the
    /// JSON it happens to be built from.
    func testArgumentDisplayFieldsUseHumanLabelsAndDemoteInternalIdentifiers() throws {
        let plan = ActionPlan.reviewFixture(actions: [
            PlanAction(
                id: "event",
                tool: .calendarCreateEvent,
                arguments: [
                    "projectId": .number(3),
                    "startAt": .string("2026-07-10T14:00:00Z"),
                    "title": .string("Release review"),
                    "source": .string("voice")
                ]
            )
        ])
        let session = ReviewSession(plan: plan)
        let item = try XCTUnwrap(session.items.first)

        let fields = item.argumentDisplayFields()

        XCTAssertEqual(fields.map(\.key), ["title", "startAt", "source", "projectId"])
        XCTAssertEqual(fields.first?.labelKey, "Title")
        XCTAssertEqual(fields[1].labelKey, "Starts")
        XCTAssertEqual(fields[1].kind, .timestamp)
        // Casing variants of the same concept resolve to one label.
        XCTAssertEqual(fields.last?.labelKey, "Project")
        XCTAssertEqual(fields.last?.kind, .identifier)
        // An argument outside the planning vocabulary keeps its raw key rather
        // than being relabelled into something it is not.
        XCTAssertEqual(fields[2].labelKey, "source")
    }

    func testArgumentDisplayFieldsAreEmptyWhenThereIsNothingToApprove() throws {
        let plan = ActionPlan.reviewFixture(actions: [
            PlanAction(id: "list", tool: .taskList, arguments: [:])
        ])
        let session = ReviewSession(plan: plan)
        let item = try XCTUnwrap(session.items.first)

        XCTAssertTrue(item.argumentDisplayFields().isEmpty)
    }

    func testArgumentDisplayFieldsClassifyBooleanValuesAsFlags() throws {
        let plan = ActionPlan.reviewFixture(actions: [
            PlanAction(
                id: "write",
                tool: .taskCreate,
                arguments: ["requiresApproval": .bool(true)]
            )
        ])
        let session = ReviewSession(plan: plan)
        let item = try XCTUnwrap(session.items.first)

        let field = try XCTUnwrap(item.argumentDisplayFields().first)

        XCTAssertEqual(field.key, "requiresApproval")
        XCTAssertEqual(field.rawValue, "true")
        XCTAssertEqual(field.kind, .flag)
    }
}

final class ActionExecutorTests: XCTestCase {
    func testExecutorRejectsExpiredApprovalBeforeCallingTool() throws {
        let callTracker = ToolCallTracker()
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "write",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                callTracker.markCalled()
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        try session.approve(issuedAt: issuedAt, validity: 30)

        XCTAssertThrowsError(
            try ActionExecutor(registry: registry).execute(
                session,
                now: issuedAt.addingTimeInterval(30)
            )
        ) { error in
            XCTAssertEqual(error as? ActionExecutorError, .invalidApproval(.expired))
        }
        XCTAssertFalse(callTracker.wasCalled)
    }

    func testExecutorConsumesApprovedExecutionNonceOnlyOnce() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "write",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        let approval = try session.approve(issuedAt: now)
        let replayStore = ProcessLocalApprovalReplayStore()
        let executor = ActionExecutor(registry: registry, replayStore: replayStore)

        _ = try executor.execute(session, now: now)

        XCTAssertThrowsError(try executor.execute(session, now: now)) { error in
            XCTAssertEqual(error as? ActionExecutorError, .approvalReplayDetected(approval.nonce))
        }
        XCTAssertEqual(try replayStore.state(for: approval.nonce), .completed)
    }

    func testExecutorResolvesTypedOutputReferenceAndRevalidatesResolvedArguments() throws {
        let observedArguments = ToolArgumentsRecorder()
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .projectCreate,
                description: "project",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(
                    tool: .projectCreate,
                    status: .succeeded,
                    summary: "created",
                    output: ["projectId": .string("project-42")]
                )
            },
            StaticTool(
                name: .taskCreate,
                description: "task",
                inputSchema: ToolInputSchema(
                    required: ["title", "projectId"],
                    properties: ["title": "string", "projectId": "string"]
                ),
                permissionLevel: .writeWithApproval
            ) { arguments, _ in
                observedArguments.record(arguments)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("Alpha")]),
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        try session.approve(issuedAt: now)

        let executed = try ActionExecutor(registry: registry).execute(session, now: now)

        XCTAssertEqual(executed.executionStatus, .completed)
        XCTAssertEqual(observedArguments.arguments?["projectId"], .string("project-42"))
    }

    func testExecutorFailsClosedWhenResolvedOutputViolatesTargetSchema() throws {
        let callTracker = ToolCallTracker()
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .projectCreate,
                description: "project",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(
                    tool: .projectCreate,
                    status: .succeeded,
                    summary: "created",
                    output: ["projectId": .number(42)]
                )
            },
            StaticTool(
                name: .taskCreate,
                description: "task",
                inputSchema: ToolInputSchema(
                    required: ["title", "projectId"],
                    properties: ["title": "string", "projectId": "string"]
                ),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                callTracker.markCalled()
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("Alpha")]),
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        try session.approve(issuedAt: now)

        let executed = try ActionExecutor(registry: registry).execute(session, now: now)

        XCTAssertEqual(executed.executionStatus, .failed)
        XCTAssertEqual(executed.items.map(\.executionStatus), [.succeeded, .failed])
        XCTAssertFalse(callTracker.wasCalled)
    }

    func testExecutorRejectsEnabledActionThatReferencesDisabledSourceBeforeSideEffects() throws {
        let callTracker = ToolCallTracker()
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .projectCreate,
                description: "project",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                callTracker.markCalled()
                return ToolResult(
                    tool: .projectCreate,
                    status: .succeeded,
                    summary: "created",
                    output: ["projectId": .string("project-42")]
                )
            },
            StaticTool(
                name: .taskCreate,
                description: "task",
                inputSchema: ToolInputSchema(
                    required: ["title", "projectId"],
                    properties: ["title": "string", "projectId": "string"]
                ),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                callTracker.markCalled()
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("Alpha")]),
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
        ]))
        session.setActionEnabled(id: "project", false)
        try session.approve(issuedAt: now)

        XCTAssertThrowsError(try ActionExecutor(registry: registry).execute(session, now: now)) { error in
            XCTAssertEqual(
                error as? ActionExecutorError,
                .invalidActionGraph("Action task references disabled action project.")
            )
        }
        XCTAssertFalse(callTracker.wasCalled)
    }

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

    func testExecutorTreatsFailedToolResultAsActionFailure() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "verification", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(
                    tool: .projectList,
                    status: .failed,
                    summary: "Verification failed",
                    output: ["passed": .bool(false)]
                )
            },
            StaticTool(name: .taskListDue, description: "after", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .taskListDue, status: .succeeded, summary: "should not run")
            }
        ])
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "verification", tool: .projectList),
            PlanAction(id: "after", tool: .taskListDue)
        ]))

        let executed = try ActionExecutor(registry: registry).execute(session)

        XCTAssertEqual(executed.executionStatus, .failed)
        XCTAssertEqual(executed.items.map(\.executionStatus), [.failed, .skipped])
        XCTAssertEqual(executed.items.first?.result?.status, .failed)
        XCTAssertEqual(executed.items.first?.errorMessage, "Verification failed")
        XCTAssertEqual(executed.items.first?.failureRecovery, .retryable)
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

    func testExecutorReportsUnavailableToolBeforeExecution() throws {
        let registry = ToolRegistry()
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "missing", tool: .projectList)
        ]))

        XCTAssertThrowsError(try ActionExecutor(registry: registry).execute(session)) { error in
            guard case .validationFailed(let issues) = error as? ActionExecutorError else {
                XCTFail("Expected validation failure, got \(error)")
                return
            }
            XCTAssertEqual(issues, [
                ToolInputValidationIssue(
                    actionID: "missing",
                    field: "tool",
                    message: "Tool project.list is not available in the active registry."
                )
            ])
        }
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

    func testExecutorRedactsToolResultSummaryBeforeAuditPersistence() throws {
        let logger = InMemoryAuditLogger()
        let secret = "sk-" + "sampleSecret"
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "success", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "Loaded apiKey=\(secret)")
            }
        ])
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "read", tool: .projectList)
        ]))

        _ = try ActionExecutor(registry: registry, auditLogger: logger).execute(session)

        let toolEvent = try XCTUnwrap(logger.recordedEvents.first { $0.category == "tool" && $0.status == .succeeded })
        let summary = try XCTUnwrap(toolEvent.metadata["summary"])
        XCTAssertFalse(summary.contains(secret))
        XCTAssertTrue(summary.contains("[REDACTED_SECRET]"))
    }

    func testExecutorRedactsToolErrorBeforeAuditPersistence() throws {
        let logger = InMemoryAuditLogger()
        let secret = "sk-" + "sampleSecret"
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "failure", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                throw ToolExecutionError.executionFailed(.projectList, "provider token=\(secret) rejected")
            }
        ])
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "read", tool: .projectList)
        ]))

        let executed = try ActionExecutor(registry: registry, auditLogger: logger).execute(session)

        let toolEvent = try XCTUnwrap(logger.recordedEvents.first { $0.category == "tool" && $0.status == .failed })
        let error = try XCTUnwrap(toolEvent.metadata["error"])
        XCTAssertFalse(error.contains(secret))
        XCTAssertTrue(error.contains("[REDACTED_SECRET]"))
        XCTAssertEqual(executed.items.first?.errorMessage, "project.list failed: provider token=[REDACTED_SECRET] rejected")
    }

    func testExecutorPreservesSucceededToolStateWhenAuditFailsAfterExecutionStarts() throws {
        let logger = SequencedActionAuditLogger(failOnCall: 2)
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "success", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "ok")
            }
        ])
        let session = ReviewSession(plan: .reviewFixture(actions: [
            PlanAction(id: "read", tool: .projectList)
        ]))

        let executed = try ActionExecutor(registry: registry, auditLogger: logger).execute(session)

        XCTAssertEqual(executed.executionStatus, .completed)
        XCTAssertEqual(executed.items.first?.executionStatus, .succeeded)
        XCTAssertEqual(executed.items.first?.result?.summary, "ok")
        XCTAssertEqual(executed.auditErrorMessage, "Action audit log could not be saved.")
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

private final class ToolArgumentsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedArguments: [String: JSONValue]?

    var arguments: [String: JSONValue]? {
        lock.lock()
        defer { lock.unlock() }
        return recordedArguments
    }

    func record(_ arguments: [String: JSONValue]) {
        lock.lock()
        defer { lock.unlock() }
        recordedArguments = arguments
    }
}

private enum ActionExecutorAuditTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "unavailable"
    }
}

private final class SequencedActionAuditLogger: AuditLogger, @unchecked Sendable {
    private let failOnCall: Int
    private var callCount = 0
    private let lock = NSLock()

    init(failOnCall: Int) {
        self.failOnCall = failOnCall
    }

    func record(_ event: AuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        if callCount >= failOnCall {
            throw ActionExecutorAuditTestError.unavailable
        }
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
