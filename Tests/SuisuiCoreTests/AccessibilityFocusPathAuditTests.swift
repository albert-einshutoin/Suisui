import XCTest
@testable import SuisuiCore

final class AccessibilityFocusPathAuditTests: XCTestCase {
    func testPseudoVoiceOverAuditAcceptsCompleteTaskCreateEditDeleteAndExecutionPath() {
        let nodes = [
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
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task in the local Suisui database."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-status-move-in_progress", role: .button, label: "Move to In Progress", help: "Moves the selected task to In Progress."),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Prepares review-only local automation for the selected task."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs only after explicit user approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes the selected task after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Task", help: "Cancels deletion and returns to the inspector."),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms permanent deletion.", confirmsDestructiveAction: true),
            node("project-inspector-complete", role: .button, label: "Complete Project", help: "Completes the selected project in the local Suisui database."),
            node("project-inspector-delete", role: .button, label: "Delete Project", help: "Deletes the selected project after confirmation.", isDestructive: true),
            node("project-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Project", help: "Cancels deletion and returns to the inspector."),
            node("project-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Project", help: "Confirms permanent deletion.", confirmsDestructiveAction: true)
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.taskLifecycleAndExecution
        )

        XCTAssertTrue(result.findings.isEmpty, result.findings.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(result.coveredRequiredNodeIDs.count, AccessibilityFocusPathRequirement.taskLifecycleAndExecution.requiredNodeIDs.count)
    }

    func testPseudoVoiceOverAuditReportsMissingExecutionReviewAndConfirmation() {
        let nodes = [
            node("project-board-sidebar", role: .outline, label: "Project navigation"),
            node("project-board-detail", role: .group, label: "Project board detail"),
            node("project-task-list", role: .group, label: "Project task list"),
            node("project-header-add-task", role: .button, label: "Add Task", help: "Opens inline task composer."),
            node("inline-task-title", role: .textField, label: "Task title"),
            node("inline-task-create", role: .button, label: "Create Task", help: "Creates the task in the local Suisui database."),
            node("task-card-open-details", role: .button, label: "Open task details", help: "Opens the task inspector."),
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits."),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes the selected task.", isDestructive: true)
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.taskLifecycleAndExecution
        )

        XCTAssertTrue(result.findings.contains { $0.nodeID == "task-auto-execution-review" && $0.kind == .missingRequiredNode })
        XCTAssertTrue(result.findings.contains { $0.nodeID == "project-board-task-auto-execution-review" && $0.kind == .missingRequiredNode })
        XCTAssertTrue(result.findings.contains { $0.nodeID == "approved-execution-receipt" && $0.kind == .missingRequiredNode })
        XCTAssertTrue(result.findings.contains { $0.nodeID == "task-inspector-delete-confirmation-confirm" && $0.kind == .missingRequiredNode })
        XCTAssertTrue(result.findings.contains { $0.nodeID == "task-inspector-delete" && $0.kind == .missingDestructiveConfirmation })
    }

    func testPseudoVoiceOverAuditRequiresDeleteConfirmationCancelPath() {
        let nodes = [
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
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task in the local Suisui database."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-status-move-in_progress", role: .button, label: "Move to In Progress", help: "Moves the selected task to In Progress."),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Prepares review-only local automation for the selected task."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs only after explicit user approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes the selected task after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms permanent deletion.", confirmsDestructiveAction: true)
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.taskLifecycleAndExecution
        )

        XCTAssertTrue(result.findings.contains { $0.nodeID == "task-inspector-delete-confirmation-cancel" && $0.kind == .missingRequiredNode })
    }

    func testPseudoVoiceOverAuditRequiresProjectCompletionAndCascadeDeletePath() {
        let nodes = [
            node("project-board-sidebar", role: .outline, label: "Project navigation"),
            node("project-board-detail", role: .group, label: "Project board detail"),
            node("project-header-add-task", role: .button, label: "Add Task", help: "Opens inline task composer."),
            node("inline-task-title", role: .textField, label: "Task title"),
            node("inline-task-detail", role: .textArea, label: "Task detail"),
            node("inline-task-create", role: .button, label: "Create Task", help: "Creates the task in the local Suisui database."),
            node("project-board-task-auto-execution-review", role: .button, label: "Review Task Automation", help: "Prepares review-only task automation from configured settings."),
            node("task-card-open-details", role: .button, label: "Open task details", help: "Opens the task inspector."),
            node("task-inspector-title", role: .textField, label: "Task title"),
            node("task-inspector-detail", role: .textArea, label: "Task detail"),
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task in the local Suisui database."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-status-move-in_progress", role: .button, label: "Move to In Progress", help: "Moves the selected task to In Progress."),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Prepares review-only local automation for the selected task."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs only after explicit user approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes the selected task after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Task", help: "Cancels deletion and returns to the inspector."),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms permanent deletion.", confirmsDestructiveAction: true)
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.taskLifecycleAndExecution
        )

        XCTAssertTrue(result.findings.contains { $0.nodeID == "project-inspector-complete" && $0.kind == .missingRequiredNode })
        XCTAssertTrue(result.findings.contains { $0.nodeID == "project-inspector-delete" && $0.kind == .missingRequiredNode })
        XCTAssertTrue(result.findings.contains { $0.nodeID == "project-inspector-delete-confirmation-cancel" && $0.kind == .missingRequiredNode })
        XCTAssertTrue(result.findings.contains { $0.nodeID == "project-inspector-delete-confirmation-confirm" && $0.kind == .missingRequiredNode })
    }

    func testPseudoVoiceOverAuditRequiresConcreteStatusMoveButtonNotOnlyStatusGroup() {
        let nodes = [
            node("project-board-sidebar", role: .outline, label: "Project navigation"),
            node("project-board-detail", role: .group, label: "Project board detail"),
            node("project-header-add-task", role: .button, label: "Add Task", help: "Opens inline task composer."),
            node("inline-task-title", role: .textField, label: "Task title"),
            node("inline-task-detail", role: .textArea, label: "Task detail"),
            node("inline-task-create", role: .button, label: "Create Task", help: "Creates the task in the local Suisui database."),
            node("project-board-task-auto-execution-review", role: .button, label: "Review Task Automation", help: "Prepares review-only task automation from configured settings."),
            node("task-card-open-details", role: .button, label: "Open task details", help: "Opens the task inspector."),
            node("task-inspector-title", role: .textField, label: "Task title"),
            node("task-inspector-detail", role: .textArea, label: "Task detail"),
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task in the local Suisui database."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Prepares review-only local automation for the selected task."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs only after explicit user approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes the selected task after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Task", help: "Cancels deletion and returns to the inspector."),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms permanent deletion.", confirmsDestructiveAction: true),
            node("project-inspector-complete", role: .button, label: "Complete Project", help: "Completes the selected project in the local Suisui database."),
            node("project-inspector-delete", role: .button, label: "Delete Project", help: "Deletes the selected project after confirmation.", isDestructive: true),
            node("project-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Project", help: "Cancels deletion and returns to the inspector."),
            node("project-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Project", help: "Confirms permanent deletion.", confirmsDestructiveAction: true)
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.taskLifecycleAndExecution
        )

        XCTAssertTrue(result.findings.contains { $0.nodeID == "task-status-move-in_progress" && $0.kind == .missingRequiredNode })
    }

    func testPseudoVoiceOverAuditAcceptsRuntimeStatusMoveIdentifierWithTaskIDSuffix() {
        let nodes = [
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
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task in the local Suisui database."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-status-move-in_progress-42", role: .button, label: "Move to In Progress", help: "Moves the selected task to In Progress."),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Prepares review-only local automation for the selected task."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs only after explicit user approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes the selected task after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Task", help: "Cancels deletion and returns to the inspector."),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms permanent deletion.", confirmsDestructiveAction: true),
            node("project-inspector-complete", role: .button, label: "Complete Project", help: "Completes the selected project in the local Suisui database."),
            node("project-inspector-delete", role: .button, label: "Delete Project", help: "Deletes the selected project after confirmation.", isDestructive: true),
            node("project-inspector-delete-confirmation-cancel", role: .button, label: "Cancel Delete Project", help: "Cancels deletion and returns to the inspector."),
            node("project-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Project", help: "Confirms permanent deletion.", confirmsDestructiveAction: true)
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.taskLifecycleAndExecution
        )

        XCTAssertTrue(result.findings.isEmpty, result.findings.map(\.message).joined(separator: "\n"))
        XCTAssertTrue(result.coveredRequiredNodeIDs.contains("task-status-move-in_progress"))
    }

    func testPseudoVoiceOverAuditAcceptsCompleteTodayCockpitPath() {
        let nodes = [
            node("sidebar-destination-today", role: .button, label: "Today, 3 open due or overdue tasks", help: "Opens Today cockpit."),
            node("today-workflow", role: .group, label: "Today"),
            node("today-briefing-panel", role: .group, label: "Today briefing"),
            node("today-focus-recommendation", role: .group, label: "Ship release"),
            node("today-primary-action", role: .button, label: "Start Focus", help: "Starts local focus without changing task status."),
            node("today-command-capture-field", role: .textField, label: "Today command title"),
            node("today-secondary-actions-menu", role: .button, label: "More Today actions", help: "Open secondary actions."),
            node("today-flow-strip", role: .group, label: "Today flow"),
            node("today-assistant-rail", role: .group, label: "Today assistant rail"),
            node("today-rail-next-action", role: .group, label: "Start recommended task"),
            node("today-rail-task-detail", role: .group, label: "Task detail"),
            node("today-rail-actions-menu", role: .button, label: "Task actions", help: "Opens contextual task actions.")
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.todayCockpit
        )

        XCTAssertTrue(result.findings.isEmpty, result.findings.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(result.coveredRequiredNodeIDs, AccessibilityFocusPathRequirement.todayCockpit.requiredNodeIDs)
    }

    func testPseudoVoiceOverAuditRequiresTodayRailActionsNotOnlyScreenshotMarkers() {
        let nodes = [
            node("sidebar-destination-today", role: .button, label: "Today", help: "Opens Today cockpit."),
            node("today-workflow", role: .group, label: "Today"),
            node("today-briefing-panel", role: .group, label: "Today briefing"),
            node("today-focus-recommendation", role: .group, label: "Ship release"),
            node("today-primary-action", role: .button, label: "Start Focus", help: "Starts local focus."),
            node("today-command-capture-field", role: .textField, label: "Today command title"),
            node("today-secondary-actions-menu", role: .button, label: "More Today actions", help: "Open secondary actions."),
            node("today-flow-strip", role: .group, label: "Today flow"),
            node("today-assistant-rail", role: .group, label: "Today assistant rail"),
            node("today-rail-next-action", role: .group, label: "Start recommended task"),
            node("today-rail-task-detail", role: .group, label: "Task detail")
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.todayCockpit
        )

        XCTAssertTrue(result.findings.contains { $0.nodeID == "today-rail-actions-menu" && $0.kind == .missingRequiredNode })
    }

    func testPseudoVoiceOverAuditAcceptsEmptyTodayCockpitWithoutRailActions() {
        let nodes = [
            node("sidebar-destination-today", role: .button, label: "Today, 0 open due or overdue tasks", help: "Opens Today cockpit."),
            node("today-workflow", role: .group, label: "Today"),
            node("today-briefing-panel", role: .group, label: "Today briefing"),
            node("today-focus-recommendation", role: .group, label: "No focus task"),
            node("today-primary-action", role: .button, label: "Add a task for today", help: "Prepare a new local Inbox task."),
            node("today-command-capture-field", role: .textField, label: "Today command title"),
            node("today-secondary-actions-menu", role: .button, label: "More Today actions", help: "Open secondary actions."),
            node("today-flow-strip", role: .group, label: "Today flow"),
            node("today-assistant-rail", role: .group, label: "Today assistant rail"),
            node("today-rail-next-action", role: .group, label: "Capture the next task"),
            node("today-rail-task-detail", role: .group, label: "No due task selected")
        ]

        let result = AccessibilityFocusPathAudit().audit(
            nodes: nodes,
            requirements: AccessibilityFocusPathRequirement.todayEmptyCockpit
        )

        XCTAssertTrue(result.findings.isEmpty, result.findings.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(result.coveredRequiredNodeIDs, AccessibilityFocusPathRequirement.todayEmptyCockpit.requiredNodeIDs)
    }

    func testApprovalFlowRequiresInboxContextCompactNavigationAndQueueActions() {
        let audit = AccessibilityFocusPathAudit()
        let reviewNodes = approvalFlowNodes(
            primaryID: "assistant-queue-approve-visual-waiting",
            primaryLabel: "Approve",
            includesEditPath: true
        )
        let executionNodes = approvalFlowNodes(
            primaryID: "assistant-queue-run-visual-approved",
            primaryLabel: "Run",
            includesEditPath: true
        )
        let recoveryNodes = approvalFlowNodes(
            primaryID: "assistant-queue-retry-visual-failed",
            primaryLabel: "Reopen",
            includesEditPath: false
        )
        let stageFixtures: [
            (
                name: String,
                primaryPrefix: String,
                nodes: [AccessibilityNodeSnapshot],
                requirements: AccessibilityFocusPathRequirement
            )
        ] = [
            ("Review", "assistant-queue-approve", reviewNodes, .approvalFlowReview),
            ("Execution", "assistant-queue-run", executionNodes, .approvalFlowExecution),
            ("Recovery", "assistant-queue-retry", recoveryNodes, .approvalFlowRecovery)
        ]

        for fixture in stageFixtures {
            let result = audit.audit(nodes: fixture.nodes, requirements: fixture.requirements)
            XCTAssertTrue(
                result.findings.isEmpty,
                "\(fixture.name): \(result.findings.map(\.message).joined(separator: "\n"))"
            )
        }

        for fixture in stageFixtures {
            let missingPrimary = fixture.nodes.filter {
                !$0.id.hasPrefix("\(fixture.primaryPrefix)-")
            }
            let result = audit.audit(nodes: missingPrimary, requirements: fixture.requirements)

            XCTAssertTrue(
                result.findings.contains {
                    $0.nodeID == fixture.primaryPrefix && $0.kind == .missingRequiredNode
                },
                "\(fixture.name) must report its missing stage-specific primary action"
            )
        }

        for fixture in stageFixtures.prefix(2) {
            for missingPrefix in ["assistant-queue-more", "assistant-queue-edit"] {
                let incompleteNodes = fixture.nodes.filter {
                    $0.id != "\(missingPrefix)-visual-waiting"
                        && $0.id != "\(missingPrefix)-visual-approved"
                }
                let result = audit.audit(nodes: incompleteNodes, requirements: fixture.requirements)

                XCTAssertTrue(
                    result.findings.contains {
                        $0.nodeID == missingPrefix && $0.kind == .missingRequiredNode
                    },
                    "\(fixture.name) must report a missing \(missingPrefix) path"
                )
            }
        }

        for fixture in stageFixtures {
            var outOfOrderNodes = fixture.nodes
            guard
                let workflowIndex = outOfOrderNodes.firstIndex(where: {
                    $0.id == "assistant-queue-workflow"
                }),
                let primaryIndex = outOfOrderNodes.firstIndex(where: {
                    $0.id.hasPrefix("\(fixture.primaryPrefix)-")
                })
            else {
                XCTFail("\(fixture.name) fixture must contain its workflow and primary action")
                continue
            }
            outOfOrderNodes.swapAt(workflowIndex, primaryIndex)

            let result = audit.audit(nodes: outOfOrderNodes, requirements: fixture.requirements)
            XCTAssertTrue(
                result.findings.contains {
                    $0.nodeID == fixture.primaryPrefix && $0.kind == .outOfOrderRequiredNode
                },
                "\(fixture.name) must report its primary action when focus order skips queue context"
            )
        }
    }

    func testPseudoVoiceOverAuditRejectsGenericButtonsWithoutHelp() {
        let result = AccessibilityFocusPathAudit().audit(
            nodes: [
                node("task-auto-execution-review", role: .button, label: "Button", help: "")
            ],
            requirements: AccessibilityFocusPathRequirement(requiredNodeIDs: ["task-auto-execution-review"])
        )

        XCTAssertEqual(result.findings.map(\.kind), [.genericButtonWithoutHelp])
    }

    func testPseudoVoiceOverAuditRejectsDisabledRequiredLifecycleControls() {
        let result = AccessibilityFocusPathAudit().audit(
            nodes: [
                node(
                    "task-auto-execution-run-plan",
                    role: .button,
                    label: "Run approved plan",
                    help: "Runs only after explicit user approval.",
                    isEnabled: false
                )
            ],
            requirements: AccessibilityFocusPathRequirement(requiredNodeIDs: ["task-auto-execution-run-plan"])
        )

        XCTAssertEqual(result.findings.map(\.kind), [.disabledRequiredNode])
        XCTAssertEqual(result.findings.first?.nodeID, "task-auto-execution-run-plan")
    }

    func testPseudoVoiceOverAuditRejectsOutOfOrderRequiredLifecycleNodes() {
        let result = AccessibilityFocusPathAudit().audit(
            nodes: [
                node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms permanent deletion.", confirmsDestructiveAction: true),
                node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task.")
            ],
            requirements: AccessibilityFocusPathRequirement(requiredNodeIDs: [
                "task-inspector-save",
                "task-inspector-delete-confirmation-confirm"
            ])
        )

        XCTAssertEqual(result.findings.map(\.kind), [.outOfOrderRequiredNode])
        XCTAssertEqual(result.findings.first?.nodeID, "task-inspector-delete-confirmation-confirm")
    }

    func testPseudoVoiceOverAuditRejectsDuplicateNodeIDsInsteadOfChoosingOneSilently() {
        let result = AccessibilityFocusPathAudit().audit(
            nodes: [
                node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task."),
                node("task-inspector-save", role: .button, label: "Save Duplicate", help: "Duplicate control.")
            ],
            requirements: AccessibilityFocusPathRequirement(requiredNodeIDs: ["task-inspector-save"])
        )

        XCTAssertEqual(result.findings.map(\.kind), [.duplicateNodeID])
        XCTAssertEqual(result.findings.first?.nodeID, "task-inspector-save")
        XCTAssertEqual(result.coveredRequiredNodeIDs, ["task-inspector-save"])
    }

    func testPseudoVoiceOverAuditRejectsBlankNodeIDsBecauseAutomationCannotTargetThem() {
        let result = AccessibilityFocusPathAudit().audit(
            nodes: [
                node("   ", role: .button, label: "Save Changes", help: "Saves edits to the selected task."),
                node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task.")
            ],
            requirements: AccessibilityFocusPathRequirement(requiredNodeIDs: ["task-inspector-save"])
        )

        XCTAssertEqual(result.findings.map(\.kind), [.blankNodeID])
        XCTAssertEqual(result.findings.first?.nodeID, "   ")
        XCTAssertEqual(result.coveredRequiredNodeIDs, ["task-inspector-save"])
    }

    func testPseudoVoiceOverAuditRejectsUnlabeledRequiredGroupNodes() {
        let result = AccessibilityFocusPathAudit().audit(
            nodes: [
                node("approved-execution-receipt", role: .group, label: "   ")
            ],
            requirements: AccessibilityFocusPathRequirement(requiredNodeIDs: ["approved-execution-receipt"])
        )

        XCTAssertEqual(result.findings.map(\.kind), [.unlabeledRequiredNode])
        XCTAssertEqual(result.findings.first?.nodeID, "approved-execution-receipt")
    }

    private func approvalFlowNodes(
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
            let runtimeSuffix = primaryID.hasPrefix("assistant-queue-approve-")
                ? "visual-waiting"
                : "visual-approved"
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
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        confirmsDestructiveAction: Bool = false
    ) -> AccessibilityNodeSnapshot {
        AccessibilityNodeSnapshot(
            id: id,
            role: role,
            label: label,
            help: help,
            isEnabled: isEnabled,
            isDestructive: isDestructive,
            confirmsDestructiveAction: confirmsDestructiveAction
        )
    }
}
