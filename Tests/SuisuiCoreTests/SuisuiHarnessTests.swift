import XCTest
@testable import SuisuiCore

final class SuisuiHarnessTests: XCTestCase {
    func testScenarioCatalogCoversPhase13AutomationSurfaces() throws {
        let catalog = SuisuiHarnessScenario.templateCatalog()
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
        let decoded = try JSONDecoder().decode(SuisuiHarnessScenario.self, from: encoded)
        XCTAssertEqual(decoded, taskMutation)

        let accessibility = try XCTUnwrap(catalog.first { $0.kind == .accessibilityFocusPath })
        XCTAssertEqual(accessibility.id, "mcp-pseudo-voiceover-focus-path")
        XCTAssertTrue(accessibility.requiredCapabilities.contains(.mcpToolCall))
        XCTAssertTrue(accessibility.requiredCapabilities.contains(.accessibilityAudit))
        XCTAssertTrue(accessibility.assertions.contains(.accessibilityFocusPathCovered))
        XCTAssertEqual(accessibility.requiredTodayCockpitOperations, SuisuiHarnessScenario.completeTodayCockpitOperations)
    }

    func testTaskLifecycleHarnessRequiresCreateEditExecuteAndDeleteCoverage() throws {
        let catalog = SuisuiHarnessScenario.templateCatalog()
        let requiredLifecycle: [SuisuiHarnessTaskLifecycleOperation] = [
            .taskList,
            .create,
            .editContent,
            .statusMove,
            .automationReview,
            .executeContent,
            .approvedExecution,
            .deleteConfirmation,
            .projectCompletion,
            .projectDeleteCascade
        ]

        let taskMutation = try XCTUnwrap(catalog.first { $0.kind == .taskMutationFlow })
        XCTAssertEqual(taskMutation.requiredTaskLifecycleOperations, requiredLifecycle)
        XCTAssertTrue(taskMutation.missingTaskLifecycleOperations().isEmpty)

        let accessibility = try XCTUnwrap(catalog.first { $0.kind == .accessibilityFocusPath })
        XCTAssertEqual(accessibility.requiredTaskLifecycleOperations, requiredLifecycle)
        XCTAssertEqual(accessibility.requiredTodayCockpitOperations, SuisuiHarnessScenario.completeTodayCockpitOperations)
        XCTAssertTrue(accessibility.missingTaskLifecycleOperations().isEmpty)
        XCTAssertTrue(accessibility.missingTodayCockpitOperations().isEmpty)
    }

    func testTaskLifecycleOperationsMapToCompletePseudoVoiceOverFocusNodes() {
        let mappedNodeIDs = SuisuiHarnessScenario.requiredFocusNodeIDs(
            for: SuisuiHarnessScenario.completeTaskLifecycleOperations
        )

        XCTAssertEqual(
            mappedNodeIDs,
            AccessibilityFocusPathRequirement.taskLifecycleAndExecution.requiredNodeIDs
        )
        for operation in SuisuiHarnessTaskLifecycleOperation.allCases {
            XCTAssertFalse(
                operation.requiredFocusNodeIDs.isEmpty,
                "\(operation.rawValue) must map to at least one AX focus node"
            )
        }
        XCTAssertEqual(
            SuisuiHarnessTaskLifecycleOperation.taskList.requiredFocusNodeIDs,
            ["project-task-list"]
        )
        XCTAssertEqual(
            SuisuiHarnessTaskLifecycleOperation.executeContent.requiredFocusNodeIDs,
            ["task-auto-execution-run-plan", "approved-execution-receipt"]
        )
        XCTAssertTrue(
            SuisuiHarnessTaskLifecycleOperation.approvedExecution.requiredFocusNodeIDs.contains("approved-execution-receipt")
        )
        XCTAssertEqual(
            SuisuiHarnessTaskLifecycleOperation.projectCompletion.requiredFocusNodeIDs,
            ["project-inspector-complete"]
        )
        XCTAssertEqual(
            SuisuiHarnessTaskLifecycleOperation.projectDeleteCascade.requiredFocusNodeIDs,
            [
                "project-inspector-delete",
                "project-inspector-delete-confirmation-cancel",
                "project-inspector-delete-confirmation-confirm"
            ]
        )
    }

