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

    func testReviewExecutionReceiptLinksNotificationReferencesFromToolOutput() throws {
        var session = ReviewSession(
            id: "review-notification",
            plan: ActionPlan(
                id: "plan-notification",
                userInput: "Remind me about standup",
                summary: "Schedule a notification",
                actions: [
                    PlanAction(
                        id: "action-notification",
                        tool: .notificationSchedule,
                        arguments: [
                            "title": .string("Standup"),
                            "scheduledAt": .string("2026-07-01T09:00:00Z")
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        try session.approve(token: ApprovalToken(id: "approval-notification", sessionID: session.id))
        session.executionStatus = .completed
        session.markAction(
            id: "action-notification",
            status: .succeeded,
            result: ToolResult(
                tool: .notificationSchedule,
                status: .succeeded,
                summary: "Scheduled notification Standup",
                output: ["notificationId": .string("notification-standup")]
            )
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-notification",
            model: nil,
            usage: .unknown,
            startedAt: Date(timeIntervalSince1970: 30),
            finishedAt: Date(timeIntervalSince1970: 31)
        )

        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .notification, id: "notification-standup")))
    }

    func testReviewExecutionReceiptLinksReminderReferenceFromToolOutput() throws {
        var session = ReviewSession(
            id: "review-reminder",
            plan: ActionPlan(
                id: "plan-reminder",
                userInput: "Remind me to send the launch notes",
                summary: "Create a reminder",
                actions: [
                    PlanAction(
                        id: "action-reminder",
                        tool: .remindersCreate,
                        arguments: [
                            "title": .string("Send launch notes"),
                            "dueAt": .string("2026-07-01T09:00:00Z")
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        try session.approve(token: ApprovalToken(id: "approval-reminder", sessionID: session.id))
        session.executionStatus = .completed
        session.markAction(
            id: "action-reminder",
            status: .succeeded,
            result: ToolResult(
                tool: .remindersCreate,
                status: .succeeded,
                summary: "Created reminder Send launch notes",
                output: ["reminderId": .string("reminder-launch")]
            )
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-reminder",
            model: nil,
            usage: .unavailable,
            startedAt: Date(timeIntervalSince1970: 32),
            finishedAt: Date(timeIntervalSince1970: 33)
        )

        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .reminder, id: "reminder-launch")))
    }

    func testReviewExecutionReceiptLinksBulkReminderReferencesFromToolOutput() throws {
        var session = ReviewSession(
            id: "review-reminder-bulk",
            plan: ActionPlan(
                id: "plan-reminder-bulk",
                userInput: "Create reminder checklist",
                summary: "Create reminders",
                actions: [
                    PlanAction(
                        id: "action-reminder-bulk",
                        tool: .remindersBulkCreate,
                        arguments: [
                            "reminders": .array([
                                .object(["title": .string("Send agenda")]),
                                .object(["title": .string("Book room")])
                            ])
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        try session.approve(token: ApprovalToken(id: "approval-reminder-bulk", sessionID: session.id))
        session.executionStatus = .completed
        session.markAction(
            id: "action-reminder-bulk",
            status: .succeeded,
            result: ToolResult(
                tool: .remindersBulkCreate,
                status: .succeeded,
                summary: "Created 2 reminders",
                output: ["reminderIds": .array([.string("reminder-agenda"), .string("reminder-room")])]
            )
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-reminder-bulk",
            model: nil,
            usage: .unavailable,
            startedAt: Date(timeIntervalSince1970: 34),
            finishedAt: Date(timeIntervalSince1970: 35)
        )

        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .reminder, id: "reminder-agenda")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .reminder, id: "reminder-room")))
    }

    func testReviewExecutionReceiptDeduplicatesBulkReminderReferencesFromToolOutput() throws {
        var session = ReviewSession(
            id: "review-reminder-bulk-duplicate",
            plan: ActionPlan(
                id: "plan-reminder-bulk-duplicate",
                userInput: "Create reminder checklist",
                summary: "Create reminders",
                actions: [
                    PlanAction(
                        id: "action-reminder-bulk-duplicate",
                        tool: .remindersBulkCreate,
                        arguments: [
                            "reminders": .array([
                                .object(["title": .string("Send agenda")]),
                                .object(["title": .string("Send agenda again")])
                            ])
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        try session.approve(token: ApprovalToken(id: "approval-reminder-bulk-duplicate", sessionID: session.id))
        session.executionStatus = .completed
        session.markAction(
            id: "action-reminder-bulk-duplicate",
            status: .succeeded,
            result: ToolResult(
                tool: .remindersBulkCreate,
                status: .succeeded,
                summary: "Created 2 reminders",
                output: ["reminderIds": .array([.string("reminder-agenda"), .string("reminder-agenda")])]
            )
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-reminder-bulk-duplicate",
            model: nil,
            usage: .unavailable,
            startedAt: Date(timeIntervalSince1970: 36),
            finishedAt: Date(timeIntervalSince1970: 37)
        )

        XCTAssertEqual(
            receipt.references.filter { $0 == ExecutionReceiptReference(kind: .reminder, id: "reminder-agenda") }.count,
            1
        )
    }

    func testReviewExecutionReceiptLinksDevelopmentBranchEvidenceFromPRWorkflowOutput() throws {
        let branchName = "feature/solopm-7-42-fix-calendar-sync"
        let privateWorkspacePath = "/Users/alice/private-work/soloPM"
        let gitSecret = "token" + "=" + "git-secret"
        var session = ReviewSession(
            id: "review-development-pr",
            plan: ActionPlan(
                id: "plan-development-pr",
                userInput: "Prepare a PR workflow for the calendar sync task.",
                summary: "Create a local development branch before any push or PR.",
                actions: [
                    PlanAction(
                        id: "action-development-pr",
                        tool: .developmentPreparePullRequestWorkflow,
                        arguments: [
                            "projectId": .number(7),
                            "taskId": .number(42),
                            "branchName": .string(branchName)
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        try session.approve(token: ApprovalToken(id: "approval-development-pr", sessionID: session.id))
        session.executionStatus = .completed
        session.markAction(
            id: "action-development-pr",
            status: .succeeded,
            result: ToolResult(
                tool: .developmentPreparePullRequestWorkflow,
                status: .succeeded,
                summary: "Prepared local development branch \(branchName). Push and PR creation require a separate approval gate.",
                output: [
                    "projectId": .number(7),
                    "taskId": .number(42),
                    "branchName": .string(branchName),
                    "workspacePath": .string(privateWorkspacePath),
                    "status": .string("## \(branchName)\n M Sources/Secret.swift \(gitSecret)"),
                    "diffStat": .string("\(privateWorkspacePath)/Sources/Secret.swift | 1 +"),
                    "requiresPushApproval": .bool(true),
                    "requiresPullRequestApproval": .bool(true),
                    "externalWritePreview": .string("git push -u origin \(branchName) && gh pr create --fill")
                ]
            )
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-development-pr",
            model: nil,
            usage: .unavailable,
            startedAt: Date(timeIntervalSince1970: 38),
            finishedAt: Date(timeIntervalSince1970: 39)
        )
        let displayedText = [
            receipt.outputSummary,
            receipt.actions.first?.outputSummary ?? "",
            ExecutionReceiptHistoryReadModel.snapshot(from: [receipt]).rows.first?.referenceSummary ?? ""
        ].joined(separator: " ")

        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: "7")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: "42")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        XCTAssertEqual(receipt.visibleSurfaces, [.taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(receipt.actions.first?.outputSummary?.contains(branchName) == true)
        XCTAssertTrue(receipt.actions.first?.outputSummary?.contains("Push approval required") == true)
        XCTAssertTrue(receipt.actions.first?.outputSummary?.contains("Pull request approval required") == true)
        XCTAssertTrue(displayedText.contains("Development Branch"))
        XCTAssertFalse(displayedText.contains(privateWorkspacePath))
        XCTAssertFalse(displayedText.contains("Sources/Secret.swift"))
        XCTAssertFalse(displayedText.contains(gitSecret))
        XCTAssertFalse(displayedText.contains("gh pr create"))
    }

    func testFailedDevelopmentPRWorkflowReceiptKeepsBranchEvidenceFromToolOutput() throws {
        let branchName = "feature/solopm-7-42-fix-calendar-sync"
        let gitSecret = "token" + "=" + "git-secret"
        var session = ReviewSession(
            id: "review-development-pr-failed",
            plan: ActionPlan(
                id: "plan-development-pr-failed",
                userInput: "Prepare a PR workflow for the calendar sync task.",
                summary: "Create a local development branch before any push or PR.",
                actions: [
                    PlanAction(
                        id: "action-development-pr-failed",
                        tool: .developmentPreparePullRequestWorkflow,
                        arguments: [
                            "projectId": .number(7),
                            "taskId": .number(42),
                            "branchName": .string(branchName)
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        try session.approve(token: ApprovalToken(id: "approval-development-pr-failed", sessionID: session.id))
        session.executionStatus = .failed
        session.markAction(
            id: "action-development-pr-failed",
            status: .failed,
            result: ToolResult(
                tool: .developmentPreparePullRequestWorkflow,
                status: .failed,
                summary: "Prepared local development branch \(branchName), but could not capture git evidence. Push and PR creation require a separate approval gate.",
                output: [
                    "projectId": .number(7),
                    "taskId": .number(42),
                    "branchName": .string(branchName),
                    "gitEvidenceError": .string("git status failed [REDACTED_SECRET]"),
                    "requiresPushApproval": .bool(true),
                    "requiresPullRequestApproval": .bool(true)
                ]
            ),
            errorMessage: "git status failed \(gitSecret)",
            failureRecovery: .retryable
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-development-pr-failed",
            model: nil,
            usage: .unavailable,
            startedAt: Date(timeIntervalSince1970: 40),
            finishedAt: Date(timeIntervalSince1970: 41)
        )

        XCTAssertEqual(receipt.status, .failed)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: "7")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: "42")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        XCTAssertEqual(receipt.visibleSurfaces, [.taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(receipt.actions.first?.outputSummary?.contains("No git status or diff-stat evidence was returned.") == true)
        XCTAssertTrue(receipt.actions.first?.errorSummary?.contains("[REDACTED_SECRET]") == true)
        XCTAssertFalse(receipt.actions.first?.errorSummary?.contains(gitSecret) == true)
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

    func testScheduleDraftApplyReceiptRedactsSecretsAndLinksCalendarReferences() throws {
        let taskTitleSecret = "token" + "=" + "schedule-task-secret"
        let projectTitleSecret = "secret" + "=" + "schedule-project-secret"
        let calendarTitleSecret = "api_key" + "=" + "calendar-title-secret"
        let calendarNoteSecret = "sk-" + "proj-calendar-note-secret"
        let approvalSecret = "approval-token-secret"
        let task = ProjectBoardTask(
            id: 42,
            projectID: 7,
            title: "Calendar block \(taskTitleSecret)",
            detail: "Do not persist \(calendarNoteSecret)",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21"
        )
        let block = TodayTimeBlock(
            label: "09:00",
            task: task,
            startAt: "2026-06-21T09:00:00Z",
            endAt: "2026-06-21T10:00:00Z"
        )
        let event = CalendarEventRecord(
            id: "calendar-event-1",
            draft: CalendarEventDraft(
                title: "Calendar block \(calendarTitleSecret)",
                startAt: "2026-06-21T09:00:00Z",
                endAt: "2026-06-21T10:00:00Z",
                notes: "Reviewed schedule note \(calendarNoteSecret)"
            )
        )

        let receipt = ExecutionReceiptFactory.makeScheduleDraftApplyReceipt(
            writeCandidates: [try XCTUnwrap(ScheduleDraftApplyWriteCandidate(block: block))],
            unscheduledTaskCount: 0,
            createdEvents: [
                ScheduleDraftApplyCreatedEvent(
                    candidate: try XCTUnwrap(ScheduleDraftApplyWriteCandidate(block: block)),
                    record: event
                )
            ],
            projectTitlesByID: [7: "Client Launch \(projectTitleSecret)"],
            runID: "schedule-run-1",
            approvalID: "schedule-draft-apply-approval:123",
            status: .succeeded,
            createdAt: Date(timeIntervalSince1970: 40)
        )

        XCTAssertEqual(receipt.id, "receipt:schedule-run-1:schedule-draft-apply")
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.approvalID, "schedule-draft-apply-approval:123")
        XCTAssertEqual(receipt.primaryToolName, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertEqual(receipt.usage.state, .unavailable)
        XCTAssertEqual(receipt.references.map(\.kind), [.task, .project, .calendarEvent])
        XCTAssertEqual(receipt.visibleSurfaces, [.taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(receipt.outputSummary.contains("1 Calendar event"))
        XCTAssertTrue(receipt.references[0].label?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertTrue(receipt.references[1].label?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertTrue(receipt.references[2].label?.contains("[REDACTED_SECRET]") ?? false)

        let encoded = try JSONEncoder().encode(receipt)
        let encodedReceipt = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedReceipt.contains(taskTitleSecret))
        XCTAssertFalse(encodedReceipt.contains(projectTitleSecret))
        XCTAssertFalse(encodedReceipt.contains(calendarTitleSecret))
        XCTAssertFalse(encodedReceipt.contains(calendarNoteSecret))
        XCTAssertFalse(encodedReceipt.contains(approvalSecret))
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
        XCTAssertEqual(receipt.queueApproval?.approvalID, approvedQueueItem.approval?.approvalID)
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
                approvalID: "queue-approval-json",
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
        XCTAssertEqual(decoded.queueApproval?.approvalID, "queue-approval-json")
    }

    func testExecutionReceiptDecodesUnknownReferenceKindsWithoutDroppingReceipt() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "receipt-unknown-reference-kind",
          "runID": "run-unknown-reference-kind",
          "createdAt": 100,
          "status": "succeeded",
          "inputPreview": "Input",
          "outputSummary": "Output",
          "usage": { "state": "unknown" },
          "references": [
            { "kind": "future_connector_record", "id": "future-1" }
          ],
          "sourceLinks": [],
          "actions": [],
          "visibleSurfaces": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ExecutionReceipt.self, from: json)

        XCTAssertEqual(decoded.id, "receipt-unknown-reference-kind")
        XCTAssertEqual(decoded.references, [ExecutionReceiptReference(kind: .unknown, id: "future-1")])
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

    func testFileExecutionReceiptStoreKeepsMultipleAssistantQueueReceiptsAndRejectsDuplicateIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileExecutionReceiptStore(directoryURL: directory)
        let failed = ExecutionReceipt(
            id: "receipt-run-1",
            runID: "run-1",
            assistantQueueItemID: "queue-1",
            status: .failed,
            inputPreview: "Input 1",
            outputSummary: "Failed"
        )
        let succeeded = ExecutionReceipt(
            id: "receipt-run-2",
            runID: "run-2",
            assistantQueueItemID: "queue-1",
            status: .succeeded,
            inputPreview: "Input 2",
            outputSummary: "Succeeded"
        )

        try store.save(failed)
        try store.save(succeeded)

        let loaded = try store.list(limit: 10)
        XCTAssertEqual(Set(loaded.map(\.id)), Set(["receipt-run-1", "receipt-run-2"]))
        XCTAssertEqual(loaded.filter { $0.assistantQueueItemID == "queue-1" }.count, 2)
        XCTAssertThrowsError(try store.save(failed)) { error in
            XCTAssertEqual(error as? ExecutionReceiptStoreError, .duplicateReceiptID("receipt-run-1"))
        }
    }

    func testFileExecutionReceiptStoreScopedListDoesNotLoseOlderMatchingReceiptsBehindGlobalLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileExecutionReceiptStore(directoryURL: directory)
        let matchingReceipt = ExecutionReceipt(
            id: "receipt-task-match",
            runID: "run-task-match",
            createdAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20),
            status: .succeeded,
            inputPreview: "Older scoped receipt",
            outputSummary: "Updated old scoped task",
            primaryToolName: ActionTool.taskUpdate.rawValue,
            references: [
                ExecutionReceiptReference(kind: .task, id: "42"),
                ExecutionReceiptReference(kind: .project, id: "7")
            ],
            visibleSurfaces: [.taskDetail, .projectDetail]
        )
        try store.save(matchingReceipt)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: directory.appendingPathComponent("receipt-task-match.json").path
        )

        for index in 0..<120 {
            try store.save(ExecutionReceipt(
                id: "receipt-unrelated-\(index)",
                runID: "run-unrelated-\(index)",
                createdAt: Date(timeIntervalSince1970: 1_000 + TimeInterval(index)),
                finishedAt: Date(timeIntervalSince1970: 1_010 + TimeInterval(index)),
                status: .succeeded,
                inputPreview: "New unrelated receipt",
                outputSummary: "Not a task detail row",
                primaryToolName: "calendar.create",
                references: [ExecutionReceiptReference(kind: .task, id: "420")],
                visibleSurfaces: [.doneList]
            ))
        }

        let scopedReceipts = try store.list(
            referenceKind: .task,
            referenceID: "42",
            visibleSurface: .taskDetail,
            limit: 5
        )
        XCTAssertEqual(scopedReceipts.map(\.id), ["receipt-task-match"])
    }

    func testExecutionReceiptHistoryRowsExposeOnlySafeGlobalAuditFields() throws {
        let promptSecret = "sk-" + "proj-history-secret"
        let argumentSecret = "token" + "=" + "argument-secret"
        let outputSecret = "secret" + "=" + "output-secret"
        let rawReceiptID = "receipt:https://docs.example.com/raw-id?token=receipt-id-secret"
        let reminderID = "reminder-raw-id-secret"
        let receipt = ExecutionReceipt(
            id: rawReceiptID,
            runID: "run-history-safe",
            createdAt: Date(timeIntervalSince1970: 10),
            startedAt: Date(timeIntervalSince1970: 20),
            finishedAt: Date(timeIntervalSince1970: 30),
            status: .succeeded,
            inputPreview: "Raw provider prompt \(promptSecret) from /Users/alice/private-source.md",
            outputSummary: "Created launch task with \(outputSecret)",
            model: ExecutionReceiptModel(provider: "OpenAI", name: "gpt-5.3"),
            primaryToolName: ActionTool.taskCreate.rawValue,
            usage: ExecutionReceiptUsage(
                inputTokens: 120,
                outputTokens: 32,
                estimatedCostCents: 3.2,
                currencyCode: "USD",
                isEstimated: true
            ),
            references: [
                ExecutionReceiptReference(kind: .task, id: "42", label: "Launch task \(argumentSecret)"),
                ExecutionReceiptReference(kind: .project, id: "7", label: "Release Project"),
                ExecutionReceiptReference(kind: .reminder, id: reminderID)
            ],
            sourceLinks: [
                ExecutionReceiptSourceLink(
                    kind: .document,
                    title: "Spec \(promptSecret)",
                    url: "file:///Users/alice/private-source.md"
                )
            ],
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-history-safe",
                    toolName: ActionTool.taskCreate.rawValue,
                    status: .succeeded,
                    inputPreview: "title: \(argumentSecret)",
                    outputSummary: "Created with \(outputSecret)"
                )
            ],
            visibleSurfaces: [.auditLog]
        )

        let row = try XCTUnwrap(ExecutionReceiptHistoryReadModel.snapshot(from: [receipt]).rows.first)
        let displayedText = [
            row.id,
            row.statusLabel,
            row.toolLabel,
            row.outcomeSummary,
            row.usageLabel,
            row.referenceSummary,
            row.sourceSummary,
            row.occurredAtLabel,
            row.receiptIDLabel,
            row.accessibilityValue
        ].joined(separator: " ")

        XCTAssertTrue(row.id.hasPrefix("receipt-"))
        XCTAssertEqual(row.id.count, "receipt-".count + 16)
        XCTAssertTrue(row.receiptIDLabel.contains(row.id))
        XCTAssertEqual(row.status, .succeeded)
        XCTAssertEqual(row.statusLabel, "Succeeded")
        XCTAssertEqual(row.toolLabel, "task.create")
        XCTAssertTrue(row.usageLabel.contains("Estimated"))
        XCTAssertTrue(row.usageLabel.contains("152 tokens"))
        XCTAssertTrue(row.usageLabel.contains("USD"))
        XCTAssertTrue(row.referenceSummary.contains("Task"))
        XCTAssertTrue(row.referenceSummary.contains("Project"))
        XCTAssertTrue(row.referenceSummary.contains("Reminder"))
        XCTAssertTrue(row.sourceSummary.contains("Document"))
        XCTAssertFalse(displayedText.contains(promptSecret))
        XCTAssertFalse(displayedText.contains("argument-secret"))
        XCTAssertFalse(displayedText.contains("output-secret"))
        XCTAssertFalse(displayedText.contains("/Users/alice/private-source.md"))
        XCTAssertFalse(displayedText.contains("file://"))
        XCTAssertFalse(displayedText.contains("Raw provider prompt"))
        XCTAssertFalse(displayedText.contains("title:"))
        XCTAssertFalse(displayedText.contains(rawReceiptID))
        XCTAssertFalse(displayedText.contains("receipt-id-secret"))
        XCTAssertFalse(displayedText.contains(reminderID))
    }

    func testExecutionReceiptHistorySortsByOutcomeTimeAndIncludesFailureCanceledAndUsageStates() {
        let failed = ExecutionReceipt(
            id: "receipt-failed",
            runID: "run-failed",
            createdAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 40),
            status: .failed,
            inputPreview: "Input failed",
            outputSummary: "Tool failed",
            primaryToolName: "calendar.create",
            usage: .unknown
        )
        let canceled = ExecutionReceipt(
            id: "receipt-canceled",
            runID: "run-canceled",
            createdAt: Date(timeIntervalSince1970: 50),
            startedAt: Date(timeIntervalSince1970: 60),
            finishedAt: nil,
            status: .canceled,
            inputPreview: "Input canceled",
            outputSummary: "Canceled by user",
            primaryToolName: "notification.send",
            usage: .unavailable
        )
        let measured = ExecutionReceipt(
            id: "receipt-measured",
            runID: "run-measured",
            createdAt: Date(timeIntervalSince1970: 20),
            finishedAt: Date(timeIntervalSince1970: 30),
            status: .succeeded,
            inputPreview: "Input measured",
            outputSummary: "Done",
            primaryToolName: "task.update",
            usage: ExecutionReceiptUsage(
                inputTokens: 8,
                outputTokens: 4,
                estimatedCostCents: 1.0,
                currencyCode: "USD",
                isEstimated: false
            )
        )

        let snapshot = ExecutionReceiptHistoryReadModel.snapshot(from: [failed, canceled, measured], limit: 10)

        XCTAssertEqual(snapshot.rows.map(\.toolLabel), ["notification.send", "calendar.create", "task.update"])
        XCTAssertEqual(snapshot.rows.map(\.status), [.canceled, .failed, .succeeded])
        XCTAssertTrue(snapshot.rows[0].usageLabel.contains("Unavailable"))
        XCTAssertTrue(snapshot.rows[1].usageLabel.contains("Unknown"))
        XCTAssertTrue(snapshot.rows[2].usageLabel.contains("Measured"))
        XCTAssertTrue(snapshot.rows[2].usageLabel.contains("12 tokens"))
    }

    func testExecutionReceiptHistoryFiltersScopedRowsByReferenceAndVisibleSurface() throws {
        let matchingTask = ExecutionReceipt(
            id: "receipt-task-match",
            runID: "run-task-match",
            createdAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 30),
            status: .succeeded,
            inputPreview: "Raw task prompt token=scoped-secret",
            outputSummary: "Updated scoped task",
            primaryToolName: ActionTool.taskUpdate.rawValue,
            references: [
                ExecutionReceiptReference(kind: .task, id: "42", label: "Scoped task token=scoped-secret"),
                ExecutionReceiptReference(kind: .project, id: "7", label: "Scoped project")
            ],
            sourceLinks: [
                ExecutionReceiptSourceLink(kind: .document, title: "Spec token=scoped-secret", url: "file:///Users/alice/private.md")
            ],
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-scoped",
                    toolName: ActionTool.taskUpdate.rawValue,
                    status: .succeeded,
                    inputPreview: "detail=token=scoped-secret"
                )
            ],
            visibleSurfaces: [.taskDetail, .projectDetail]
        )
        let wrongSurface = ExecutionReceipt(
            id: "receipt-wrong-surface",
            runID: "run-wrong-surface",
            createdAt: Date(timeIntervalSince1970: 20),
            finishedAt: Date(timeIntervalSince1970: 40),
            status: .succeeded,
            inputPreview: "Wrong surface",
            outputSummary: "Should not show",
            primaryToolName: "calendar.create",
            references: [ExecutionReceiptReference(kind: .task, id: "42")],
            visibleSurfaces: [.doneList]
        )
        let wrongReference = ExecutionReceipt(
            id: "receipt-wrong-reference",
            runID: "run-wrong-reference",
            createdAt: Date(timeIntervalSince1970: 30),
            finishedAt: Date(timeIntervalSince1970: 50),
            status: .succeeded,
            inputPreview: "Wrong reference",
            outputSummary: "Should not show either",
            primaryToolName: "notification.send",
            references: [ExecutionReceiptReference(kind: .task, id: "420")],
            visibleSurfaces: [.taskDetail]
        )

        let taskSnapshot = ExecutionReceiptHistoryReadModel.snapshot(
            from: [wrongReference, wrongSurface, matchingTask],
            referenceKind: .task,
            referenceID: "42",
            visibleSurface: .taskDetail,
            limit: 5
        )
        let projectSnapshot = ExecutionReceiptHistoryReadModel.snapshot(
            from: [wrongReference, wrongSurface, matchingTask],
            referenceKind: .project,
            referenceID: "7",
            visibleSurface: .projectDetail,
            limit: 5
        )

        let taskRow = try XCTUnwrap(taskSnapshot.rows.first)
        XCTAssertEqual(taskSnapshot.rows.count, 1)
        XCTAssertEqual(taskRow.toolLabel, ActionTool.taskUpdate.rawValue)
        XCTAssertEqual(taskRow.outcomeSummary, "Updated scoped task")
        XCTAssertFalse(taskRow.accessibilityValue.contains("scoped-secret"))
        XCTAssertFalse(taskRow.accessibilityValue.contains("file:///Users/alice/private.md"))
        XCTAssertEqual(projectSnapshot.rows.map(\.toolLabel), [ActionTool.taskUpdate.rawValue])
    }

    func testExecutionReceiptStoreSearchFiltersBeforeLimitForAuditRows() throws {
        let matchingReceipt = ExecutionReceipt(
            id: "receipt-audit-match",
            runID: "run-audit-match",
            createdAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20),
            status: .failed,
            inputPreview: "Raw launch prompt token=search-secret",
            outputSummary: "Recovered launch audit row",
            primaryToolName: ActionTool.taskUpdate.rawValue,
            references: [
                ExecutionReceiptReference(kind: .task, id: "42"),
                ExecutionReceiptReference(kind: .project, id: "7")
            ],
            visibleSurfaces: [.auditLog, .taskDetail]
        )
        let newerUnrelatedReceipts = (0..<120).map { index in
            ExecutionReceipt(
                id: "receipt-audit-unrelated-\(index)",
                runID: "run-audit-unrelated-\(index)",
                createdAt: Date(timeIntervalSince1970: 1_000 + TimeInterval(index)),
                finishedAt: Date(timeIntervalSince1970: 1_010 + TimeInterval(index)),
                status: .succeeded,
                inputPreview: "New unrelated prompt",
                outputSummary: "Calendar row that should not match",
                primaryToolName: ActionTool.calendarCreateWorkBlock.rawValue,
                references: [ExecutionReceiptReference(kind: .calendarEvent, id: "event-\(index)")],
                visibleSurfaces: [.doneList]
            )
        }
        let filter = ExecutionReceiptSearchFilter(
            query: "launch",
            statuses: [.failed],
            toolNames: [ActionTool.taskUpdate.rawValue],
            referenceKinds: [.task],
            visibleSurface: .auditLog
        )

        let memoryStore = InMemoryExecutionReceiptStore(receipts: [matchingReceipt] + newerUnrelatedReceipts)
        XCTAssertEqual(try memoryStore.list(matching: filter, limit: 5).map(\.id), ["receipt-audit-match"])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = try FileExecutionReceiptStore(directoryURL: directory)
        try fileStore.save(matchingReceipt)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: directory.appendingPathComponent("receipt-audit-match.json").path
        )
        for receipt in newerUnrelatedReceipts {
            try fileStore.save(receipt)
        }

        XCTAssertEqual(try fileStore.list(matching: filter, limit: 5).map(\.id), ["receipt-audit-match"])
    }

    func testExecutionReceiptHistorySearchAndExportExposeOnlyRedactedAuditFields() throws {
        let promptSecret = "sk-" + "proj-export-secret"
        let argumentSecret = "token" + "=" + "argument-export-secret"
        let outputSecret = "secret" + "=" + "output-export-secret"
        let rawReceiptID = "receipt:https://docs.example.com/raw-id?token=receipt-export-secret"
        let taskReferenceID = "task-raw-reference-secret"
        let receipt = ExecutionReceipt(
            id: rawReceiptID,
            runID: "run-export-safe",
            createdAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 30),
            status: .succeeded,
            inputPreview: "Raw provider prompt \(promptSecret) from /Users/alice/private-export.md",
            outputSummary: "Created launch audit summary",
            primaryToolName: ActionTool.taskCreate.rawValue,
            usage: ExecutionReceiptUsage(
                inputTokens: 20,
                outputTokens: 5,
                estimatedCostCents: 2.4,
                currencyCode: "USD",
                isEstimated: true
            ),
            references: [
                ExecutionReceiptReference(kind: .task, id: taskReferenceID, label: "Launch \(argumentSecret)")
            ],
            sourceLinks: [
                ExecutionReceiptSourceLink(
                    kind: .document,
                    title: "Spec \(promptSecret)",
                    url: "file:///Users/alice/private-export.md"
                )
            ],
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-export-safe",
                    toolName: ActionTool.taskCreate.rawValue,
                    status: .succeeded,
                    inputPreview: "title: \(argumentSecret)",
                    outputSummary: "Created with \(outputSecret)"
                )
            ],
            visibleSurfaces: [.auditLog]
        )
        let wrongReceipt = ExecutionReceipt(
            id: "receipt-export-wrong",
            runID: "run-export-wrong",
            createdAt: Date(timeIntervalSince1970: 40),
            finishedAt: Date(timeIntervalSince1970: 50),
            status: .failed,
            inputPreview: "Wrong prompt",
            outputSummary: "Unrelated row",
            primaryToolName: ActionTool.calendarCreateWorkBlock.rawValue,
            references: [ExecutionReceiptReference(kind: .calendarEvent, id: "event-1")],
            visibleSurfaces: [.auditLog]
        )
        let filter = ExecutionReceiptSearchFilter(
            query: "launch audit",
            statuses: [.succeeded],
            toolNames: [ActionTool.taskCreate.rawValue],
            referenceKinds: [.task],
            visibleSurface: .auditLog
        )

        let snapshot = ExecutionReceiptHistoryReadModel.snapshot(
            from: [wrongReceipt, receipt],
            matching: filter,
            limit: 10
        )
        let exportData = try ExecutionReceiptHistoryExporter.exportJSON(
            snapshot: snapshot,
            exportedAt: Date(timeIntervalSince1970: 100)
        )
        let exportText = try XCTUnwrap(String(data: exportData, encoding: .utf8))

        XCTAssertEqual(snapshot.rows.map(\.toolLabel), [ActionTool.taskCreate.rawValue])
        XCTAssertTrue(exportText.contains("receipt-"))
        XCTAssertTrue(exportText.contains("Created launch audit summary"))
        XCTAssertTrue(exportText.contains(ActionTool.taskCreate.rawValue))
        XCTAssertTrue(exportText.contains("Estimated"))
        XCTAssertFalse(exportText.contains(promptSecret))
        XCTAssertFalse(exportText.contains("argument-export-secret"))
        XCTAssertFalse(exportText.contains("output-export-secret"))
        XCTAssertFalse(exportText.contains(rawReceiptID))
        XCTAssertFalse(exportText.contains(taskReferenceID))
        XCTAssertFalse(exportText.contains("file://"))
        XCTAssertFalse(exportText.contains("/Users/alice/private-export.md"))
        XCTAssertFalse(exportText.contains("Raw provider prompt"))
        XCTAssertFalse(exportText.contains("title:"))
        XCTAssertFalse(exportText.contains("action-export-safe"))
    }

    func testExecutionReceiptSearchDoesNotMatchRawInputsURLsOrReferenceIDs() throws {
        let promptSecret = "sk-" + "proj-search-secret"
        let argumentSecret = "token" + "=" + "argument-search-secret"
        let referenceID = "task-reference-search-secret"
        let sourceURL = "file:///Users/alice/search-secret.md"
        let receipt = ExecutionReceipt(
            id: "receipt-search-safe",
            runID: "run-search-safe",
            status: .succeeded,
            inputPreview: "Raw provider prompt \(promptSecret)",
            outputSummary: "Created safe searchable launch summary",
            primaryToolName: ActionTool.taskCreate.rawValue,
            references: [
                ExecutionReceiptReference(kind: .task, id: referenceID, label: "Search label")
            ],
            sourceLinks: [
                ExecutionReceiptSourceLink(kind: .document, title: "Search doc", url: sourceURL)
            ],
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-search-safe",
                    toolName: ActionTool.taskCreate.rawValue,
                    status: .succeeded,
                    inputPreview: "title: \(argumentSecret)"
                )
            ],
            visibleSurfaces: [.auditLog]
        )

        XCTAssertTrue(ExecutionReceiptSearchFilter(query: "safe searchable launch").matches(receipt))
        XCTAssertFalse(ExecutionReceiptSearchFilter(query: promptSecret).matches(receipt))
        XCTAssertFalse(ExecutionReceiptSearchFilter(query: "argument-search-secret").matches(receipt))
        XCTAssertFalse(ExecutionReceiptSearchFilter(query: referenceID).matches(receipt))
        XCTAssertFalse(ExecutionReceiptSearchFilter(query: sourceURL).matches(receipt))
        XCTAssertFalse(ExecutionReceiptSearchFilter(query: "action-search-safe").matches(receipt))
    }
}
