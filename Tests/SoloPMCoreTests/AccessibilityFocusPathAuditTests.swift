import XCTest
@testable import SoloPMCore

final class AccessibilityFocusPathAuditTests: XCTestCase {
    func testPseudoVoiceOverAuditAcceptsCompleteTaskCreateEditDeleteAndExecutionPath() {
        let nodes = [
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
            node("task-inspector-save", role: .button, label: "Save Changes", help: "Saves edits to the selected task in the local SoloPM database."),
            node("task-status-move-controls", role: .group, label: "Task status controls"),
            node("task-status-move-in_progress", role: .button, label: "Move to In Progress", help: "Moves the selected task to In Progress."),
            node("task-auto-execution-review", role: .button, label: "Review automation plan", help: "Builds a review-only LLM plan for the selected task."),
            node("task-auto-execution-run-plan", role: .button, label: "Run approved plan", help: "Runs only after explicit user approval."),
            node("approved-execution-receipt", role: .group, label: "Approved execution receipt"),
            node("task-inspector-delete", role: .button, label: "Delete Task", help: "Deletes the selected task after confirmation.", isDestructive: true),
            node("task-inspector-delete-confirmation-confirm", role: .button, label: "Confirm Delete Task", help: "Confirms permanent deletion.", confirmsDestructiveAction: true)
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
            node("project-header-add-task", role: .button, label: "Add Task", help: "Opens inline task composer."),
            node("inline-task-title", role: .textField, label: "Task title"),
            node("inline-task-create", role: .button, label: "Create Task", help: "Creates the task in the local SoloPM database."),
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
