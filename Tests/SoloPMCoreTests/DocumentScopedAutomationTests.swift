import XCTest
@testable import SoloPMCore

final class DocumentScopedAutomationTests: XCTestCase {
    func testDocumentAutomationScopesDefineDefaultsAndSelectionBoundaries() {
        XCTAssertEqual(DocumentAutomationScope.allCases, [.appDocs, .projectDocs, .taskArtifacts, .externalSources])
        XCTAssertEqual(DocumentAutomationScope.appDocs.defaultSelection, .offUntilSelected)
        XCTAssertEqual(DocumentAutomationScope.projectDocs.defaultSelection, .projectOptIn)
        XCTAssertEqual(DocumentAutomationScope.taskArtifacts.defaultSelection, .projectOptIn)
        XCTAssertEqual(DocumentAutomationScope.externalSources.defaultSelection, .laterConnectorSpecific)
    }

    func testDocumentScopedRequestReviewSummaryShowsDocsReasonOutputsRiskAndApproval() {
        let request = DocumentScopedAutomationRequest(
            id: "doc-auto-1",
            userRequest: "Prepare release tasks",
            documents: [
                ScopedAutomationDocument(
                    id: "phase13",
                    title: "Phase13 plan",
                    scope: .projectDocs,
                    redactedSummary: "Cloud Relay and iOS scope",
                    inclusionReason: "Project plan was explicitly selected."
                ),
                ScopedAutomationDocument(
                    id: "release-checklist",
                    title: "Release checklist",
                    scope: .appDocs,
                    redactedSummary: "Signing and notarization gates",
                    inclusionReason: "App release checklist was selected for preparation."
                )
            ],
            contextStrategy: .providerPromptContext,
            proposedOutputs: [
                DocumentAutomationProposedOutput(kind: .preparationChecklist, title: "Release prep checklist", riskLevel: .draft, requiresApproval: true),
                DocumentAutomationProposedOutput(kind: .taskDraft, title: "Create notarization task", riskLevel: .write, requiresApproval: true)
            ]
        )

        let review = request.reviewSummary

        XCTAssertEqual(review.documentsConsidered.map(\.title), ["Phase13 plan", "Release checklist"])
        XCTAssertEqual(review.documentReasons.map(\.reason), [
            "Project plan was explicitly selected.",
            "App release checklist was selected for preparation."
        ])
        XCTAssertEqual(review.proposedChanges.map(\.title), ["Release prep checklist", "Create notarization task"])
        XCTAssertEqual(review.highestRisk, .write)
        XCTAssertTrue(review.requiresApproval)
    }

    func testDocumentAutomationToolFlowCoversPrepArtifactsAndSelectableContextAdapters() {
        let flow = DocumentAutomationToolFlow.defaultPro

        XCTAssertEqual(
            flow.outputKinds,
            [.taskDraft, .statusChange, .dueDateChange, .preparationChecklist, .draftArtifact, .releaseNotes, .pullRequestPlan]
        )
        XCTAssertEqual(flow.contextStrategies, [.localFTS, .localEmbeddings, .providerPromptContext])
        XCTAssertEqual(flow.processingBoundary(for: .localFTS), .localIndex)
        XCTAssertEqual(flow.processingBoundary(for: .localEmbeddings), .localVectorIndex)
        XCTAssertEqual(flow.processingBoundary(for: .providerPromptContext), .providerRequest)
    }
}
