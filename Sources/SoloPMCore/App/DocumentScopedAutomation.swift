import Foundation

public enum DocumentAutomationScope: String, Codable, CaseIterable, Equatable, Sendable {
    case appDocs
    case projectDocs
    case taskArtifacts
    case externalSources

    public var defaultSelection: DocumentAutomationDefaultSelection {
        switch self {
        case .appDocs:
            .offUntilSelected
        case .projectDocs, .taskArtifacts:
            .projectOptIn
        case .externalSources:
            .laterConnectorSpecific
        }
    }
}

public enum DocumentAutomationDefaultSelection: String, Codable, Equatable, Sendable {
    case offUntilSelected
    case projectOptIn
    case laterConnectorSpecific
}

public struct ScopedAutomationDocument: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var scope: DocumentAutomationScope
    public var redactedSummary: String
    public var inclusionReason: String

    public init(
        id: String,
        title: String,
        scope: DocumentAutomationScope,
        redactedSummary: String,
        inclusionReason: String
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.redactedSummary = DeveloperSecretRedactor().redact(redactedSummary).text
        self.inclusionReason = inclusionReason
    }
}

public enum DocumentAutomationContextStrategy: String, Codable, CaseIterable, Equatable, Sendable {
    case localFTS
    case localEmbeddings
    case providerPromptContext
}

public enum DocumentAutomationProcessingBoundary: String, Codable, Equatable, Sendable {
    case localIndex
    case localVectorIndex
    case providerRequest
}

public enum DocumentAutomationOutputKind: String, Codable, CaseIterable, Equatable, Sendable {
    case taskDraft
    case statusChange
    case dueDateChange
    case preparationChecklist
    case draftArtifact
    case releaseNotes
    case pullRequestPlan
}

public struct DocumentAutomationProposedOutput: Codable, Equatable, Sendable {
    public var kind: DocumentAutomationOutputKind
    public var title: String
    public var riskLevel: RiskLevel
    public var requiresApproval: Bool

    public init(
        kind: DocumentAutomationOutputKind,
        title: String,
        riskLevel: RiskLevel,
        requiresApproval: Bool
    ) {
        self.kind = kind
        self.title = title
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
    }
}

public struct DocumentAutomationDocumentReason: Codable, Equatable, Sendable {
    public var documentID: String
    public var title: String
    public var reason: String

    public init(documentID: String, title: String, reason: String) {
        self.documentID = documentID
        self.title = title
        self.reason = reason
    }
}

public struct DocumentScopedAutomationReviewSummary: Codable, Equatable, Sendable {
    public var documentsConsidered: [ScopedAutomationDocument]
    public var documentReasons: [DocumentAutomationDocumentReason]
    public var proposedChanges: [DocumentAutomationProposedOutput]
    public var highestRisk: RiskLevel
    public var requiresApproval: Bool

    public init(
        documentsConsidered: [ScopedAutomationDocument],
        documentReasons: [DocumentAutomationDocumentReason],
        proposedChanges: [DocumentAutomationProposedOutput]
    ) {
        self.documentsConsidered = documentsConsidered
        self.documentReasons = documentReasons
        self.proposedChanges = proposedChanges
        self.highestRisk = proposedChanges.map(\.riskLevel).max() ?? .read
        // Document-scoped automation explains what it read and what it proposes;
        // even draft outputs need review until project-level policies are explicit.
        self.requiresApproval = proposedChanges.contains { $0.requiresApproval } || highestRisk >= .draft
    }

    public var proposedOutputs: [DocumentAutomationProposedOutput] {
        proposedChanges
    }
}

public struct DocumentScopedAutomationRequest: Codable, Equatable, Sendable {
    public var id: String
    public var userRequest: String
    public var documents: [ScopedAutomationDocument]
    public var contextStrategy: DocumentAutomationContextStrategy
    public var proposedOutputs: [DocumentAutomationProposedOutput]

    public init(
        id: String,
        userRequest: String,
        documents: [ScopedAutomationDocument],
        contextStrategy: DocumentAutomationContextStrategy,
        proposedOutputs: [DocumentAutomationProposedOutput]
    ) {
        self.id = id
        self.userRequest = userRequest
        self.documents = documents
        self.contextStrategy = contextStrategy
        self.proposedOutputs = proposedOutputs
    }

    public var reviewSummary: DocumentScopedAutomationReviewSummary {
        DocumentScopedAutomationReviewSummary(
            documentsConsidered: documents,
            documentReasons: documents.map {
                DocumentAutomationDocumentReason(
                    documentID: $0.id,
                    title: $0.title,
                    reason: $0.inclusionReason
                )
            },
            proposedChanges: proposedOutputs
        )
    }
}

public struct DocumentAutomationToolFlow: Codable, Equatable, Sendable {
    public var outputKinds: [DocumentAutomationOutputKind]
    public var contextStrategies: [DocumentAutomationContextStrategy]

