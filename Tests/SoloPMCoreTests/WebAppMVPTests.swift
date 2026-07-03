import XCTest
@testable import SoloPMCore
@testable import SoloPMWeb

final class WebAppMVPTests: XCTestCase {
    func testWebConfigurationCoversRequiredMVPWorkspaceAndAdminSurfaces() {
        let configuration = WebAppMVPConfiguration.default

        XCTAssertEqual(
            Set(configuration.surfaces),
            [
                .taskBoard,
                .taskList,
                .projectDocs,
                .conversation,
                .automationReview,
                .account,
                .billing,
                .devices,
                .relayTokens,
                .hostedMCPEndpoints,
                .harnessRuns
            ]
        )
        XCTAssertEqual(configuration.backendBoundary.readModel, .syncDomainPayload)
        XCTAssertEqual(configuration.backendBoundary.mutationEndpoint, .cloudRelayTaskMutation)
        XCTAssertEqual(configuration.backendBoundary.adminEndpoint, .accountBillingDevicesRelayTokens)
        XCTAssertEqual(configuration.backendBoundary.executionBoundary, .cloudSafeActionsOnly)
    }

    func testWebTaskActionsMapToCloudRelayCompatibleMutations() throws {
        let create = try WebTaskAction.create(title: "Web capture", projectID: 12)
            .mutationPayload(source: .cloudRelay)
        XCTAssertEqual(create.operation, .create)
        XCTAssertEqual(create.title, "Web capture")
        XCTAssertEqual(create.projectID, 12)
        XCTAssertEqual(create.approvalState, .notRequired)

        let status = try WebTaskAction.changeStatus(taskID: 42, status: "in_review")
            .mutationPayload(source: .cloudRelay)
        XCTAssertEqual(status.operation, .update)
        XCTAssertEqual(status.status, "in_review")
        XCTAssertEqual(status.approvalState, .pendingApproval)

        let due = try WebTaskAction.changeDueDate(taskID: 42, dueAt: "2026-06-23")
            .mutationPayload(source: .cloudRelay)
        XCTAssertEqual(due.operation, .updateDueDate)
        XCTAssertEqual(due.dueAt, "2026-06-23")

        let move = try WebTaskAction.moveToProject(taskID: 42, projectID: 7)
            .mutationPayload(source: .cloudRelay)
        XCTAssertEqual(move.operation, .moveProject)
        XCTAssertEqual(move.projectID, 7)
    }

    func testWebWorkspaceStateIncludesTaskBoardDocsConversationAutomationAndRelayAdmin() {
        let state = WebWorkspaceState.fixture()

        XCTAssertEqual(state.boardColumns.map(\.status), ["todo", "in_progress", "done"])
        XCTAssertEqual(state.taskList.map(\.title), ["Prepare hosted MCP docs", "Review sync ledger"])
        XCTAssertEqual(state.projectDocuments.map(\.title), ["Phase13 plan"])
        XCTAssertEqual(state.conversations.map(\.title), ["Launch prep"])
        XCTAssertEqual(state.automationReviews.map(\.id), ["auto-1"])
        XCTAssertEqual(state.account.billingPlan, "Pro")
        XCTAssertEqual(state.devices.map(\.platform), ["macOS", "iOS"])
        XCTAssertEqual(state.relayTokens.map(\.displayName), ["Gemini task capture"])
        XCTAssertEqual(state.hostedMCPEndpoints.map(\.toolNames), [["task_create", "task_update", "task_complete"]])
    }

    func testWebShowsOSBoundActionsAsUnavailableWithRequiredLocalSurface() {
        let actions = WebOSBoundActionNotice.defaultNotices

        XCTAssertTrue(actions.contains {
            $0.action == .localFilesystemWrite
                && $0.webAvailability == .requiresConnectedMac
                && $0.requiredSurface == .macOSApp
        })
        XCTAssertTrue(actions.contains {
            $0.action == .calendarWrite
                && $0.webAvailability == .requiresConnectedMac
                && $0.requiredSurface == .macOSApp
        })
        XCTAssertFalse(actions.contains { $0.webAvailability == .availableInWeb })
    }

    func testWebRendererContainsTaskBoardAutomationReviewAndRelayManagementRegions() {
        let html = WebAppRenderer.render(workspace: .fixture())

        XCTAssertTrue(html.contains("data-region=\"task-board\""))
        XCTAssertTrue(html.contains("data-region=\"project-docs\""))
        XCTAssertTrue(html.contains("data-region=\"conversation\""))
        XCTAssertTrue(html.contains("data-region=\"automation-review\""))
        XCTAssertTrue(html.contains("data-region=\"relay-tokens\""))
        XCTAssertTrue(html.contains("data-region=\"os-bound-actions\""))
        XCTAssertTrue(html.contains("Gemini task capture"))
        XCTAssertFalse(html.contains("sk-web-secret"))
    }

    func testPackageManifestDeclaresWebProductTargetAndBuildGate() throws {
        let package = try String(contentsOfFile: "Package.swift")
        let source = try String(contentsOfFile: "Sources/SoloPMWeb/SoloPMWebMVP.swift")
        let document = try String(contentsOfFile: "docs/sync/web-app-mvp.md")

        XCTAssertTrue(package.contains("name: \"SoloPMWeb\""))
        XCTAssertTrue(package.contains("targets: [\"SoloPMWeb\"]"))
        XCTAssertTrue(package.contains("path: \"Sources/SoloPMWeb\""))
        XCTAssertTrue(source.contains("public enum WebAppRenderer"))
        XCTAssertTrue(document.contains("Web frontend / backend boundary"))
    }
}
