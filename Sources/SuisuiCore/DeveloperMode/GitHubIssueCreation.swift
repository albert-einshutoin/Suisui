import Foundation

public struct GitHubRepository: Equatable, Sendable {
    public var owner: String
    public var name: String

    public init(owner: String, name: String) {
        self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var slug: String {
        "\(owner)/\(name)"
    }
}

public struct GitHubIssueDraftRequest: Equatable, Sendable {
    public var repository: GitHubRepository
    public var title: String
    public var body: String
    public var labels: [String]
    public var assignees: [String]

    public init(
        repository: GitHubRepository,
        title: String,
        body: String,
        labels: [String] = [],
        assignees: [String] = []
    ) {
        self.repository = repository
        self.title = title
        self.body = body
        self.labels = labels
        self.assignees = assignees
    }
}

public struct GitHubIssueDraft: Equatable, Sendable {
    public var toolName: String
    public var repository: GitHubRepository
    public var title: String
    public var body: String
    public var labels: [String]
    public var assignees: [String]
    public var reviewChecklist: [String]

    public init(
        toolName: String = "github.issue.create_draft",
        repository: GitHubRepository,
        title: String,
        body: String,
        labels: [String],
        assignees: [String],
        reviewChecklist: [String]
    ) {
        self.toolName = toolName
        self.repository = repository
        self.title = title
        self.body = body
        self.labels = labels
        self.assignees = assignees
        self.reviewChecklist = reviewChecklist
    }
}

public struct GitHubCreatedIssue: Equatable, Sendable {
    public var number: Int
    public var htmlURL: URL

    public init(number: Int, htmlURL: URL) {
        self.number = number
        self.htmlURL = htmlURL
    }
}

public enum GitHubIssueApproval: Equatable, Sendable {
    case notApproved
    case approved(reviewedBy: String)

    public var isApproved: Bool {
        switch self {
        case .notApproved:
            false
        case .approved:
            true
        }
    }
}

public enum GitHubIssueCreationError: Error, Equatable, Sendable {
    case invalidRepository
    case emptyTitle
    case approvalRequired
    case missingToken
}

public protocol GitHubIssueClient: Sendable {
    func createIssue(from draft: GitHubIssueDraft, token: String) async throws -> GitHubCreatedIssue
}

public struct GitHubIssueCreationService: Sendable {
    private let secretStore: any SecretStore
    private let client: any GitHubIssueClient

    public init(secretStore: any SecretStore, client: any GitHubIssueClient) {
        self.secretStore = secretStore
        self.client = client
    }

    public func createDraft(_ request: GitHubIssueDraftRequest) throws -> GitHubIssueDraft {
        guard !request.repository.owner.isEmpty, !request.repository.name.isEmpty else {
            throw GitHubIssueCreationError.invalidRepository
        }

        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw GitHubIssueCreationError.emptyTitle
        }

        let labels = request.labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let assignees = request.assignees
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return GitHubIssueDraft(
            repository: request.repository,
            title: title,
            body: request.body,
            labels: labels,
            assignees: assignees,
            reviewChecklist: [
                "Repository: \(request.repository.slug)",
                "Title: \(title)",
                "Labels: \(labels.isEmpty ? "(none)" : labels.joined(separator: ", "))",
                "Assignees: \(assignees.isEmpty ? "(none)" : assignees.joined(separator: ", "))",
                "GitHub write tool: github.issue.create_with_approval",
                "Token source: SecretStore/Keychain only"
            ]
        )
    }

    public func createWithApproval(
        draft: GitHubIssueDraft,
        approval: GitHubIssueApproval
    ) async throws -> GitHubCreatedIssue {
        guard approval.isApproved else {
            throw GitHubIssueCreationError.approvalRequired
        }

        guard let token = try secretStore.read(.githubToken),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubIssueCreationError.missingToken
        }

        return try await client.createIssue(from: draft, token: token)
    }
}
