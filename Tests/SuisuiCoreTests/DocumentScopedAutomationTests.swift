import XCTest
@testable import SuisuiCore

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

    func testScopedAutomationDocumentRedactsTitleAndReasonBeforeReviewOrProviderContext() {
        let document = ScopedAutomationDocument(
            id: "secret-doc",
            title: "Release checklist sk-proj-title-secret",
            scope: .appDocs,
            redactedSummary: "Use token=summary-secret for notarization notes.",
            inclusionReason: "Selected after token=reason-secret appeared in the note title."
        )
        let request = DocumentAutomationArtifactPlanner().makeRequest(
            id: "doc-redaction",
            userRequest: "Create release notes from selected docs",
            documents: [document],
            contextStrategy: .providerPromptContext
        )

        let review = request.reviewSummary
        let serializedContext = [
            request.documents.map(\.title).joined(separator: "\n"),
            request.documents.map(\.redactedSummary).joined(separator: "\n"),
            request.documents.map(\.inclusionReason).joined(separator: "\n"),
            review.documentsConsidered.map(\.title).joined(separator: "\n"),
            review.documentReasons.map(\.reason).joined(separator: "\n")
        ].joined(separator: "\n")

        XCTAssertTrue(serializedContext.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(serializedContext.contains("sk-proj-title-secret"))
        XCTAssertFalse(serializedContext.contains("summary-secret"))
        XCTAssertFalse(serializedContext.contains("reason-secret"))
    }

    func testDeliverableDraftRedactsSourceIdentityBeforeReviewOrProviderContext() {
        let source = DocumentAutomationDeliverableSource(
            id: "doc-sk-proj-sourceidentity123",
            title: "Release notes source token=source-title-secret",
            redactedSummary: "Use token=summary-secret before generating the draft.",
            inclusionReason: "Selected because token=reason-secret matched the request."
        )
        let draft = DocumentAutomationDeliverableDraft(
            kind: .releaseNotes,
            title: "Release notes token=deliverable-title-secret",
            suggestedPath: ".tmp/document-automation/token=path-secret/notes.md",
            sourceDocumentIDs: ["doc-sk-proj-sourceidentity123"],
            sourceDocuments: [source],
            rationale: "Draft release notes from token=rationale-secret.",
            riskLevel: .draft,
            requiresApproval: true
        )

        let serializedDraft = [
            draft.title,
            draft.suggestedPath,
            draft.sourceDocumentIDs.joined(separator: "\n"),
            draft.sourceDocuments.map(\.id).joined(separator: "\n"),
            draft.sourceDocuments.map(\.title).joined(separator: "\n"),
            draft.sourceDocuments.map(\.redactedSummary).joined(separator: "\n"),
            draft.sourceDocuments.map(\.inclusionReason).joined(separator: "\n"),
            draft.rationale
        ].joined(separator: "\n")

        XCTAssertTrue(serializedDraft.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(serializedDraft.contains("sk-proj-sourceidentity123"))
        XCTAssertFalse(serializedDraft.contains("source-title-secret"))
        XCTAssertFalse(serializedDraft.contains("summary-secret"))
        XCTAssertFalse(serializedDraft.contains("reason-secret"))
        XCTAssertFalse(serializedDraft.contains("deliverable-title-secret"))
        XCTAssertFalse(serializedDraft.contains("path-secret"))
        XCTAssertFalse(serializedDraft.contains("rationale-secret"))
    }

    func testDocumentAutomationDecodeReappliesRedactionBoundaries() throws {
        let documentData = Data(
            """
            {
              "id": "doc-token=decoded-doc-id-secret",
              "title": "Decoded release source token=decoded-title-secret",
              "scope": "appDocs",
              "redactedSummary": "Use token=decoded-summary-secret in notes.",
              "inclusionReason": "Selected because token=decoded-reason-secret matched."
            }
            """.utf8
        )
        let sourceData = Data(
            """
            {
              "id": "source-sk-proj-decodedsrc123",
              "title": "Decoded source token=decoded-source-title-secret",
              "redactedSummary": "Use token=decoded-source-summary-secret.",
              "inclusionReason": "Selected because token=decoded-source-reason-secret matched."
            }
            """.utf8
        )
        let draftData = Data(
            """
            {
              "kind": "releaseNotes",
              "title": "Decoded draft token=decoded-draft-title-secret",
              "suggestedPath": ".tmp/document-automation/token=decoded-path-secret/notes.md",
              "sourceDocumentIDs": ["source-sk-proj-decodedsrc123"],
              "sourceDocuments": [
                {
                  "id": "source-sk-proj-decodedsrc123",
                  "title": "Decoded source token=decoded-source-title-secret",
                  "redactedSummary": "Use token=decoded-source-summary-secret.",
                  "inclusionReason": "Selected because token=decoded-source-reason-secret matched."
                }
              ],
              "rationale": "Draft from token=decoded-rationale-secret.",
              "riskLevel": "draft",
              "requiresApproval": true
            }
            """.utf8
        )

        let document = try JSONDecoder().decode(ScopedAutomationDocument.self, from: documentData)
        let source = try JSONDecoder().decode(DocumentAutomationDeliverableSource.self, from: sourceData)
        let draft = try JSONDecoder().decode(DocumentAutomationDeliverableDraft.self, from: draftData)
        let serializedDecodedValues = [
            document.id,
            document.title,
            document.redactedSummary,
            document.inclusionReason,
            source.id,
            source.title,
            source.redactedSummary,
            source.inclusionReason,
            draft.title,
            draft.suggestedPath,
            draft.sourceDocumentIDs.joined(separator: "\n"),
            draft.sourceDocuments.map(\.id).joined(separator: "\n"),
            draft.sourceDocuments.map(\.title).joined(separator: "\n"),
            draft.sourceDocuments.map(\.redactedSummary).joined(separator: "\n"),
            draft.sourceDocuments.map(\.inclusionReason).joined(separator: "\n"),
            draft.rationale
        ].joined(separator: "\n")

        XCTAssertTrue(serializedDecodedValues.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-doc-id-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-title-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-summary-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-reason-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("sk-proj-decodedsrc123"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-source-title-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-source-summary-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-source-reason-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-draft-title-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-path-secret"))
        XCTAssertFalse(serializedDecodedValues.contains("decoded-rationale-secret"))
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
        XCTAssertEqual(drafts.first { $0.kind == .releaseNotes }?.sourceDocumentIDs, ["release"])
        XCTAssertEqual(drafts.first { $0.kind == .pullRequestPlan }?.sourceDocumentIDs, ["phase14"])
        XCTAssertEqual(drafts.first { $0.kind == .draftArtifact }?.sourceDocumentIDs, ["artifact-notes"])
        XCTAssertTrue(drafts.first { $0.kind == .pullRequestPlan }?.rationale.contains("PR plan") == true)
        XCTAssertFalse(drafts.map(\.rationale).joined().contains("sk-test-secret"))
    }

    func testDocumentArtifactPlannerBindsEachDeliverableToRelevantSourceDocuments() {
        let documents = [
            ScopedAutomationDocument(
                id: "release-notes",
                title: "Release notes source",
                scope: .appDocs,
                redactedSummary: "Public alpha release notes and changelog highlights.",
                inclusionReason: "Selected for release communication."
            ),
            ScopedAutomationDocument(
                id: "pr-plan",
                title: "Implementation regression plan",
                scope: .projectDocs,
                redactedSummary: "Implementation plan, pull request checklist, regression tests, and verification commands.",
                inclusionReason: "Selected for PR planning."
            ),
            ScopedAutomationDocument(
                id: "artifact-draft",
                title: "README artifact notes",
                scope: .taskArtifacts,
                redactedSummary: "Draft README.md and article.md artifact content.",
                inclusionReason: "Selected for draft artifact output."
            ),
            ScopedAutomationDocument(
                id: "general-context",
                title: "General project context",
                scope: .projectDocs,
                redactedSummary: "Background information that should not be cited for specific deliverables.",
                inclusionReason: "Selected for orientation."
            )
        ]

        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes, a PR plan, and draft artifacts from the relevant docs.",
            documents: documents
        )

        XCTAssertEqual(
            drafts.first { $0.kind == .releaseNotes }?.sourceDocumentIDs,
            ["release-notes"]
        )
        XCTAssertEqual(
            drafts.first { $0.kind == .pullRequestPlan }?.sourceDocumentIDs,
            ["pr-plan"]
        )
        XCTAssertEqual(
            drafts.first { $0.kind == .draftArtifact }?.sourceDocumentIDs,
            ["artifact-draft"]
        )
        XCTAssertFalse(drafts.map(\.sourceDocumentIDs).joined().contains("general-context"))
    }

    func testDocumentArtifactPlannerDoesNotCreateSpecificDeliverablesFromUserRequestAlone() {
        let documents = [
            ScopedAutomationDocument(
                id: "background",
                title: "General project background",
                scope: .projectDocs,
                redactedSummary: "Product positioning, user interview themes, and current operating constraints.",
                inclusionReason: "Selected as general context for the automation review."
            )
        ]

        let plan = DocumentAutomationArtifactPlanner().plan(
            userRequest: "Create release notes and a PR plan from these docs.",
            documents: documents
        )
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Create release notes and a PR plan from these docs.",
            documents: documents
        )

        XCTAssertEqual(plan.proposedOutputs.map(\.kind), [.preparationChecklist])
        XCTAssertEqual(drafts.map(\.kind), [.preparationChecklist])
        XCTAssertEqual(drafts.first?.sourceDocumentIDs, ["background"])
        XCTAssertFalse(drafts.contains { $0.kind == .releaseNotes })
        XCTAssertFalse(drafts.contains { $0.kind == .pullRequestPlan })
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

    func testDocumentArtifactPlannerDoesNotPlanOutputsFromExternalSourcesOnly() {
        let plan = DocumentAutomationArtifactPlanner().plan(
            userRequest: "Create release notes and a PR plan from the GitHub issue mirror.",
            documents: [
                ScopedAutomationDocument(
                    id: "github-issue",
                    title: "GitHub issue mirror",
                    scope: .externalSources,
                    redactedSummary: "Release notes, PR plan, task drafts, and due-date changes from remote connector state.",
                    inclusionReason: "External source preview is visible but not approved."
                )
            ]
        )

        XCTAssertEqual(plan.proposedOutputs, [])
        XCTAssertEqual(plan.highestRisk, .read)
        XCTAssertFalse(plan.requiresApproval)
        XCTAssertEqual(plan.documentsConsidered.map(\.id), ["github-issue"])
        XCTAssertEqual(plan.documentReasons.map(\.reason), ["External sources require connector-specific review before use."])
    }

    func testDocumentArtifactPlannerIgnoresExternalSourceSignalsWhenApprovedDocsDoNotSupportDeliverable() {
        let plan = DocumentAutomationArtifactPlanner().plan(
            userRequest: "Create the appropriate outputs from the selected documents.",
            documents: [
                ScopedAutomationDocument(
                    id: "local-note",
                    title: "Local project memo",
                    scope: .projectDocs,
                    redactedSummary: "General project background without release or PR instructions.",
                    inclusionReason: "Local project note was selected."
                ),
                ScopedAutomationDocument(
                    id: "github-issue",
                    title: "GitHub issue mirror",
                    scope: .externalSources,
                    redactedSummary: "Release notes, PR plan, task drafts, and due-date changes from remote connector state.",
                    inclusionReason: "External source preview is visible but not approved."
                )
            ]
        )

        XCTAssertEqual(plan.proposedOutputs.map(\.kind), [.preparationChecklist])
        XCTAssertEqual(plan.documentReasons.map(\.documentID), ["local-note", "github-issue"])
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
                    redactedSummary: "release notes, PR plan, Gatekeeper, notarization",
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
