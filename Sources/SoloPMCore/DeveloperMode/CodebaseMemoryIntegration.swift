import Foundation

public enum CodebaseMemoryPolicy: Equatable, Sendable {
    case disabled
    case previewOnly
    case enabledWithApproval
}

public enum CodebaseMemorySendApproval: Equatable, Sendable {
    case notApproved
    case approved(reviewedBy: String)

    var isApproved: Bool {
        switch self {
        case .notApproved:
            false
        case .approved:
            true
        }
    }
}

public struct CodebaseMemoryWorkspace: Equatable, Sendable {
    public var rootPath: String
    public var selectedRelativePaths: [String]

    public init(rootPath: String, selectedRelativePaths: [String]) {
        self.rootPath = rootPath
        self.selectedRelativePaths = selectedRelativePaths
    }
}

public struct CodebaseMemoryPreview: Equatable, Sendable {
    public var body: String
    public var redactionReport: SecretRedactionReport

    public init(body: String, redactionReport: SecretRedactionReport) {
        self.body = body
        self.redactionReport = redactionReport
    }
}

public struct CodebaseMemorySearchRequest: Equatable, Sendable {
    public var query: String
    public var workspace: CodebaseMemoryWorkspace
    public var previewBody: String

    public init(query: String, workspace: CodebaseMemoryWorkspace, previewBody: String) {
        self.query = query
        self.workspace = workspace
        self.previewBody = previewBody
    }
}

public struct CodebaseMemorySnippet: Equatable, Sendable {
    public var id: String
    public var title: String
    public var sourcePath: String
    public var bodyPreview: String

    public init(id: String, title: String, sourcePath: String, bodyPreview: String) {
        self.id = id
        self.title = title
        self.sourcePath = sourcePath
        self.bodyPreview = bodyPreview
    }
}

public protocol CodebaseMemoryConnector: Sendable {
    func search(_ request: CodebaseMemorySearchRequest) async throws -> [CodebaseMemorySnippet]
}

public struct CodebaseMemoryPlanningIntegration: Sendable {
    private let policy: CodebaseMemoryPolicy
    private let connector: (any CodebaseMemoryConnector)?
    private let redactor: DeveloperSecretRedactor

    public init(
        policy: CodebaseMemoryPolicy,
        connector: (any CodebaseMemoryConnector)? = nil,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.policy = policy
        self.connector = connector
        self.redactor = redactor
    }

    public func preview(
        request: PlanningRequest,
        workspace: CodebaseMemoryWorkspace
    ) -> CodebaseMemoryPreview {
        let body = """
        Workspace: \(workspace.rootPath)
        Selected paths:
        \(workspace.selectedRelativePaths.map { "- \($0)" }.joined(separator: "\n"))

        User request:
        \(request.userInput)
        """
        let redaction = redactor.redact(body)

        return CodebaseMemoryPreview(
            body: redaction.text,
            redactionReport: redaction.report
        )
    }

    public func enrichPlanningRequest(
        _ request: PlanningRequest,
        workspace: CodebaseMemoryWorkspace,
        approval: CodebaseMemorySendApproval
    ) async throws -> PlanningRequest {
        guard policy == .enabledWithApproval,
              approval.isApproved,
              let connector else {
            return request
        }

        let preview = preview(request: request, workspace: workspace)
        let snippets = try await connector.search(
            CodebaseMemorySearchRequest(
                query: request.userInput,
                workspace: workspace,
                previewBody: preview.body
            )
        )

        var enriched = request
        enriched.knowledgeFrameCandidates.append(
            contentsOf: snippets.map { snippet in
                KnowledgeFrameCandidate(
                    id: "codebase-memory:\(snippet.id)",
                    name: snippet.title,
                    triggers: [snippet.sourcePath],
                    bodyPreview: snippet.bodyPreview
                )
            }
        )
        return enriched
    }
}
