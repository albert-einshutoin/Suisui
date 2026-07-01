import XCTest
@testable import SoloPMCore

final class VoiceDevelopmentPullRequestAutomationRequestBuilderTests: XCTestCase {
    func testProjectSelectionRequiresExactlyOneApprovedActiveProject() {
        let active = ProjectRecord(
            id: 1,
            title: "Active Repo",
            status: "active",
            workspacePath: "/tmp/active",
            workspaceBookmarkData: Data("active-bookmark".utf8)
        )
        let completed = ProjectRecord(
            id: 2,
            title: "Completed Repo",
            status: "completed",
            workspacePath: "/tmp/completed",
            workspaceBookmarkData: Data("completed-bookmark".utf8)
        )
        let missingBookmark = ProjectRecord(
            id: 3,
            title: "Missing Bookmark",
            status: "active",
            workspacePath: "/tmp/missing-bookmark",
            workspaceBookmarkData: nil
        )
        let secondActive = ProjectRecord(
            id: 4,
            title: "Second Active Repo",
            status: "active",
            workspacePath: "/tmp/second-active",
            workspaceBookmarkData: Data("second-active-bookmark".utf8)
        )

        XCTAssertEqual(
            VoiceDevelopmentProjectSelection.uniqueApprovedActiveProject(from: [completed, missingBookmark, active])?.id,
            active.id
        )
        XCTAssertNil(VoiceDevelopmentProjectSelection.uniqueApprovedActiveProject(from: [completed, missingBookmark]))
        XCTAssertNil(VoiceDevelopmentProjectSelection.uniqueApprovedActiveProject(from: [active, secondActive]))
    }

    func testBuildsReviewGateAutomationRequestFromExplicitVoiceRouteAndApprovedBookmark() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let project = ProjectRecord(
            id: 7,
            title: "SoloPM",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-bookmark".utf8)
        )
        let route = VoiceCommandRouter().route(transcript: """
        Review PR https://github.com/albert-einshutoin/soloPM/pull/116 branch feature/solopm-7-merge-gate base feature/phase14-product-completion
        """)
        let builder = VoiceDevelopmentPullRequestAutomationRequestBuilder(
            bookmarkResolver: StaticBookmarkResolver(url: workspace),
            requestIDProvider: { "voice-pr-review" }
        )

        let request = try builder.makeReviewGateRequest(route: route, project: project)

        XCTAssertEqual(request.id, "voice-pr-review")
        XCTAssertEqual(request.source, .conversation)
        XCTAssertEqual(request.approvalState, .pendingApproval)
        XCTAssertEqual(request.sourceClientID, "voice")
        XCTAssertEqual(request.toolName, ActionTool.developmentReviewPullRequestGate.rawValue)
        XCTAssertTrue(request.redactedArgumentSummary.contains("Voice development PR review"))
        XCTAssertEqual(request.developmentPullRequest, SyncDevelopmentPullRequestPayload(
            projectID: 7,
            operation: .reviewGate,
            pullRequestURL: "https://github.com/albert-einshutoin/soloPM/pull/116",
            branchName: "feature/solopm-7-merge-gate",
            baseBranch: "feature/phase14-product-completion"
        ))

        let item = AssistantQueueAdapter.makeItem(automationRequest: request)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.requiredCapabilities, [
            .connectedMacRequired,
            .tool(.developmentReviewPullRequestGate),
            .providerExecutionApproval
        ])
    }

    func testRequiresBookmarkBackedProjectWorkspace() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let project = ProjectRecord(
            id: 7,
            title: "SoloPM",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: nil
        )
        let route = VoiceCommandRouter().route(transcript: """
        Review PR https://github.com/albert-einshutoin/soloPM/pull/116 branch feature/solopm-7-merge-gate base feature/phase14-product-completion
        """)
        let builder = VoiceDevelopmentPullRequestAutomationRequestBuilder(
            bookmarkResolver: StaticBookmarkResolver(url: workspace)
        )

        XCTAssertThrowsError(try builder.makeReviewGateRequest(route: route, project: project)) { error in
            XCTAssertEqual(
                error as? VoiceDevelopmentPullRequestAutomationRequestError,
                .projectWorkspaceBookmarkRequired(7)
            )
        }
    }

    func testRejectsUnsafeHeadBranchAndMatchingBaseBranch() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let project = ProjectRecord(
            id: 7,
            title: "SoloPM",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-bookmark".utf8)
        )
        let builder = VoiceDevelopmentPullRequestAutomationRequestBuilder(
            bookmarkResolver: StaticBookmarkResolver(url: workspace)
        )
        let mainBranchRoute = VoiceCommandRouter().route(transcript: """
        Review PR https://github.com/albert-einshutoin/soloPM/pull/116 branch main base feature/phase14-product-completion
        """)
        let matchingBranchRoute = VoiceCommandRouter().route(transcript: """
        Review PR https://github.com/albert-einshutoin/soloPM/pull/116 branch feature/solopm-7-merge-gate base feature/solopm-7-merge-gate
        """)

        XCTAssertThrowsError(try builder.makeReviewGateRequest(route: mainBranchRoute, project: project)) { error in
            XCTAssertEqual(
                error as? VoiceDevelopmentPullRequestAutomationRequestError,
                .invalidHeadBranch("main")
            )
        }
        XCTAssertThrowsError(try builder.makeReviewGateRequest(route: matchingBranchRoute, project: project)) { error in
            XCTAssertEqual(
                error as? VoiceDevelopmentPullRequestAutomationRequestError,
                .branchMatchesBase
            )
        }
    }

    func testRedactsSecretsAndLocalPathsFromReviewSummary() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let project = ProjectRecord(
            id: 7,
            title: "SoloPM",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: Data("approved-bookmark".utf8)
        )
        let route = VoiceCommandRouter().route(transcript: """
        Review PR https://github.com/albert-einshutoin/soloPM/pull/116 branch feature/solopm-7-merge-gate base feature/phase14-product-completion after reading /Users/alice/Secret Project/notes.md token=sk-summary-secret123
        """)
        let builder = VoiceDevelopmentPullRequestAutomationRequestBuilder(
            bookmarkResolver: StaticBookmarkResolver(url: workspace),
            requestIDProvider: { "voice-pr-review" }
        )

        let request = try builder.makeReviewGateRequest(route: route, project: project)

        XCTAssertFalse(request.redactedArgumentSummary.contains("/Users/alice"))
        XCTAssertFalse(request.redactedArgumentSummary.contains("Secret Project"))
        XCTAssertFalse(request.redactedArgumentSummary.contains("sk-summary-secret"))
        XCTAssertTrue(request.redactedArgumentSummary.contains("[REDACTED"))
    }

    private func makeWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloPMVoicePRBuilderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct StaticBookmarkResolver: ProjectWorkspaceBookmarkResolving {
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
