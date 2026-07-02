import XCTest
@testable import SoloPMCore

final class AssistantQueueExecutionTests: XCTestCase {
    func testCoordinatorRunsApprovedActionPlanAndPersistsQueueReceipt() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                XCTAssertEqual(context.source, .reviewUI)
                return ToolResult(
                    tool: .taskCreate,
                    status: .succeeded,
                    summary: "Created Launch checklist",
                    output: ["taskId": .number(42), "projectId": .number(7)]
                )
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-success" },
            now: { Date(timeIntervalSince1970: 100) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        XCTAssertNil(try queueStore.get(id: approved.id).blockingReason)
        XCTAssertNil(try queueStore.get(id: approved.id).approval?.executionTokenID)

        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertEqual(receipt.queueApproval?.reviewerID, "local-user")
        XCTAssertEqual(receipt.queueApproval?.reviewedContentDigest, approved.approval?.reviewedContentFingerprint)
        XCTAssertEqual(receipt.approvalID, result.session.approvalToken?.id)
        XCTAssertEqual(receipt.references.first, ExecutionReceiptReference(kind: .assistantQueue, id: approved.id, label: "Create Launch checklist"))
        XCTAssertEqual(receipt.actions.first?.status, .succeeded)
        XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue, .taskDetail, .projectDetail, .auditLog])
        XCTAssertEqual(
            try receiptStore.list(referenceKind: .task, referenceID: "42", visibleSurface: .taskDetail, limit: 5).map(\.id),
            [receipt.id]
        )
        XCTAssertEqual(
            try receiptStore.list(referenceKind: .project, referenceID: "7", visibleSurface: .projectDetail, limit: 5).map(\.id),
            [receipt.id]
        )
    }

    func testCoordinatorRunsQueuedDevelopmentPrepareWorkflowWithApprovedProjectBookmark() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let workspace = temporaryDirectory()
        let project = try projectStore.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-development-workspace-bookmark".utf8)
        )
        let task = try taskStore.create(
            title: "Queue development branch",
            projectID: project.id,
            sourceCommand: "voice"
        )
        let branchName = "feature/solopm-\(project.id)-\(task.id)-queue-development-branch"
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "development-prepare-queue",
                userInput: "Prepare a development branch for the selected task",
                summary: "Prepare local development branch",
                actions: [
                    PlanAction(
                        id: "development-prepare",
                        tool: .developmentPreparePullRequestWorkflow,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(task.id))
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Prepare a development branch",
            interpretationSummary: "Development branch preparation",
            reason: "Needs review before local branch mutation."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let gitRunner = RecordingAssistantQueueGitRunner()
        gitRunner.stub(
            arguments: ["switch", "-c", branchName],
            output: GitCommandOutput(standardOutput: "", standardError: "", exitCode: 0)
        )
        gitRunner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        gitRunner.stub(
            arguments: ["diff", "--stat"],
            output: GitCommandOutput(standardOutput: "Sources/SoloPMApp/SoloPMApp.swift | 1 +\n", standardError: "", exitCode: 0)
        )
        let registry = try ToolRegistry(tools: [
            DevelopmentPRWorkflowTool(
                projectStore: projectStore,
                taskStore: taskStore,
                gitRunner: gitRunner,
                bookmarkResolver: AssistantQueueStaticBookmarkResolver(url: workspace),
                requireBookmark: true
            )
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-development-prepare" },
            now: { Date(timeIntervalSince1970: 170) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.developmentPreparePullRequestWorkflow.rawValue)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue, .taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(project.id))))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: String(task.id))))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        XCTAssertEqual(gitRunner.recordedInvocations, [
            GitCommandInvocation(arguments: ["switch", "-c", branchName], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["diff", "--stat"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCoordinatorRunsQueuedDevelopmentRepositoryCreateWithBranchAndReceiptReferences() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let artifactStore = SQLiteArtifactStore(connection: connection)
        let workspace = temporaryDirectory()
        let project = try projectStore.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-repository-edit-bookmark".utf8)
        )
        let task = try taskStore.create(
            title: "Create repository file",
            projectID: project.id,
            sourceCommand: "voice"
        )
        let branchName = "feature/solopm-\(project.id)-\(task.id)-repository-edit"
        let source = "func reviewedRepositoryEdit() {}\n"
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "development-repository-create-queue",
                userInput: "Create a reviewed repository file",
                summary: "Create reviewed repository file on \(branchName).",
                actions: [
                    PlanAction(
                        id: "development-repository-create",
                        tool: .developmentRepositoryCreateFile,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(task.id)),
                            "branchName": .string(branchName),
                            "relativePath": .string("Sources/ReviewedEdit.swift"),
                            "contents": .string(source)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Create a reviewed repository file",
            interpretationSummary: "Repository create review",
            reason: "Needs review before writing an approved repository file."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let gitRunner = RecordingAssistantQueueGitRunner()
        gitRunner.stub(
            arguments: ["branch", "--show-current"],
            output: GitCommandOutput(standardOutput: "\(branchName)\n", standardError: "", exitCode: 0)
        )
        let registry = try ToolRegistry(tools: [
            DevelopmentRepositoryFileTool(
                name: .developmentRepositoryCreateFile,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: AssistantQueueStaticBookmarkResolver(url: workspace),
                requireBookmark: true,
                gitRunner: gitRunner
            )
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-development-repository-create" },
            now: { Date(timeIntervalSince1970: 172) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        XCTAssertEqual(
            try String(contentsOf: workspace.appendingPathComponent("Sources/ReviewedEdit.swift"), encoding: .utf8),
            source
        )
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.developmentRepositoryCreateFile.rawValue)
        XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue, .taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(project.id))))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: String(task.id))))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        let actionInputs = receipt.actions.map(\.inputPreview).joined(separator: "\n")
        XCTAssertTrue(actionInputs.contains("contents: [REDACTED_REPOSITORY_FILE_CONTENT]"))
        XCTAssertFalse(actionInputs.contains("reviewedRepositoryEdit"))
        XCTAssertEqual(gitRunner.recordedInvocations, [
            GitCommandInvocation(arguments: ["branch", "--show-current"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCoordinatorRunsQueuedDevelopmentPushWorkflowWithApprovedProjectBookmark() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let workspace = temporaryDirectory()
        let project = try projectStore.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-development-push-bookmark".utf8)
        )
        let branchName = "feature/solopm-\(project.id)-push-queue"
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "development-push-queue",
                userInput: "Push reviewed development branch",
                summary: "Push reviewed development branch. Pull request creation requires a separate approval.",
                actions: [
                    PlanAction(
                        id: "development-push",
                        tool: .developmentPushBranch,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "branchName": .string(branchName)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Push the reviewed development branch",
            interpretationSummary: "Development branch push",
            reason: "Needs review before pushing a branch to origin."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let gitRunner = RecordingAssistantQueueGitRunner()
        gitRunner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        gitRunner.stub(
            arguments: ["remote", "get-url", "--push", "--all", "origin"],
            output: GitCommandOutput(standardOutput: "git@github.com:acme/solo-pm.git\n", standardError: "", exitCode: 0)
        )
        gitRunner.stub(
            arguments: ["push", "-u", "origin", branchName],
            output: GitCommandOutput(standardOutput: "branch pushed\n", standardError: "", exitCode: 0)
        )
        let registry = try ToolRegistry(tools: [
            DevelopmentPushWorkflowTool(
                projectStore: projectStore,
                gitRunner: gitRunner,
                bookmarkResolver: AssistantQueueStaticBookmarkResolver(url: workspace)
            )
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-development-push" },
            now: { Date(timeIntervalSince1970: 175) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.developmentPushBranch.rawValue)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(project.id))))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        XCTAssertTrue(receipt.actions.first?.outputSummary?.contains("Remote repository acme/solo-pm") == true)
        XCTAssertEqual(gitRunner.recordedInvocations, [
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["remote", "get-url", "--push", "--all", "origin"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["push", "-u", "origin", branchName], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCoordinatorFailsQueuedDevelopmentPushWhenPushURLIsNotGitHub() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let workspace = temporaryDirectory()
        let project = try projectStore.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-development-push-bookmark".utf8)
        )
        let branchName = "feature/solopm-\(project.id)-push-queue"
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "development-push-invalid-origin",
                userInput: "Push reviewed development branch",
                summary: "Push reviewed development branch. Pull request creation requires a separate approval.",
                actions: [
                    PlanAction(
                        id: "development-push",
                        tool: .developmentPushBranch,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "branchName": .string(branchName)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Push the reviewed development branch",
            interpretationSummary: "Development branch push",
            reason: "Needs review before pushing a branch to origin."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let gitRunner = RecordingAssistantQueueGitRunner()
        gitRunner.stub(
            arguments: ["status", "--short", "--branch"],
            output: GitCommandOutput(standardOutput: "## \(branchName)\n", standardError: "", exitCode: 0)
        )
        gitRunner.stub(
            arguments: ["remote", "get-url", "--push", "--all", "origin"],
            output: GitCommandOutput(standardOutput: "https://example.com/acme/solo-pm.git\n", standardError: "", exitCode: 0)
        )
        let registry = try ToolRegistry(tools: [
            DevelopmentPushWorkflowTool(
                projectStore: projectStore,
                gitRunner: gitRunner,
                bookmarkResolver: AssistantQueueStaticBookmarkResolver(url: workspace)
            )
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-development-push-invalid-origin" },
            now: { Date(timeIntervalSince1970: 176) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .failed)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .failed)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.developmentPushBranch.rawValue)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(project.id))))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        XCTAssertTrue(receipt.actions.first?.errorSummary?.contains("Origin remote must resolve to a GitHub repository.") == true)
        XCTAssertEqual(gitRunner.recordedInvocations, [
            GitCommandInvocation(arguments: ["status", "--short", "--branch"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath()),
            GitCommandInvocation(arguments: ["remote", "get-url", "--push", "--all", "origin"], workingDirectory: workspace.standardizedFileURL.resolvingSymlinksInPath())
        ])
    }

    func testCoordinatorRunsScheduleDraftCalendarApplyAndKeepsScopedReceiptReferences() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let calendarClient = InMemoryCalendarClient()
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "schedule-draft-calendar-apply:2026-06-30:digest:task:42",
                userInput: "Queue reviewed Schedule draft for Calendar apply",
                summary: "Schedule draft Calendar apply for 1 work block.",
                actions: [
                    PlanAction(
                        id: "calendar-work-block-1-task-42",
                        tool: .calendarCreateWorkBlock,
                        arguments: [
                            "title": .string("Calendar block token=task-secret"),
                            "startAt": .string("2026-06-30T09:30:00Z"),
                            "durationMinutes": .number(30),
                            "notes": .string("Created from a reviewed SoloPM schedule draft."),
                            "taskId": .number(42),
                            "projectId": .number(7)
                        ],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Schedule draft Calendar apply",
            interpretationSummary: "Schedule draft Calendar apply",
            reason: "Schedule draft suggested 1 Calendar work block."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            CalendarTool(name: .calendarCreateWorkBlock, client: calendarClient)
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-schedule-queue" },
            now: { Date(timeIntervalSince1970: 160) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        let events = try calendarClient.listEvents()
        XCTAssertEqual(events.map(\.id), ["calendar-event-1"])
        XCTAssertEqual(events.first?.draft.title, "Calendar block token=task-secret")
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: "42")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: "7")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .calendarEvent, id: "calendar-event-1")))
        XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue, .taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(receipt.actions.first?.inputPreview.contains("[REDACTED_SECRET]") ?? false)
        let encodedReceipt = try XCTUnwrap(String(data: JSONEncoder().encode(receipt), encoding: .utf8))
        XCTAssertFalse(encodedReceipt.contains("task-secret"))
    }

    func testCoordinatorRunsApprovedMailDraftQueueItemIntoLocalDraftReceipt() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let draftsDirectory = temporaryDirectory().appendingPathComponent("MailDrafts", isDirectory: true)
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "notification-draft:test",
                userInput: "Draft release notification",
                summary: "Prepare a text-only notification draft without sending it.",
                actions: [
                    PlanAction(
                        id: "notification-draft-mail",
                        tool: .mailDraftCreateText,
                        arguments: [
                            "to": .string("team@example.com"),
                            "subject": .string("Release delay"),
                            "body": .string("Draft only. No external send.")
                        ],
                        riskLevel: .draft
                    )
                ],
                riskLevel: .draft,
                requiresApproval: false
            ),
            sourceTranscript: "Slack draft for release delay",
            interpretationSummary: "Notification draft",
            reason: "Notification draft needs review before any external message or local notification is created."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            MailDraftTool(client: LocalFileMailDraftClient(draftsDirectoryURL: draftsDirectory))
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-mail-draft-queue" },
            now: { Date(timeIntervalSince1970: 180) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        let files = try FileManager.default.contentsOfDirectory(at: draftsDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: files[0])) as? [String: Any])
        XCTAssertEqual(object["subject"] as? String, "Release delay")
        XCTAssertEqual(object["body"] as? String, "Draft only. No external send.")

        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.mailDraftCreateText.rawValue)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue])
        XCTAssertFalse(receipt.outputSummary.contains("Draft only"))
        XCTAssertEqual(receipt.actions.first?.inputPreview, "subject: Release delay, to: [REDACTED_RECIPIENT], body: [REDACTED_DRAFT_BODY]")
        let encodedReceipt = try XCTUnwrap(String(data: JSONEncoder().encode(receipt), encoding: .utf8))
        XCTAssertFalse(encodedReceipt.contains("Draft only"))
        XCTAssertFalse(encodedReceipt.contains("team@example.com"))
    }

    func testCoordinatorRejectsBlockedConnectorSendGateBeforeExecution() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let item = AssistantQueueAdapter.makeConnectorSendGateItem(
            serviceID: "discord",
            serviceDisplayName: "Discord",
            redactedSourceTranscript: "Discordに今すぐ投稿して",
            redactedArgumentSummary: "Connector send requested for Discord.",
            routeSummary: "Route as connector.send_gate without sending.",
            requestIDProvider: { "connector-send-discord" }
        )
        try queueStore.save(item)
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: try ActionExecutor(registry: ToolRegistry(tools: [])),
            executionReceiptStore: receiptStore
        )

        XCTAssertThrowsError(try coordinator.execute(id: item.id)) { error in
            XCTAssertEqual(error as? AssistantQueueExecutionError, .unsupportedPayload)
        }
        XCTAssertEqual(try queueStore.get(id: item.id).state, .blocked)
        XCTAssertTrue(receiptStore.receipts.isEmpty)
    }

    func testCoordinatorCopiesCostPreviewIntoEstimatedReceiptUsage() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let preview = makeCostPreview(inputTokens: 1_000, outputTokens: 500)
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: preview),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-cost-preview" },
            now: { Date(timeIntervalSince1970: 125) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.receipt.usage.state, .estimated)
        XCTAssertEqual(result.receipt.usage.inputTokens, 1_000)
        XCTAssertEqual(result.receipt.usage.outputTokens, 500)
        XCTAssertEqual(result.receipt.usage.estimatedCostCents ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.receipt.usage.currencyCode, "USD")
        XCTAssertEqual(result.receipt.model, ExecutionReceiptModel(provider: "openai", name: "gpt-test"))
    }

    func testCoordinatorRecordsSoloPMManagedUsageLedgerEntryAfterReceiptPersistence() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let ledgerStore = RecordingManagedAIUsageLedgerStore()
        let preview = AssistantQueueCostRateCard(
            provider: "openai sk-secret /Users/alice/private",
            modelName: "gpt-managed",
            currencyCode: "USD",
            inputTokenCentsPerMillion: 100,
            outputTokenCentsPerMillion: 300
        ).preview(inputTokens: 1_000, outputTokens: 500, hardCapCents: 2)
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: preview),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIUsageLedgerStore: ledgerStore,
            runIDProvider: { "run-queue-managed-ledger" },
            now: { Date(timeIntervalSince1970: 126) }
        )

        let result = try coordinator.execute(id: approved.id)

        let entry = try XCTUnwrap(ledgerStore.entries.first)
        XCTAssertEqual(ledgerStore.entries.count, 1)
        XCTAssertEqual(entry.sourceReceiptDigest, ManagedAIUsageLedgerEntry.digestIdentifier(kind: "receipt", value: result.receipt.id))
        XCTAssertEqual(entry.assistantQueueItemDigest, ManagedAIUsageLedgerEntry.digestIdentifier(kind: "assistant_queue_item", value: approved.id))
        XCTAssertEqual(entry.billingMode, .soloPMManaged)
        XCTAssertFalse(entry.provider.contains("sk-secret"))
        XCTAssertFalse(entry.provider.contains("/Users/alice"))
        XCTAssertEqual(entry.modelName, "gpt-managed")
        XCTAssertEqual(entry.inputTokens, 1_000)
        XCTAssertEqual(entry.outputTokens, 500)
        XCTAssertEqual(entry.costCents, 0.25, accuracy: 0.0001)
        XCTAssertEqual(entry.currencyCode, "USD")
        XCTAssertEqual(entry.usageState, .estimated)
    }

    func testCoordinatorBlocksSoloPMManagedRunWhenDailyLedgerCapWouldBeExceeded() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let ledgerStore = RecordingManagedAIUsageLedgerStore(entries: [
            ManagedAIUsageLedgerEntry(
                sourceReceiptDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "receipt", value: "existing-daily"),
                assistantQueueItemDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "assistant_queue_item", value: "existing-daily"),
                billingMode: .soloPMManaged,
                provider: "openai",
                modelName: "gpt-managed",
                usageState: .estimated,
                inputTokens: 1_000,
                outputTokens: 500,
                costCents: 80,
                currencyCode: "USD",
                occurredAt: Date(timeIntervalSince1970: 1_788_280_400)
            )
        ])
        let preview = makeCostPreview(inputTokens: 1_000, outputTokens: 500)
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: preview),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                XCTFail("Managed AI cap enforcement must stop before tool execution.")
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIUsageLedgerStore: ledgerStore,
            managedAIBillingSettings: ManagedAIBillingSettings(
                isEnabled: true,
                dailyCapCents: 80
            ),
            runIDProvider: { "run-queue-managed-ledger-cap" },
            now: { Date(timeIntervalSince1970: 1_788_282_000) }
        )

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            guard case .managedUsageCapExceeded(let projection, true) = error as? AssistantQueueExecutionError else {
                return XCTFail("Expected managed usage cap exceeded, got \(error)")
            }
            XCTAssertEqual(projection.scope, .daily)
        }
        let failed = try queueStore.get(id: approved.id)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(
            failed.blockingReason,
            "Managed AI daily cap would be exceeded. Current USD 0.80 plus this run USD 0.0025 exceeds USD 0.80."
        )
        XCTAssertTrue(receiptStore.receipts.isEmpty)
        XCTAssertEqual(ledgerStore.entries.count, 1)
    }

    func testCoordinatorReadsManagedBillingSettingsAtExecutionTime() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let ledgerStore = RecordingManagedAIUsageLedgerStore(entries: [
            ManagedAIUsageLedgerEntry(
                sourceReceiptDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "receipt", value: "existing-settings"),
                assistantQueueItemDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "assistant_queue_item", value: "existing-settings"),
                billingMode: .soloPMManaged,
                provider: "openai",
                modelName: "gpt-managed",
                usageState: .estimated,
                inputTokens: 1_000,
                outputTokens: 500,
                costCents: 80,
                currencyCode: "USD",
                occurredAt: Date(timeIntervalSince1970: 1_788_280_400)
            )
        ])
        var runtimeBillingSettings = ManagedAIBillingSettings.default
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: makeCostPreview(inputTokens: 1_000, outputTokens: 500)),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                XCTFail("Updated runtime cap settings must stop before tool execution.")
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIUsageLedgerStore: ledgerStore,
            managedAIBillingSettingsProvider: { runtimeBillingSettings },
            runIDProvider: { "run-queue-managed-settings-provider" },
            now: { Date(timeIntervalSince1970: 1_788_282_000) }
        )

        runtimeBillingSettings = ManagedAIBillingSettings(isEnabled: true, dailyCapCents: 80)

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            guard case .managedUsageCapExceeded(let projection, true) = error as? AssistantQueueExecutionError else {
                return XCTFail("Expected managed usage cap exceeded, got \(error)")
            }
            XCTAssertEqual(projection.scope, .daily)
        }
    }

    func testCoordinatorDoesNotRequireLedgerStoreForPerRunOnlyManagedBilling() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: makeCostPreview(inputTokens: 1_000, outputTokens: 500)),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIBillingSettings: ManagedAIBillingSettings(
                isEnabled: true,
                perRunCapCents: 2
            ),
            runIDProvider: { "run-queue-managed-per-run-only" },
            now: { Date(timeIntervalSince1970: 1_788_282_100) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(receiptStore.receipts.count, 1)
    }

    func testCoordinatorDoesNotRecordProviderBilledUsageInManagedLedger() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let ledgerStore = RecordingManagedAIUsageLedgerStore()
        let preview = AssistantQueueCostPreview.userProviderBilled(
            provider: "openai.chat_completions",
            modelName: "gpt-5.5",
            observedUsage: ExecutionReceiptUsage(inputTokens: 900, outputTokens: 120, isEstimated: false)
        )
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: preview),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIUsageLedgerStore: ledgerStore,
            runIDProvider: { "run-queue-provider-ledger" },
            now: { Date(timeIntervalSince1970: 127) }
        )

        _ = try coordinator.execute(id: approved.id)

        XCTAssertTrue(ledgerStore.entries.isEmpty)
    }

    func testCoordinatorMarksFailedWhenManagedUsageLedgerCannotBePersisted() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let preview = makeCostPreview(inputTokens: 1_000, outputTokens: 500)
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: preview),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            managedAIUsageLedgerStore: FailingManagedAIUsageLedgerStore(),
            runIDProvider: { "run-queue-managed-ledger-failure" },
            now: { Date(timeIntervalSince1970: 128) }
        )

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            XCTAssertEqual(
                error as? AssistantQueueExecutionError,
                .managedUsageLedgerPersistenceFailed(queueStateMarkedFailed: true)
            )
        }
        let failed = try queueStore.get(id: approved.id)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(
            failed.blockingReason,
            "Execution completed, but the managed AI usage ledger could not be saved. Fix billing ledger storage before retrying."
        )
        XCTAssertEqual(receiptStore.receipts.count, 1)
    }

    func testCoordinatorCopiesMeasuredProviderUsageAndBillingContextIntoReceipt() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let preview = AssistantQueueCostPreview.userProviderBilled(
            provider: "openai.chat_completions",
            modelName: "gpt-5.5",
            observedUsage: ExecutionReceiptUsage(inputTokens: 900, outputTokens: 120, isEstimated: false)
        )
        let approved = try AssistantQueueStateMachine.approve(
            makeActionPlanItem(costPreview: preview),
            reviewerID: "local-user"
        )
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created Launch checklist")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-measured-provider-usage" },
            now: { Date(timeIntervalSince1970: 130) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.receipt.usage.state, .measured)
        XCTAssertEqual(result.receipt.usage.inputTokens, 900)
        XCTAssertEqual(result.receipt.usage.outputTokens, 120)
        XCTAssertNil(result.receipt.usage.estimatedCostCents)
        XCTAssertEqual(result.receipt.model, ExecutionReceiptModel(provider: "openai.chat_completions", name: "gpt-5.5"))
        XCTAssertTrue(result.receipt.outputSummary.contains("provider-billed"))
        XCTAssertTrue(result.receipt.outputSummary.contains("SoloPM managed charge unavailable"))
    }

    func testCoordinatorRunsApprovedAutomationRequestTaskMutationThroughActionExecutor() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeTaskMutationItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskUpdate,
                description: "update task",
                inputSchema: ToolInputSchema(required: ["id"], properties: ["id": "number", "dueAt": "string"]),
                permissionLevel: .writeWithApproval
            ) { arguments, context in
                XCTAssertNotNil(context.approvalToken)
                XCTAssertEqual(context.source, .reviewUI)
                XCTAssertEqual(arguments["id"], .number(42))
                XCTAssertEqual(arguments["dueAt"], .string("2026-07-01T09:00:00Z"))
                return ToolResult(
                    tool: .taskUpdate,
                    status: .succeeded,
                    summary: "Updated due date",
                    output: ["taskId": .number(42)]
                )
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-automation-task-mutation" },
            now: { Date(timeIntervalSince1970: 150) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(result.session.originalPlan.id, "automation-request:automation-task-due")
        XCTAssertEqual(result.session.originalPlan.actions.map(\.tool), [.taskUpdate])
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)

        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        let queueReference = try XCTUnwrap(receipt.references.first)
        XCTAssertEqual(queueReference.kind, .assistantQueue)
        XCTAssertEqual(queueReference.id, approved.id)
        XCTAssertTrue(queueReference.label?.contains("taskID=42, dueAt=2026-07-01T09:00:00Z") ?? false)
        XCTAssertTrue(queueReference.label?.contains("Mutation: operation=updateDueDate") ?? false)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: "42")))
        XCTAssertEqual(receipt.actions.first?.toolName, ActionTool.taskUpdate.rawValue)
    }

    func testCoordinatorRunsApprovedAutomationRequestTaskMutationAgainstSQLiteTaskTool() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let task = try taskStore.create(title: "Existing remote task")
        let item = AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: "automation-real-task-due",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
            redactedArgumentSummary: "taskID=\(task.id), dueAt=2026-07-03T09:00:00Z",
            taskMutation: SyncTaskMutationPayload(
                taskID: task.id,
                operation: .updateDueDate,
                dueAt: "2026-07-03T09:00:00Z",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            TaskTool(name: .taskUpdate, store: taskStore, projectStore: projectStore)
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-automation-real-task-mutation" },
            now: { Date(timeIntervalSince1970: 175) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try taskStore.get(id: task.id).dueAt, "2026-07-03T09:00:00Z")
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: String(task.id))))
    }

    func testExecutableFactoryBuildsDevelopmentPullRequestReviewGatePlanFromAutomationRequest() throws {
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let request = SyncAutomationRequestPayload(
            id: "automation-pr-review",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            redactedArgumentSummary: "Review PR #116 before merge",
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: 7,
                operation: .reviewGate,
                pullRequestURL: pullRequestURL,
                branchName: "feature/solopm-7-merge-gate",
                baseBranch: "feature/phase14-product-completion"
            )
        )

        let plan = try XCTUnwrap(AssistantQueueExecutableActionPlanFactory.actionPlan(for: .automationRequest(request)))

        XCTAssertEqual(plan.id, "automation-request:automation-pr-review")
        XCTAssertEqual(plan.requiresApproval, true)
        XCTAssertEqual(plan.actions.map(\.tool), [.developmentReviewPullRequestGate])
        XCTAssertEqual(plan.actions.first?.arguments["projectId"], .number(7))
        XCTAssertEqual(plan.actions.first?.arguments["pullRequestURL"], .string(pullRequestURL))
        XCTAssertEqual(plan.actions.first?.arguments["branchName"], .string("feature/solopm-7-merge-gate"))
        XCTAssertEqual(plan.actions.first?.arguments["baseBranch"], .string("feature/phase14-product-completion"))
        XCTAssertTrue(plan.summary.contains("Review PR #116 before merge"))
        XCTAssertTrue(plan.summary.contains("operation=reviewGate"))
    }

    func testExecutableFactoryBuildsDevelopmentPullRequestMergePlanFromAutomationRequest() throws {
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let request = SyncAutomationRequestPayload(
            id: "automation-pr-merge",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: ActionTool.developmentMergePullRequest.rawValue,
            redactedArgumentSummary: "Merge PR #116 after checks pass",
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: 7,
                operation: .merge,
                pullRequestURL: pullRequestURL,
                branchName: "feature/solopm-7-merge-gate",
                baseBranch: "feature/phase14-product-completion"
            )
        )

        let plan = try XCTUnwrap(AssistantQueueExecutableActionPlanFactory.actionPlan(for: .automationRequest(request)))

        XCTAssertEqual(plan.id, "automation-request:automation-pr-merge")
        XCTAssertEqual(plan.requiresApproval, true)
        XCTAssertEqual(plan.actions.map(\.tool), [.developmentMergePullRequest])
        XCTAssertEqual(plan.actions.first?.arguments["projectId"], .number(7))
        XCTAssertEqual(plan.actions.first?.arguments["pullRequestURL"], .string(pullRequestURL))
        XCTAssertTrue(plan.summary.contains("operation=merge"))
    }

    func testCoordinatorRunsQueuedDevelopmentPullRequestReviewThenMergeRequestsAndPersistsReceipts() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let workspace = temporaryDirectory()
        let project = try projectStore.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-pr-workspace-bookmark".utf8)
        )
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let baseBranch = "feature/phase14-product-completion"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let headRefOID = "0123456789abcdef0123456789abcdef01234567"

        let reviewItem = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(automationRequest: developmentPullRequestAutomationRequest(
                id: "automation-pr-review",
                projectID: project.id,
                operation: .reviewGate,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: baseBranch
            )),
            reviewerID: "local-user"
        )
        let mergeItem = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(automationRequest: developmentPullRequestAutomationRequest(
                id: "automation-pr-merge",
                projectID: project.id,
                operation: .merge,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: baseBranch
            )),
            reviewerID: "local-user"
        )
        try queueStore.save(reviewItem)
        try queueStore.save(mergeItem)

        let gitRunner = RecordingAssistantQueueGitRunner()
        gitRunner.stub(
            arguments: ["remote", "get-url", "origin"],
            output: GitCommandOutput(
                standardOutput: "https://github.com/albert-einshutoin/soloPM.git\n",
                standardError: "",
                exitCode: 0
            )
        )
        let githubRunner = RecordingAssistantQueueGitHubRunner(outputs: [
            GitHubCLICommandOutput(
                standardOutput: pullRequestStatusJSON(
                    url: pullRequestURL,
                    headBranch: branchName,
                    baseBranch: baseBranch,
                    headRefOID: headRefOID
                ),
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: reviewThreadsJSON(totalCount: 0, unresolvedCount: 0),
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: pullRequestStatusJSON(
                    url: pullRequestURL,
                    headBranch: branchName,
                    baseBranch: baseBranch,
                    headRefOID: headRefOID
                ),
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: reviewThreadsJSON(totalCount: 0, unresolvedCount: 0),
                standardError: "",
                exitCode: 0
            ),
            GitHubCLICommandOutput(
                standardOutput: "Merged pull request #116 token=merge-secret\n",
                standardError: "",
                exitCode: 0
            )
        ])
        let registry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: workspace,
                enabledCapabilities: [.developmentPRWorkflow]
            ),
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: AssistantQueueStaticBookmarkResolver(url: workspace),
            projectStore: projectStore,
            taskStore: taskStore
        )
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-\(UUID().uuidString)" },
            now: { Date(timeIntervalSince1970: 180) }
        )

        let reviewResult = try coordinator.execute(id: reviewItem.id)
        let mergeResult = try coordinator.execute(id: mergeItem.id)

        XCTAssertEqual(reviewResult.item.state, .done)
        XCTAssertEqual(mergeResult.item.state, .done)
        XCTAssertEqual(receiptStore.receipts.map(\.status), [.succeeded, .succeeded])
        XCTAssertEqual(receiptStore.receipts.map(\.primaryToolName), [
            ActionTool.developmentReviewPullRequestGate.rawValue,
            ActionTool.developmentMergePullRequest.rawValue
        ])
        for receipt in receiptStore.receipts {
            XCTAssertEqual(receipt.assistantQueueItemID?.hasPrefix("automation-request:"), true)
            XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(project.id))))
            XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
            XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentCommit, id: headRefOID)))
            XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .pullRequest, id: pullRequestURL)))
            XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue, .projectDetail, .auditLog])
        }
        XCTAssertTrue(receiptStore.receipts[0].actions.first?.outputSummary?.contains("Review, CI, and mergeability gates passed") == true)
        XCTAssertTrue(receiptStore.receipts[1].actions.first?.outputSummary?.contains("Merged pull request") == true)
        XCTAssertFalse(
            String(data: try JSONEncoder().encode(receiptStore.receipts), encoding: .utf8)?
                .contains("merge-secret") ?? true
        )
        XCTAssertEqual(gitRunner.recordedInvocations.map(\.arguments), [
            ["remote", "get-url", "origin"],
            ["remote", "get-url", "origin"]
        ])
        XCTAssertEqual(githubRunner.recordedInvocations.map(\.arguments), [
            ["pr", "view", pullRequestURL, "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields],
            DevelopmentGitHubPRCommandPolicy.reviewThreadsArguments(
                owner: "albert-einshutoin",
                repository: "soloPM",
                number: 116
            ),
            ["pr", "view", pullRequestURL, "--json", DevelopmentGitHubPRCommandPolicy.statusJSONFields],
            DevelopmentGitHubPRCommandPolicy.reviewThreadsArguments(
                owner: "albert-einshutoin",
                repository: "soloPM",
                number: 116
            ),
            [
                "pr", "merge", pullRequestURL,
                "--merge", "--delete-branch",
                "--match-head-commit", headRefOID
            ]
        ])
        XCTAssertEqual(
            try receiptStore.list(referenceKind: .pullRequest, referenceID: pullRequestURL, visibleSurface: .auditLog, limit: 5)
                .map(\.primaryToolName),
            [
                ActionTool.developmentMergePullRequest.rawValue,
                ActionTool.developmentReviewPullRequestGate.rawValue
            ]
        )
    }

    func testCoordinatorPersistsDevelopmentPullRequestReferencesWhenGitHubStatusThrows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let workspace = temporaryDirectory()
        let project = try projectStore.create(
            title: "SoloPM",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-pr-workspace-bookmark".utf8)
        )
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let item = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(automationRequest: developmentPullRequestAutomationRequest(
                id: "automation-pr-review-invalid-json",
                projectID: project.id,
                operation: .reviewGate,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: "feature/phase14-product-completion"
            )),
            reviewerID: "local-user"
        )
        try queueStore.save(item)
        let gitRunner = RecordingAssistantQueueGitRunner()
        gitRunner.stub(
            arguments: ["remote", "get-url", "origin"],
            output: GitCommandOutput(
                standardOutput: "https://github.com/albert-einshutoin/soloPM.git\n",
                standardError: "",
                exitCode: 0
            )
        )
        let githubRunner = RecordingAssistantQueueGitHubRunner(outputs: [
            GitHubCLICommandOutput(standardOutput: "not-json", standardError: "", exitCode: 0)
        ])
        let registry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: workspace,
                enabledCapabilities: [.developmentPRWorkflow]
            ),
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: AssistantQueueStaticBookmarkResolver(url: workspace),
            projectStore: projectStore,
            taskStore: taskStore
        )
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-pr-status-failure" },
            now: { Date(timeIntervalSince1970: 190) }
        )

        let result = try coordinator.execute(id: item.id)

        XCTAssertEqual(result.item.state, .failed)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.assistantQueueItemID, item.id)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(project.id))))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .pullRequest, id: pullRequestURL)))
        XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue, .projectDetail, .auditLog])
        XCTAssertTrue(receipt.actions.first?.errorSummary?.contains("unreadable pull request status") == true)
    }

    func testCoordinatorFailsDevelopmentPullRequestAutomationWithoutApprovedBookmarkBeforeGitHubCalls() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let workspace = temporaryDirectory()
        let project = try projectStore.create(title: "SoloPM", workspacePath: workspace.path)
        let branchName = "feature/solopm-\(project.id)-merge-gate"
        let pullRequestURL = "https://github.com/albert-einshutoin/soloPM/pull/116"
        let gitRunner = RecordingAssistantQueueGitRunner()
        let githubRunner = RecordingAssistantQueueGitHubRunner(outputs: [
            GitHubCLICommandOutput(standardOutput: "{}", standardError: "", exitCode: 0)
        ])
        let registry = try ToolRegistryFactory.developerMode(
            settings: DeveloperModeSettings(
                isEnabled: true,
                workspaceRoot: workspace,
                enabledCapabilities: [.developmentPRWorkflow]
            ),
            gitRunner: gitRunner,
            githubRunner: githubRunner,
            bookmarkResolver: AssistantQueueStaticBookmarkResolver(url: workspace),
            projectStore: projectStore,
            taskStore: taskStore
        )
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-pr-missing-bookmark" },
            now: { Date(timeIntervalSince1970: 195) }
        )

        for operation in [SyncDevelopmentPullRequestOperation.reviewGate, .merge] {
            let item = try AssistantQueueStateMachine.approve(
                AssistantQueueAdapter.makeItem(automationRequest: developmentPullRequestAutomationRequest(
                    id: "automation-pr-\(operation.rawValue)-no-bookmark",
                    projectID: project.id,
                    operation: operation,
                    pullRequestURL: pullRequestURL,
                    branchName: branchName,
                    baseBranch: "feature/phase14-product-completion"
                )),
                reviewerID: "local-user"
            )
            try queueStore.save(item)

            let result = try coordinator.execute(id: item.id)

            XCTAssertEqual(result.item.state, .failed)
            XCTAssertTrue(result.receipt.actions.first?.errorSummary?.contains("bookmark") == true)
        }
        XCTAssertTrue(gitRunner.recordedInvocations.isEmpty)
        XCTAssertTrue(githubRunner.recordedInvocations.isEmpty)
    }

    func testCoordinatorRejectsMalformedAutomationRequestBeforeRunning() throws {
        let queueStore = try makeQueueStore()
        let missingTaskID = try AssistantQueueStateMachine.approve(
            makeMalformedTaskMutationItem(id: "automation-missing-task-id"),
            reviewerID: "local-user"
        )
        let noOpUpdate = try AssistantQueueStateMachine.approve(
            makeNoOpUpdateTaskMutationItem(id: "automation-no-op-update"),
            reviewerID: "local-user"
        )
        let mismatchedTool = try AssistantQueueStateMachine.approve(
            makeTaskMutationItem(id: "automation-mismatched-tool", toolName: HostedMCPTaskToolName.taskCreate.rawValue),
            reviewerID: "local-user"
        )
        let malformedPullRequest = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
                id: "automation-pr-malformed",
                source: .cloudRelay,
                approvalState: .pendingApproval,
                sourceClientID: "web",
                toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
                redactedArgumentSummary: "Malformed PR review request",
                developmentPullRequest: SyncDevelopmentPullRequestPayload(
                    projectID: 7,
                    operation: .reviewGate,
                    pullRequestURL: "https://example.com/not-github",
                    branchName: "main",
                    baseBranch: "main"
                )
            )),
            reviewerID: "local-user"
        )
        let ambiguousPayload = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
                id: "automation-ambiguous-payload",
                source: .cloudRelay,
                approvalState: .pendingApproval,
                sourceClientID: "web",
                toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
                redactedArgumentSummary: "Ambiguous remote request",
                taskMutation: SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .complete,
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                developmentPullRequest: SyncDevelopmentPullRequestPayload(
                    projectID: 7,
                    operation: .reviewGate,
                    pullRequestURL: "https://github.com/albert-einshutoin/soloPM/pull/116",
                    branchName: "feature/solopm-7-merge-gate",
                    baseBranch: "feature/phase14-product-completion"
                )
            )),
            reviewerID: "local-user"
        )
        let missingToolName = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
                id: "automation-pr-missing-tool-name",
                source: .cloudRelay,
                approvalState: .pendingApproval,
                sourceClientID: "web",
                redactedArgumentSummary: "PR review without tool name",
                developmentPullRequest: SyncDevelopmentPullRequestPayload(
                    projectID: 7,
                    operation: .reviewGate,
                    pullRequestURL: "https://github.com/albert-einshutoin/soloPM/pull/116",
                    branchName: "feature/solopm-7-merge-gate",
                    baseBranch: "feature/phase14-product-completion"
                )
            )),
            reviewerID: "local-user"
        )
        let mismatchedPullRequestTool = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
                id: "automation-pr-mismatched-tool",
                source: .cloudRelay,
                approvalState: .pendingApproval,
                sourceClientID: "web",
                toolName: ActionTool.developmentMergePullRequest.rawValue,
                redactedArgumentSummary: "PR review with mismatched merge tool",
                developmentPullRequest: SyncDevelopmentPullRequestPayload(
                    projectID: 7,
                    operation: .reviewGate,
                    pullRequestURL: "https://github.com/albert-einshutoin/soloPM/pull/116",
                    branchName: "feature/solopm-7-merge-gate",
                    baseBranch: "feature/phase14-product-completion"
                )
            )),
            reviewerID: "local-user"
        )
        let remoteLocalDevelopmentTools = try [
            ActionTool.developmentPreparePullRequestWorkflow,
            .developmentRepositoryCreateFile,
            .developmentCommitChanges
        ].map { tool in
            try AssistantQueueStateMachine.approve(
                AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
                    id: "automation-local-dev-\(tool.rawValue.replacingOccurrences(of: ".", with: "-"))",
                    source: .cloudRelay,
                    approvalState: .pendingApproval,
                    sourceClientID: "web",
                    toolName: tool.rawValue,
                    redactedArgumentSummary: "Remote request must not execute local development tool \(tool.rawValue)",
                    developmentPullRequest: SyncDevelopmentPullRequestPayload(
                        projectID: 7,
                        operation: .reviewGate,
                        pullRequestURL: "https://github.com/albert-einshutoin/soloPM/pull/116",
                        branchName: "feature/solopm-7-merge-gate",
                        baseBranch: "feature/phase14-product-completion"
                    )
                )),
                reviewerID: "local-user"
            )
        }
        try queueStore.save(missingTaskID)
        try queueStore.save(noOpUpdate)
        try queueStore.save(mismatchedTool)
        try queueStore.save(malformedPullRequest)
        try queueStore.save(ambiguousPayload)
        try queueStore.save(missingToolName)
        try queueStore.save(mismatchedPullRequestTool)
        for item in remoteLocalDevelopmentTools {
            try queueStore.save(item)
        }
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: ToolRegistry()),
            executionReceiptStore: VolatileExecutionReceiptStore()
        )

        for item in [
            missingTaskID,
            noOpUpdate,
            mismatchedTool,
            malformedPullRequest,
            ambiguousPayload,
            missingToolName,
            mismatchedPullRequestTool
        ] + remoteLocalDevelopmentTools {
            XCTAssertThrowsError(try coordinator.execute(id: item.id)) { error in
                XCTAssertEqual(error as? AssistantQueueExecutionError, .unsupportedPayload)
            }
            XCTAssertEqual(try queueStore.get(id: item.id).state, .approved)
        }
    }

    func testExecutableFactoryMapsTaskMutationOperationsToLocalTaskTools() throws {
        let cases: [(SyncTaskMutationPayload, ActionTool, [String: JSONValue])] = [
            (
                SyncTaskMutationPayload(
                    operation: .create,
                    title: "Remote task",
                    detail: "Details",
                    projectID: 7,
                    dueAt: "2026-07-01",
                    priority: "high",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskCreate,
                [
                    "title": .string("Remote task"),
                    "detail": .string("Details"),
                    "projectId": .number(7),
                    "dueAt": .string("2026-07-01"),
                    "priority": .string("high")
                ]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .update,
                    title: "Renamed",
                    status: "in_progress",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskUpdate,
                [
                    "id": .number(42),
                    "title": .string("Renamed"),
                    "status": .string("in_progress")
                ]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .complete,
                    status: "completed",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskComplete,
                ["id": .number(42)]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .moveProject,
                    projectID: 8,
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskUpdate,
                ["id": .number(42), "projectId": .number(8)]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .updateDueDate,
                    dueAt: "2026-07-02",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskUpdate,
                ["id": .number(42), "dueAt": .string("2026-07-02")]
            )
        ]

        for (index, testCase) in cases.enumerated() {
            let request = SyncAutomationRequestPayload(
                id: "automation-\(index)",
                source: .cloudRelay,
                approvalState: .pendingApproval,
                toolName: hostedToolName(for: testCase.0.operation),
                redactedArgumentSummary: "case-\(index)",
                taskMutation: testCase.0
            )
            let plan = try XCTUnwrap(AssistantQueueExecutableActionPlanFactory.actionPlan(for: .automationRequest(request)))

            XCTAssertEqual(plan.id, "automation-request:automation-\(index)")
            XCTAssertEqual(plan.requiresApproval, true)
            XCTAssertEqual(plan.actions.first?.tool, testCase.1)
            XCTAssertEqual(plan.actions.first?.arguments, testCase.2)
        }
    }

    func testExecutableFactoryIncludesRedactedMutationDetailInReviewSummary() throws {
        let request = SyncAutomationRequestPayload(
            id: "automation-redacted-detail",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
            redactedArgumentSummary: "",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .update,
                detail: "Use token=detail-secret before launch",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        let summary = AssistantQueueExecutableActionPlanFactory.reviewSummary(for: request)
        let plan = try XCTUnwrap(AssistantQueueExecutableActionPlanFactory.actionPlan(for: .automationRequest(request)))

        XCTAssertTrue(summary.contains("detail=Use [REDACTED_SECRET] before launch"))
        XCTAssertFalse(summary.contains("detail-secret"))
        XCTAssertEqual(plan.summary, summary)
    }

    func testCoordinatorRequiresQueueApprovalBeforeRunning() throws {
        let queueStore = try makeQueueStore()
        let item = makeActionPlanItem()
        try queueStore.save(item)
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: ToolRegistry()),
            executionReceiptStore: VolatileExecutionReceiptStore()
        )

        XCTAssertThrowsError(try coordinator.execute(id: item.id)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .approvalRequiredBeforeRunning)
        }
        XCTAssertEqual(try queueStore.get(id: item.id).state, .waitingReview)
    }

    func testCoordinatorMarksQueueFailedAndPersistsFailedReceiptWhenToolFails() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                throw ToolExecutionError.executionFailed(.taskCreate, "provider failed token=queue-secret")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-failure" },
            now: { Date(timeIntervalSince1970: 200) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .failed)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .failed)
        XCTAssertEqual(try queueStore.get(id: approved.id).blockingReason, "Execution failed. Review the receipt before retrying.")

        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertEqual(receipt.queueApproval?.reviewerID, "local-user")
        XCTAssertTrue(receipt.outputSummary.contains("failed"))
        XCTAssertTrue(receipt.actions.first?.errorSummary?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(receipt.actions.first?.errorSummary?.contains("queue-secret") ?? true)
    }

    func testCoordinatorCanRunReapprovedFailedItemAfterRetryReviewAndKeepsSeparateReceipts() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let failingRegistry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                throw ToolExecutionError.executionFailed(.taskCreate, "provider failed")
            }
        ])
        let failingCoordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: failingRegistry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-retry-failure" },
            now: { Date(timeIntervalSince1970: 200) }
        )

        _ = try failingCoordinator.execute(id: approved.id)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .failed)

        let reopened = try queueStore.transition(id: approved.id) { item in
            try AssistantQueueStateMachine.reopenFailedForReview(item)
        }
        XCTAssertEqual(reopened.state, .waitingReview)
        XCTAssertNil(reopened.approval)
        let reapproved = try queueStore.transition(id: approved.id) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
        let successRegistry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created after retry")
            }
        ])
        let successCoordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: successRegistry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-retry-success" },
            now: { Date(timeIntervalSince1970: 300) }
        )

        let result = try successCoordinator.execute(id: reapproved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        XCTAssertEqual(receiptStore.receipts.map(\.assistantQueueItemID), [approved.id, approved.id])
        XCTAssertEqual(receiptStore.receipts.map(\.status), [.failed, .succeeded])
        XCTAssertEqual(receiptStore.receipts.map(\.runID), ["run-queue-retry-failure", "run-queue-retry-success"])
        XCTAssertEqual(receiptStore.receipts[0].queueApproval?.reviewedContentDigest, receiptStore.receipts[1].queueApproval?.reviewedContentDigest)
        XCTAssertNotEqual(receiptStore.receipts[0].queueApproval?.approvalID, receiptStore.receipts[1].queueApproval?.approvalID)
    }

    func testCoordinatorCanRunReapprovedFailedTaskMutationAutomationRequestAfterRetryReview() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = VolatileExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeTaskMutationItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let failingRegistry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskUpdate,
                description: "update task",
                inputSchema: ToolInputSchema(required: ["id"], properties: ["id": "integer", "dueAt": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                throw ToolExecutionError.executionFailed(.taskUpdate, "provider failed")
            }
        ])
        let failingCoordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: failingRegistry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-automation-retry-failure" },
            now: { Date(timeIntervalSince1970: 200) }
        )

        _ = try failingCoordinator.execute(id: approved.id)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .failed)

        let reopened = try queueStore.transition(id: approved.id) { item in
            try AssistantQueueStateMachine.reopenFailedForReview(item)
        }
        XCTAssertEqual(reopened.state, .waitingReview)
        XCTAssertNil(reopened.approval)
        let reapproved = try queueStore.transition(id: approved.id) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
        let successRegistry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskUpdate,
                description: "update task",
                inputSchema: ToolInputSchema(required: ["id"], properties: ["id": "integer", "dueAt": "string"]),
                permissionLevel: .writeWithApproval
            ) { arguments, context in
                XCTAssertNotNil(context.approvalToken)
                XCTAssertEqual(arguments["id"], .number(42))
                XCTAssertEqual(arguments["dueAt"], .string("2026-07-01T09:00:00Z"))
                return ToolResult(tool: .taskUpdate, status: .succeeded, summary: "Updated after retry")
            }
        ])
        let successCoordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: successRegistry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-automation-retry-success" },
            now: { Date(timeIntervalSince1970: 300) }
        )

        let result = try successCoordinator.execute(id: reapproved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        XCTAssertEqual(receiptStore.receipts.map(\.assistantQueueItemID), [approved.id, approved.id])
        XCTAssertEqual(receiptStore.receipts.map(\.status), [.failed, .succeeded])
        XCTAssertEqual(receiptStore.receipts.map(\.runID), [
            "run-queue-automation-retry-failure",
            "run-queue-automation-retry-success"
        ])
        XCTAssertEqual(receiptStore.receipts[0].queueApproval?.reviewedContentDigest, receiptStore.receipts[1].queueApproval?.reviewedContentDigest)
        XCTAssertNotEqual(receiptStore.receipts[0].queueApproval?.approvalID, receiptStore.receipts[1].queueApproval?.approvalID)
    }

    func testCoordinatorMarksFailedWhenSuccessfulExecutionReceiptCannotBePersisted() throws {
        let queueStore = try makeQueueStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: FailingExecutionReceiptStore(),
            runIDProvider: { "run-queue-receipt-failure" },
            now: { Date(timeIntervalSince1970: 300) }
        )

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            XCTAssertEqual(
                error as? AssistantQueueExecutionError,
                .receiptPersistenceFailed(queueStateMarkedFailed: true)
            )
        }
        let failed = try queueStore.get(id: approved.id)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(
            failed.blockingReason,
            "Execution completed, but the execution receipt could not be saved. Fix receipt storage before retrying."
        )
    }

    func testCoordinatorMarksFailedWhenFailedExecutionReceiptCannotBePersisted() throws {
        let queueStore = try makeQueueStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .failed, summary: "Provider rejected the request")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: FailingExecutionReceiptStore(),
            runIDProvider: { "run-queue-failed-receipt-failure" },
            now: { Date(timeIntervalSince1970: 310) }
        )

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            XCTAssertEqual(
                error as? AssistantQueueExecutionError,
                .receiptPersistenceFailed(queueStateMarkedFailed: true)
            )
        }
        let failed = try queueStore.get(id: approved.id)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(
            failed.blockingReason,
            "Execution failed, and the execution receipt could not be saved. Fix receipt storage before retrying."
        )
    }

    func testCoordinatorMarksFailedWhenExecutorThrowsAndReceiptCannotBePersisted() throws {
        let queueStore = try makeQueueStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: ToolRegistry()),
            executionReceiptStore: FailingExecutionReceiptStore(),
            runIDProvider: { "run-queue-thrown-receipt-failure" },
            now: { Date(timeIntervalSince1970: 320) }
        )

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            XCTAssertEqual(
                error as? AssistantQueueExecutionError,
                .receiptPersistenceFailed(queueStateMarkedFailed: true)
            )
        }
        let failed = try queueStore.get(id: approved.id)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(
            failed.blockingReason,
            "Execution failed, and the execution receipt could not be saved. Fix receipt storage before retrying."
        )
    }

    func testCoordinatorReportsReceiptPersistenceFailureWhenQueueCannotMarkFailed() throws {
        let queueStore = MarkFailedTransitionFailingQueueStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: FailingExecutionReceiptStore(),
            runIDProvider: { "run-queue-receipt-and-state-failure" },
            now: { Date(timeIntervalSince1970: 330) }
        )

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            XCTAssertEqual(
                error as? AssistantQueueExecutionError,
                .receiptPersistenceFailed(queueStateMarkedFailed: false)
            )
        }
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .running)
    }

    private func makeQueueStore() throws -> SQLiteAssistantQueueStore {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return SQLiteAssistantQueueStore(connection: connection)
    }

    private func makeActionPlanItem(costPreview: AssistantQueueCostPreview? = nil) -> AssistantQueueItem {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "plan-queue-execution",
                userInput: "Create Launch checklist",
                summary: "Create Launch checklist",
                actions: [
                    PlanAction(
                        id: "action-create",
                        tool: .taskCreate,
                        arguments: ["title": .string("Launch checklist")],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Create Launch checklist",
            interpretationSummary: "Task creation",
            reason: "Needs review before execution."
        )
        guard let costPreview else {
            return item
        }
        return AssistantQueueItem(
            id: item.id,
            state: item.state,
            payload: item.payload,
            riskLevel: item.riskLevel,
            sourceTranscript: item.sourceTranscript,
            interpretationSummary: item.interpretationSummary,
            reviewReason: item.reviewReason,
            redactedSummary: item.redactedSummary,
            requiredCapabilities: item.requiredCapabilities,
            approval: item.approval,
            blockingReason: item.blockingReason,
            costPreview: costPreview
        )
    }

    private func makeCostPreview(inputTokens: Int, outputTokens: Int) -> AssistantQueueCostPreview {
        AssistantQueueCostRateCard(
            provider: "openai",
            modelName: "gpt-test",
            currencyCode: "USD",
            inputTokenCentsPerMillion: 100,
            outputTokenCentsPerMillion: 300
        ).preview(inputTokens: inputTokens, outputTokens: outputTokens, hardCapCents: 2)
    }

    private func makeTaskMutationItem(
        id: String = "automation-task-due",
        toolName: String = HostedMCPTaskToolName.taskDueDateUpdate.rawValue
    ) -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: toolName,
            redactedArgumentSummary: "taskID=42, dueAt=2026-07-01T09:00:00Z",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .updateDueDate,
                dueAt: "2026-07-01T09:00:00Z",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
    }

    private func makeMalformedTaskMutationItem(id: String) -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskComplete.rawValue,
            redactedArgumentSummary: "Complete remote task without taskID",
            taskMutation: SyncTaskMutationPayload(
                operation: .complete,
                status: "completed",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
    }

    private func makeNoOpUpdateTaskMutationItem(id: String) -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
            redactedArgumentSummary: "Update remote task without changed fields",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .update,
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
    }

    private func developmentPullRequestAutomationRequest(
        id: String,
        projectID: Int64,
        operation: SyncDevelopmentPullRequestOperation,
        pullRequestURL: String,
        branchName: String,
        baseBranch: String
    ) -> SyncAutomationRequestPayload {
        SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: actionTool(for: operation).rawValue,
            redactedArgumentSummary: "PR \(operation.rawValue) \(pullRequestURL)",
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: projectID,
                operation: operation,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: baseBranch
            )
        )
    }

    private func actionTool(for operation: SyncDevelopmentPullRequestOperation) -> ActionTool {
        switch operation {
        case .reviewGate:
            return .developmentReviewPullRequestGate
        case .merge:
            return .developmentMergePullRequest
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloPMAssistantQueueExecutionTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pullRequestStatusJSON(
        url: String,
        headBranch: String,
        baseBranch: String,
        headRefOID: String = "0123456789abcdef0123456789abcdef01234567"
    ) -> String {
        """
        {
          "url": "\(url)",
          "headRefName": "\(headBranch)",
          "headRefOid": "\(headRefOID)",
          "baseRefName": "\(baseBranch)",
          "headRepository": {
            "name": "soloPM",
            "nameWithOwner": "albert-einshutoin/soloPM"
          },
          "headRepositoryOwner": {
            "login": "albert-einshutoin"
          },
          "isCrossRepository": false,
          "reviewDecision": "APPROVED",
          "mergeable": "MERGEABLE",
          "mergeStateStatus": "CLEAN",
          "statusCheckRollup": [
            {
              "__typename": "CheckRun",
              "name": "SwiftPM macOS",
              "status": "COMPLETED",
              "conclusion": "SUCCESS"
            },
            {
              "__typename": "CheckRun",
              "name": "GitGuardian Security Checks",
              "status": "COMPLETED",
              "conclusion": "SUCCESS"
            }
          ]
        }
        """
    }

    private func reviewThreadsJSON(
        totalCount: Int,
        unresolvedCount: Int,
        hasNextPage: Bool = false
    ) -> String {
        let resolvedCount = max(0, totalCount - unresolvedCount)
        let nodes = Array(repeating: #"{"isResolved": false}"#, count: unresolvedCount)
            + Array(repeating: #"{"isResolved": true}"#, count: resolvedCount)
        return """
        {
          "data": {
            "repository": {
              "pullRequest": {
                "reviewThreads": {
                  "totalCount": \(totalCount),
                  "nodes": [\(nodes.joined(separator: ","))],
                  "pageInfo": {
                    "hasNextPage": \(hasNextPage ? "true" : "false")
                  }
                }
              }
            }
          }
        }
        """
    }

    private func hostedToolName(for operation: SyncTaskMutationOperation) -> String {
        switch operation {
        case .create:
            return HostedMCPTaskToolName.taskCreate.rawValue
        case .update:
            return HostedMCPTaskToolName.taskUpdate.rawValue
        case .complete:
            return HostedMCPTaskToolName.taskComplete.rawValue
        case .moveProject:
            return HostedMCPTaskToolName.taskProjectMove.rawValue
        case .updateDueDate:
            return HostedMCPTaskToolName.taskDueDateUpdate.rawValue
        }
    }
}

private final class MarkFailedTransitionFailingQueueStore: AssistantQueueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: AssistantQueueItem] = [:]

    @discardableResult
    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        lock.lock()
        defer { lock.unlock() }
        items[item.id] = item
        return item
    }

    func get(id: String) throws -> AssistantQueueItem {
        lock.lock()
        defer { lock.unlock() }
        guard let item = items[id] else {
            throw AssistantQueueStoreError.notFound(id)
        }
        return item
    }

    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem] {
        lock.lock()
        defer { lock.unlock() }
        return Array(items.values)
            .filter { filter.includes($0.state) }
            .sorted(by: { $0.id < $1.id })
            .prefix(filter.limit)
            .map { $0 }
    }

    func stateCounts() throws -> AssistantQueueStateCounts {
        lock.lock()
        defer { lock.unlock() }
        return AssistantQueueStateCounts(items: Array(items.values))
    }

    @discardableResult
    func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem {
        lock.lock()
        defer { lock.unlock() }
        guard let item = items[id] else {
            throw AssistantQueueStoreError.notFound(id)
        }
        let next = try transform(item)
        guard next.state != .failed else {
            throw AssistantQueueStoreError.saveFailed
        }
        items[id] = next
        return next
    }
}

