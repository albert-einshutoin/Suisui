import XCTest
@testable import SoloPMCore

final class AssistantQueueStoreTests: XCTestCase {
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
        XCTAssertTrue(row.costPreviewLabel?.contains("SoloPM managed") ?? false)
        XCTAssertTrue(row.costPreviewLabel?.contains("USD") ?? false)
        XCTAssertTrue(
            row.costPreviewLabel?.contains("1,500 tokens") ?? false,
            row.costPreviewLabel ?? "missing cost preview label"
        )
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

        let snapshot = AssistantQueueReadModel.snapshot(from: [missingPreview, overCap, approvedOverCap])

        XCTAssertFalse(snapshot.rows.first { $0.id == missingPreview.id }?.canApprove ?? true)
        XCTAssertFalse(snapshot.rows.first { $0.id == overCap.id }?.canApprove ?? true)
        XCTAssertFalse(snapshot.rows.first { $0.id == approvedOverCap.id }?.canRun ?? true)
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
        XCTAssertFalse(automationRow.canRetry)
        XCTAssertTrue(automationRow.canEdit)
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
        let receiptStore = InMemoryExecutionReceiptStore()
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

        XCTAssertTrue(viewModel.approveAssistantQueueItem(id: waiting.id))
        XCTAssertEqual(try assistantQueueStore.get(id: waiting.id).state, .approved)
        XCTAssertNil(try assistantQueueStore.get(id: waiting.id).approval?.executionTokenID)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == waiting.id }?.state, .approved)

        XCTAssertTrue(viewModel.deferAssistantQueueItem(id: deferred.id))
        XCTAssertEqual(try assistantQueueStore.get(id: deferred.id).state, .deferred)
        XCTAssertNil(viewModel.assistantQueueSnapshot.rows.first { $0.id == deferred.id })
        viewModel.setAssistantQueueViewFilter(.deferred)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == deferred.id }?.state, .deferred)
        viewModel.setAssistantQueueViewFilter(.needsAttention)

        XCTAssertFalse(viewModel.approveAssistantQueueItem(id: blocked.id))
        XCTAssertEqual(try assistantQueueStore.get(id: blocked.id).state, .blocked)
        XCTAssertEqual(viewModel.errorMessage, "Blocked Assistant Queue items cannot be approved.")

        XCTAssertTrue(viewModel.rejectAssistantQueueItem(id: blocked.id))
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
        try assistantQueueStore.save(waiting)
        try assistantQueueStore.save(approved)
        try assistantQueueStore.save(failed)
        try assistantQueueStore.save(done)
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
        XCTAssertEqual(viewModel.assistantQueueSnapshot.totalCount, 4)

        viewModel.setAssistantQueueViewFilter(.done)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [done.id])

        viewModel.setAssistantQueueViewFilter(.all)
        viewModel.setAssistantQueueSort(.titleAscending)
        XCTAssertEqual(
            viewModel.assistantQueueSnapshot.rows.map(\.title),
            ["Approved cleanup", "Done cleanup", "Failed cleanup", "Review waiting"]
        )

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
        XCTAssertTrue(viewModel.toggleAssistantQueueSelection(id: failed.id))
        XCTAssertTrue(viewModel.toggleAssistantQueueSelection(id: done.id))
        XCTAssertFalse(viewModel.rejectSelectedAssistantQueueItems())
        XCTAssertEqual(try assistantQueueStore.get(id: failed.id).state, .failed)
        XCTAssertEqual(try assistantQueueStore.get(id: done.id).state, .done)
        XCTAssertEqual(viewModel.errorMessage, "No selected Assistant Queue items can be rejected.")
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

        XCTAssertTrue(viewModel.retryAssistantQueueItem(id: failed.id))
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

        XCTAssertFalse(viewModel.retryAssistantQueueItem(id: failed.id))
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
        XCTAssertTrue(viewModel.retryAssistantQueueItem(id: failed.id))
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

        XCTAssertTrue(viewModel.editAssistantQueueItem(
            id: approved.id,
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
    func testProjectBoardViewModelRunsApprovedAssistantQueueItemThroughExecutionCoordinator() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = InMemoryExecutionReceiptStore()
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
        XCTAssertTrue(viewModel.runAssistantQueueItem(id: approved.id))
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
