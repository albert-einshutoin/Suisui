import XCTest
@testable import SoloPMCore

final class SoloPMHarnessTests: XCTestCase {
    func testScenarioCatalogCoversPhase13AutomationSurfaces() throws {
        let catalog = SoloPMHarnessScenario.templateCatalog()
        XCTAssertEqual(
            Set(catalog.map(\.kind)),
            [
                .providerPromptRegression,
                .taskMutationFlow,
                .documentScopedAutomation,
                .mcpCompatibility,
                .accessibilityFocusPath
            ]
        )

        let taskMutation = try XCTUnwrap(catalog.first { $0.kind == .taskMutationFlow })
        XCTAssertEqual(
            taskMutation.expectedMutations.map(\.operation),
            [.create, .update, .complete, .updateDueDate, .moveProject]
        )
        XCTAssertTrue(taskMutation.assertions.contains(.approvalBoundary))
        XCTAssertTrue(taskMutation.assertions.contains(.auditLogRecorded))
        XCTAssertTrue(taskMutation.requiredCapabilities.contains(.taskMutation))

        let encoded = try JSONEncoder().encode(taskMutation)
        let decoded = try JSONDecoder().decode(SoloPMHarnessScenario.self, from: encoded)
        XCTAssertEqual(decoded, taskMutation)

        let accessibility = try XCTUnwrap(catalog.first { $0.kind == .accessibilityFocusPath })
        XCTAssertEqual(accessibility.id, "mcp-pseudo-voiceover-focus-path")
        XCTAssertTrue(accessibility.requiredCapabilities.contains(.mcpToolCall))
        XCTAssertTrue(accessibility.requiredCapabilities.contains(.accessibilityAudit))
        XCTAssertTrue(accessibility.assertions.contains(.accessibilityFocusPathCovered))
    }

    func testTaskLifecycleHarnessRequiresCreateEditExecuteAndDeleteCoverage() throws {
        let catalog = SoloPMHarnessScenario.templateCatalog()
        let requiredLifecycle: [SoloPMHarnessTaskLifecycleOperation] = [
            .create,
            .editContent,
            .statusMove,
            .automationReview,
            .executeContent,
            .approvedExecution,
            .deleteConfirmation
        ]

        let taskMutation = try XCTUnwrap(catalog.first { $0.kind == .taskMutationFlow })
        XCTAssertEqual(taskMutation.requiredTaskLifecycleOperations, requiredLifecycle)
        XCTAssertTrue(taskMutation.missingTaskLifecycleOperations().isEmpty)

        let accessibility = try XCTUnwrap(catalog.first { $0.kind == .accessibilityFocusPath })
        XCTAssertEqual(accessibility.requiredTaskLifecycleOperations, requiredLifecycle)
        XCTAssertTrue(accessibility.missingTaskLifecycleOperations().isEmpty)
    }

    func testDocumentAutomationHarnessRequiresReviewableDeliverableCoverage() throws {
        let catalog = SoloPMHarnessScenario.templateCatalog()
        let scenario = try XCTUnwrap(catalog.first { $0.kind == .documentScopedAutomation })

        XCTAssertEqual(
            scenario.requiredDocumentDeliverableKinds,
            [.preparationChecklist, .draftArtifact, .releaseNotes, .pullRequestPlan]
        )
        XCTAssertTrue(scenario.missingDocumentDeliverableKinds().isEmpty)
    }

    func testDocumentAutomationHarnessRunPassesSelectedDocDeliverableDrafts() {
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes, a PR plan, and the right draft artifacts from these docs.",
            documents: documentAutomationHarnessDocuments()
        )

        let run = SoloPMHarnessDocumentAutomationRunner().run(
            id: "run-document-pass",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            drafts: drafts
        )

