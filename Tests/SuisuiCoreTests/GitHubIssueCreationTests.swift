import XCTest
@testable import SuisuiCore

final class GitHubIssueCreationTests: XCTestCase {
    func testCreateDraftBuildsReviewableIssueWithoutReadingToken() throws {
        let service = GitHubIssueCreationService(
            secretStore: InMemorySecretStore(values: [.githubToken: fakeClassicToken("secret_should_not_leave_store")]),
            client: RecordingGitHubIssueClient()
        )

        let draft = try service.createDraft(
            GitHubIssueDraftRequest(
                repository: GitHubRepository(owner: "solo", name: "pm"),
                title: "Add developer CLI",
                body: "Ship local read commands",
                labels: ["developer-mode"],
                assignees: ["shuto"]
            )
        )

        XCTAssertEqual(draft.toolName, "github.issue.create_draft")
        XCTAssertEqual(draft.repository.slug, "solo/pm")
        XCTAssertEqual(draft.title, "Add developer CLI")
        XCTAssertEqual(draft.labels, ["developer-mode"])
        XCTAssertEqual(draft.assignees, ["shuto"])
        XCTAssertTrue(draft.reviewChecklist.contains("Repository: solo/pm"))
        XCTAssertFalse(draft.reviewChecklist.joined(separator: "\n").contains(fakeClassicToken("secret")))
    }

    func testCreateWithApprovalRejectsMissingApprovalBeforeClientCall() async throws {
        let client = RecordingGitHubIssueClient()
        let service = GitHubIssueCreationService(
            secretStore: InMemorySecretStore(values: [.githubToken: fakeClassicToken("secret")]),
            client: client
        )
        let draft = try service.createDraft(
            GitHubIssueDraftRequest(
                repository: GitHubRepository(owner: "solo", name: "pm"),
                title: "Guard GitHub writes",
                body: "Approval is required."
            )
        )

        do {
            _ = try await service.createWithApproval(draft: draft, approval: .notApproved)
            XCTFail("createWithApproval should reject missing approval")
        } catch let error as GitHubIssueCreationError {
            XCTAssertEqual(error, .approvalRequired)
        }

        XCTAssertEqual(client.requests.count, 0)
    }

    func testCreateWithApprovalUsesStoredTokenOnlyAfterApproval() async throws {
        let token = fakeFineGrainedToken("secret")
        let client = RecordingGitHubIssueClient(
            result: GitHubCreatedIssue(number: 42, htmlURL: URL(string: "https://github.com/solo/pm/issues/42")!)
        )
        let service = GitHubIssueCreationService(
            secretStore: InMemorySecretStore(values: [.githubToken: token]),
            client: client
        )
        let draft = try service.createDraft(
            GitHubIssueDraftRequest(
                repository: GitHubRepository(owner: "solo", name: "pm"),
                title: "Create approved issue",
                body: "Write only after approval."
            )
        )

        let created = try await service.createWithApproval(draft: draft, approval: .approved(reviewedBy: "tester"))

        XCTAssertEqual(created.number, 42)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.token, token)
        XCTAssertEqual(client.requests.first?.draft.title, "Create approved issue")
    }

    private func fakeClassicToken(_ suffix: String) -> String {
        "ghp" + "_" + suffix
    }

    private func fakeFineGrainedToken(_ suffix: String) -> String {
        "github" + "_pat_" + suffix
    }
}

private final class RecordingGitHubIssueClient: GitHubIssueClient, @unchecked Sendable {
    struct Request: Equatable {
        var draft: GitHubIssueDraft
        var token: String
    }

    private(set) var requests: [Request] = []
    private let result: GitHubCreatedIssue

    init(result: GitHubCreatedIssue = GitHubCreatedIssue(number: 1, htmlURL: URL(string: "https://github.com/solo/pm/issues/1")!)) {
        self.result = result
    }

    func createIssue(from draft: GitHubIssueDraft, token: String) async throws -> GitHubCreatedIssue {
        requests.append(Request(draft: draft, token: token))
        return result
    }
}
