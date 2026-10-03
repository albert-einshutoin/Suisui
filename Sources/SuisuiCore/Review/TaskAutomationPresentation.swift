import Foundation

public struct TaskAutomationDocumentSourceReview: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var redactedSummary: String
    public var inclusionReason: String

    public init(id: String, title: String, redactedSummary: String, inclusionReason: String) {
        let redactor = DeveloperSecretRedactor()
        self.id = redactor.redact(id).text
        self.title = redactor.redact(title).text
        self.redactedSummary = redactor.redact(redactedSummary).text
        self.inclusionReason = redactor.redact(inclusionReason).text
    }
}

public struct TaskAutomationDocumentDeliverableReview: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: DocumentAutomationOutputKind
    public var title: String
    public var suggestedPath: String
    public var sourceDocuments: [TaskAutomationDocumentSourceReview]
    public var rationale: String
    public var riskLevel: RiskLevel
    public var requiresApproval: Bool

    public init(
        kind: DocumentAutomationOutputKind,
        title: String,
        suggestedPath: String,
        sourceDocuments: [TaskAutomationDocumentSourceReview],
        rationale: String,
        riskLevel: RiskLevel,
        requiresApproval: Bool
    ) {
        let redactor = DeveloperSecretRedactor()
        self.kind = kind
        self.title = redactor.redact(title).text
        self.suggestedPath = redactor.redact(suggestedPath).text
        self.sourceDocuments = sourceDocuments
        self.rationale = redactor.redact(rationale).text
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
        self.id = [kind.rawValue, self.suggestedPath].joined(separator: ":")
    }
}