    func testTodayCockpitOperationsMapToCompletePseudoVoiceOverFocusNodes() {
        let mappedNodeIDs = SuisuiHarnessScenario.requiredTodayCockpitFocusNodeIDs(
            for: SuisuiHarnessScenario.completeTodayCockpitOperations
        )

        XCTAssertEqual(
            mappedNodeIDs,
            AccessibilityFocusPathRequirement.todayCockpit.requiredNodeIDs
        )
        for operation in SuisuiHarnessTodayCockpitOperation.allCases {
            XCTAssertFalse(
                operation.requiredFocusNodeIDs.isEmpty,
                "\(operation.rawValue) must map to at least one Today AX focus node"
            )
        }
        XCTAssertEqual(
            SuisuiHarnessTodayCockpitOperation.openToday.requiredFocusNodeIDs,
            ["sidebar-destination-today", "today-workflow"]
        )
        XCTAssertEqual(
            SuisuiHarnessTodayCockpitOperation.railActions.requiredFocusNodeIDs,
            ["today-rail-actions-menu"]
        )
    }

    func testDocumentAutomationHarnessRequiresReviewableDeliverableCoverage() throws {
        let catalog = SuisuiHarnessScenario.templateCatalog()
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

        let run = SuisuiHarnessDocumentAutomationRunner().run(
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
            "document-deliverable-pullRequestPlan",
            "document-deliverable-unique-suggested-paths"
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

        let run = SuisuiHarnessDocumentAutomationRunner().run(
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

        let run = SuisuiHarnessDocumentAutomationRunner().run(
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

        let run = SuisuiHarnessDocumentAutomationRunner().run(
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

    func testDocumentAutomationHarnessRunFailsWhenDeliverablesShareSuggestedOutputPath() throws {
        var drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes, a PR plan, and the right draft artifacts from these docs.",
            documents: documentAutomationHarnessDocuments()
        )
        let releaseNotesPath = try XCTUnwrap(drafts.first { $0.kind == .releaseNotes }?.suggestedPath)
        let pullRequestPlanIndex = try XCTUnwrap(drafts.firstIndex { $0.kind == .pullRequestPlan })
        drafts[pullRequestPlanIndex].suggestedPath = "  \(releaseNotesPath)//  "

        let run = SuisuiHarnessDocumentAutomationRunner().run(
            id: "run-document-duplicate-path",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            drafts: drafts
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "document-deliverable-unique-suggested-paths")
        XCTAssertEqual(run.diff?.expected, "one reviewable document deliverable per suggested output path")
        XCTAssertTrue(run.diff?.actual.contains("duplicateSuggestedPath") ?? false)
        XCTAssertTrue(run.failureReason?.contains("releaseNotes") ?? false)
        XCTAssertTrue(run.failureReason?.contains("pullRequestPlan") ?? false)
    }

    func testTaskLifecycleCoverageReportsMissingExecuteAndDeleteRequirements() {
        let scenario = SuisuiHarnessScenario(
            id: "partial-task-lifecycle",
            name: "Partial task lifecycle",
            kind: .taskMutationFlow,
            requiredCapabilities: [.taskMutation],
            expectedMutations: [],
            assertions: [.approvalBoundary],
            requiredTaskLifecycleOperations: [.create, .editContent, .statusMove, .automationReview]
        )

        XCTAssertEqual(
            scenario.missingTaskLifecycleOperations(),
            [.taskList, .executeContent, .approvedExecution, .deleteConfirmation, .projectCompletion, .projectDeleteCascade]
        )
    }

    func testTodayCockpitCoverageReportsMissingRailRequirements() {
        let scenario = SuisuiHarnessScenario(
            id: "partial-today-cockpit",
            name: "Partial Today cockpit",
            kind: .accessibilityFocusPath,
            requiredCapabilities: [.accessibilityAudit],
            expectedMutations: [],
            assertions: [.accessibilityFocusPathCovered],
            requiredTodayCockpitOperations: [.openToday, .captureCommand, .commonActions]
        )

        XCTAssertEqual(
            scenario.missingTodayCockpitOperations(),
            [.focusSuggestions, .localFocusAndPlanning, .railContext, .railActions]
        )
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

        let scenario = try JSONDecoder().decode(SuisuiHarnessScenario.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(scenario.requiredTaskLifecycleOperations, [])
        XCTAssertEqual(scenario.requiredTodayCockpitOperations, [])
        XCTAssertEqual(scenario.requiredDocumentDeliverableKinds, [])
        XCTAssertEqual(scenario.missingTaskLifecycleOperations(), SuisuiHarnessScenario.completeTaskLifecycleOperations)
        XCTAssertEqual(scenario.missingTodayCockpitOperations(), SuisuiHarnessScenario.completeTodayCockpitOperations)
        XCTAssertEqual(scenario.missingDocumentDeliverableKinds(), SuisuiHarnessScenario.completeDocumentDeliverableKinds)
    }

    func testAccessibilityHarnessRunPassesCompletePseudoVoiceOverFocusPath() {
        let run = SuisuiHarnessAccessibilityAuditRunner().run(
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
        let run = SuisuiHarnessAccessibilityAuditRunner().run(
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
        let run = SuisuiHarnessAccessibilityAuditRunner().run(
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
        let run = SuisuiHarnessAccessibilityAuditRunner().run(
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

        let run = SuisuiHarnessAccessibilityAuditRunner().run(
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

    func testAccessibilityHarnessRunFailsWhenSnapshotContainsBlankNodeID() {
        let nodes = completeAccessibilityNodes() + [
            node("   ", role: .button, label: "Untargetable extra action", help: "This cannot be targeted by MCP.")
        ]

        let run = SuisuiHarnessAccessibilityAuditRunner().run(
            id: "run-ax-blank-node-id",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: nodes,
            approvedExecutionReceipt: approvedExecutionReceipt()
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "focus-path-snapshot-blankNodeID")
        XCTAssertTrue(run.diff?.actual.contains("blankNodeID") ?? false)
    }

    func testAccessibilityHarnessRunFailsDynamicRequiredNodeDuplicateOnMappedStep() {
        let nodes = completeAccessibilityNodes() + [
            node("task-status-move-in_progress-42", role: .button, label: "Duplicate move", help: "Duplicate dynamic AX target.")
        ]

        let run = SuisuiHarnessAccessibilityAuditRunner().run(
            id: "run-ax-duplicate-dynamic-node-id",
            trigger: .cloudTriggered,
            startedAt: "2026-06-23T00:00:00Z",
            finishedAt: "2026-06-23T00:00:01Z",
            nodes: nodes,
            approvedExecutionReceipt: approvedExecutionReceipt()
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "focus-path-task-status-move-in_progress")
        XCTAssertTrue(run.diff?.actual.contains("duplicateNodeID") ?? false)
    }

    func testAccessibilityHarnessRunFailsWithConcreteMissingFocusPathDiff() {
        let incompleteNodes = completeAccessibilityNodes()
            .filter { $0.id != "task-auto-execution-run-plan" }

        let run = SuisuiHarnessAccessibilityAuditRunner().run(
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

    func testAccessibilityHarnessAuditsApprovalFlowStageFixtures() {
        let runner = SuisuiHarnessAccessibilityAuditRunner()
        let reviewNodes = approvalFlowAccessibilityNodes(
            primaryID: "assistant-queue-approve-harness-waiting",
            primaryLabel: "Approve",
            includesEditPath: true
        )
        let executionNodes = approvalFlowAccessibilityNodes(
            primaryID: "assistant-queue-run-harness-approved",
            primaryLabel: "Run",
            includesEditPath: true
        )

        for fixture in [
            (name: "Review", nodes: reviewNodes, requirements: AccessibilityFocusPathRequirement.approvalFlowReview),
            (name: "Execution", nodes: executionNodes, requirements: AccessibilityFocusPathRequirement.approvalFlowExecution)
        ] {
            let passingRun = runner.run(
                id: "run-ax-approval-\(fixture.name.lowercased())",
                trigger: .local,
                startedAt: "2026-07-28T00:00:00Z",
                finishedAt: "2026-07-28T00:00:01Z",
                nodes: fixture.nodes,
                requirements: fixture.requirements
            )
            XCTAssertEqual(passingRun.status, .passed, fixture.name)

            let missingMoreRun = runner.run(
                id: "run-ax-approval-\(fixture.name.lowercased())-missing-more",
                trigger: .local,
                startedAt: "2026-07-28T00:00:00Z",
                finishedAt: "2026-07-28T00:00:01Z",
                nodes: fixture.nodes.filter { !$0.id.hasPrefix("assistant-queue-more-") },
                requirements: fixture.requirements
            )
            XCTAssertEqual(missingMoreRun.status, .failed, fixture.name)
            XCTAssertEqual(missingMoreRun.diff?.stepID, "focus-path-assistant-queue-more")
            XCTAssertTrue(missingMoreRun.diff?.actual.contains("missingRequiredNode") ?? false)
        }

        let recoveryRun = runner.run(
            id: "run-ax-approval-recovery",
            trigger: .local,
            startedAt: "2026-07-28T00:00:00Z",
            finishedAt: "2026-07-28T00:00:01Z",
            nodes: approvalFlowAccessibilityNodes(
                primaryID: "assistant-queue-retry-harness-failed",
                primaryLabel: "Reopen",
                includesEditPath: false
            ),
            requirements: .approvalFlowRecovery
        )
        XCTAssertEqual(recoveryRun.status, .passed)
        XCTAssertFalse(
            AccessibilityFocusPathRequirement.approvalFlowRecovery.requiredNodeIDs.contains("assistant-queue-more")
        )
    }

    func testAccessibilityHarnessRejectsApprovalEvidenceCombinedFromDifferentRows() {
        let mixedNodes = approvalFlowAccessibilityNodes(
            primaryID: "assistant-queue-approve-row-a",
            primaryLabel: "Approve",
            includesEditPath: true
        ).map { node -> AccessibilityNodeSnapshot in
            guard node.id.hasPrefix("assistant-queue-"),
                  !node.id.hasPrefix("assistant-queue-approve-"),
                  node.id != "assistant-queue-workflow" else {
                return node
            }
            var mixedNode = node
            mixedNode.id = node.id.replacingOccurrences(of: "-row-a", with: "-row-b")
            return mixedNode
        }

        let run = SuisuiHarnessAccessibilityAuditRunner().run(
            id: "run-ax-approval-mixed-rows",
            trigger: .local,
            startedAt: "2026-07-28T00:00:00Z",
            finishedAt: "2026-07-28T00:00:01Z",
            nodes: mixedNodes,
            requirements: .approvalFlowReview
        )

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.diff?.stepID, "focus-path-assistant-queue-more")
        XCTAssertTrue(run.diff?.actual.contains("missingRequiredNode") ?? false)
    }

    func testAccessibilityHarnessReportsNestedPrefixFindingToMostSpecificStep() throws {
        let requirements = AccessibilityFocusPathRequirement(
            requiredNodeIDs: [
                "assistant-queue-edit",
                "assistant-queue-edit-reason"
            ],
            dynamicRequiredNodeIDPrefixes: [
                "assistant-queue-edit",
                "assistant-queue-edit-reason"
            ]
        )
        let duplicateNestedNodes = [
            node(
                "assistant-queue-edit-row-a",
                role: .button,
                label: "Edit",
                help: "Edit review details."
            ),
            node(
                "assistant-queue-edit-reason-row-a",
                role: .textField,
                label: "Review reason"
            ),
            node(
                "assistant-queue-edit-reason-row-a",
                role: .textField,
                label: "Duplicate review reason"
            )
        ]

        let run = SuisuiHarnessAccessibilityAuditRunner().run(
            id: "run-ax-nested-prefix-reporting",
            trigger: .local,
            startedAt: "2026-07-28T00:00:00Z",
            finishedAt: "2026-07-28T00:00:01Z",
            nodes: duplicateNestedNodes,
            requirements: requirements
        )

        let editStep = try XCTUnwrap(run.steps.first { $0.id == "focus-path-assistant-queue-edit" })
        let reasonStep = try XCTUnwrap(
            run.steps.first { $0.id == "focus-path-assistant-queue-edit-reason" }
        )
        XCTAssertFalse(editStep.actual.contains("duplicateNodeID"))
        XCTAssertTrue(reasonStep.actual.contains("duplicateNodeID"))
    }

    func testAccessibilityHarnessMapsRoleAndHelpFindingsToRequiredSteps() throws {
        let nodes = approvalFlowAccessibilityNodes(
            primaryID: "assistant-queue-approve-harness-contract",
            primaryLabel: "Approve",
            includesEditPath: true
        ).map { node -> AccessibilityNodeSnapshot in
            var changedNode = node
            if node.id == "assistant-queue-approve-harness-contract" {
                changedNode.role = .group
            } else if node.id == "assistant-queue-more-harness-contract" {
                changedNode.help = ""
            }
            return changedNode
        }

        let run = SuisuiHarnessAccessibilityAuditRunner().run(
            id: "run-ax-approval-role-help",
            trigger: .local,
            startedAt: "2026-07-28T00:00:00Z",
            finishedAt: "2026-07-28T00:00:01Z",
            nodes: nodes,
            requirements: .approvalFlowReview
        )

        let approveStep = try XCTUnwrap(
            run.steps.first { $0.id == "focus-path-assistant-queue-approve" }
        )
        let moreStep = try XCTUnwrap(
            run.steps.first { $0.id == "focus-path-assistant-queue-more" }
        )
        XCTAssertTrue(approveStep.actual.contains("wrongRequiredRole"))
        XCTAssertTrue(moreStep.actual.contains("missingRequiredHelp"))
    }

    func testLocalAndCloudTriggeredRunsShareResultEnvelopeShape() {
        let scenario = SuisuiHarnessScenario.templateCatalog()[0]
        let step = SuisuiHarnessStepResult(
            id: "provider-plan",
            status: .passed,
            expected: "task.create action",
            actual: "task.create action",
            failureReason: nil,
            durationMilliseconds: 42
        )

        let local = SuisuiHarnessRun.completed(
            id: "run-local",
            scenario: scenario,
            trigger: .local,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [step],
            logs: [SuisuiHarnessLogEntry(level: .info, message: "provider smoke passed")]
        )
        let cloud = SuisuiHarnessRun.completed(
            id: "run-cloud",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [step],
            logs: [SuisuiHarnessLogEntry(level: .info, message: "provider smoke passed")]
        )

        XCTAssertEqual(local.resultEnvelope.shape, cloud.resultEnvelope.shape)
        XCTAssertEqual(local.resultEnvelope.schemaVersion, 1)
        XCTAssertEqual(cloud.resultEnvelope.schemaVersion, 1)
        XCTAssertEqual(local.status, .passed)
        XCTAssertEqual(cloud.status, .passed)
    }

    func testHistoryStorePersistsDiffFailureReasonAndRedactedLogs() throws {
        let rawCredential = "sk-" + "proj-redacted123456"
        let scenario = SuisuiHarnessScenario(
            id: "mcp-compatibility-smoke",
            name: "MCP compatibility smoke",
            kind: .mcpCompatibility,
            requiredCapabilities: [.mcpToolCall],
            expectedMutations: [],
            assertions: [.redactedLogs, .resultDiffRecorded]
        )
        let failedStep = SuisuiHarnessStepResult(
            id: "call-task-create",
            status: .failed,
            expected: "tool call succeeds",
            actual: "401 credential \(rawCredential)",
            failureReason: "MCP server rejected the request",
            durationMilliseconds: 130
        )
        let run = SuisuiHarnessRun.completed(
            id: "run-failed",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [failedStep],
            logs: [
                SuisuiHarnessLogEntry(level: .error, message: "credential \(rawCredential) failed")
            ]
        )

        var store = RedactingSuisuiHarnessRunStore()
        try store.save(run, plan: .pro)
        let saved = try XCTUnwrap(store.runs.first)

        XCTAssertEqual(saved.status, .failed)
        XCTAssertEqual(saved.diff?.expected, "tool call succeeds")
        XCTAssertEqual(saved.diff?.actual, "401 credential [REDACTED_SECRET]")
        XCTAssertEqual(saved.failureReason, "MCP server rejected the request")
        XCTAssertEqual(saved.redactedLogs[0].message, "credential [REDACTED_SECRET] failed")
    }

    func testHarnessRunMapsToSyncPayloadWithoutRawLogs() {
        let scenario = SuisuiHarnessScenario.templateCatalog()[1]
        let run = SuisuiHarnessRun.completed(
            id: "run-sync",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [
                SuisuiHarnessStepResult(
                    id: "mutation",
                    status: .failed,
                    expected: "status=in_progress",
                    actual: "status=blocked",
                    failureReason: "Unexpected status",
                    durationMilliseconds: 55
                )
            ],
            logs: [SuisuiHarnessLogEntry(level: .error, message: "raw provider details")]
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
        let syncPolicy = SuisuiHarnessRetentionPolicy.policy(for: .sync)
        XCTAssertEqual(syncPolicy.requiredFeature, .harnessHistory)
        XCTAssertEqual(syncPolicy.historyStorage, .disabled)
        XCTAssertEqual(syncPolicy.maxRuns, 0)
        XCTAssertEqual(syncPolicy.retentionDays, 0)

        let proPolicy = SuisuiHarnessRetentionPolicy.policy(for: .pro)
        XCTAssertEqual(proPolicy.historyStorage, .cloudBacked)
        XCTAssertEqual(proPolicy.maxRuns, 250)
        XCTAssertEqual(proPolicy.retentionDays, 30)

        let founderPolicy = SuisuiHarnessRetentionPolicy.policy(for: .founder)
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
            node("project-task-list", role: .group, label: "Project task list"),
            node("project-header-add-task", role: .button, label: "Add Task", help: "Opens inline task composer."),
            node("inline-task-title", role: .textField, label: "Task title"),
            node("inline-task-detail", role: .textArea, label: "Task detail"),
            node("inline-task-create", role: .button, label: "Create Task", help: "Creates the task in the local Suisui database."),
            node("project-board-task-auto-execution-review", role: .button, label: "Review Task Automation", help: "Prepares review-only task automation from configured settings."),
            node("task-card-open-details", role: .button, label: "Open task details", help: "Opens the task inspector."),
            node("task-inspector-title", role: .textField, label: "Task title"),
            node("task-inspector-detail", role: .textArea, label: "Task detail"),
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-status-move-in_progress-42", role: .button, label: "Move to In Progress", help: "Moves the selected task to In Progress."),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Prepares review-only local automation."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs after explicit approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Task", help: "Cancels deletion and returns to the inspector."),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms deletion.", confirmsDestructiveAction: true),
            node("project-inspector-complete", role: .button, label: "Complete Project", help: "Completes the selected project."),
            node("project-inspector-delete", role: .button, label: "Delete Project", help: "Deletes after confirmation.", isDestructive: true),
            node("project-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Project", help: "Cancels deletion and returns to the inspector."),
            node("project-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Project", help: "Confirms deletion.", confirmsDestructiveAction: true)
        ]
    }

    private func approvalFlowAccessibilityNodes(
        primaryID: String,
        primaryLabel: String,
        includesEditPath: Bool
    ) -> [AccessibilityNodeSnapshot] {
        var nodes = [
            node("inbox-selected-context", role: .group, label: "Selected Item"),
            node("inbox-action-grid", role: .group, label: "Inbox classification actions"),
            node(
                "review-hub-compact-navigation",
                role: .button,
                label: "Review view chooser",
                help: "Choose Review destination."
            ),
            node(
                "projects-hub-compact-navigation",
                role: .button,
                label: "Project view chooser",
                help: "Choose Project destination."
            ),
            node("assistant-queue-workflow", role: .group, label: "Assistant Queue"),
            node(
                primaryID,
                role: .button,
                label: primaryLabel,
                help: "Moves this queue item to its next approval stage."
            )
        ]

        if includesEditPath {
            let primaryPrefix = primaryID.hasPrefix("assistant-queue-approve-")
                ? "assistant-queue-approve-"
                : "assistant-queue-run-"
            let runtimeSuffix = String(primaryID.dropFirst(primaryPrefix.count))
            nodes.append(contentsOf: [
                node(
                    "assistant-queue-more-\(runtimeSuffix)",
                    role: .button,
                    label: "More",
                    help: "More Assistant Queue actions"
                ),
                node(
                    "assistant-queue-edit-\(runtimeSuffix)",
                    role: .button,
                    label: "Edit",
                    help: "Edit review details before approving this queue item"
                ),
                node(
                    "assistant-queue-edit-reason-\(runtimeSuffix)",
                    role: .textField,
                    label: "Review reason"
                ),
                node(
                    "assistant-queue-edit-save-\(runtimeSuffix)",
                    role: .button,
                    label: "Save",
                    help: "Saves edited review details."
                ),
                node(
                    "assistant-queue-edit-cancel-\(runtimeSuffix)",
                    role: .button,
                    label: "Cancel",
                    help: "Discards local edits."
                )
            ])
        }

        return nodes
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