    public init(
        outputKinds: [DocumentAutomationOutputKind],
        contextStrategies: [DocumentAutomationContextStrategy]
    ) {
        self.outputKinds = outputKinds
        self.contextStrategies = contextStrategies
    }

    public static let defaultPro = DocumentAutomationToolFlow(
        outputKinds: [
            .taskDraft,
            .statusChange,
            .dueDateChange,
            .preparationChecklist,
            .draftArtifact,
            .releaseNotes,
            .pullRequestPlan
        ],
        contextStrategies: [.localFTS, .localEmbeddings, .providerPromptContext]
    )

    public func processingBoundary(
        for strategy: DocumentAutomationContextStrategy
    ) -> DocumentAutomationProcessingBoundary {
        switch strategy {
        case .localFTS:
            .localIndex
        case .localEmbeddings:
            .localVectorIndex
        case .providerPromptContext:
            .providerRequest
        }
    }
}

public struct DocumentAutomationArtifactPlanner: Sendable {
    public init() {}

    public func plan(
        userRequest: String,
        documents: [ScopedAutomationDocument]
    ) -> DocumentScopedAutomationReviewSummary {
        DocumentScopedAutomationReviewSummary(
            documentsConsidered: documents,
            documentReasons: documents.map {
                DocumentAutomationDocumentReason(
                    documentID: $0.id,
                    title: $0.title,
                    reason: artifactReason(for: $0)
                )
            },
            proposedChanges: proposedOutputs(userRequest: userRequest, documents: documents)
        )
    }

    public func makeRequest(
        id: String,
        userRequest: String,
        documents: [ScopedAutomationDocument],
        contextStrategy: DocumentAutomationContextStrategy
    ) -> DocumentScopedAutomationRequest {
        DocumentScopedAutomationRequest(
            id: id,
            userRequest: userRequest,
            documents: documents,
            contextStrategy: contextStrategy,
            proposedOutputs: proposedOutputs(userRequest: userRequest, documents: documents)
        )
    }

    private func proposedOutputs(
        userRequest: String,
        documents: [ScopedAutomationDocument]
    ) -> [DocumentAutomationProposedOutput] {
        let searchable = ([userRequest] + documents.flatMap { [$0.title, $0.redactedSummary, $0.inclusionReason] })
            .joined(separator: "\n")
            .lowercased()
        var kinds: [DocumentAutomationOutputKind] = []

        append(.taskDraft, to: &kinds, when: searchable.containsAny(["task", "todo", "phase", "implementation", "実装", "タスク"]))
        append(.preparationChecklist, to: &kinds, when: searchable.containsAny(["checklist", "gate", "signing", "notarization", "voiceover", "release", "準備"]))
        append(.draftArtifact, to: &kinds, when: searchable.containsAny(["artifact", ".md", "draft", "readme", "article", "成果物", "下書き"]))
        append(.releaseNotes, to: &kinds, when: searchable.containsAny(["release note", "release notes", "changelog", "public alpha", "リリース"]))
        append(.pullRequestPlan, to: &kinds, when: searchable.containsAny(["pull request", "pr plan", "pr", "implementation", "phase", "regression", "実装"]))

        if kinds.isEmpty {
            kinds = [.preparationChecklist]
        }

        // Proposed document outputs can mutate tasks or produce files later, so
        // every item remains approval-gated even when the planner itself is local.
        return kinds.map { kind in
            DocumentAutomationProposedOutput(
                kind: kind,
                title: title(for: kind),
                riskLevel: riskLevel(for: kind),
                requiresApproval: true
            )
        }
    }

    private func artifactReason(for document: ScopedAutomationDocument) -> String {
        switch document.scope {
        case .appDocs:
            "App documentation can define release, privacy, or product-wide output requirements."
        case .projectDocs:
            "Project documentation can define tasks, milestones, and implementation plans."
        case .taskArtifacts:
            "Task artifacts can provide draftable output paths and acceptance criteria."
        case .externalSources:
            "External sources require connector-specific review before use."
        }
    }

    private func append(
        _ kind: DocumentAutomationOutputKind,
        to kinds: inout [DocumentAutomationOutputKind],
        when condition: Bool
    ) {
        guard condition, !kinds.contains(kind) else {
            return
        }
        kinds.append(kind)
    }

    private func title(for kind: DocumentAutomationOutputKind) -> String {
        switch kind {
        case .taskDraft:
            "Implementation task draft"
        case .statusChange:
            "Status change proposal"
        case .dueDateChange:
            "Due date change proposal"
        case .preparationChecklist:
            "Preparation checklist"
        case .draftArtifact:
            "Draft artifact"
        case .releaseNotes:
            "Release notes draft"
        case .pullRequestPlan:
            "Pull request plan"
        }
    }

    private func riskLevel(for kind: DocumentAutomationOutputKind) -> RiskLevel {
        switch kind {
        case .taskDraft, .statusChange, .dueDateChange:
            .write
        case .preparationChecklist, .draftArtifact, .releaseNotes, .pullRequestPlan:
            .draft
        }
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