private final class FailingExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
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

private final class RecordingManagedAIUsageLedgerStore: ManagedAIUsageLedgerStore, @unchecked Sendable {
    private(set) var entries: [ManagedAIUsageLedgerEntry]

    init(entries: [ManagedAIUsageLedgerEntry] = []) {
        self.entries = entries
    }

    func record(_ entry: ManagedAIUsageLedgerEntry) throws {
        entries.append(entry)
    }

    func list(limit: Int) throws -> [ManagedAIUsageLedgerEntry] {
        Array(entries.prefix(limit))
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

private final class RecordingAssistantQueueGitRunner: GitCommandRunner, @unchecked Sendable {
    private var stubs: [String: GitCommandOutput] = [:]
    private(set) var recordedInvocations: [GitCommandInvocation] = []

    func stub(arguments: [String], output: GitCommandOutput) {
        stubs[arguments.joined(separator: "\u{1f}")] = output
    }

    func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        recordedInvocations.append(GitCommandInvocation(arguments: arguments, workingDirectory: workingDirectory))
        return stubs[arguments.joined(separator: "\u{1f}")] ?? GitCommandOutput(
            standardOutput: "",
            standardError: "unexpected command",
            exitCode: 127
        )
    }
}

private final class RecordingAssistantQueueGitHubRunner: GitHubCLICommandRunner, @unchecked Sendable {
    private var outputs: [GitHubCLICommandOutput]
    private(set) var recordedInvocations: [GitHubCLICommandInvocation] = []

    init(outputs: [GitHubCLICommandOutput]) {
        self.outputs = outputs
    }

    func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput {
        recordedInvocations.append(GitHubCLICommandInvocation(arguments: arguments, workingDirectory: workingDirectory))
        if outputs.count > 1 {
            return outputs.removeFirst()
        }
        return outputs.first ?? GitHubCLICommandOutput(
            standardOutput: "",
            standardError: "unexpected command",
            exitCode: 127
        )
    }
}

private struct AssistantQueueStaticBookmarkResolver: ProjectWorkspaceBookmarkResolving {
    var url: URL

    func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution {
        ProjectWorkspaceBookmarkResolution(
            url: url,
            isStale: false,
            didStartAccessing: true,
            stopAccessing: {}
        )
    }
}
