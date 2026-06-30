import XCTest
@testable import SoloPMCore

final class ExecutionReceiptTests: XCTestCase {
    func testReviewExecutionReceiptRedactsSecretsAndDisallowedLocalPaths() throws {
        let providerKey = "sk-" + "proj-user-secret"
        let titleSecret = "token" + "=" + "secret-title"
        let outputSecret = "secret" + "=" + "output-secret"
        var session = ReviewSession(
            id: "review-1",
            plan: ActionPlan(
                id: "plan-1",
                userInput: "Create task with \(providerKey) and inspect /Users/alice/My Project/secrets.md",
                summary: "Create a launch task from /Volumes/Satechi/Developer/soloPM/docs/plan.md",
                actions: [
                    PlanAction(
                        id: "action-1",
                        tool: .taskCreate,
                        arguments: [
                            "title": .string("Launch task \(titleSecret)"),
                            "detail": .string("Allowed /Volumes/Satechi/Developer/soloPM/docs/plan.md disallowed /Volumes/Satechi/Developer/soloPM/../Private/escape.md and /Users/alice/My Project/secrets.md")
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        try session.approve(token: ApprovalToken(id: "approval-1", sessionID: session.id, approvedAt: Date(timeIntervalSince1970: 11)))
        session.executionStatus = .completed
        session.markAction(
            id: "action-1",
            status: .succeeded,
            result: ToolResult(
                tool: .taskCreate,
                status: .succeeded,
                summary: "Created task with \(outputSecret) from /Users/alice/My Project/secrets.md",
                output: ["taskId": .number(42), "projectId": .number(7)]
            )
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-1",
            model: ExecutionReceiptModel(provider: "OpenAI", name: "gpt-5.3"),
            usage: ExecutionReceiptUsage(
                inputTokens: 120,
                outputTokens: 32,
                estimatedCostCents: 3.2,
                currencyCode: "USD",
                isEstimated: true
            ),
            startedAt: Date(timeIntervalSince1970: 12),
            finishedAt: Date(timeIntervalSince1970: 13),
            redactionPolicy: ExecutionReceiptRedactionPolicy(
                allowedLocalPathPrefixes: ["/Volumes/Satechi/Developer/soloPM"]
            )
        )

        XCTAssertEqual(receipt.id, "receipt:run-1:review-1")
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.approvalID, "approval-1")
        XCTAssertEqual(receipt.model, ExecutionReceiptModel(provider: "OpenAI", name: "gpt-5.3"))
        XCTAssertEqual(receipt.usage.totalTokens, 152)
        XCTAssertEqual(receipt.usage.state, .estimated)
        XCTAssertTrue(receipt.inputPreview.contains("[REDACTED_SECRET]"))
        XCTAssertTrue(receipt.inputPreview.contains("[REDACTED_LOCAL_PATH]"))
        XCTAssertTrue(receipt.inputPreview.contains("/Volumes/Satechi/Developer/soloPM/docs/plan.md"))
        XCTAssertFalse(receipt.inputPreview.contains(providerKey))
        XCTAssertFalse(receipt.inputPreview.contains("My Project"))
        XCTAssertFalse(receipt.actions[0].inputPreview.contains("Private/escape.md"))
        XCTAssertFalse(receipt.actions[0].inputPreview.contains("secret-title"))
        XCTAssertFalse(receipt.actions[0].outputSummary?.contains("output-secret") ?? true)
        XCTAssertFalse(receipt.actions[0].outputSummary?.contains("secrets.md") ?? true)
        XCTAssertEqual(receipt.references.map(\.kind), [.reviewSession, .actionPlan, .task, .project])
        XCTAssertEqual(receipt.visibleSurfaces, [])
    }

    func testFailedReviewExecutionReceiptCapturesRedactedFailure() throws {
        var session = ReviewSession(
            id: "review-failed",
            plan: ActionPlan(
                id: "plan-failed",
                userInput: "Create calendar block",
                summary: "Schedule a work block",
                actions: [
                    PlanAction(
                        id: "action-calendar",
                        tool: .calendarCreateEvent,
                        arguments: ["title": .string("Customer call")],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        try session.approve(token: ApprovalToken(id: "approval-failed", sessionID: session.id))
        session.executionStatus = .failed
        session.markAction(
            id: "action-calendar",
            status: .failed,
            errorMessage: "Calendar permission denied for \("api_key" + "=" + "calendar-secret")",
            failureRecovery: .notRetryable
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-failed",
            model: nil,
            usage: .unknown,
            startedAt: Date(timeIntervalSince1970: 20),
            finishedAt: Date(timeIntervalSince1970: 21)
        )

        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.actions[0].status, .failed)
        XCTAssertEqual(receipt.actions[0].failureRecovery, .notRetryable)
        XCTAssertEqual(receipt.usage.state, .unknown)
        XCTAssertTrue(receipt.outputSummary.contains("1 failed"))
        XCTAssertTrue(receipt.actions[0].errorSummary?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(receipt.actions[0].errorSummary?.contains("calendar-secret") ?? true)
    }

    func testReviewReceiptKeepsNotStartedAndRunningDistinctFromStarted() {
        var session = ReviewSession(
            id: "review-pending",
            plan: ActionPlan(
                id: "plan-pending",
                userInput: "List tasks",
                summary: "List tasks",
                actions: [PlanAction(id: "action-pending", tool: .taskList, riskLevel: .read)],
                riskLevel: .read,
                requiresApproval: false
            )
        )
        let pendingReceipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-pending",
            model: nil,
            usage: .unknown,
            startedAt: nil,
            finishedAt: nil
        )
        XCTAssertEqual(pendingReceipt.status, .notStarted)
        XCTAssertEqual(pendingReceipt.actions[0].status, .notStarted)

        session.executionStatus = .executing
        session.markAction(id: "action-pending", status: .executing)
        let runningReceipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-running",
            model: nil,
            usage: .unknown,
            startedAt: Date(timeIntervalSince1970: 22),
            finishedAt: nil
        )
        XCTAssertEqual(runningReceipt.status, .running)
        XCTAssertEqual(runningReceipt.actions[0].status, .running)
    }

    func testApprovedAutomationReceiptCanBeLiftedToCommonExecutionReceipt() {
        let titleSecret = "secret" + "=" + "title-secret"
        let detailSecret = "sk-" + "proj-detail-secret"
        let reviewSecret = "token" + "=" + "review-secret"
        let automationReceipt = ApprovedAutomationExecutionReceipt(
            taskID: 42,
            projectID: 7,
            redactedTaskTitle: "Launch \(titleSecret)",
            redactedTaskDetail: "Reviewed \(detailSecret)",
            statusBefore: .planned,
            statusAfter: .inProgress,
            priority: .high,
            dueAt: "2026-07-01T09:00:00Z",
            reviewReason: "User approved \(reviewSecret)"
        )

        let receipt = ExecutionReceiptFactory.makeApprovedAutomationReceipt(
            automationReceipt,
            runID: "run-automation",
            approvalID: "approval-automation",
            createdAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.taskUpdate.rawValue)
        XCTAssertEqual(receipt.approvalID, "approval-automation")
        XCTAssertEqual(receipt.references, [
            ExecutionReceiptReference(kind: .task, id: "42", label: "Launch [REDACTED_SECRET]"),
            ExecutionReceiptReference(kind: .project, id: "7", label: nil)
        ])
        XCTAssertTrue(receipt.outputSummary.contains("planned"))
        XCTAssertTrue(receipt.outputSummary.contains("in_progress"))
        XCTAssertEqual(receipt.usage.state, .unavailable)
        XCTAssertTrue(receipt.actions[0].inputPreview.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(receipt.inputPreview.contains("title-secret"))
        XCTAssertFalse(receipt.inputPreview.contains("detail-secret"))
        XCTAssertFalse(receipt.inputPreview.contains("review-secret"))
    }

    func testAssistantQueueReceiptKeepsQueueApprovalSeparateFromExecutionToken() throws {
        let providerKey = "sk-" + "proj-queue-secret"
        let argumentSecret = "token" + "=" + "queue-argument-secret"
        let spokenSecret = "token" + "=" + "spoken-secret"
        let queueItem = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "plan-queue",
                userInput: "Create a task with \(providerKey)",
                summary: "Create a task from /Users/alice/My Project/queue-secret.md",
                actions: [
                    PlanAction(
                        id: "action-queue",
                        tool: .taskCreate,
                        arguments: ["detail": .string("Use \(argumentSecret)")],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Create a task with \(spokenSecret)",
            interpretationSummary: "Task creation",
            reason: "Needs review."
        )
        let approvedQueueItem = try AssistantQueueStateMachine.approve(queueItem, reviewerID: "user-1")

        let receipt = ExecutionReceiptFactory.makeAssistantQueueReceipt(
            item: approvedQueueItem,
            runID: "run-queue",
            executionApprovalID: "execution-approval-1",
            status: .succeeded,
            outputSummary: "Queued task was executed."
        )

        XCTAssertEqual(receipt.assistantQueueItemID, approvedQueueItem.id)
        XCTAssertEqual(receipt.approvalID, "execution-approval-1")
        XCTAssertEqual(receipt.queueApproval?.reviewerID, "user-1")
        XCTAssertEqual(receipt.queueApproval?.reviewedContentDigest, approvedQueueItem.approval?.reviewedContentFingerprint)
        XCTAssertEqual(receipt.queueApproval?.reviewedContentDigest.count, 64)
        XCTAssertEqual(approvedQueueItem.approval?.executionTokenID, nil)
        XCTAssertTrue(receipt.inputPreview.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(receipt.inputPreview.contains("spoken-secret"))
        XCTAssertEqual(receipt.references.first?.kind, .assistantQueue)
        XCTAssertEqual(receipt.references.first?.id, approvedQueueItem.id)
        XCTAssertTrue(receipt.references.first?.label?.contains("[REDACTED_LOCAL_PATH]") ?? false)

        let encoded = try JSONEncoder().encode(receipt)
        let encodedReceipt = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedReceipt.contains(providerKey))
        XCTAssertFalse(encodedReceipt.contains("queue-secret.md"))
        XCTAssertFalse(encodedReceipt.contains("queue-argument-secret"))
    }

    func testExecutionReceiptRoundTripsThroughJSONForSyncedMetadata() throws {
        let receipt = ExecutionReceipt(
            id: "receipt-json",
            runID: "run-json",
            approvalID: "approval-json",
            assistantQueueItemID: "queue-json",
            queueApproval: ExecutionReceiptQueueApproval(
                reviewerID: "reviewer-json",
                note: "Looks good",
                reviewedContentFingerprint: "fingerprint-json"
            ),
            createdAt: Date(timeIntervalSince1970: 100),
            startedAt: Date(timeIntervalSince1970: 101),
            finishedAt: Date(timeIntervalSince1970: 102),
            status: .succeeded,
            inputPreview: "Input",
            outputSummary: "Output",
            model: ExecutionReceiptModel(provider: "Local", name: "oss-stt"),
            primaryToolName: "task.create",
            usage: ExecutionReceiptUsage(inputTokens: 1, outputTokens: 2, estimatedCostCents: 0, currencyCode: "USD", isEstimated: false),
            references: [ExecutionReceiptReference(kind: .task, id: "1", label: "Task")],
            sourceLinks: [ExecutionReceiptSourceLink(kind: .document, title: "Spec", url: "file://allowed/spec.md")],
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-json",
                    toolName: "task.create",
                    status: .succeeded,
                    inputPreview: "title: Task",
                    outputSummary: "Created",
                    errorSummary: nil,
                    failureRecovery: .retryable
                )
            ],
            visibleSurfaces: [.assistantQueue, .taskDetail]
        )

        let encoded = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(ExecutionReceipt.self, from: encoded)

        XCTAssertEqual(decoded, receipt)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testFileExecutionReceiptStorePersistsRedactedReceipts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileSecret = "token" + "=" + "file-secret"
        let outputSecret = "secret" + "=" + "output-secret"
        let argumentSecret = "token" + "=" + "argument-secret"
        let toolSecret = "api_key" + "=" + "tool-secret"

        let store = try FileExecutionReceiptStore(directoryURL: directory)
        let receipt = ExecutionReceipt(
            id: "receipt/file:json",
            runID: "run-file",
            status: .failed,
            inputPreview: "Input \(fileSecret) from /Users/alice/private.md",
            outputSummary: "Output \(outputSecret)",
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-file",
                    toolName: ActionTool.taskCreate.rawValue,
                    status: .failed,
                    inputPreview: "title: Draft \(argumentSecret)",
                    errorSummary: "Failed \(toolSecret)"
                )
            ]
        )

        try store.save(receipt)

        let loaded = try store.list(limit: 10)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "receipt/file:json")
        XCTAssertTrue(loaded.first?.inputPreview.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertTrue(loaded.first?.inputPreview.contains("[REDACTED_LOCAL_PATH]") ?? false)
        let rawFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let rawContent = try String(contentsOf: rawFile, encoding: .utf8)
        XCTAssertFalse(rawContent.contains("file-secret"))
        XCTAssertFalse(rawContent.contains("private.md"))
        XCTAssertFalse(rawContent.contains("argument-secret"))
        XCTAssertFalse(rawContent.contains("tool-secret"))
    }
}
