import XCTest
@testable import SoloPMCore

final class IOSCompanionTests: XCTestCase {
    func testMVPConfigurationCoversRequiredMobileSurfacesAndInputs() {
        let configuration = IOSCompanionMVPConfiguration.default

        XCTAssertEqual(
            Set(configuration.surfaces),
            [
                .inbox,
                .today,
                .projectTaskList,
                .boardLiteStatusControls,
                .conversation,
                .pendingActionApprovalInbox
            ]
        )
        XCTAssertEqual(
            Set(configuration.captureInputs),
            [.textConversation, .voiceInput, .shortcutsCreateTask, .shortcutsAskSoloPM, .shareSheetCapture]
        )
        XCTAssertEqual(
            configuration.registrationFlow.steps,
            [.signIn, .restoreEntitlement, .registerDevice, .enableSync]
        )
    }

    func testMobileTaskActionsMapToPlatformNeutralMutations() throws {
        let create = try IOSCompanionTaskAction.create(title: "Call supplier", projectID: 7)
            .mutationPayload(source: .conversation)
        XCTAssertEqual(create.operation, .create)
        XCTAssertEqual(create.title, "Call supplier")
        XCTAssertEqual(create.projectID, 7)
        XCTAssertEqual(create.approvalState, .pendingApproval)

        let complete = try IOSCompanionTaskAction.complete(taskID: 42)
            .mutationPayload(source: .conversation)
        XCTAssertEqual(complete.operation, .complete)
        XCTAssertEqual(complete.status, "completed")

        let status = try IOSCompanionTaskAction.changeStatus(taskID: 42, status: "in_progress")
            .mutationPayload(source: .conversation)
        XCTAssertEqual(status.operation, .update)
        XCTAssertEqual(status.status, "in_progress")

        let due = try IOSCompanionTaskAction.changeDueDate(taskID: 42, dueAt: "2026-06-22T09:00:00Z")
            .mutationPayload(source: .conversation)
        XCTAssertEqual(due.operation, .updateDueDate)
        XCTAssertEqual(due.dueAt, "2026-06-22T09:00:00Z")

        let move = try IOSCompanionTaskAction.moveToProject(taskID: 42, projectID: 9)
            .mutationPayload(source: .conversation)
        XCTAssertEqual(move.operation, .moveProject)
        XCTAssertEqual(move.projectID, 9)
    }

    func testMobileTaskActionsRejectBlankUserInputBeforeCreatingMutations() {
        XCTAssertThrowsError(
            try IOSCompanionTaskAction.create(title: "  ", projectID: nil)
                .mutationPayload(source: .conversation)
        ) { error in
            XCTAssertEqual(error as? IOSCompanionTaskActionError, .blankTitle)
        }
        XCTAssertThrowsError(
            try IOSCompanionTaskAction.changeStatus(taskID: 1, status: "")
                .mutationPayload(source: .conversation)
        ) { error in
            XCTAssertEqual(error as? IOSCompanionTaskActionError, .blankStatus)
        }
        XCTAssertThrowsError(
            try IOSCompanionTaskAction.changeDueDate(taskID: 1, dueAt: "\n")
                .mutationPayload(source: .conversation)
        ) { error in
            XCTAssertEqual(error as? IOSCompanionTaskActionError, .blankDueDate)
        }
    }

    func testApprovalInboxApprovesPendingAutomationRequests() throws {
        let pending = SyncAutomationRequestPayload(
            id: "request-1",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "iphone",
            toolName: "task_update",
            redactedArgumentSummary: "taskID=42, status=in_progress",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .update,
                status: "in_progress",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        let approved = try IOSPendingActionApproval.approve(pending)
        XCTAssertEqual(approved.approvalState, .approved)
        XCTAssertEqual(approved.taskMutation?.approvalState, .approved)
        XCTAssertEqual(approved.sourceClientID, "iphone")
    }

    func testApprovalInboxRejectsAlreadyReviewedRequests() {
        let approved = SyncAutomationRequestPayload(
            id: "request-2",
            source: .cloudRelay,
            approvalState: .approved
        )

        XCTAssertThrowsError(try IOSPendingActionApproval.approve(approved)) { error in
            XCTAssertEqual(error as? IOSPendingActionApprovalError, .requestIsNotPending)
        }
    }

    func testPackageManifestDeclaresIOSSupportTargetAndBuildGate() throws {
        let package = try String(contentsOfFile: "Package.swift")
        let source = try String(contentsOfFile: "Sources/SoloPMiOS/SoloPMiOSCompanion.swift")
        XCTAssertTrue(package.contains(".iOS(.v17)"))
        XCTAssertTrue(package.contains("name: \"SoloPMiOS\""))
        XCTAssertTrue(package.contains("targets: [\"SoloPMiOS\"]"))
        XCTAssertTrue(package.contains("path: \"Sources/SoloPMiOS\""))
        XCTAssertTrue(source.contains("public struct SoloPMiOSCompanionApp: App"))
        XCTAssertTrue(source.contains("SoloPMiOSRootView()"))
    }
}
