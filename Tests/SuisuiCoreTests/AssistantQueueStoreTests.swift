import XCTest
@testable import SuisuiCore

final class AssistantQueueStoreTests: XCTestCase {
    func testConversationOriginMarkerPersistsAndChangesReviewRevision() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let store = SQLiteAssistantQueueStore(connection: connection)
        let ordinary = makeItem(
            id: "queue-conversation-origin",
            summary: "Create launch task"
        )
        let conversation =
            ordinary.minimizingUnapprovedConversationTranscript()

        XCTAssertNotEqual(
            ordinary.contentFingerprint,
            conversation.contentFingerprint
        )
        XCTAssertNotEqual(
            ordinary.mutationRevision,
            conversation.mutationRevision
        )

        try store.save(conversation)

        let restored = try store.get(id: conversation.id)
        XCTAssertTrue(restored.requiresConversationActionLink)
        XCTAssertEqual(restored.mutationRevision, conversation.mutationRevision)
        XCTAssertEqual(
            try connection.queryStrings(
                """
                SELECT requires_conversation_action_link
                FROM assistant_queue_items
                WHERE id = ?;
                """,
                parameters: [.text(conversation.id)]
            ),
            ["1"]
        )
    }

    func testLegacyQueueJSONDefaultsConversationOriginMarkerToFalse() throws {
        let item = makeItem(
            id: "queue-legacy-json",
            summary: "Legacy queue item"
        )
        let encoded = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "requiresConversationActionLink")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            AssistantQueueItem.self,
            from: legacy
        )

        XCTAssertFalse(decoded.requiresConversationActionLink)
    }

    func testConversationMinimizationKeepsSemanticPlanWithoutSpeechText() throws {
        let secretSpeech =
            "Please create Launch task and remember my unreleased codename"
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "plan-minimize-speech",
                userInput: secretSpeech,
                summary: "Create Launch task",
                actions: [
                    PlanAction(
                        id: "create-launch",
                        tool: .taskCreate,
                        arguments: ["title": .string("Launch")]
                    ),
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: secretSpeech,
            interpretationSummary: "Create a Task titled Launch.",
            reason: "Review the semantic task creation."
        )

        let minimized =
            item.minimizingUnapprovedConversationTranscript()

        XCTAssertNil(minimized.sourceTranscript)
        XCTAssertTrue(minimized.requiresConversationActionLink)
        guard case .actionPlan(let plan) = minimized.payload else {
            return XCTFail("Expected ActionPlan payload")
        }
        XCTAssertFalse(plan.userInput.contains("unreleased codename"))
        XCTAssertEqual(plan.summary, "Create Launch task")
        XCTAssertEqual(
            plan.actions.first?.arguments["title"],
            .string("Launch")
        )
    }

    func testSQLiteStorePersistsQueueItemsAndLoadsByState() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let waiting = makeItem(id: "queue-waiting", state: .waitingReview, summary: "Create launch task")
        let blocked = makeItem(id: "queue-blocked", state: .blocked, summary: "Blocked filesystem write")

        try store.save(waiting)
        try store.save(blocked)

        XCTAssertEqual(try store.get(id: waiting.id), waiting)
        XCTAssertEqual(try store.get(id: blocked.id), blocked)
        XCTAssertEqual(
            Set(try store.list(filter: .states([.waitingReview], limit: 10)).map(\.id)),
            Set([waiting.id])
        )
        XCTAssertEqual(
            Set(try store.list(filter: .states([.waitingReview, .blocked], limit: 10)).map(\.id)),
            Set([waiting.id, blocked.id])
        )
    }

    func testSQLiteStorePersistsCostPreviewAndReadModelShowsEstimatedManagedCost() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let preview = makeCostPreview(inputTokens: 1_000, outputTokens: 500)
        let item = makeItem(id: "queue-cost-preview", summary: "Create launch task", costPreview: preview)

        try store.save(item)
        let reloaded = try store.get(id: item.id)
        let row = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [reloaded]).rows.first)

        XCTAssertEqual(reloaded.costPreview, preview)
        XCTAssertTrue(row.costPreviewLabel?.contains("Preview only") ?? false)
        XCTAssertTrue(row.costPreviewLabel?.contains("estimated before run") ?? false)
        XCTAssertTrue(row.costPreviewLabel?.contains("not charged yet") ?? false)
        XCTAssertTrue(row.costPreviewLabel?.contains("Suisui managed") ?? false)
        XCTAssertTrue(row.costPreviewLabel?.contains("USD") ?? false)
        XCTAssertTrue(
            row.costPreviewLabel?.contains("1,500 tokens") ?? false,
            row.costPreviewLabel ?? "missing cost preview label"
        )
    }

    func testSQLiteReadModelReviewRevisionUsesStoredSummaryBeforeDisplayRedaction() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(
            id: "queue-review-revision-redaction",
            summary: "Create task with token=sk-review-revision-secret"
        )
        try store.save(item)

        let row = try XCTUnwrap(
            store.readModelSnapshot(filter: .all(limit: 10)).rows.first
        )

        XCTAssertEqual(row.mutationRevision, item.mutationRevision)
        XCTAssertFalse(row.redactedSummary.contains("sk-review-revision-secret"))
        XCTAssertTrue(row.canApproveAndRun)
    }

    func testSQLiteReadModelSnapshotDoesNotDecodeActionPayloadJSONForListRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        try connection.execute(
            """
            INSERT INTO assistant_queue_items (
                id,
                schema_version,
                payload_kind,
                payload_json,
                state,
                risk_level,
                source_transcript,
                interpretation_summary,
                review_reason,
                redacted_summary,
                required_capabilities_json,
                approval_json,
                blocking_reason,
                cost_preview_json,
                created_at,
                updated_at
            )
            VALUES (
                'queue-summary-invalid-payload',
                1,
                'action_plan',
                '{not-json',
                'waitingReview',
                'write',
                'Create task token=sk-summary-secret',
                'Routed as task intent.',
                'Summary row should not need full action payload.',
                'Create task token=sk-summary-secret',
                '[]',
                NULL,
                NULL,
                NULL,
                '2026-07-05T00:00:00Z',
                '2026-07-05T00:00:00Z'
            );
            """
        )

        let snapshot = try store.readModelSnapshot(
            filter: .all(limit: 10),
            receipts: [],
            viewFilter: .all,
            sort: .needsActionFirst
        )

        let row = try XCTUnwrap(snapshot.rows.first)
        XCTAssertEqual(row.id, "queue-summary-invalid-payload")
        XCTAssertFalse(row.redactedSummary.contains("sk-summary-secret"))
        XCTAssertThrowsError(try store.list(filter: .all(limit: 10))) { error in
            XCTAssertEqual(error as? AssistantQueueStoreError, .decodingFailed(column: "assistant_queue_items.payload_json"))
        }
    }

    func testSQLiteReadModelBlocksRetryWhenFailedActionPlanPayloadContainsDanger() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = AssistantQueueItem(
            id: "queue-failed-hidden-danger",
            state: .failed,
            payload: .actionPlan(ActionPlan(
                id: "hidden-danger-plan",
                userInput: "Delete task during retry",
                summary: "Delete task during retry",
                actions: [
                    PlanAction(id: "danger-action", tool: .taskDelete, riskLevel: .danger)
                ],
                riskLevel: .write,
                requiresApproval: true
            )),
            riskLevel: .write,
            sourceTranscript: nil,
            interpretationSummary: "Delete task",
            reviewReason: "Retry failed local action.",
            redactedSummary: "Delete task",
            requiredCapabilities: [.tool(.taskDelete), .providerExecutionApproval],
            blockingReason: "Dangerous retry should stay gated."
        )

        try store.save(item)
        let snapshot = try store.readModelSnapshot(
            filter: .all(limit: 10),
            receipts: [],
            viewFilter: .all,
            sort: .needsActionFirst
        )

        let sqliteRow = try XCTUnwrap(snapshot.rows.first)
        XCTAssertFalse(sqliteRow.canRetry)
        let inMemoryRow = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [item]).rows.first)
        XCTAssertFalse(inMemoryRow.canRetry)
    }

    func testReadModelBlocksApprovalAndRunWithoutAllowedCostPreview() throws {
        let missingPreview = AssistantQueueItem(
            id: "queue-missing-preview",
            state: .waitingReview,
            payload: makeItem(id: "queue-missing-preview-source").payload,
            riskLevel: .write,
            sourceTranscript: "Create task",
            interpretationSummary: "Routed as task intent.",
            reviewReason: "Needs review.",
            redactedSummary: "Create task",
            requiredCapabilities: [.tool(.taskCreate), .providerExecutionApproval]
        )
        let overCap = makeItem(
            id: "queue-over-cap",
            state: .waitingReview,
            summary: "Managed over cap",
            costPreview: makeCostPreview(inputTokens: 2_000, outputTokens: 1_000, hardCapCents: 0.10)
        )
        let malformedManagedPreview = makeItem(
            id: "queue-managed-preview-without-cost",
            state: .waitingReview,
            summary: "Managed missing cost",
            costPreview: AssistantQueueCostPreview(
                billingMode: .suisuiManaged,
                state: .estimated,
                usage: AssistantQueueCostUsage(inputTokens: 2_000, outputTokens: 1_000),
                estimatedCostCents: nil,
                currencyCode: "USD",
                model: ExecutionReceiptModel(provider: "openai", name: "gpt-test"),
                capStatus: .withinLimit
            )
        )
        let approvedOverCap = AssistantQueueItem(
            id: "queue-approved-over-cap",
            state: .approved,
            payload: overCap.payload,
            riskLevel: overCap.riskLevel,
            sourceTranscript: overCap.sourceTranscript,
            interpretationSummary: overCap.interpretationSummary,
            reviewReason: overCap.reviewReason,
            redactedSummary: overCap.redactedSummary,
            requiredCapabilities: overCap.requiredCapabilities,
            approval: AssistantQueueApprovalRecord(
                reviewerID: "local-user",
                reviewedContentFingerprint: "stale"
            ),
            costPreview: overCap.costPreview
        )

        let snapshot = AssistantQueueReadModel.snapshot(from: [missingPreview, overCap, malformedManagedPreview, approvedOverCap])

        XCTAssertFalse(snapshot.rows.first { $0.id == missingPreview.id }?.canApprove ?? true)
        XCTAssertFalse(snapshot.rows.first { $0.id == overCap.id }?.canApprove ?? true)
        XCTAssertFalse(snapshot.rows.first { $0.id == malformedManagedPreview.id }?.canApprove ?? true)
        XCTAssertFalse(snapshot.rows.first { $0.id == approvedOverCap.id }?.canRun ?? true)
        XCTAssertThrowsError(try AssistantQueueStateMachine.approve(malformedManagedPreview, reviewerID: "local-user")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .managedCostCapExceeded)
        }
    }

    func testSQLiteStorePersistsApprovalWithoutExecutionToken() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(id: "queue-approval")

        try store.save(item)
        let approved = try store.transition(id: item.id) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
        let reloaded = try store.get(id: item.id)

        XCTAssertEqual(reloaded, approved)
        XCTAssertEqual(reloaded.state, .approved)
        XCTAssertEqual(reloaded.approval?.reviewerID, "local-user")
        XCTAssertNil(reloaded.approval?.executionTokenID)
    }

    func testSQLiteStoreRejectsInvalidStoredState() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(id: "queue-invalid")

        try store.save(item)
        try connection.execute("UPDATE assistant_queue_items SET state = 'not_real' WHERE id = 'queue-invalid';")

        XCTAssertThrowsError(try store.get(id: item.id)) { error in
            XCTAssertEqual(
                error as? AssistantQueueStoreError,
                .invalidStoredValue(column: "assistant_queue_items.state", value: "not_real")
            )
        }
    }

    func testReadModelCountsReviewableItemsAndRedactsSourcePreview() throws {
        let secretSource = "Create task with token=sk-assistantQueueStoreSecret"
        let waiting = makeItem(
            id: "queue-read-model-waiting",
            state: .waitingReview,
            sourceTranscript: secretSource,
            summary: secretSource
        )
        let blocked = makeItem(id: "queue-read-model-blocked", state: .blocked, summary: "Blocked task")
        let done = makeItem(id: "queue-read-model-done", state: .done, summary: "Done task")
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-read-model-approved", state: .waitingReview, summary: "Approved task"),
            reviewerID: "local-user"
        )
        let approvedAutomation = try AssistantQueueStateMachine.approve(makeAutomationRequestItem(), reviewerID: "local-user")
        let failed = makeItem(id: "queue-read-model-failed", state: .failed, summary: "Failed task")

        let snapshot = AssistantQueueReadModel.snapshot(from: [done, blocked, waiting, approved, approvedAutomation, failed])

        XCTAssertEqual(snapshot.waitingReviewCount, 1)
        XCTAssertEqual(snapshot.blockedCount, 1)
        XCTAssertEqual(snapshot.needsAttentionCount, 5)
        XCTAssertEqual(snapshot.reviewableCount, snapshot.needsAttentionCount)
        XCTAssertEqual(snapshot.rows.map(\.id), [blocked.id, waiting.id, approvedAutomation.id, approved.id, failed.id, done.id])
        let waitingRow = try XCTUnwrap(snapshot.rows.first { $0.id == waiting.id })
        XCTAssertFalse(waitingRow.title.contains("sk-assistantQueueStoreSecret"))
        XCTAssertFalse(waitingRow.redactedSummary.contains("sk-assistantQueueStoreSecret"))
        XCTAssertFalse(waitingRow.sourcePreview?.contains("sk-assistantQueueStoreSecret") ?? true)
        XCTAssertTrue(waitingRow.canApprove)
        XCTAssertTrue(waitingRow.canApproveAndRun)
        XCTAssertFalse(waitingRow.canRun)
        XCTAssertTrue(waitingRow.canDefer)
        XCTAssertTrue(waitingRow.canEdit)
        XCTAssertTrue(waitingRow.canReject)
        let approvedRow = try XCTUnwrap(snapshot.rows.first { $0.id == approved.id })
        XCTAssertFalse(approvedRow.canApprove)
        XCTAssertTrue(approvedRow.canRun)
        XCTAssertTrue(approvedRow.canEdit)
        let automationRow = try XCTUnwrap(snapshot.rows.first { $0.id == approvedAutomation.id })
        XCTAssertFalse(automationRow.canRun)
        XCTAssertFalse(automationRow.canApproveAndRun)
        XCTAssertFalse(automationRow.canRetry)
        XCTAssertTrue(automationRow.canEdit)

        var unsupportedWaitingAutomation = makeAutomationRequestItem(
            id: "queue-read-model-unsupported-waiting-automation"
        )
        unsupportedWaitingAutomation.state = .waitingReview
        let unsupportedWaitingRow = try XCTUnwrap(
            AssistantQueueReadModel.snapshot(from: [unsupportedWaitingAutomation])
                .rows.first
        )
        XCTAssertTrue(unsupportedWaitingRow.canApprove)
        XCTAssertFalse(unsupportedWaitingRow.canApproveAndRun)
        let blockedRow = try XCTUnwrap(snapshot.rows.first { $0.id == blocked.id })
        XCTAssertFalse(blockedRow.canApprove)
        XCTAssertFalse(blockedRow.canRun)
        XCTAssertFalse(blockedRow.canRetry)
        XCTAssertFalse(blockedRow.canEdit)
        XCTAssertTrue(blockedRow.canReject)
        let failedRow = try XCTUnwrap(snapshot.rows.first { $0.id == failed.id })
        XCTAssertEqual(failedRow.stateLabel, "Failed")
        XCTAssertFalse(failedRow.canRun)
        XCTAssertTrue(failedRow.canRetry)
        XCTAssertFalse(failedRow.canEdit)
        XCTAssertFalse(failedRow.canReject)
    }

    func testRowActionPresentationTracksRealStateMachineTransitionsAndHidesRunningReject() throws {
        let waiting = makeItem(
            id: "queue-row-action-transitions",
            state: .waitingReview,
            summary: "Create transition test task"
        )

        let waitingRow = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [waiting]).rows.first)
        let waitingPresentation = AssistantQueueRowActionPresentation.make(for: waitingRow)
        XCTAssertEqual(waitingPresentation.primaryAction, .approve)
        XCTAssertEqual(waitingPresentation.secondaryActions, [.edit, .defer, .reject])

        let approved = try AssistantQueueStateMachine.approve(waiting, reviewerID: "local-user")
        let approvedRow = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [approved]).rows.first)
        let approvedPresentation = AssistantQueueRowActionPresentation.make(for: approvedRow)
        XCTAssertEqual(approvedPresentation.primaryAction, .run)
        XCTAssertEqual(approvedPresentation.secondaryActions, [.edit, .defer, .reject])

        let running = try AssistantQueueStateMachine.startRunning(approved)
        let runningRow = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [running]).rows.first)
        XCTAssertFalse(
            runningRow.canReject,
            "In-flight work cannot be cancelled by changing only its queue review state."
        )
        let runningPresentation = AssistantQueueRowActionPresentation.make(for: runningRow)
        XCTAssertNil(runningPresentation.primaryAction)
        XCTAssertEqual(
            runningPresentation.secondaryActions,
            [],
            "Reject cannot cancel in-flight coordination, so the UI must not present a false cancellation action."
        )

        let failed = try AssistantQueueStateMachine.markFailed(running, reason: "Transition test failure.")
        let failedRow = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [failed]).rows.first)
        let failedPresentation = AssistantQueueRowActionPresentation.make(for: failedRow)
        XCTAssertEqual(failedPresentation.primaryAction, .reopen)
        XCTAssertEqual(failedPresentation.secondaryActions, [])
    }

    func testReadModelMarksApprovedTaskMutationAutomationRequestRunnable() throws {
        let approvedMutation = try AssistantQueueStateMachine.approve(
            makeAutomationRequestItem(
                id: "queue-read-model-runnable-automation",
                toolName: HostedMCPTaskToolName.taskComplete.rawValue,
                taskMutation: SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .complete,
                    status: "completed",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                )
            ),
            reviewerID: "local-user"
        )
        let approvedWithoutMutation = try AssistantQueueStateMachine.approve(
            makeAutomationRequestItem(id: "queue-read-model-unsupported-automation"),
            reviewerID: "local-user"
        )

        let snapshot = AssistantQueueReadModel.snapshot(from: [approvedMutation, approvedWithoutMutation])

        XCTAssertTrue(snapshot.rows.first { $0.id == approvedMutation.id }?.canRun ?? false)
        XCTAssertFalse(snapshot.rows.first { $0.id == approvedWithoutMutation.id }?.canRun ?? true)
    }

    func testReadModelShowsBlockedConnectorSendGateAsNonRunnable() throws {
        let item = AssistantQueueAdapter.makeConnectorSendGateItem(
            serviceID: "slack",
            serviceDisplayName: "Slack",
            redactedSourceTranscript: "Slackに今すぐ送信して",
            redactedArgumentSummary: "Connector send requested for Slack.",
            routeSummary: "Route as connector.send_gate without sending.",
            requestIDProvider: { "connector-send-test" }
        )

        let row = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [item]).rows.first)

        XCTAssertEqual(row.id, "automation-request:connector-send-test")
        XCTAssertEqual(row.state, .blocked)
        XCTAssertEqual(row.stateLabel, "Blocked")
        XCTAssertEqual(row.capabilityLabels, ["connector.slack.message.send", "provider_execution_approval"])
        XCTAssertEqual(row.blockingReason, "Slack connector send is not configured. Create a reviewed draft instead; no external message was sent.")
        XCTAssertFalse(row.canApprove)
        XCTAssertFalse(row.canRun)
        XCTAssertFalse(row.canDefer)
        XCTAssertTrue(row.canReject)
    }

    func testReadModelDoesNotMarkMalformedTaskMutationAutomationRequestRunnable() throws {
        let missingTaskID = try AssistantQueueStateMachine.approve(
            makeAutomationRequestItem(
                id: "queue-read-model-missing-task-id",
                toolName: HostedMCPTaskToolName.taskComplete.rawValue,
                taskMutation: SyncTaskMutationPayload(
                    operation: .complete,
                    status: "completed",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                )
            ),
            reviewerID: "local-user"
        )
        let noOpUpdate = try AssistantQueueStateMachine.approve(
            makeAutomationRequestItem(
                id: "queue-read-model-no-op-update",
                toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
                taskMutation: SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .update,
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                )
            ),
            reviewerID: "local-user"
        )
        let mismatchedTool = try AssistantQueueStateMachine.approve(
            makeAutomationRequestItem(
                id: "queue-read-model-mismatched-tool",
                toolName: HostedMCPTaskToolName.taskCreate.rawValue,
                taskMutation: SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .complete,
                    status: "completed",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                )
            ),
            reviewerID: "local-user"
        )

        let snapshot = AssistantQueueReadModel.snapshot(from: [missingTaskID, noOpUpdate, mismatchedTool])

        XCTAssertFalse(snapshot.rows.first { $0.id == missingTaskID.id }?.canRun ?? true)
        XCTAssertFalse(snapshot.rows.first { $0.id == noOpUpdate.id }?.canRun ?? true)
        XCTAssertFalse(snapshot.rows.first { $0.id == mismatchedTool.id }?.canRun ?? true)
    }

    func testReadModelFiltersAndSortsRowsWithoutHidingAttentionCounts() throws {
        let blocked = makeItem(id: "queue-filter-blocked", state: .blocked, summary: "Blocked write")
        let waitingLow = makeItem(id: "queue-filter-waiting-low", state: .waitingReview, summary: "Low review")
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-filter-approved", state: .waitingReview, summary: "Approved work"),
            reviewerID: "local-user"
        )
        let failedHigh = makeItem(id: "queue-filter-failed-high", state: .failed, summary: "Failed high")
        let deferred = makeItem(id: "queue-filter-deferred", state: .deferred, summary: "Deferred work")
        let done = makeItem(id: "queue-filter-done", state: .done, summary: "Done work")
        let captured = makeItem(id: "queue-filter-captured", state: .captured, summary: "Captured work")
        let allItems = [done, deferred, approved, waitingLow, failedHigh, captured, blocked]

        let needsAttention = AssistantQueueReadModel.snapshot(
            from: allItems,
            viewFilter: .needsAttention,
            sort: .needsActionFirst
        )
        XCTAssertEqual(
            needsAttention.rows.map(\.id),
            [blocked.id, waitingLow.id, captured.id, approved.id, failedHigh.id]
        )
        XCTAssertEqual(needsAttention.totalCount, allItems.count)
        XCTAssertEqual(needsAttention.waitingReviewCount, 1)
        XCTAssertEqual(needsAttention.blockedCount, 1)
        XCTAssertEqual(needsAttention.approvedCount, 1)
        XCTAssertEqual(needsAttention.failedCount, 1)
        XCTAssertEqual(needsAttention.deferredCount, 1)
        XCTAssertEqual(needsAttention.doneCount, 1)
        XCTAssertEqual(needsAttention.needsAttentionCount, 5)

        let failedOnly = AssistantQueueReadModel.snapshot(
            from: allItems,
            viewFilter: .failed,
            sort: .titleAscending
        )
        XCTAssertEqual(failedOnly.rows.map(\.id), [failedHigh.id])
        XCTAssertEqual(failedOnly.totalCount, allItems.count)

        let riskSorted = AssistantQueueReadModel.snapshot(
            from: allItems,
            viewFilter: .all,
            sort: .riskHighFirst
        )
        XCTAssertEqual(riskSorted.rows.first?.riskLabel, "Write")
        XCTAssertEqual(riskSorted.totalCount, allItems.count)
    }

    func testSQLiteStoreFiltersAttentionStatesBeforeLimit() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let oldWaiting = makeItem(id: "queue-old-waiting", state: .waitingReview, summary: "Old waiting review")
        try store.save(oldWaiting)
        for index in 0..<80 {
            try store.save(makeItem(
                id: "queue-new-done-\(index)",
                state: .done,
                summary: "Done \(index)"
            ))
        }

        let attentionItems = try store.list(filter: .states(AssistantQueueViewFilter.needsAttention.states, limit: 10))

        XCTAssertEqual(attentionItems.map(\.id), [oldWaiting.id])
    }

    func testReadModelSnapshotScalesToLargeQueueWhilePreservingAttentionCounts() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)

        let requiredCapabilitiesJSON = try jsonString([
            AssistantQueueRequiredCapability.tool(.taskCreate),
            .providerExecutionApproval
        ])
        let largeActionPlanPayload = try largeActionPlanPayloadJSON(
            actions: 48,
            argumentSize: 512
        )
        let automationPayload = try automationRequestPayloadJSON(
            id: "queue-scale-automation",
            toolName: HostedMCPTaskToolName.taskCreate.rawValue
        )

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<5000 {
            try insertQueueItem(
                connection: connection,
                id: "queue-scale-done-\(String(format: "%05d", index))",
                state: .done,
                payloadKind: "action_plan",
                payloadJSON: largeActionPlanPayload,
                updatedAt: baseDate.addingTimeInterval(Double(index)),
                reviewReason: "Queue terminal fixture row",
                redactedSummary: "Scale terminal row \(index)",
                requiredCapabilitiesJSON: requiredCapabilitiesJSON
            )
        }

        for index in 0..<20 {
            try insertQueueItem(
                connection: connection,
                id: "queue-scale-waiting-\(String(format: "%03d", index))",
                state: .waitingReview,
                payloadKind: index.isMultiple(of: 4) ? "automation_request" : "action_plan",
                payloadJSON: index.isMultiple(of: 4) ? automationPayload : largeActionPlanPayload,
                updatedAt: baseDate.addingTimeInterval(-Double(index + 1)),
                reviewReason: "Queue attention fixture row",
                redactedSummary: "Scale waiting row \(index)",
                requiredCapabilitiesJSON: requiredCapabilitiesJSON
            )
        }

        for index in 0..<10 {
            try insertQueueItem(
                connection: connection,
                id: "queue-scale-blocked-\(String(format: "%03d", index))",
                state: .blocked,
                payloadKind: "action_plan",
                payloadJSON: largeActionPlanPayload,
                updatedAt: baseDate.addingTimeInterval(-Double(index + 25)),
                reviewReason: "Queue attention fixture row",
                redactedSummary: "Scale blocked row \(index)",
                requiredCapabilitiesJSON: requiredCapabilitiesJSON,
                blockingReason: "Blocked by policy review."
            )
        }

        for index in 0..<10 {
            try insertQueueItem(
                connection: connection,
                id: "queue-scale-failed-\(String(format: "%03d", index))",
                state: .failed,
                payloadKind: "automation_request",
                payloadJSON: automationPayload,
                updatedAt: baseDate.addingTimeInterval(-Double(index + 50)),
                reviewReason: "Queue retry fixture row",
                redactedSummary: "Scale failed row \(index)",
                requiredCapabilitiesJSON: requiredCapabilitiesJSON
            )
        }

        var receipts: [ExecutionReceipt] = []
        for index in 4_500..<4_600 {
            let itemID = "queue-scale-done-\(String(format: "%05d", index))"
            receipts.append(contentsOf: [
                makeReceipt(
                    id: "queue-scale-receipt-old-\(itemID)",
                    itemID: itemID,
                    status: .failed,
                    outputSummary: "Older execution for \(itemID)",
                    finishedAt: baseDate.addingTimeInterval(Double(index))
                ),
                makeReceipt(
                    id: "queue-scale-receipt-new-\(itemID)",
                    itemID: itemID,
                    status: .succeeded,
                    outputSummary: "Latest execution for \(itemID)",
                    finishedAt: baseDate.addingTimeInterval(Double(index) + 0.5)
                )
            ])
        }

        let allSnapshot = try store.readModelSnapshot(
            filter: .all(limit: 500),
            receipts: receipts,
            viewFilter: .all,
            sort: .needsActionFirst
        )
        XCTAssertEqual(allSnapshot.rows.count, 500)
        XCTAssertEqual(allSnapshot.totalCount, 5040)
        XCTAssertEqual(allSnapshot.doneCount, 5000)
        XCTAssertEqual(allSnapshot.waitingReviewCount, 20)
        XCTAssertEqual(allSnapshot.blockedCount, 10)
        XCTAssertEqual(allSnapshot.failedCount, 10)
        XCTAssertEqual(allSnapshot.needsAttentionCount, 40)
        XCTAssertTrue(allSnapshot.rows.allSatisfy { $0.state == .done })

        let firstVisibleDone = "queue-scale-done-04500"
        let row = try XCTUnwrap(allSnapshot.rows.first { $0.id == firstVisibleDone })
        XCTAssertEqual(row.latestReceipt?.status, .succeeded)
        XCTAssertEqual(row.latestReceipt?.id, "queue-scale-receipt-new-\(firstVisibleDone)")

        let attentionSnapshot = try store.readModelSnapshot(
            filter: .states(AssistantQueueViewFilter.needsAttention.states, limit: 25),
            receipts: receipts,
            viewFilter: .needsAttention,
            sort: .needsActionFirst
        )
        XCTAssertEqual(attentionSnapshot.rows.count, 25)
        XCTAssertEqual(attentionSnapshot.totalCount, 5040)
        XCTAssertTrue(attentionSnapshot.rows.allSatisfy { AssistantQueueViewFilter.needsAttention.states.contains($0.state) })
        XCTAssertEqual(attentionSnapshot.waitingReviewCount, 20)
        XCTAssertEqual(attentionSnapshot.blockedCount, 10)
        XCTAssertEqual(attentionSnapshot.failedCount, 10)
    }

    func testReadModelSnapshotDoesNotDecodeLargeActionPlanPayloadForWindowedListRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let malformedPayload = String(
            repeating: "\"",
            count: 25_000
        ) + "{ \"state\": \"actionPlan\" , payload_kind: action_plan"

        let requiredCapabilitiesJSON = try jsonString([
            AssistantQueueRequiredCapability.tool(.taskCreate),
            .providerExecutionApproval
        ])
        let largeActionPlanPayload = try largeActionPlanPayloadJSON(actions: 96, argumentSize: 768)
        let baseDate = Date(timeIntervalSince1970: 1_700_001_000)

        for index in 0..<300 {
            try insertQueueItem(
                connection: connection,
                id: "queue-scale-no-decode-done-\(index)",
                state: .done,
                payloadKind: "action_plan",
                payloadJSON: largeActionPlanPayload,
                updatedAt: baseDate.addingTimeInterval(Double(index)),
                reviewReason: "Queue list fixture row",
                redactedSummary: "Scale done row \(index)",
                requiredCapabilitiesJSON: requiredCapabilitiesJSON
            )
        }

        try insertQueueItem(
            connection: connection,
            id: "queue-scale-no-decode-invalid-action-plan",
            state: .waitingReview,
            payloadKind: "action_plan",
            payloadJSON: malformedPayload,
            updatedAt: baseDate.addingTimeInterval(1_000),
            reviewReason: "Queue list fixture invalid payload",
            redactedSummary: "Scale invalid action plan payload",
            requiredCapabilitiesJSON: requiredCapabilitiesJSON
        )

        let snapshot = try store.readModelSnapshot(
            filter: .all(limit: 50),
            receipts: [],
            viewFilter: .all,
            sort: .needsActionFirst
        )

        let invalidRow = try XCTUnwrap(snapshot.rows.first { $0.id == "queue-scale-no-decode-invalid-action-plan" })
        XCTAssertEqual(invalidRow.state, .waitingReview)
        XCTAssertEqual(invalidRow.redactedSummary, "Scale invalid action plan payload")
        XCTAssertFalse(invalidRow.title.isEmpty)

        XCTAssertThrowsError(try store.list(filter: .all(limit: 50))) { error in
            XCTAssertEqual(error as? AssistantQueueStoreError, .decodingFailed(column: "assistant_queue_items.payload_json"))
        }
    }

    @MainActor
    func testProjectBoardViewModelCountsAttentionStatesBeyondTerminalRowLimit() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let oldWaiting = makeItem(id: "queue-count-old-waiting", state: .waitingReview, summary: "Old waiting review")
        try assistantQueueStore.save(oldWaiting)
        for index in 0..<520 {
            try assistantQueueStore.save(makeItem(
                id: "queue-count-done-\(index)",
                state: .done,
                summary: "Done \(index)"
            ))
        }
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()

        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [oldWaiting.id])
        XCTAssertEqual(viewModel.assistantQueueSnapshot.totalCount, 521)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.waitingReviewCount, 1)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.doneCount, 520)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.needsAttentionCount, 1)
    }

    func testReadModelKeepsFullRedactedSummaryForEditing() throws {
        let longSummary = String(repeating: "Long review summary. ", count: 12) + "Final detail."
        let item = makeItem(id: "queue-long-summary", state: .waitingReview, summary: longSummary)

        let row = try XCTUnwrap(AssistantQueueReadModel.snapshot(from: [item]).rows.first)

        XCTAssertEqual(row.redactedSummary, longSummary)
        XCTAssertEqual(row.title, String(longSummary.prefix(160)) + "...")
        XCTAssertLessThan(row.title.count, row.redactedSummary.count)
    }

    func testReadModelMarksOnlyFailedRunnableRowsRetryable() throws {
        let failedActionPlan = makeItem(id: "queue-retry-failed-action", state: .failed)
        let waitingActionPlan = makeItem(id: "queue-retry-waiting-action", state: .waitingReview)
        let dangerousActionPlan = AssistantQueueItem(
            id: "queue-retry-danger-action",
            state: .failed,
            payload: .actionPlan(ActionPlan(
                id: "danger-plan",
                userInput: "Delete task",
                summary: "Delete task",
                actions: [PlanAction(id: "danger-action", tool: .taskDelete, riskLevel: .danger)],
                riskLevel: .danger,
                requiresApproval: true
            )),
            riskLevel: .danger,
            sourceTranscript: "Delete task",
            interpretationSummary: "Danger",
            reviewReason: "Danger retry.",
            redactedSummary: "Delete task",
            requiredCapabilities: [.tool(.taskDelete), .providerExecutionApproval],
            blockingReason: "Dangerous action plans cannot be retried."
        )
        let failedRunnableAutomation = AssistantQueueItem(
            id: "queue-retry-failed-runnable-automation",
            state: .failed,
            payload: makeAutomationRequestItem(
                id: "queue-retry-runnable-automation",
                toolName: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
                taskMutation: SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .updateDueDate,
                    dueAt: "2026-07-01T09:00:00Z",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                )
            ).payload,
            riskLevel: .write,
            sourceTranscript: nil,
            interpretationSummary: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
            reviewReason: "Remote request failed.",
            redactedSummary: "Remote request failed",
            requiredCapabilities: [.connectedMacRequired, .providerExecutionApproval],
            blockingReason: "Remote execution failed."
        )
        let dangerousRunnableAutomation = AssistantQueueItem(
            id: "queue-retry-dangerous-runnable-automation",
            state: .failed,
            payload: failedRunnableAutomation.payload,
            riskLevel: .danger,
            sourceTranscript: nil,
            interpretationSummary: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
            reviewReason: "Remote request failed.",
            redactedSummary: "Remote request failed",
            requiredCapabilities: [.connectedMacRequired, .providerExecutionApproval],
            blockingReason: "Remote execution failed."
        )
        let failedUnsupportedAutomation = AssistantQueueItem(
            id: "queue-retry-failed-unsupported-automation",
            state: .failed,
            payload: makeAutomationRequestItem().payload,
            riskLevel: .write,
            sourceTranscript: nil,
            interpretationSummary: "task.create",
            reviewReason: "Remote request failed.",
            redactedSummary: "Remote request failed",
            requiredCapabilities: [.connectedMacRequired, .providerExecutionApproval],
            blockingReason: "Remote execution failed."
        )

        let snapshot = AssistantQueueReadModel.snapshot(from: [
            failedActionPlan,
            waitingActionPlan,
            dangerousActionPlan,
            failedRunnableAutomation,
            dangerousRunnableAutomation,
            failedUnsupportedAutomation
        ])

        let failedActionPlanRow = try XCTUnwrap(snapshot.rows.first { $0.id == failedActionPlan.id })
        let waitingActionPlanRow = try XCTUnwrap(snapshot.rows.first { $0.id == waitingActionPlan.id })
        let dangerousActionPlanRow = try XCTUnwrap(snapshot.rows.first { $0.id == dangerousActionPlan.id })
        let failedRunnableAutomationRow = try XCTUnwrap(snapshot.rows.first { $0.id == failedRunnableAutomation.id })
        let dangerousRunnableAutomationRow = try XCTUnwrap(snapshot.rows.first { $0.id == dangerousRunnableAutomation.id })
        let failedUnsupportedAutomationRow = try XCTUnwrap(snapshot.rows.first { $0.id == failedUnsupportedAutomation.id })
        XCTAssertTrue(failedActionPlanRow.canRetry)
        XCTAssertFalse(waitingActionPlanRow.canRetry)
        XCTAssertFalse(dangerousActionPlanRow.canRetry)
        XCTAssertTrue(failedRunnableAutomationRow.canRetry)
        XCTAssertFalse(dangerousRunnableAutomationRow.canRetry)
        XCTAssertFalse(failedUnsupportedAutomationRow.canRetry)
    }

    func testReadModelAttachesLatestAssistantQueueExecutionReceiptSummary() throws {
        let item = makeItem(id: "queue-read-model-receipt", state: .done, summary: "Create launch task")
        let olderReceipt = makeReceipt(
            id: "receipt-old",
            itemID: item.id,
            status: .failed,
            outputSummary: "Failed with token=sk-olderSecret",
            finishedAt: Date(timeIntervalSince1970: 10)
        )
        let latestReceipt = makeReceipt(
            id: "receipt-latest",
            itemID: item.id,
            status: .succeeded,
            outputSummary: "Created task from /Users/local/private-plan.md",
            finishedAt: Date(timeIntervalSince1970: 20),
            actionCount: 2,
            usage: ExecutionReceiptUsage(
                inputTokens: 1_000,
                outputTokens: 500,
                estimatedCostCents: 0.25,
                currencyCode: "USD",
                state: .estimated
            )
        )
        let unrelatedReceipt = makeReceipt(
            id: "receipt-unrelated",
            itemID: "other-queue-item",
            status: .succeeded,
            outputSummary: "Other queue item",
            finishedAt: Date(timeIntervalSince1970: 30)
        )
        let hiddenReceipt = makeReceipt(
            id: "receipt-hidden",
            itemID: item.id,
            status: .failed,
            outputSummary: "Hidden from Assistant Queue",
            finishedAt: Date(timeIntervalSince1970: 40),
            visibleSurfaces: []
        )

        let snapshot = AssistantQueueReadModel.snapshot(
            from: [item],
            receipts: [olderReceipt, latestReceipt, unrelatedReceipt, hiddenReceipt]
        )

        let row = try XCTUnwrap(snapshot.rows.first)
        let receipt = try XCTUnwrap(row.latestReceipt)
        XCTAssertEqual(receipt.id, latestReceipt.id)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.statusLabel, "Succeeded")
        XCTAssertEqual(receipt.actionCount, 2)
        XCTAssertTrue(receipt.usageLabel.contains("Estimated"))
        XCTAssertTrue(receipt.usageLabel.contains("1,500 tokens"))
        XCTAssertTrue(receipt.usageLabel.contains("USD 0.0025"))
        XCTAssertFalse(receipt.outputSummary.contains("/Users/local/private-plan.md"))
        XCTAssertTrue(receipt.outputSummary.contains("[REDACTED_LOCAL_PATH]"))
    }

    @MainActor
    func testProjectBoardViewModelLoadsAssistantQueueSnapshotFromStore() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(id: "queue-project-board", state: .waitingReview, summary: "Create board-visible task")
        try assistantQueueStore.save(item)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()

        XCTAssertEqual(viewModel.assistantQueueSnapshot.reviewableCount, 1)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first?.id, item.id)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelLoadsAssistantQueueReceiptSummaries() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let item = makeItem(id: "queue-project-board-receipt", state: .done, summary: "Create visible receipt task")
        try assistantQueueStore.save(item)
        try receiptStore.save(makeReceipt(
            id: "receipt-project-board",
            itemID: item.id,
            status: .succeeded,
            outputSummary: "Created visible receipt task",
            finishedAt: Date(timeIntervalSince1970: 50)
        ))
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )

        viewModel.load()
        viewModel.setAssistantQueueViewFilter(.done)

        let row = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == item.id })
        XCTAssertEqual(row.latestReceipt?.id, "receipt-project-board")
        XCTAssertEqual(row.latestReceipt?.statusLabel, "Succeeded")
        XCTAssertEqual(row.latestReceipt?.outputSummary, "Created visible receipt task")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelTransitionsAssistantQueueRowsFromVisibleInboxActions() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let waiting = makeItem(id: "queue-visible-approve", state: .waitingReview, summary: "Create visible inbox task")
        let deferred = makeItem(id: "queue-visible-defer", state: .waitingReview, summary: "Review later")
        let blocked = makeItem(id: "queue-visible-blocked", state: .blocked, summary: "Blocked destructive plan")
        try assistantQueueStore.save(waiting)
        try assistantQueueStore.save(deferred)
        try assistantQueueStore.save(blocked)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()
        let waitingRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == waiting.id }?.mutationRevision
        )
        let blockedRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == blocked.id }?.mutationRevision
        )
        let deferredRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == deferred.id }?.mutationRevision
        )

        XCTAssertTrue(viewModel.approveAssistantQueueItem(
            id: waiting.id,
            expectedMutationRevision: waitingRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: waiting.id).state, .approved)
        XCTAssertNil(try assistantQueueStore.get(id: waiting.id).approval?.executionTokenID)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == waiting.id }?.state, .approved)

        XCTAssertTrue(viewModel.deferAssistantQueueItem(
            id: deferred.id,
            expectedMutationRevision: deferredRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: deferred.id).state, .deferred)
        XCTAssertNil(viewModel.assistantQueueSnapshot.rows.first { $0.id == deferred.id })
        viewModel.setAssistantQueueViewFilter(.deferred)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == deferred.id }?.state, .deferred)
        viewModel.setAssistantQueueViewFilter(.needsAttention)

        XCTAssertFalse(viewModel.approveAssistantQueueItem(
            id: blocked.id,
            expectedMutationRevision: blockedRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: blocked.id).state, .blocked)
        XCTAssertEqual(viewModel.errorMessage, "Blocked Assistant Queue items cannot be approved.")

        XCTAssertTrue(viewModel.rejectAssistantQueueItem(
            id: blocked.id,
            expectedMutationRevision: blockedRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: blocked.id).state, .rejected)
        XCTAssertNil(viewModel.assistantQueueSnapshot.rows.first { $0.id == blocked.id })
        viewModel.setAssistantQueueViewFilter(.all)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == blocked.id }?.state, .rejected)
    }

    @MainActor
    func testProjectBoardViewModelFiltersSortsAndSafelyBatchCleansAssistantQueueRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let waiting = makeItem(id: "queue-batch-waiting", state: .waitingReview, summary: "Review waiting")
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-batch-approved", state: .waitingReview, summary: "Approved cleanup"),
            reviewerID: "local-user"
        )
        let failed = makeItem(id: "queue-batch-failed", state: .failed, summary: "Failed cleanup")
        let done = makeItem(id: "queue-batch-done", state: .done, summary: "Done cleanup")
        let running = try AssistantQueueStateMachine.startRunning(
            AssistantQueueStateMachine.approve(
                makeItem(id: "queue-batch-running", state: .waitingReview, summary: "Running cleanup"),
                reviewerID: "local-user"
            )
        )
        try assistantQueueStore.save(waiting)
        try assistantQueueStore.save(approved)
        try assistantQueueStore.save(failed)
        try assistantQueueStore.save(done)
        try assistantQueueStore.save(running)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()

        XCTAssertEqual(viewModel.assistantQueueViewFilter, .needsAttention)
        XCTAssertEqual(viewModel.assistantQueueSort, .needsActionFirst)
        XCTAssertEqual(
            Set(viewModel.assistantQueueSnapshot.rows.map(\.id)),
            Set([waiting.id, approved.id, failed.id])
        )
        XCTAssertEqual(viewModel.assistantQueueSnapshot.totalCount, 5)

        viewModel.setAssistantQueueViewFilter(.done)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [done.id])

        viewModel.setAssistantQueueViewFilter(.all)
        viewModel.setAssistantQueueSort(.titleAscending)
        XCTAssertEqual(
            viewModel.assistantQueueSnapshot.rows.map(\.title),
            ["Approved cleanup", "Done cleanup", "Failed cleanup", "Review waiting", "Running cleanup"]
        )

        XCTAssertFalse(viewModel.setAssistantQueueSelection(id: running.id, selected: true))
        XCTAssertFalse(viewModel.assistantQueueSelectedItemIDs.contains(running.id))
        XCTAssertEqual(try assistantQueueStore.get(id: running.id).state, .running)
        let runningRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == running.id }?.mutationRevision
        )
        XCTAssertFalse(viewModel.approveAssistantQueueItem(
            id: running.id,
            expectedMutationRevision: runningRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: running.id).state, .running)
        XCTAssertFalse(viewModel.rejectAssistantQueueItem(
            id: running.id,
            expectedMutationRevision: runningRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: running.id).state, .running)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue item cannot be changed by that review action in its current state."
        )
        XCTAssertFalse(viewModel.deferAssistantQueueItem(
            id: running.id,
            expectedMutationRevision: runningRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: running.id).state, .running)

        XCTAssertTrue(viewModel.toggleAssistantQueueSelection(id: waiting.id))
        XCTAssertTrue(viewModel.toggleAssistantQueueSelection(id: approved.id))
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, Set([waiting.id, approved.id]))
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: waiting.id, selected: true))
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, Set([waiting.id, approved.id]))
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: waiting.id, selected: false))
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, Set([approved.id]))
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: waiting.id, selected: true))
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, Set([waiting.id, approved.id]))
        XCTAssertTrue(viewModel.deferSelectedAssistantQueueItems())
        XCTAssertEqual(try assistantQueueStore.get(id: waiting.id).state, .deferred)
        XCTAssertEqual(try assistantQueueStore.get(id: approved.id).state, .deferred)
        XCTAssertTrue(viewModel.assistantQueueSelectedItemIDs.isEmpty)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Deferred 2 Assistant Queue items.")

        viewModel.setAssistantQueueViewFilter(.all)
        XCTAssertFalse(viewModel.toggleAssistantQueueSelection(id: failed.id))
        XCTAssertFalse(viewModel.toggleAssistantQueueSelection(id: done.id))
        XCTAssertTrue(viewModel.assistantQueueSelectedItemIDs.isEmpty)
        XCTAssertFalse(viewModel.rejectSelectedAssistantQueueItems())
        XCTAssertEqual(try assistantQueueStore.get(id: failed.id).state, .failed)
        XCTAssertEqual(try assistantQueueStore.get(id: done.id).state, .done)
        XCTAssertEqual(viewModel.errorMessage, "No selected Assistant Queue items can be rejected.")
    }

    @MainActor
    func testProjectBoardViewModelBatchTransitionIsAtomicWhenAnotherWindowStartsAnItem() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let first = makeItem(id: "queue-batch-atomic-first", state: .waitingReview, summary: "First review")
        let second = makeItem(id: "queue-batch-atomic-second", state: .waitingReview, summary: "Second review")
        try assistantQueueStore.save(first)
        try assistantQueueStore.save(second)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: first.id, selected: true))
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: second.id, selected: true))

        let approved = try AssistantQueueStateMachine.approve(
            assistantQueueStore.get(id: second.id),
            reviewerID: "other-window"
        )
        try assistantQueueStore.save(AssistantQueueStateMachine.startRunning(approved))

        XCTAssertFalse(viewModel.rejectSelectedAssistantQueueItems())
        XCTAssertEqual(try assistantQueueStore.get(id: first.id).state, .waitingReview)
        XCTAssertEqual(try assistantQueueStore.get(id: second.id).state, .running)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue item changed elsewhere. Review the latest version before acting."
        )
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [first.id])
    }

    @MainActor
    func testProjectBoardViewModelBatchTransitionRejectsMixedEligibilityWithoutPartialWork() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let waiting = makeItem(id: "queue-batch-mixed-waiting", state: .waitingReview, summary: "Waiting")
        let blocked = makeItem(id: "queue-batch-mixed-blocked", state: .blocked, summary: "Blocked")
        try store.save(waiting)
        try store.save(blocked)
        let viewModel = ProjectBoardViewModel(
            store: SQLiteProjectBoardStore(connection: connection),
            assistantQueueStore: store
        )
        viewModel.load()
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: waiting.id, selected: true))
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: blocked.id, selected: true))

        XCTAssertFalse(viewModel.deferSelectedAssistantQueueItems())

        XCTAssertEqual(try store.get(id: waiting.id).state, .waitingReview)
        XCTAssertEqual(try store.get(id: blocked.id).state, .blocked)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Every selected Assistant Queue item must support Defer."
        )
    }

    @MainActor
    func testProjectBoardViewModelReopensFailedAssistantQueueItemForRetryReview() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-visible-retry", state: .waitingReview, summary: "Create retry task"),
            reviewerID: "local-user"
        )
        let running = try AssistantQueueStateMachine.startRunning(approved)
        let failed = try AssistantQueueStateMachine.markFailed(running, reason: "Execution failed.")
        try assistantQueueStore.save(failed)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()
        let failedRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == failed.id }?.mutationRevision
        )

        XCTAssertTrue(viewModel.retryAssistantQueueItem(
            id: failed.id,
            expectedMutationRevision: failedRevision
        ))
        let reopened = try assistantQueueStore.get(id: failed.id)
        XCTAssertEqual(reopened.state, .waitingReview)
        XCTAssertNil(reopened.approval)
        XCTAssertNil(reopened.blockingReason)
        XCTAssertEqual(reopened.reviewReason, "Retry after failed execution. Review this Assistant Queue item before running it again.")
        let row = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == failed.id })
        XCTAssertTrue(row.canApprove)
        XCTAssertFalse(row.canRun)
        XCTAssertFalse(row.canRetry)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Reopened Assistant Queue item for review.")
        XCTAssertNil(viewModel.errorMessage)

        let reopenedRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == failed.id }?.mutationRevision
        )
        XCTAssertFalse(viewModel.retryAssistantQueueItem(
            id: failed.id,
            expectedMutationRevision: reopenedRevision
        ))
        XCTAssertEqual(viewModel.errorMessage, "Only failed runnable Assistant Queue items can be retried.")
        XCTAssertNil(viewModel.integrationStatusMessage)
    }

    @MainActor
    func testProjectBoardViewModelReopensFailedTaskMutationAutomationRequestForRetryReview() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let item = AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: "queue-visible-automation-retry",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
            redactedArgumentSummary: "taskID=42, dueAt=2026-07-01T09:00:00Z",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .updateDueDate,
                dueAt: "2026-07-01T09:00:00Z",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        let running = try AssistantQueueStateMachine.startRunning(approved)
        let failed = try AssistantQueueStateMachine.markFailed(running, reason: "Remote task update failed.")
        try assistantQueueStore.save(failed)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()

        let failedRow = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == failed.id })
        XCTAssertTrue(failedRow.canRetry)
        XCTAssertTrue(viewModel.retryAssistantQueueItem(
            id: failed.id,
            expectedMutationRevision: try XCTUnwrap(failedRow.mutationRevision)
        ))
        let reopened = try assistantQueueStore.get(id: failed.id)
        XCTAssertEqual(reopened.state, .waitingReview)
        XCTAssertNil(reopened.approval)
        XCTAssertNil(reopened.blockingReason)
        XCTAssertEqual(reopened.reviewReason, "Retry after failed execution. Review this Assistant Queue item before running it again.")
        let row = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == failed.id })
        XCTAssertTrue(row.canApprove)
        XCTAssertFalse(row.canRun)
        XCTAssertFalse(row.canRetry)
    }

    @MainActor
    func testProjectBoardViewModelEditsAssistantQueueReviewDetailsAndClearsApproval() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-visible-edit", state: .waitingReview, summary: "Create visible edit task"),
            reviewerID: "local-user"
        )
        try assistantQueueStore.save(approved)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()
        let expectedMutationRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id }?.mutationRevision
        )

        XCTAssertTrue(viewModel.editAssistantQueueItem(
            id: approved.id,
            expectedMutationRevision: expectedMutationRevision,
            reviewReason: "User narrowed the scope",
            redactedSummary: "Create [REDACTED_SECRET] edit task"
        ))
        let edited = try assistantQueueStore.get(id: approved.id)
        XCTAssertEqual(edited.state, .waitingReview)
        XCTAssertNil(edited.approval)
        XCTAssertEqual(edited.reviewReason, "User narrowed the scope")
        XCTAssertEqual(edited.redactedSummary, "Create [REDACTED_SECRET] edit task")
        let row = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id })
        XCTAssertTrue(row.canApprove)
        XCTAssertFalse(row.canRun)
        XCTAssertTrue(row.canEdit)
        XCTAssertEqual(row.reviewReason, "User narrowed the scope")
        XCTAssertEqual(row.redactedSummary, "Create [REDACTED_SECRET] edit task")
        XCTAssertEqual(row.title, "Create [REDACTED_SECRET] edit task")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Updated Assistant Queue review details.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelRejectsStaleReviewEditFromAnotherWindow() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(
            id: "queue-stale-review-edit",
            state: .waitingReview,
            summary: "Original review summary"
        )
        try assistantQueueStore.save(item)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let staleRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == item.id }?.mutationRevision
        )

        var concurrentEdit = try assistantQueueStore.get(id: item.id)
        concurrentEdit.reviewReason = "Updated in another window"
        concurrentEdit.redactedSummary = "Latest review summary"
        try assistantQueueStore.save(concurrentEdit)

        XCTAssertFalse(viewModel.editAssistantQueueItem(
            id: item.id,
            expectedMutationRevision: staleRevision,
            reviewReason: "Stale review reason",
            redactedSummary: "Stale review summary"
        ))
        let stored = try assistantQueueStore.get(id: item.id)
        XCTAssertEqual(stored.reviewReason, "Updated in another window")
        XCTAssertEqual(stored.redactedSummary, "Latest review summary")
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue item changed elsewhere. Review the latest version before acting."
        )
        let latestRow = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == item.id }
        )
        XCTAssertNotEqual(latestRow.mutationRevision, staleRevision)
        XCTAssertEqual(latestRow.reviewReason, "Updated in another window")
        XCTAssertEqual(latestRow.redactedSummary, "Latest review summary")
    }

    @MainActor
    func testProjectBoardViewModelKeepsFilteredOutStaleEditRowVisibleForRecovery() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(
            id: "queue-filtered-stale-review-edit",
            state: .waitingReview,
            summary: "Original filtered review summary"
        )
        try store.save(item)
        let viewModel = ProjectBoardViewModel(
            store: SQLiteProjectBoardStore(connection: connection),
            assistantQueueStore: store
        )
        viewModel.load()
        viewModel.setAssistantQueueViewFilter(.waiting)
        let staleRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == item.id }?.mutationRevision
        )
        _ = try store.transition(id: item.id) { current in
            try AssistantQueueStateMachine.approve(
                current,
                reviewerID: "another-window"
            )
        }

        XCTAssertFalse(viewModel.editAssistantQueueItem(
            id: item.id,
            expectedMutationRevision: staleRevision,
            reviewReason: "Local draft that must stay in the editor",
            redactedSummary: "Local draft summary"
        ))

        XCTAssertEqual(viewModel.assistantQueueViewFilter, .all)
        let latestRow = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == item.id }
        )
        XCTAssertEqual(latestRow.state, .approved)
        XCTAssertNotEqual(latestRow.mutationRevision, staleRevision)
        XCTAssertEqual(try store.get(id: item.id).state, .approved)
    }

    @MainActor
    func testProjectBoardViewModelRejectsApprovalForContentChangedInAnotherWindow() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(
            id: "queue-stale-approval",
            state: .waitingReview,
            summary: "Original approval scope"
        )
        try store.save(item)
        let viewModel = ProjectBoardViewModel(
            store: SQLiteProjectBoardStore(connection: connection),
            assistantQueueStore: store
        )
        viewModel.load()
        let staleRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == item.id }?.mutationRevision
        )
        var concurrentEdit = try store.get(id: item.id)
        concurrentEdit.reviewReason = "Changed approval scope"
        concurrentEdit.redactedSummary = "Latest approval scope"
        try store.save(concurrentEdit)

        XCTAssertFalse(viewModel.approveAssistantQueueItem(
            id: item.id,
            expectedMutationRevision: staleRevision
        ))

        let stored = try store.get(id: item.id)
        XCTAssertEqual(stored.state, .waitingReview)
        XCTAssertNil(stored.approval)
        XCTAssertEqual(stored.redactedSummary, "Latest approval scope")
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue item changed elsewhere. Review the latest version before acting."
        )
    }

    @MainActor
    func testProjectBoardViewModelLegacyUnversionedReviewActionsFailClosed() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(
            id: "queue-legacy-unversioned-mutation",
            state: .waitingReview,
            summary: "Original review scope"
        )
        try store.save(item)
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(
                id: "queue-legacy-unversioned-run",
                state: .waitingReview,
                summary: "Approved legacy run"
            ),
            reviewerID: "local-user"
        )
        try store.save(approved)
        let failed = try AssistantQueueStateMachine.markFailed(
            AssistantQueueStateMachine.startRunning(
                AssistantQueueStateMachine.approve(
                    makeItem(
                        id: "queue-legacy-unversioned-retry",
                        state: .waitingReview,
                        summary: "Failed legacy retry"
                    ),
                    reviewerID: "local-user"
                )
            ),
            reason: "Execution failed."
        )
        try store.save(failed)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(
                    required: ["title"],
                    properties: ["title": "string"]
                ),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                XCTFail("An unversioned Run action must not reach the executor.")
                return ToolResult(
                    tool: .taskCreate,
                    status: .failed,
                    summary: "must not execute"
                )
            }
        ])
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: SQLiteProjectBoardStore(connection: connection),
            assistantQueueStore: store,
            assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator(
                queueStore: store,
                executor: ActionExecutor(registry: registry),
                executionReceiptStore: receiptStore
            ),
            executionReceiptStore: receiptStore
        )
        viewModel.load()

        XCTAssertFalse(viewModel.approveAssistantQueueItem(id: item.id))
        XCTAssertFalse(viewModel.deferAssistantQueueItem(id: item.id))
        XCTAssertFalse(viewModel.rejectAssistantQueueItem(id: item.id))
        XCTAssertFalse(viewModel.editAssistantQueueItem(
            id: item.id,
            reviewReason: "Unversioned edit",
            redactedSummary: "Unversioned summary"
        ))
        XCTAssertFalse(viewModel.retryAssistantQueueItem(id: failed.id))
        XCTAssertFalse(viewModel.runAssistantQueueItem(id: approved.id))

        let stored = try store.get(id: item.id)
        XCTAssertEqual(stored.state, .waitingReview)
        XCTAssertNil(stored.approval)
        XCTAssertEqual(stored.reviewReason, item.reviewReason)
        XCTAssertEqual(stored.redactedSummary, item.redactedSummary)
        XCTAssertEqual(try store.get(id: failed.id).state, .failed)
        XCTAssertEqual(try store.get(id: approved.id).state, .approved)
        XCTAssertTrue(receiptStore.receipts.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue action needs the latest revision. Reload the queue and try again."
        )
    }

    @MainActor
    func testProjectBoardViewModelReportsActionNeutralMessageForStaleBatchMutation() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(
            id: "queue-stale-batch",
            state: .waitingReview,
            summary: "Original batch scope"
        )
        try store.save(item)
        let viewModel = ProjectBoardViewModel(
            store: SQLiteProjectBoardStore(connection: connection),
            assistantQueueStore: store
        )
        viewModel.load()
        XCTAssertTrue(viewModel.setAssistantQueueSelection(id: item.id, selected: true))

        var concurrentEdit = try store.get(id: item.id)
        concurrentEdit.reviewReason = "Updated outside this window"
        try store.save(concurrentEdit)

        XCTAssertFalse(viewModel.deferSelectedAssistantQueueItems())
        XCTAssertEqual(try store.get(id: item.id).state, .waitingReview)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue item changed elsewhere. Review the latest version before acting."
        )
    }

    @MainActor
    func testProjectBoardViewModelRunsApprovedAssistantQueueItemThroughExecutionCoordinator() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-visible-run", state: .waitingReview, summary: "Create runnable task"),
            reviewerID: "local-user"
        )
        try assistantQueueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created runnable task")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-board-queue" },
            now: { Date(timeIntervalSince1970: 500) }
        )
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id }?.canRun, true)
        XCTAssertTrue(viewModel.runAssistantQueueItem(
            id: approved.id,
            expectedMutationRevision: try XCTUnwrap(approved.mutationRevision)
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: approved.id).state, .done)
        XCTAssertNil(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id })
        viewModel.setAssistantQueueViewFilter(.done)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id }?.state, .done)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id }?.latestReceipt?.status, .succeeded)
        XCTAssertEqual(receiptStore.receipts.first?.assistantQueueItemID, approved.id)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Executed Assistant Queue item.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelApproveAndRunUsesFreshApprovalRevision() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let waiting = makeItem(
            id: "queue-visible-approve-and-run",
            state: .waitingReview,
            summary: "Create approve and run task"
        )
        try assistantQueueStore.save(waiting)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created approve and run task")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-board-queue-approve-and-run" },
            now: { Date(timeIntervalSince1970: 505) }
        )
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        let initialRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == waiting.id }?.mutationRevision
        )
        XCTAssertTrue(viewModel.approveAndRunAssistantQueueItem(
            id: waiting.id,
            expectedMutationRevision: initialRevision
        ))
        XCTAssertEqual(try assistantQueueStore.get(id: waiting.id).state, .done)
        XCTAssertEqual(receiptStore.receipts.first?.assistantQueueItemID, waiting.id)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Executed Assistant Queue item.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelApproveAndRunRejectsMutationAfterApproval() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let waiting = makeItem(
            id: "queue-approve-and-run-concurrent-mutation",
            state: .waitingReview,
            summary: "Original reviewed summary"
        )
        try assistantQueueStore.save(waiting)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created task")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore
        )
        var shouldMutateAfterApproval = true
        var concurrentMutationError: Error?
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: receiptStore,
            onChange: {
                guard shouldMutateAfterApproval else {
                    return
                }
                shouldMutateAfterApproval = false
                do {
                    _ = try assistantQueueStore.transition(id: waiting.id) { current in
                        let edited = try AssistantQueueStateMachine.editReviewDetails(
                            current,
                            reviewReason: "Concurrent review",
                            redactedSummary: "Changed reviewed summary"
                        )
                        return try AssistantQueueStateMachine.approve(
                            edited,
                            reviewerID: "concurrent-reviewer"
                        )
                    }
                } catch {
                    concurrentMutationError = error
                }
            }
        )

        viewModel.load()

        let initialRevision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == waiting.id }?.mutationRevision
        )
        XCTAssertFalse(viewModel.approveAndRunAssistantQueueItem(
            id: waiting.id,
            expectedMutationRevision: initialRevision
        ))
        XCTAssertNil(concurrentMutationError)
        let stored = try assistantQueueStore.get(id: waiting.id)
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.redactedSummary, "Changed reviewed summary")
        XCTAssertTrue(receiptStore.receipts.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue item changed. Review the latest details before running it."
        )
    }

    @MainActor
    func testProjectBoardViewModelApproveAndRunLeavesUnsupportedPayloadInReview() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let unsupported = makeAutomationRequestItem(
            id: "queue-unsupported-approve-and-run"
        )
        var waitingUnsupported = unsupported
        waitingUnsupported.state = .waitingReview
        try assistantQueueStore.save(waitingUnsupported)
        let receiptStore = VolatileExecutionReceiptStore()
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: try ToolRegistry(tools: [])),
            executionReceiptStore: receiptStore
        )
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        let revision = try XCTUnwrap(
            viewModel.assistantQueueSnapshot.rows.first { $0.id == waitingUnsupported.id }?.mutationRevision
        )
        XCTAssertFalse(viewModel.approveAndRunAssistantQueueItem(
            id: waitingUnsupported.id,
            expectedMutationRevision: revision
        ))
        let stored = try assistantQueueStore.get(id: waitingUnsupported.id)
        XCTAssertEqual(stored.state, .waitingReview)
        XCTAssertNil(stored.approval)
        XCTAssertTrue(receiptStore.receipts.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This Assistant Queue item cannot run from Project Board yet."
        )
    }

    @MainActor
    func testProjectBoardViewModelReportsReceiptPersistenceFailureAfterAssistantQueueExecution() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = FailingAssistantQueueExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-receipt-persistence-failure", state: .waitingReview, summary: "Create receipt failure task"),
            reviewerID: "local-user"
        )
        try assistantQueueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created receipt failure task")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-board-queue-receipt-failure" },
            now: { Date(timeIntervalSince1970: 510) }
        )
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        XCTAssertFalse(viewModel.runAssistantQueueItem(
            id: approved.id,
            expectedMutationRevision: try XCTUnwrap(approved.mutationRevision)
        ))
        let failed = try assistantQueueStore.get(id: approved.id)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(
            failed.blockingReason,
            "Execution completed, but the execution receipt could not be saved. Fix receipt storage before retrying."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Assistant Queue execution finished, but the execution receipt could not be saved. Fix receipt storage before retrying."
        )
        XCTAssertNil(viewModel.integrationStatusMessage)
    }

    @MainActor
    func testProjectBoardViewModelReportsManagedUsageLedgerFailureAfterAssistantQueueExecution() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(
                id: "queue-managed-usage-ledger-failure",
                state: .waitingReview,
                summary: "Create managed ledger failure task",
                costPreview: makeCostPreview(inputTokens: 1_000, outputTokens: 500)
            ),
            reviewerID: "local-user"
        )
        try assistantQueueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created managed ledger failure task")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIUsageLedgerStore: FailingManagedAIUsageLedgerStore(),
            runIDProvider: { "run-board-queue-managed-ledger-failure" },
            now: { Date(timeIntervalSince1970: 520) }
        )
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        XCTAssertFalse(viewModel.runAssistantQueueItem(
            id: approved.id,
            expectedMutationRevision: try XCTUnwrap(approved.mutationRevision)
        ))
        let failed = try assistantQueueStore.get(id: approved.id)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(
            failed.blockingReason,
            "Execution completed, but the managed AI usage ledger could not be saved. Fix billing ledger storage before retrying."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Assistant Queue execution finished, but managed AI usage could not be saved. Fix billing ledger storage before retrying."
        )
        XCTAssertNil(viewModel.integrationStatusMessage)
        XCTAssertEqual(receiptStore.receipts.count, 1)
    }

    @MainActor
    func testProjectBoardViewModelReportsManagedUsageCapExceededDetailAfterAssistantQueueExecution() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let ledgerStore = SQLiteManagedAIUsageLedgerStore(connection: connection)
        try ledgerStore.record(ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "receipt", value: "existing-board-cap"),
            assistantQueueItemDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "assistant_queue_item", value: "existing-board-cap"),
            billingMode: .suisuiManaged,
            provider: "openai",
            modelName: "gpt-managed",
            usageState: .estimated,
            inputTokens: 1_000,
            outputTokens: 500,
            costCents: 80,
            currencyCode: "USD",
            occurredAt: Date(timeIntervalSince1970: 1_788_280_400)
        ))
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(
                id: "queue-managed-usage-cap-exceeded",
                state: .waitingReview,
                summary: "Create managed cap task",
                costPreview: makeCostPreview(inputTokens: 1_000, outputTokens: 500)
            ),
            reviewerID: "local-user"
        )
        try assistantQueueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                XCTFail("Managed AI cap enforcement must stop before ProjectBoard tool execution.")
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created managed cap task")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIUsageLedgerStore: ledgerStore,
            managedAIBillingSettings: ManagedAIBillingSettings(
                isEnabled: true,
                dailyCapCents: 80
            ),
            runIDProvider: { "run-board-queue-managed-cap" },
            now: { Date(timeIntervalSince1970: 1_788_282_000) }
        )
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        XCTAssertFalse(viewModel.runAssistantQueueItem(
            id: approved.id,
            expectedMutationRevision: try XCTUnwrap(approved.mutationRevision)
        ))
        XCTAssertEqual(
            viewModel.errorMessage,
            "Managed AI daily cap would be exceeded. Current USD 0.80 plus this run USD 0.0025 exceeds USD 0.80."
        )
        XCTAssertTrue(receiptStore.receipts.isEmpty)
    }

    @MainActor
    func testProjectBoardViewModelFocusesVoiceHandoffApprovedQueueItemDespiteStaleFilter() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-voice-handoff-approved", state: .waitingReview, summary: "Create voice handoff task"),
            reviewerID: "local-user"
        )
        try assistantQueueStore.save(approved)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()
        viewModel.setAssistantQueueViewFilter(.done)

        XCTAssertFalse(viewModel.assistantQueueSnapshot.rows.contains { $0.id == approved.id })

        XCTAssertTrue(viewModel.focusAssistantQueueExecutionHandoff(id: approved.id))

        XCTAssertEqual(viewModel.assistantQueueViewFilter, .approved)
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, Set([approved.id]))
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id }?.state, .approved)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.integrationStatusMessage)
    }

    @MainActor
    func testProjectBoardViewModelReportsMissingVoiceHandoffQueueItem() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()

        XCTAssertFalse(viewModel.focusAssistantQueueExecutionHandoff(id: "missing-voice-handoff"))

        XCTAssertEqual(viewModel.assistantQueueViewFilter, .all)
        XCTAssertTrue(viewModel.assistantQueueSelectedItemIDs.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Assistant Queue item is no longer available.")
        XCTAssertNil(viewModel.integrationStatusMessage)
    }

    @MainActor
    func testProjectBoardViewModelReportsVoiceHandoffStoreFailureBeforeMissingItem() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: FailingAssistantQueueStore(error: AssistantQueueStoreError.saveFailed)
        )

        XCTAssertFalse(viewModel.focusAssistantQueueExecutionHandoff(id: "queue-store-failure"))

        XCTAssertEqual(
            viewModel.errorMessage,
            "Assistant Queue could not save generated work. Confirm local data storage is available, then try again."
        )
        XCTAssertNil(viewModel.integrationStatusMessage)
    }

    private func makeItem(
        id: String = "queue-item",
        state: AssistantQueueState = .waitingReview,
        sourceTranscript: String = "Create a task",
        summary: String = "Create task",
        costPreview: AssistantQueueCostPreview? = .localOnly()
    ) -> AssistantQueueItem {
        AssistantQueueItem(
            id: id,
            state: state,
            payload: .actionPlan(ActionPlan(
                id: "\(id)-plan",
                userInput: sourceTranscript,
                summary: summary,
                actions: [
                    PlanAction(
                        id: "\(id)-action",
                        tool: .taskCreate,
                        arguments: ["title": .string(summary)],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )),
            riskLevel: .write,
            sourceTranscript: sourceTranscript,
            interpretationSummary: "Routed as task intent.",
            reviewReason: "Voice planning draft needs review.",
            redactedSummary: summary,
            requiredCapabilities: [.tool(.taskCreate), .providerExecutionApproval],
            blockingReason: state == .blocked ? "Dangerous action plans cannot be approved from Assistant Queue." : nil,
            costPreview: costPreview
        )
    }

    private func makeCostPreview(
        inputTokens: Int,
        outputTokens: Int,
        hardCapCents: Double = 2
    ) -> AssistantQueueCostPreview {
        AssistantQueueCostRateCard(
            provider: "openai",
            modelName: "gpt-test",
            currencyCode: "USD",
            inputTokenCentsPerMillion: 100,
            outputTokenCentsPerMillion: 300
        ).preview(inputTokens: inputTokens, outputTokens: outputTokens, hardCapCents: hardCapCents)
    }

    private func jsonString<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func largeActionPlanPayloadJSON(actions: Int, argumentSize: Int) throws -> String {
        let actionArguments = String(repeating: "x", count: argumentSize)
        let payload = ActionPlan(
            id: "scale-plan",
            userInput: "Scale plan with large argument payload.",
            summary: "Scale payload for performance regression fixture.",
            actions: (0..<actions).map { index in
                PlanAction(
                    id: "scale-action-\(index)",
                    tool: .taskCreate,
                    arguments: ["title": .string("\(actionArguments) #\(index)")],
                    riskLevel: .write
                )
            },
            riskLevel: .write,
            requiresApproval: true
        )
        return try jsonString(AssistantQueuePayload.actionPlan(payload))
    }

    private func automationRequestPayloadJSON(id: String, toolName: String) throws -> String {
        let payload = AssistantQueueAdapter.makeItem(
            automationRequest: SyncAutomationRequestPayload(
                id: id,
                source: .cloudRelay,
                approvalState: .pendingApproval,
                sourceClientID: "web",
                toolName: toolName,
                redactedArgumentSummary: "Task create request fixture",
                taskMutation: SyncTaskMutationPayload(
                    taskID: 101,
                    operation: .create,
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                )
            )
        ).payload
        return try jsonString(payload)
    }

    private func insertQueueItem(
        connection: SQLiteConnection,
        id: String,
        state: AssistantQueueState,
        payloadKind: String,
        payloadJSON: String,
        updatedAt: Date,
        sourceTranscript: String = "Scale queue source transcript",
        interpretationSummary: String = "Scale queue intent",
        reviewReason: String,
        redactedSummary: String,
        requiredCapabilitiesJSON: String,
        blockingReason: String? = nil,
        costPreviewJSON: String? = nil
    ) throws {
        let timestamp = iso8601String(updatedAt)
        let sourceTranscriptSQL = optionalStringLiteral(sourceTranscript)
        let interpretationSummarySQL = optionalStringLiteral(interpretationSummary)
        let blockingReasonSQL = optionalStringLiteral(blockingReason)
        let costPreviewSQL = optionalStringLiteral(costPreviewJSON)
        try connection.execute(
            """
            INSERT INTO assistant_queue_items (
                id,
                schema_version,
                payload_kind,
                payload_json,
                state,
                risk_level,
                source_transcript,
                interpretation_summary,
                review_reason,
                redacted_summary,
                required_capabilities_json,
                approval_json,
                blocking_reason,
                cost_preview_json,
                created_at,
                updated_at
            )
            VALUES (
                '\(sqlEscaped(id))',
                1,
                '\(sqlEscaped(payloadKind))',
                '\(sqlEscaped(payloadJSON))',
                '\(sqlEscaped(state.rawValue))',
                'write',
                \(sourceTranscriptSQL),
                \(interpretationSummarySQL),
                '\(sqlEscaped(reviewReason))',
                '\(sqlEscaped(redactedSummary))',
                '\(sqlEscaped(requiredCapabilitiesJSON))',
                NULL,
                \(blockingReasonSQL),
                \(costPreviewJSON == nil ? "NULL" : costPreviewSQL),
                '\(timestamp)',
                '\(timestamp)'
            );
            """
        )
    }

    private func optionalStringLiteral(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }
        return "'\(sqlEscaped(value))'"
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func sqlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func makeAutomationRequestItem(
        id: String = "queue-read-model-automation",
        toolName: String = "task.create",
        taskMutation: SyncTaskMutationPayload? = nil
    ) -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: toolName,
            redactedArgumentSummary: "Create remote task draft",
            taskMutation: taskMutation
        ))
    }

    private func makeReceipt(
        id: String,
        itemID: String,
        status: ExecutionReceiptStatus,
        outputSummary: String,
        finishedAt: Date,
        actionCount: Int = 1,
        visibleSurfaces: [ExecutionReceiptSurface] = [.assistantQueue],
        usage: ExecutionReceiptUsage = .unavailable
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            id: id,
            runID: "run-\(id)",
            assistantQueueItemID: itemID,
            createdAt: finishedAt,
            startedAt: finishedAt,
            finishedAt: finishedAt,
            status: status,
            inputPreview: "Queue input preview",
            outputSummary: outputSummary,
            usage: usage,
            actions: (0..<actionCount).map { index in
                ExecutionReceiptActionSummary(
                    id: "\(id)-action-\(index)",
                    toolName: ActionTool.taskCreate.rawValue,
                    status: status,
                    inputPreview: "Action input \(index)",
                    outputSummary: "Action output \(index)"
                )
            },
            visibleSurfaces: visibleSurfaces
        )
    }
}

private struct FailingAssistantQueueStore: AssistantQueueStore {
    let error: Error

    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        throw error
    }

    func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem? {
        throw error
    }

    func get(id: String) throws -> AssistantQueueItem {
        throw error
    }

    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem] {
        throw error
    }

    func stateCounts() throws -> AssistantQueueStateCounts {
        throw error
    }

    func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem {
        throw error
    }
}

private final class FailingAssistantQueueExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case saveFailed
    }

    func save(_ receipt: ExecutionReceipt) throws {
        throw Error.saveFailed
    }

    func list(limit: Int) throws -> [ExecutionReceipt] {
        []
    }

    func list(matching filter: ExecutionReceiptSearchFilter, limit: Int) throws -> [ExecutionReceipt] {
        []
    }

    func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int
    ) throws -> [ExecutionReceipt] {
        []
    }
}

private final class FailingManagedAIUsageLedgerStore: ManagedAIUsageLedgerStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case recordFailed
    }

    func record(_ entry: ManagedAIUsageLedgerEntry) throws {
        throw Error.recordFailed
    }

    func list(limit: Int) throws -> [ManagedAIUsageLedgerEntry] {
        []
    }
}
