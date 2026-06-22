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

    func testDocumentArtifactPlannerChoosesAppropriateOutputsFromDocumentGroup() {
        let documents = [
            ScopedAutomationDocument(
                id: "phase14",
                title: "Phase14 quality plan",
                scope: .projectDocs,
                redactedSummary: "High priority tasks, regression risk map, E2E smoke expansion, and due-date driven automation.",
                inclusionReason: "The user asked to use the quality plan."
            ),
            ScopedAutomationDocument(
                id: "release",
                title: "Release checklist",
                scope: .appDocs,
                redactedSummary: "Signing, notarization, VoiceOver evidence, release notes, and public alpha checklist.",
                inclusionReason: "Release readiness was selected."
            ),
            ScopedAutomationDocument(
                id: "sample",
                title: "Private raw notes",
                scope: .taskArtifacts,
                redactedSummary: "Do not leak sk-test-secret while preparing article.md and README.md drafts.",
                inclusionReason: "The artifact notes were attached."
            )
        ]

        let plan = DocumentAutomationArtifactPlanner().plan(
            userRequest: "Create the right deliverables from these docs and prepare implementation tasks.",
            documents: documents
        )

        XCTAssertEqual(
            plan.proposedOutputs.map(\.kind),
            [.taskDraft, .preparationChecklist, .draftArtifact, .releaseNotes, .pullRequestPlan]
        )
        XCTAssertTrue(plan.requiresApproval)
        XCTAssertEqual(plan.highestRisk, .write)
        XCTAssertTrue(plan.documentReasons.map(\.documentID).contains("phase14"))
        XCTAssertTrue(plan.documentReasons.map(\.documentID).contains("release"))
        XCTAssertFalse(plan.documentsConsidered.map(\.redactedSummary).joined().contains("sk-test-secret"))
    }

    func testDocumentArtifactPlannerKeepsProviderContextBehindApproval() {
        let request = DocumentAutomationArtifactPlanner().makeRequest(
            id: "doc-planner-1",
            userRequest: "Generate release notes and PR plan from selected docs",
            documents: [
                ScopedAutomationDocument(
                    id: "release",
                    title: "Release checklist",
                    scope: .appDocs,
                    redactedSummary: "release notes, Gatekeeper, notarization",
                    inclusionReason: "Selected by the user."
                )
            ],
            contextStrategy: .providerPromptContext
        )

        XCTAssertEqual(request.proposedOutputs.map(\.kind), [.preparationChecklist, .releaseNotes, .pullRequestPlan])
        XCTAssertEqual(request.contextStrategy, .providerPromptContext)
        XCTAssertTrue(request.reviewSummary.requiresApproval)
    }
}