        XCTAssertEqual(run.status, .passed)
        XCTAssertEqual(run.scenario.kind, .documentScopedAutomation)
        XCTAssertEqual(run.resultEnvelope.scenarioKind, .documentScopedAutomation)
        XCTAssertEqual(run.steps.map(\.id), [
            "document-deliverable-preparationChecklist",
            "document-deliverable-draftArtifact",
            "document-deliverable-releaseNotes",
            "document-deliverable-pullRequestPlan"
        ])
        XCTAssertNil(run.diff)
        XCTAssertTrue(run.redactedLogs.contains { $0.message.contains("deliverables covered=4/4") })
    }

    func testDocumentAutomationHarnessRunFailsWithConcreteMissingDeliverableDiff() {
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes, a PR plan, and the right draft artifacts from these docs.",
            documents: documentAutomationHarnessDocuments()
        )
        .filter { $0.kind != .releaseNotes }

        let run = SoloPMHarnessDocumentAutomationRunner().run(
            id: "run-document-fail",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            drafts: drafts
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "document-deliverable-releaseNotes")
        XCTAssertEqual(run.diff?.expected, "reviewable document deliverable draft present")
        XCTAssertTrue(run.diff?.actual.contains("missingDocumentDeliverable") ?? false)
        XCTAssertTrue(run.failureReason?.contains("releaseNotes") ?? false)
    }

    func testDocumentAutomationHarnessRunRequiresRedactedSourcePreviewsForEachDeliverable() throws {
        var drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes, a PR plan, and the right draft artifacts from these docs.",
            documents: documentAutomationHarnessDocuments()
        )
        let releaseNotesIndex = try XCTUnwrap(drafts.firstIndex { $0.kind == .releaseNotes })
        drafts[releaseNotesIndex].sourceDocuments = []

        let run = SoloPMHarnessDocumentAutomationRunner().run(
            id: "run-document-missing-source-previews",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            drafts: drafts
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "document-deliverable-releaseNotes")
        XCTAssertEqual(run.diff?.expected, "reviewable document deliverable draft present")
        XCTAssertTrue(run.diff?.actual.contains("missingSourcePreviews") ?? false)
        XCTAssertTrue(run.failureReason?.contains("source preview") ?? false)
    }

    func testDocumentAutomationHarnessRunRequiresSourcePreviewsToMatchCitedDocuments() throws {
        var drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes, a PR plan, and the right draft artifacts from these docs.",
            documents: documentAutomationHarnessDocuments()
        )
        let releaseNotesIndex = try XCTUnwrap(drafts.firstIndex { $0.kind == .releaseNotes })
        let artifactPreview = try XCTUnwrap(drafts.first { $0.kind == .draftArtifact }?.sourceDocuments.first)
        drafts[releaseNotesIndex].sourceDocuments = [artifactPreview]

        let run = SoloPMHarnessDocumentAutomationRunner().run(
            id: "run-document-mismatched-source-preview",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            drafts: drafts
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "document-deliverable-releaseNotes")
        XCTAssertTrue(run.diff?.actual.contains("missingSourcePreviews") ?? false)
    }

    func testTaskLifecycleCoverageReportsMissingExecuteAndDeleteRequirements() {
        let scenario = SoloPMHarnessScenario(
            id: "partial-task-lifecycle",
            name: "Partial task lifecycle",
            kind: .taskMutationFlow,
            requiredCapabilities: [.taskMutation],
            expectedMutations: [],
            assertions: [.approvalBoundary],
            requiredTaskLifecycleOperations: [.create, .editContent, .statusMove, .automationReview]
        )

        XCTAssertEqual(scenario.missingTaskLifecycleOperations(), [.executeContent, .approvedExecution, .deleteConfirmation])
    }

    func testScenarioDecodesLegacyPayloadWithoutLifecycleCoverage() throws {
        let legacyJSON = """
        {
          "id": "legacy",
          "name": "Legacy harness",
          "kind": "taskMutationFlow",
          "requiredCapabilities": ["taskMutation"],
          "expectedMutations": [],
          "assertions": ["approvalBoundary"]
        }
        """

        let scenario = try JSONDecoder().decode(SoloPMHarnessScenario.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(scenario.requiredTaskLifecycleOperations, [])
        XCTAssertEqual(scenario.requiredDocumentDeliverableKinds, [])
        XCTAssertEqual(scenario.missingTaskLifecycleOperations(), SoloPMHarnessScenario.completeTaskLifecycleOperations)
        XCTAssertEqual(scenario.missingDocumentDeliverableKinds(), SoloPMHarnessScenario.completeDocumentDeliverableKinds)
    }

    func testAccessibilityHarnessRunPassesCompletePseudoVoiceOverFocusPath() {
        let run = SoloPMHarnessAccessibilityAuditRunner().run(
            id: "run-ax-pass",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: completeAccessibilityNodes(),
            approvedExecutionReceipt: approvedExecutionReceipt()
        )

        XCTAssertEqual(run.status, .passed)
        XCTAssertEqual(run.scenario.kind, .accessibilityFocusPath)
        XCTAssertEqual(run.resultEnvelope.scenarioKind, .accessibilityFocusPath)
        let requiredNodeCount = AccessibilityFocusPathRequirement.taskLifecycleAndExecution.requiredNodeIDs.count
        XCTAssertEqual(run.steps.count, requiredNodeCount + 1)
        XCTAssertEqual(run.steps.last?.id, "approved-execution-receipt")
        XCTAssertNil(run.diff)
        XCTAssertTrue(run.redactedLogs.contains { $0.message.contains("covered=\(requiredNodeCount)/\(requiredNodeCount)") })
        XCTAssertTrue(run.redactedLogs.contains { $0.message.contains("approved execution receipt covered=1/1") })
    }

    func testAccessibilityHarnessRunRequiresApprovedExecutionReceiptForCompletePseudoVoiceOverPath() {
        let run = SoloPMHarnessAccessibilityAuditRunner().run(
            id: "run-ax-missing-receipt",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: completeAccessibilityNodes()
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "approved-execution-receipt")
        XCTAssertEqual(run.diff?.expected, "redacted approved automation execution receipt present")
        XCTAssertTrue(run.diff?.actual.contains("missingApprovedExecutionReceipt") ?? false)
    }

    func testAccessibilityHarnessRunRejectsUnredactedApprovedExecutionReceipt() {
        let run = SoloPMHarnessAccessibilityAuditRunner().run(
            id: "run-ax-unredacted-receipt",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: completeAccessibilityNodes(),
            approvedExecutionReceipt: approvedExecutionReceipt(
                title: "Run provider handoff token=secret-title",
                detail: "Use sk-proj-live-secret for release notes."
            )
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "approved-execution-receipt")
        XCTAssertTrue(run.diff?.actual.contains("unredactedSecret") ?? false)
        XCTAssertFalse(run.diff?.actual.contains("sk-proj-live-secret") ?? false)
    }

    func testAccessibilityHarnessRunRequiresApprovedExecutionReceiptTaskDetail() {
        let run = SoloPMHarnessAccessibilityAuditRunner().run(
            id: "run-ax-missing-receipt-detail",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: completeAccessibilityNodes(),
            approvedExecutionReceipt: approvedExecutionReceipt(detail: "   ")
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "approved-execution-receipt")
        XCTAssertTrue(run.diff?.actual.contains("missingTaskDetail") ?? false)
    }

    func testAccessibilityHarnessRunRejectsUnlabeledRequiredLandmarks() {
        let nodes = completeAccessibilityNodes().map { node in
            guard node.id == "approved-execution-receipt" else {
                return node
            }
            return AccessibilityNodeSnapshot(
                id: node.id,
                role: node.role,
                label: "   ",
                help: node.help,
                isEnabled: node.isEnabled,
                isDestructive: node.isDestructive,
                confirmsDestructiveAction: node.confirmsDestructiveAction
            )
        }

        let run = SoloPMHarnessAccessibilityAuditRunner().run(
            id: "run-ax-unlabeled-receipt-landmark",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: nodes,
            approvedExecutionReceipt: approvedExecutionReceipt()
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "focus-path-approved-execution-receipt")
        XCTAssertTrue(run.diff?.actual.contains("unlabeledRequiredNode") ?? false)
    }

    func testAccessibilityHarnessRunFailsWithConcreteMissingFocusPathDiff() {
        let incompleteNodes = completeAccessibilityNodes()
            .filter { $0.id != "task-auto-execution-run-plan" }

        let run = SoloPMHarnessAccessibilityAuditRunner().run(
            id: "run-ax-fail",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: incompleteNodes
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "focus-path-task-auto-execution-run-plan")
        XCTAssertEqual(run.diff?.expected, "required focus path node present and descriptive")
        XCTAssertTrue(run.diff?.actual.contains("missingRequiredNode") ?? false)
        XCTAssertTrue(run.failureReason?.contains("task-auto-execution-run-plan") ?? false)
    }

    func testLocalAndCloudTriggeredRunsShareResultEnvelopeShape() {
        let scenario = SoloPMHarnessScenario.templateCatalog()[0]
        let step = SoloPMHarnessStepResult(
            id: "provider-plan",
            status: .passed,
            expected: "task.create action",
            actual: "task.create action",
            failureReason: nil,
            durationMilliseconds: 42
        )

        let local = SoloPMHarnessRun.completed(
            id: "run-local",
            scenario: scenario,
            trigger: .local,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [step],
            logs: [SoloPMHarnessLogEntry(level: .info, message: "provider smoke passed")]
        )
        let cloud = SoloPMHarnessRun.completed(
            id: "run-cloud",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [step],
            logs: [SoloPMHarnessLogEntry(level: .info, message: "provider smoke passed")]
        )

        XCTAssertEqual(local.resultEnvelope.shape, cloud.resultEnvelope.shape)
        XCTAssertEqual(local.resultEnvelope.schemaVersion, 1)
        XCTAssertEqual(cloud.resultEnvelope.schemaVersion, 1)
        XCTAssertEqual(local.status, .passed)
        XCTAssertEqual(cloud.status, .passed)
    }

    func testHistoryStorePersistsDiffFailureReasonAndRedactedLogs() throws {
        let rawCredential = "sk-" + "proj-redacted123456"
        let scenario = SoloPMHarnessScenario(
            id: "mcp-compatibility-smoke",
            name: "MCP compatibility smoke",
            kind: .mcpCompatibility,
            requiredCapabilities: [.mcpToolCall],
            expectedMutations: [],
            assertions: [.redactedLogs, .resultDiffRecorded]
        )
        let failedStep = SoloPMHarnessStepResult(
            id: "call-task-create",
            status: .failed,
            expected: "tool call succeeds",
            actual: "401 credential \(rawCredential)",
            failureReason: "MCP server rejected the request",
            durationMilliseconds: 130
        )
        let run = SoloPMHarnessRun.completed(
            id: "run-failed",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [failedStep],
            logs: [
                SoloPMHarnessLogEntry(level: .error, message: "credential \(rawCredential) failed")
            ]
        )

        var store = RedactingSoloPMHarnessRunStore()
        try store.save(run, plan: .pro)
        let saved = try XCTUnwrap(store.runs.first)

        XCTAssertEqual(saved.status, .failed)
        XCTAssertEqual(saved.diff?.expected, "tool call succeeds")
        XCTAssertEqual(saved.diff?.actual, "401 credential [REDACTED_SECRET]")
        XCTAssertEqual(saved.failureReason, "MCP server rejected the request")
        XCTAssertEqual(saved.redactedLogs[0].message, "credential [REDACTED_SECRET] failed")
    }

    func testHarnessRunMapsToSyncPayloadWithoutRawLogs() {
        let scenario = SoloPMHarnessScenario.templateCatalog()[1]
        let run = SoloPMHarnessRun.completed(
            id: "run-sync",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [
                SoloPMHarnessStepResult(
                    id: "mutation",
                    status: .failed,
                    expected: "status=in_progress",
                    actual: "status=blocked",
                    failureReason: "Unexpected status",
                    durationMilliseconds: 55
                )
            ],
            logs: [SoloPMHarnessLogEntry(level: .error, message: "raw provider details")]
        )

        XCTAssertEqual(
            run.syncPayload,
            SyncHarnessRunPayload(
                id: "run-sync",
                scenario: "task-mutation-flow",
                status: "failed",
                scenarioKind: "taskMutationFlow",
                trigger: "cloudTriggered",
                failureReason: "Unexpected status",
                diffSummary: "mutation: status=in_progress -> status=blocked",
                redactedLogCount: 1
            )
        )
    }

    func testRetentionPolicySeparatesSyncAndProHistoryStorage() {
        let syncPolicy = SoloPMHarnessRetentionPolicy.policy(for: .sync)
        XCTAssertEqual(syncPolicy.requiredFeature, .harnessHistory)
        XCTAssertEqual(syncPolicy.historyStorage, .disabled)
        XCTAssertEqual(syncPolicy.maxRuns, 0)
        XCTAssertEqual(syncPolicy.retentionDays, 0)

        let proPolicy = SoloPMHarnessRetentionPolicy.policy(for: .pro)
        XCTAssertEqual(proPolicy.historyStorage, .cloudBacked)
        XCTAssertEqual(proPolicy.maxRuns, 250)
        XCTAssertEqual(proPolicy.retentionDays, 30)

        let founderPolicy = SoloPMHarnessRetentionPolicy.policy(for: .founder)
        XCTAssertEqual(founderPolicy.historyStorage, .extendedCloudBacked)
        XCTAssertGreaterThan(founderPolicy.maxRuns, proPolicy.maxRuns)
        XCTAssertGreaterThan(founderPolicy.retentionDays, proPolicy.retentionDays)
    }

    private func documentAutomationHarnessDocuments() -> [ScopedAutomationDocument] {
        [
            ScopedAutomationDocument(
                id: "release",
                title: "Release checklist",
                scope: .appDocs,
                redactedSummary: "Manual VoiceOver evidence, release notes, Gatekeeper, and notarization checks.",
                inclusionReason: "The app release checklist was selected."
            ),
            ScopedAutomationDocument(
                id: "phase14",
                title: "Phase14 quality plan",
                scope: .projectDocs,
                redactedSummary: "Implementation tasks, regression tests, and PR plan requirements.",
                inclusionReason: "The phase plan was selected."
            ),
            ScopedAutomationDocument(
                id: "artifact-notes",
                title: "Draft artifact notes",
                scope: .taskArtifacts,
                redactedSummary: "Draft README.md and article.md from local notes without leaking sk-test-secret.",
                inclusionReason: "The task artifact notes were selected."
            ),
            ScopedAutomationDocument(
                id: "github-issue",
                title: "GitHub issue mirror",
                scope: .externalSources,
                redactedSummary: "External connector context is present but not approved for this release.",
                inclusionReason: "External source preview is visible."
            )
        ]
    }

    private func completeAccessibilityNodes() -> [AccessibilityNodeSnapshot] {
        [
            node("project-board-sidebar", role: .outline, label: "Project navigation"),
            node("project-board-detail", role: .group, label: "Project board detail"),
            node("project-header-add-task", role: .button, label: "Add Task", help: "Opens inline task composer."),
            node("inline-task-title", role: .textField, label: "Task title"),
            node("inline-task-detail", role: .textArea, label: "Task detail"),
            node("inline-task-create", role: .button, label: "Create Task", help: "Creates the task in the local SoloPM database."),
            node("project-board-task-auto-execution-review", role: .button, label: "Review Task Automation", help: "Builds a review-only LLM plan from configured settings."),
            node("task-card-open-details", role: .button, label: "Open task details", help: "Opens the task inspector."),
            node("task-inspector-title", role: .textField, label: "Task title"),
            node("task-inspector-detail", role: .textArea, label: "Task detail"),
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-status-move-in_progress-42", role: .button, label: "Move to In Progress", help: "Moves the selected task to In Progress."),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Builds a review-only LLM plan."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs after explicit approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms deletion.", confirmsDestructiveAction: true)
        ]
    }

    private func node(
        _ id: String,
        role: AccessibilityNodeRole,
        label: String,
        help: String = "",
        isDestructive: Bool = false,
        confirmsDestructiveAction: Bool = false
    ) -> AccessibilityNodeSnapshot {
        AccessibilityNodeSnapshot(
            id: id,
            role: role,
            label: label,
            help: help,
            isDestructive: isDestructive,
            confirmsDestructiveAction: confirmsDestructiveAction
        )
    }

    private func approvedExecutionReceipt(
        title: String = "Run release-note task",
        detail: String = "Use selected docs to draft the operator note."
    ) -> ApprovedAutomationExecutionReceipt {
        ApprovedAutomationExecutionReceipt(
            taskID: 42,
            projectID: 7,
            redactedTaskTitle: title,
            redactedTaskDetail: detail,
            statusBefore: .planned,
            statusAfter: .inProgress,
            priority: .high,
            dueAt: "2026-06-22",
            reviewReason: "Selected task is ready for review-only automation."
        )
    }
}
