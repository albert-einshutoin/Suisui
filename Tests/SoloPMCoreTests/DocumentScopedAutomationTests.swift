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
            [.taskDraft, .dueDateChange, .preparationChecklist, .draftArtifact, .releaseNotes, .pullRequestPlan]
        )
        XCTAssertTrue(plan.requiresApproval)
        XCTAssertEqual(plan.highestRisk, .write)
        XCTAssertTrue(plan.documentReasons.map(\.documentID).contains("phase14"))
        XCTAssertTrue(plan.documentReasons.map(\.documentID).contains("release"))
        XCTAssertFalse(plan.documentsConsidered.map(\.redactedSummary).joined().contains("sk-test-secret"))
    }

    func testDocumentArtifactPlannerProposesStatusAndDueDateChangesFromTaskDocs() {
        let documents = [
            ScopedAutomationDocument(
                id: "standup",
                title: "Daily execution notes",
                scope: .projectDocs,
                redactedSummary: "Move the release audit task to in progress, mark the old inbox triage task complete, and shift the notarization follow-up due date to Friday.",
                inclusionReason: "The user selected the current execution notes."
            )
        ]

        let plan = DocumentAutomationArtifactPlanner().plan(
            userRequest: "Turn these notes into the right task updates.",
            documents: documents
        )

        XCTAssertEqual(
            plan.proposedOutputs.map(\.kind),
            [.taskDraft, .statusChange, .dueDateChange, .preparationChecklist]
        )
        XCTAssertEqual(plan.highestRisk, .write)
        XCTAssertTrue(plan.proposedOutputs.allSatisfy(\.requiresApproval))
    }

    func testDocumentArtifactPlannerBuildsReviewableDeliverableDraftsFromSelectedDocs() {
        let documents = [
            ScopedAutomationDocument(
                id: "release",
                title: "Release checklist",
                scope: .appDocs,
                redactedSummary: "Manual VoiceOver evidence, release notes, Gatekeeper, and notarization checks.",
                inclusionReason: "The app release checklist was selected."
            ),
            ScopedAutomationDocument(
                id: "phase14",
                title: "Phase14 quality plan",
                scope: .projectDocs,
                redactedSummary: "Implementation tasks, regression tests, and PR plan requirements.",
                inclusionReason: "The phase plan was selected."
            ),
            ScopedAutomationDocument(
                id: "artifact-notes",
                title: "Draft artifact notes",
                scope: .taskArtifacts,
                redactedSummary: "Draft README.md and article.md from local notes without leaking sk-test-secret.",
                inclusionReason: "The task artifact notes were selected."
            ),
            ScopedAutomationDocument(
                id: "github-issue",
                title: "GitHub issue mirror",
                scope: .externalSources,
                redactedSummary: "External connector context is present but not approved for this release.",
                inclusionReason: "External source preview is visible."
            )
        ]

        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes, a PR plan, and the right draft artifacts from these docs.",
            documents: documents
        )

        XCTAssertEqual(drafts.map(\.kind), [.preparationChecklist, .draftArtifact, .releaseNotes, .pullRequestPlan])
        XCTAssertEqual(drafts.map(\.suggestedPath), [
            ".tmp/document-automation/preparation-checklist.md",
            ".tmp/document-automation/draft-artifact.md",
            "docs/release/notes-draft.md",
            ".tmp/document-automation/pr-plan.md"
        ])
        XCTAssertTrue(drafts.allSatisfy(\.requiresApproval))
        XCTAssertTrue(drafts.allSatisfy { $0.riskLevel == .draft })
        XCTAssertTrue(drafts.allSatisfy { !$0.sourceDocumentIDs.contains("github-issue") })
        XCTAssertEqual(drafts.first { $0.kind == .releaseNotes }?.sourceDocumentIDs, ["release", "phase14", "artifact-notes"])
        XCTAssertTrue(drafts.first { $0.kind == .pullRequestPlan }?.rationale.contains("PR plan") == true)
        XCTAssertFalse(drafts.map(\.rationale).joined().contains("sk-test-secret"))
    }

    func testDocumentArtifactPlannerDoesNotCreateDeliverableDraftsFromExternalSourcesOnly() {
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes from the GitHub issue mirror.",
            documents: [
                ScopedAutomationDocument(
                    id: "github-issue",
                    title: "GitHub issue mirror",
                    scope: .externalSources,
                    redactedSummary: "Release notes and PR plan from remote connector state.",
                    inclusionReason: "External source preview is visible but not approved."
                )
            ]
        )

        XCTAssertTrue(drafts.isEmpty)
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
