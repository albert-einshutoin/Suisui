import Foundation

public enum SoloPMHarnessScenarioKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case providerPromptRegression
    case taskMutationFlow
    case documentScopedAutomation
    case mcpCompatibility
    case accessibilityFocusPath
}

public enum SoloPMHarnessCapability: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case providerPrompt
    case taskMutation
    case documentAutomation
    case mcpToolCall
    case accessibilityAudit
}

public enum SoloPMHarnessAssertion: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case outputMatchesExpected
    case approvalBoundary
    case auditLogRecorded
    case redactedLogs
    case resultDiffRecorded
    case accessibilityFocusPathCovered
}

public enum SoloPMHarnessTaskLifecycleOperation: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case taskList
    case create
    case editContent
    case statusMove
    case automationReview
    case executeContent
    case approvedExecution
    case deleteConfirmation
    case projectCompletion
    case projectDeleteCascade

    public var requiredFocusNodeIDs: [String] {
        switch self {
        case .taskList:
            [
                "project-task-list"
            ]
        case .create:
            [
                "project-board-sidebar",
                "project-board-detail",
                "project-header-add-task",
                "inline-task-title",
                "inline-task-detail",
                "inline-task-create"
            ]
        case .editContent:
            [
                "task-card-open-details",
                "task-inspector-title",
                "task-inspector-detail",
                "task-inspector-save"
            ]
        case .statusMove:
            [
                "task-status-move-controls",
                "task-status-move-in_progress"
            ]
        case .automationReview:
            [
                "project-board-task-auto-execution-review",
                "task-auto-execution-review"
            ]
        case .executeContent:
            [
                "task-auto-execution-run-plan",
                "approved-execution-receipt"
            ]
        case .approvedExecution:
            [
                "approved-execution-receipt"
            ]
        case .deleteConfirmation:
            [
                "task-inspector-delete",
                "task-inspector-delete-confirmation-cancel",
                "task-inspector-delete-confirmation-confirm"
            ]
        case .projectCompletion:
            [
                "project-inspector-complete"
            ]
        case .projectDeleteCascade:
            [
                "project-inspector-delete",
                "project-inspector-delete-confirmation-cancel",
                "project-inspector-delete-confirmation-confirm"
            ]
        }
    }
}

public enum SoloPMHarnessTodayCockpitOperation: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case openToday
    case captureCommand
    case commonActions
    case focusSuggestions
    case localFocusAndPlanning
    case railContext
    case railActions

    public var requiredFocusNodeIDs: [String] {
        switch self {
        case .openToday:
            [
                "sidebar-destination-today",
                "today-workflow"
            ]
        case .captureCommand:
            [
                "today-briefing-panel",
                "today-command-capture-field",
                "today-command-add"
            ]
        case .commonActions:
            [
                "today-common-action-rail",
                "today-common-chip-add-task",
                "today-common-chip-plan-tomorrow",
                "today-common-chip-prepare-meeting",
                "today-common-chip-draft-reply"
            ]
        case .focusSuggestions:
            [
                "today-suggestion-rail"
            ]
        case .localFocusAndPlanning:
            [
                "today-start-focus",
                "today-flow-strip"
            ]
        case .railContext:
            [
                "today-assistant-rail",
                "today-rail-next-action",
                "today-rail-task-detail"
            ]
        case .railActions:
            [
                "today-rail-focus",
                "today-rail-schedule-block",
                "today-rail-edit-task",
                "today-rail-add-subtask",
                "today-rail-reminder-draft"
            ]
        }
    }
}

public struct SoloPMHarnessScenario: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: SoloPMHarnessScenarioKind
    public var requiredCapabilities: [SoloPMHarnessCapability]
    public var expectedMutations: [SyncTaskMutationPayload]
    public var assertions: [SoloPMHarnessAssertion]
    public var requiredTaskLifecycleOperations: [SoloPMHarnessTaskLifecycleOperation]
    public var requiredTodayCockpitOperations: [SoloPMHarnessTodayCockpitOperation]
    public var requiredDocumentDeliverableKinds: [DocumentAutomationOutputKind]

    public init(
        id: String,
        name: String,
        kind: SoloPMHarnessScenarioKind,
        requiredCapabilities: [SoloPMHarnessCapability],
        expectedMutations: [SyncTaskMutationPayload],
        assertions: [SoloPMHarnessAssertion],
        requiredTaskLifecycleOperations: [SoloPMHarnessTaskLifecycleOperation] = [],
        requiredTodayCockpitOperations: [SoloPMHarnessTodayCockpitOperation] = [],
        requiredDocumentDeliverableKinds: [DocumentAutomationOutputKind] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.requiredCapabilities = requiredCapabilities
        self.expectedMutations = expectedMutations
        self.assertions = assertions
        self.requiredTaskLifecycleOperations = requiredTaskLifecycleOperations
        self.requiredTodayCockpitOperations = requiredTodayCockpitOperations
        self.requiredDocumentDeliverableKinds = requiredDocumentDeliverableKinds
    }

    public static let completeTaskLifecycleOperations: [SoloPMHarnessTaskLifecycleOperation] = [
        .taskList,
        .create,
        .editContent,
        .statusMove,
        .automationReview,
        // Keep content execution distinct so review-only MCP coverage cannot hide a missing user-visible run path.
        .executeContent,
        .approvedExecution,
        .deleteConfirmation,
        // Project deletion cascades to local tasks, so the pseudo VoiceOver
        // contract keeps the project-level completion/delete path explicit
        // instead of inferring it from task CRUD coverage.
        .projectCompletion,
        .projectDeleteCascade
    ]

    public static let completeDocumentDeliverableKinds: [DocumentAutomationOutputKind] = [
        .preparationChecklist,
        .draftArtifact,
        .releaseNotes,
        .pullRequestPlan
    ]

    public static let completeTodayCockpitOperations: [SoloPMHarnessTodayCockpitOperation] = [
        .openToday,
        .captureCommand,
        .commonActions,
        .focusSuggestions,
        .localFocusAndPlanning,
        .railContext,
        .railActions
    ]

    public static func requiredFocusNodeIDs(
        for operations: [SoloPMHarnessTaskLifecycleOperation]
    ) -> [String] {
        let operationNodeIDs = Set(operations.flatMap(\.requiredFocusNodeIDs))
        // Operation order is not always VoiceOver traversal order. Keep the
        // canonical AX path as the final ordering source so the harness can
        // prove create/edit/review/run/delete without reordering focus steps.
        return AccessibilityFocusPathRequirement.taskLifecycleAndExecution.requiredNodeIDs
            .filter { operationNodeIDs.contains($0) }
    }

    public static func requiredTodayCockpitFocusNodeIDs(
        for operations: [SoloPMHarnessTodayCockpitOperation]
    ) -> [String] {
        let operationNodeIDs = Set(operations.flatMap(\.requiredFocusNodeIDs))
        // Today renders differently across horizontal and vertical layouts.
        // Filter through the canonical requirement so operation coverage does
        // not accidentally encode a layout-specific traversal order.
        return AccessibilityFocusPathRequirement.todayCockpit.requiredNodeIDs
            .filter { operationNodeIDs.contains($0) }
    }

    public func missingTaskLifecycleOperations(
        required: [SoloPMHarnessTaskLifecycleOperation] = SoloPMHarnessScenario.completeTaskLifecycleOperations
    ) -> [SoloPMHarnessTaskLifecycleOperation] {
        let covered = Set(requiredTaskLifecycleOperations)
        return required.filter { !covered.contains($0) }
    }

    public func missingTodayCockpitOperations(
        required: [SoloPMHarnessTodayCockpitOperation] = SoloPMHarnessScenario.completeTodayCockpitOperations
    ) -> [SoloPMHarnessTodayCockpitOperation] {
        let covered = Set(requiredTodayCockpitOperations)
        return required.filter { !covered.contains($0) }
    }

    public func missingDocumentDeliverableKinds(
        required: [DocumentAutomationOutputKind] = SoloPMHarnessScenario.completeDocumentDeliverableKinds
    ) -> [DocumentAutomationOutputKind] {
        required.filter { !requiredDocumentDeliverableKinds.contains($0) }
    }

    public static func templateCatalog() -> [SoloPMHarnessScenario] {
        [
            SoloPMHarnessScenario(
                id: "provider-prompt-regression",
                name: "Provider prompt regression",
                kind: .providerPromptRegression,
                requiredCapabilities: [.providerPrompt],
                expectedMutations: [
                    SyncTaskMutationPayload(
                        operation: .create,
                        title: "Draft launch checklist",
                        source: .conversation,
                        approvalState: .pendingApproval
                    )
                ],
                assertions: [.outputMatchesExpected, .approvalBoundary, .auditLogRecorded]
            ),
            SoloPMHarnessScenario(
                id: "task-mutation-flow",
                name: "Task mutation flow",
                kind: .taskMutationFlow,
                requiredCapabilities: [.taskMutation],
                expectedMutations: [
                    SyncTaskMutationPayload(
                        operation: .create,
                        title: "Capture inbox task",
                        source: .conversation,
                        approvalState: .pendingApproval
                    ),
                    SyncTaskMutationPayload(
                        taskID: 1,
                        operation: .update,
                        status: "in_progress",
                        source: .conversation,
                        approvalState: .pendingApproval
                    ),
                    SyncTaskMutationPayload(
                        taskID: 1,
                        operation: .complete,
                        status: "completed",
                        source: .conversation,
                        approvalState: .pendingApproval
                    ),
                    SyncTaskMutationPayload(
                        taskID: 1,
                        operation: .updateDueDate,
                        dueAt: "2026-06-22T09:00:00Z",
                        source: .conversation,
                        approvalState: .pendingApproval
                    ),
                    SyncTaskMutationPayload(
                        taskID: 1,
                        operation: .moveProject,
                        projectID: 10,
                        source: .conversation,
                        approvalState: .pendingApproval
                    )
                ],
                assertions: [.approvalBoundary, .auditLogRecorded, .resultDiffRecorded],
                // Delete confirmation and approved execution are lifecycle
                // requirements, not hosted-MCP mutations: external automation
                // stays review-only while the UI/AX path must still prove them.
                requiredTaskLifecycleOperations: Self.completeTaskLifecycleOperations
            ),
            SoloPMHarnessScenario(
                id: "document-scoped-automation",
                name: "Document-scoped automation",
                kind: .documentScopedAutomation,
                requiredCapabilities: [.documentAutomation],
                expectedMutations: [],
                assertions: [.approvalBoundary, .auditLogRecorded, .redactedLogs],
                // Document automation creates review artifacts, not only task
                // mutations; the harness requires every public-alpha deliverable
                // so a planner change cannot silently drop release/PR output.
                requiredDocumentDeliverableKinds: Self.completeDocumentDeliverableKinds
            ),
            SoloPMHarnessScenario(
                id: "mcp-compatibility",
                name: "MCP compatibility",
                kind: .mcpCompatibility,
                requiredCapabilities: [.mcpToolCall],
                expectedMutations: [],
                assertions: [.approvalBoundary, .auditLogRecorded, .redactedLogs, .resultDiffRecorded]
            ),
            SoloPMHarnessScenario(
                id: "mcp-pseudo-voiceover-focus-path",
                name: "MCP pseudo VoiceOver focus path",
                kind: .accessibilityFocusPath,
                requiredCapabilities: [.mcpToolCall, .accessibilityAudit],
                expectedMutations: [],
                assertions: [.outputMatchesExpected, .approvalBoundary, .auditLogRecorded, .redactedLogs, .resultDiffRecorded, .accessibilityFocusPathCovered],
                requiredTaskLifecycleOperations: Self.completeTaskLifecycleOperations,
                requiredTodayCockpitOperations: Self.completeTodayCockpitOperations
            )
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case requiredCapabilities
        case expectedMutations
        case assertions
        case requiredTaskLifecycleOperations
        case requiredTodayCockpitOperations
        case requiredDocumentDeliverableKinds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(SoloPMHarnessScenarioKind.self, forKey: .kind)
        requiredCapabilities = try container.decode([SoloPMHarnessCapability].self, forKey: .requiredCapabilities)
        expectedMutations = try container.decode([SyncTaskMutationPayload].self, forKey: .expectedMutations)
        assertions = try container.decode([SoloPMHarnessAssertion].self, forKey: .assertions)
        requiredTaskLifecycleOperations = try container.decodeIfPresent(
            [SoloPMHarnessTaskLifecycleOperation].self,
            forKey: .requiredTaskLifecycleOperations
        ) ?? []
        requiredTodayCockpitOperations = try container.decodeIfPresent(
            [SoloPMHarnessTodayCockpitOperation].self,
            forKey: .requiredTodayCockpitOperations
        ) ?? []
        requiredDocumentDeliverableKinds = try container.decodeIfPresent(
            [DocumentAutomationOutputKind].self,
            forKey: .requiredDocumentDeliverableKinds
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(requiredCapabilities, forKey: .requiredCapabilities)
        try container.encode(expectedMutations, forKey: .expectedMutations)
        try container.encode(assertions, forKey: .assertions)
        try container.encode(requiredTaskLifecycleOperations, forKey: .requiredTaskLifecycleOperations)
        try container.encode(requiredTodayCockpitOperations, forKey: .requiredTodayCockpitOperations)
        try container.encode(requiredDocumentDeliverableKinds, forKey: .requiredDocumentDeliverableKinds)
    }
}

public enum SoloPMHarnessRunTrigger: String, Codable, Equatable, Sendable {
    case local
    case cloudTriggered
}

public enum SoloPMHarnessRunStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

public struct SoloPMHarnessStepResult: Codable, Equatable, Sendable {
    public var id: String
    public var status: SoloPMHarnessRunStatus
    public var expected: String
    public var actual: String
    public var failureReason: String?
    public var durationMilliseconds: Int

    public init(
        id: String,
        status: SoloPMHarnessRunStatus,
        expected: String,
        actual: String,
        failureReason: String?,
        durationMilliseconds: Int
    ) {
        self.id = id
        self.status = status
        self.expected = expected
        self.actual = actual
        self.failureReason = failureReason
        self.durationMilliseconds = durationMilliseconds
    }
}

public enum SoloPMHarnessLogLevel: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct SoloPMHarnessLogEntry: Codable, Equatable, Sendable {
    public var level: SoloPMHarnessLogLevel
    public var message: String

    public init(level: SoloPMHarnessLogLevel, message: String) {
        self.level = level
        self.message = message
    }
}

public struct SoloPMHarnessDiff: Codable, Equatable, Sendable {
    public var stepID: String
    public var expected: String
    public var actual: String

    public init(stepID: String, expected: String, actual: String) {
        self.stepID = stepID
        self.expected = expected
        self.actual = actual
    }
}

public struct SoloPMHarnessResultShape: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var fields: [String]

    public init(schemaVersion: Int, fields: [String]) {
        self.schemaVersion = schemaVersion
        self.fields = fields
    }
}

public struct SoloPMHarnessResultEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var trigger: SoloPMHarnessRunTrigger
    public var scenarioKind: SoloPMHarnessScenarioKind
    public var status: SoloPMHarnessRunStatus
    public var stepCount: Int
    public var hasDiff: Bool
    public var hasRedactedLogs: Bool

    public init(
        schemaVersion: Int = 1,
        trigger: SoloPMHarnessRunTrigger,
        scenarioKind: SoloPMHarnessScenarioKind,
        status: SoloPMHarnessRunStatus,
        stepCount: Int,
        hasDiff: Bool,
        hasRedactedLogs: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.trigger = trigger
        self.scenarioKind = scenarioKind
        self.status = status
        self.stepCount = stepCount
        self.hasDiff = hasDiff
        self.hasRedactedLogs = hasRedactedLogs
    }

    public var shape: SoloPMHarnessResultShape {
        SoloPMHarnessResultShape(
            schemaVersion: schemaVersion,
            fields: [
                "schemaVersion",
                "trigger",
                "scenarioKind",
                "status",
                "stepCount",
                "hasDiff",
                "hasRedactedLogs"
            ]
        )
    }
}

public struct SoloPMHarnessRun: Codable, Equatable, Sendable {
    public var id: String
    public var scenario: SoloPMHarnessScenario
    public var trigger: SoloPMHarnessRunTrigger
    public var status: SoloPMHarnessRunStatus
    public var startedAt: String
    public var finishedAt: String
    public var steps: [SoloPMHarnessStepResult]
    public var diff: SoloPMHarnessDiff?
    public var failureReason: String?
    public var redactedLogs: [SoloPMHarnessLogEntry]
    public var resultEnvelope: SoloPMHarnessResultEnvelope

    public init(
        id: String,
        scenario: SoloPMHarnessScenario,
        trigger: SoloPMHarnessRunTrigger,
        status: SoloPMHarnessRunStatus,
        startedAt: String,
        finishedAt: String,
        steps: [SoloPMHarnessStepResult],
        diff: SoloPMHarnessDiff?,
        failureReason: String?,
        redactedLogs: [SoloPMHarnessLogEntry],
        resultEnvelope: SoloPMHarnessResultEnvelope
    ) {
        self.id = id
        self.scenario = scenario
        self.trigger = trigger
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.diff = diff
        self.failureReason = failureReason
        self.redactedLogs = redactedLogs
        self.resultEnvelope = resultEnvelope
    }

    public static func completed(
        id: String,
        scenario: SoloPMHarnessScenario,
        trigger: SoloPMHarnessRunTrigger,
        startedAt: String,
        finishedAt: String,
        steps: [SoloPMHarnessStepResult],
        logs: [SoloPMHarnessLogEntry]
    ) -> SoloPMHarnessRun {
        let status: SoloPMHarnessRunStatus = steps.contains { $0.status == .failed } ? .failed : .passed
        let diff = steps.first { $0.status == .failed || $0.expected != $0.actual }.map {
            SoloPMHarnessDiff(stepID: $0.id, expected: $0.expected, actual: $0.actual)
        }
        let failureReason = steps.first(where: { $0.status == .failed })?.failureReason
        let resultEnvelope = SoloPMHarnessResultEnvelope(
            trigger: trigger,
            scenarioKind: scenario.kind,
            status: status,
            stepCount: steps.count,
            hasDiff: diff != nil,
            hasRedactedLogs: !logs.isEmpty
        )

        return SoloPMHarnessRun(
            id: id,
            scenario: scenario,
            trigger: trigger,
            status: status,
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: steps,
            diff: diff,
            failureReason: failureReason,
            redactedLogs: logs,
            resultEnvelope: resultEnvelope
        )
    }

    public func redacted() -> SoloPMHarnessRun {
        let redactor = DeveloperSecretRedactor()
        let redactedSteps = steps.map {
            SoloPMHarnessStepResult(
                id: $0.id,
                status: $0.status,
                expected: redactor.redact($0.expected).text,
                actual: redactor.redact($0.actual).text,
                failureReason: $0.failureReason.map { redactor.redact($0).text },
                durationMilliseconds: $0.durationMilliseconds
            )
        }
        let redactedDiff = diff.map {
            SoloPMHarnessDiff(
                stepID: $0.stepID,
                expected: redactor.redact($0.expected).text,
                actual: redactor.redact($0.actual).text
            )
        }
        let redactedLogs = redactedLogs.map {
            SoloPMHarnessLogEntry(level: $0.level, message: redactor.redact($0.message).text)
        }

        return SoloPMHarnessRun(
            id: id,
            scenario: scenario,
            trigger: trigger,
            status: status,
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: redactedSteps,
            diff: redactedDiff,
            failureReason: failureReason.map { redactor.redact($0).text },
            redactedLogs: redactedLogs,
            resultEnvelope: resultEnvelope
        )
    }

    public var syncPayload: SyncHarnessRunPayload {
        SyncHarnessRunPayload(
            id: id,
            scenario: scenario.id,
            status: status.rawValue,
            scenarioKind: scenario.kind.rawValue,
            trigger: trigger.rawValue,
            failureReason: failureReason,
            diffSummary: diff.map { "\($0.stepID): \($0.expected) -> \($0.actual)" },
            redactedLogCount: redactedLogs.count
        )
    }
}

public struct SoloPMHarnessDocumentAutomationRunner: Sendable {
    public init() {}

    public func run(
        id: String,
        trigger: SoloPMHarnessRunTrigger,
        startedAt: String,
        finishedAt: String,
        drafts: [DocumentAutomationDeliverableDraft],
        requiredKinds: [DocumentAutomationOutputKind] = SoloPMHarnessScenario.completeDocumentDeliverableKinds
    ) -> SoloPMHarnessRun {
        let scenario = Self.documentAutomationScenario()
        // Emit one step per deliverable kind so a broad "docs automation passed"
        // smoke cannot hide a missing release note, PR plan, or draft artifact.
        let kindSteps = requiredKinds.map { kind in
            step(for: kind, drafts: drafts.filter { $0.kind == kind })
        }
        let steps = kindSteps + [uniqueSuggestedPathStep(for: drafts)]
        let coveredCount = kindSteps.filter { $0.status == .passed }.count
        let logs = [
            SoloPMHarnessLogEntry(
                level: coveredCount == requiredKinds.count ? .info : .error,
                message: "Document automation deliverables covered=\(coveredCount)/\(requiredKinds.count)"
            )
        ] + steps.compactMap { step in
            step.failureReason.map {
                SoloPMHarnessLogEntry(level: .warning, message: $0)
            }
        }

        return SoloPMHarnessRun.completed(
            id: id,
            scenario: scenario,
            trigger: trigger,
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: steps,
            logs: logs
        )
    }

    private static func documentAutomationScenario() -> SoloPMHarnessScenario {
        SoloPMHarnessScenario.templateCatalog()
            .first(where: { $0.kind == .documentScopedAutomation })
            ?? SoloPMHarnessScenario(
                id: "document-scoped-automation",
                name: "Document-scoped automation",
                kind: .documentScopedAutomation,
                requiredCapabilities: [.documentAutomation],
                expectedMutations: [],
                assertions: [.approvalBoundary, .auditLogRecorded, .redactedLogs],
                requiredDocumentDeliverableKinds: SoloPMHarnessScenario.completeDocumentDeliverableKinds
            )
    }

    private func step(
        for kind: DocumentAutomationOutputKind,
        drafts: [DocumentAutomationDeliverableDraft]
    ) -> SoloPMHarnessStepResult {
        let expected = "reviewable document deliverable draft present"
        let actual: String
        let status: SoloPMHarnessRunStatus
        let failureReason: String?

        if let draft = drafts.first {
            let problems = reviewProblems(for: draft)
            if problems.isEmpty {
                actual = expected
                status = .passed
                failureReason = nil
            } else {
                actual = problems.joined(separator: " | ")
                status = .failed
                failureReason = actual
            }
        } else {
            actual = "missingDocumentDeliverable: Missing required document deliverable \(kind.rawValue)."
            status = .failed
            failureReason = actual
        }

        return SoloPMHarnessStepResult(
            id: "document-deliverable-\(kind.rawValue)",
            status: status,
            expected: expected,
            actual: actual,
            failureReason: failureReason,
            durationMilliseconds: 0
        )
    }

    private func uniqueSuggestedPathStep(
        for drafts: [DocumentAutomationDeliverableDraft]
    ) -> SoloPMHarnessStepResult {
        let expected = "one reviewable document deliverable per suggested output path"
        let collisions = duplicateSuggestedPathDescriptions(in: drafts)
        let actual: String
        let status: SoloPMHarnessRunStatus
        let failureReason: String?

        if collisions.isEmpty {
            actual = expected
            status = .passed
            failureReason = nil
        } else {
            actual = collisions.joined(separator: " | ")
            status = .failed
            failureReason = actual
        }

        return SoloPMHarnessStepResult(
            id: "document-deliverable-unique-suggested-paths",
            status: status,
            expected: expected,
            actual: actual,
            failureReason: failureReason,
            durationMilliseconds: 0
        )
    }

    private func duplicateSuggestedPathDescriptions(
        in drafts: [DocumentAutomationDeliverableDraft]
    ) -> [String] {
        var firstKindByPath: [String: DocumentAutomationOutputKind] = [:]
        var descriptions: [String] = []

        for draft in drafts {
            let normalizedPath = normalizedSuggestedPath(draft.suggestedPath)
            guard !normalizedPath.isEmpty else {
                descriptions.append("missingSuggestedPath: \(draft.kind.rawValue) must name a reviewable draft output path.")
                continue
            }
            if let firstKind = firstKindByPath[normalizedPath] {
                descriptions.append(
                    "duplicateSuggestedPath: \(firstKind.rawValue) and \(draft.kind.rawValue) target \(normalizedPath)."
                )
            } else {
                firstKindByPath[normalizedPath] = draft.kind
            }
        }

        return descriptions
    }

    private func normalizedSuggestedPath(_ path: String) -> String {
        // A document automation run is not complete if two reviewed drafts can
        // ask the downstream provider to write the same file. Normalize only
        // enough to catch whitespace, repeated slash, trailing slash, and case
        // drift while preserving absolute-vs-relative path intent.
        let collapsed = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
        guard collapsed != "/" else {
            return collapsed
        }
        return (collapsed.hasSuffix("/") ? String(collapsed.dropLast()) : collapsed).lowercased()
    }

    private func reviewProblems(for draft: DocumentAutomationDeliverableDraft) -> [String] {
        var problems: [String] = []
        if !draft.requiresApproval {
            problems.append("missingApprovalGate: \(draft.kind.rawValue) must require review before write.")
        }
        if draft.sourceDocumentIDs.isEmpty {
            problems.append("missingSourceDocuments: \(draft.kind.rawValue) must cite selected documents.")
        }
        // IDs alone do not prove that the reviewer or provider saw the right
        // source evidence; every deliverable must carry matching redacted
        // previews so document-backed artifacts stay auditable.
        problems.append(contentsOf: sourcePreviewProblems(for: draft))
        if draft.riskLevel < .draft {
            problems.append("riskTooLow: \(draft.kind.rawValue) must be at least draft risk.")
        }
        return problems
    }

    private func sourcePreviewProblems(for draft: DocumentAutomationDeliverableDraft) -> [String] {
        guard !draft.sourceDocumentIDs.isEmpty else {
            return []
        }

        var problems: [String] = []
        if draft.sourceDocuments.isEmpty {
            problems.append("missingSourcePreviews: \(draft.kind.rawValue) must include a redacted source preview for every cited source document.")
            return problems
        }

        let requiredIDs = Set(draft.sourceDocumentIDs.map(trimmed))
        let previewIDs = Set(draft.sourceDocuments.map(\.id).map(trimmed).filter { !$0.isEmpty })
        if !requiredIDs.isSubset(of: previewIDs) {
            problems.append("missingSourcePreviews: \(draft.kind.rawValue) must include a redacted source preview for every cited source document.")
        }

        if draft.sourceDocuments.contains(where: hasIncompleteSourcePreview) {
            problems.append("incompleteSourcePreview: \(draft.kind.rawValue) source previews must include title, redacted summary, and inclusion reason.")
        }

        let redactor = DeveloperSecretRedactor()
        let remainingSecretCount = draft.sourceDocuments.reduce(0) { count, source in
            count
                + redactor.redact(source.id).report.replacementCount
                + redactor.redact(source.title).report.replacementCount
                + redactor.redact(source.redactedSummary).report.replacementCount
                + redactor.redact(source.inclusionReason).report.replacementCount
        }
        if remainingSecretCount > 0 {
            problems.append("unredactedSourcePreviewSecret: \(draft.kind.rawValue) source previews still contain secret-like content.")
        }

        return problems
    }

    private func hasIncompleteSourcePreview(_ source: DocumentAutomationDeliverableSource) -> Bool {
        trimmed(source.title).isEmpty ||
            trimmed(source.redactedSummary).isEmpty ||
            trimmed(source.inclusionReason).isEmpty
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SoloPMHarnessAccessibilityAuditRunner: Sendable {
    public init() {}

    public func run(
        id: String,
        trigger: SoloPMHarnessRunTrigger,
        startedAt: String,
        finishedAt: String,
        nodes: [AccessibilityNodeSnapshot],
        approvedExecutionReceipt: ApprovedAutomationExecutionReceipt? = nil,
        requirements: AccessibilityFocusPathRequirement = .taskLifecycleAndExecution
    ) -> SoloPMHarnessRun {
        let scenario = Self.accessibilityScenario()
        let result = AccessibilityFocusPathAudit().audit(nodes: nodes, requirements: requirements)
        // Runtime AX snapshots can report dynamic IDs or whole-snapshot ID
        // defects. Map them back into harness steps so a complete-looking
        // required path cannot hide an untargetable MCP/VoiceOver node.
        let findingsByNodeID = Dictionary(
            grouping: result.findings.compactMap { finding -> (String, AccessibilityFocusPathFinding)? in
                guard let reportingNodeID = reportingNodeID(for: finding.nodeID, requirements: requirements) else {
                    return nil
                }
                return (reportingNodeID, finding)
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
        let snapshotFindingSteps = result.findings
            .filter { reportingNodeID(for: $0.nodeID, requirements: requirements) == nil }
            .map(snapshotStep)

        // Emit one harness step per required focus node so a broad MCP smoke
        // cannot hide one missing create/edit/execute/delete control behind a
        // single aggregate "accessibility passed" line.
        let focusSteps = requirements.requiredNodeIDs.map { nodeID in
            step(for: nodeID, findings: findingsByNodeID[nodeID] ?? [], coveredNodeIDs: result.coveredRequiredNodeIDs)
        }
        let receiptSteps = requirements.requiredNodeIDs.contains("task-auto-execution-run-plan")
            ? [approvedExecutionReceiptStep(approvedExecutionReceipt)]
            : []
        let steps = focusSteps + snapshotFindingSteps + receiptSteps
        let receiptCoveredCount = receiptSteps.filter { $0.status == .passed }.count
        let logs = [
            SoloPMHarnessLogEntry(
                level: result.findings.isEmpty ? .info : .error,
                message: "MCP pseudo VoiceOver focus path covered=\(result.coveredRequiredNodeIDs.count)/\(requirements.requiredNodeIDs.count) findings=\(result.findings.count)"
            )
        ] + (receiptSteps.isEmpty ? [] : [
            SoloPMHarnessLogEntry(
                level: receiptCoveredCount == receiptSteps.count ? .info : .error,
                message: "MCP pseudo VoiceOver approved execution receipt covered=\(receiptCoveredCount)/\(receiptSteps.count)"
            )
        ]) + result.findings.map {
            SoloPMHarnessLogEntry(level: .warning, message: "\($0.kind.rawValue): \($0.message)")
        } + receiptSteps.compactMap { step in
            step.failureReason.map {
                SoloPMHarnessLogEntry(level: .warning, message: $0)
            }
        }

        return SoloPMHarnessRun.completed(
            id: id,
            scenario: scenario,
            trigger: trigger,
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: steps,
            logs: logs
        )
    }

    private func reportingNodeID(
        for nodeID: String,
        requirements: AccessibilityFocusPathRequirement
    ) -> String? {
        if requirements.requiredNodeIDs.contains(nodeID) {
            return nodeID
        }

        return requirements.dynamicRequiredNodeIDPrefixes
            .first { nodeID.hasPrefix("\($0)-") }
    }

    private func snapshotStep(
        for finding: AccessibilityFocusPathFinding
    ) -> SoloPMHarnessStepResult {
        let expected = "focus path snapshot has targetable and unique accessibility identifiers"
        let actual = "\(finding.kind.rawValue): \(finding.message)"

        return SoloPMHarnessStepResult(
            id: "focus-path-snapshot-\(finding.kind.rawValue)",
            status: .failed,
            expected: expected,
            actual: actual,
            failureReason: actual,
            durationMilliseconds: 0
        )
    }

    private static func accessibilityScenario() -> SoloPMHarnessScenario {
        SoloPMHarnessScenario.templateCatalog()
            .first(where: { $0.kind == .accessibilityFocusPath })
            ?? SoloPMHarnessScenario(
                id: "mcp-pseudo-voiceover-focus-path",
                name: "MCP pseudo VoiceOver focus path",
                kind: .accessibilityFocusPath,
                requiredCapabilities: [.mcpToolCall, .accessibilityAudit],
                expectedMutations: [],
                assertions: [.accessibilityFocusPathCovered],
                requiredTaskLifecycleOperations: SoloPMHarnessScenario.completeTaskLifecycleOperations,
                requiredTodayCockpitOperations: SoloPMHarnessScenario.completeTodayCockpitOperations
            )
    }

    private func step(
        for nodeID: String,
        findings: [AccessibilityFocusPathFinding],
        coveredNodeIDs: [String]
    ) -> SoloPMHarnessStepResult {
        let expected = "required focus path node present and descriptive"
        let actual: String
        let status: SoloPMHarnessRunStatus
        let failureReason: String?

        if findings.isEmpty, coveredNodeIDs.contains(nodeID) {
            actual = expected
            status = .passed
            failureReason = nil
        } else {
            actual = findings.isEmpty
                ? "missingRequiredNode: Missing required accessibility node \(nodeID)."
                : findings.map { "\($0.kind.rawValue): \($0.message)" }.joined(separator: " | ")
            status = .failed
            failureReason = actual
        }

        return SoloPMHarnessStepResult(
            id: "focus-path-\(nodeID)",
            status: status,
            expected: expected,
            actual: actual,
            failureReason: failureReason,
            durationMilliseconds: 0
        )
    }

    private func approvedExecutionReceiptStep(
        _ receipt: ApprovedAutomationExecutionReceipt?
    ) -> SoloPMHarnessStepResult {
        let expected = "redacted approved automation execution receipt present"
        let status: SoloPMHarnessRunStatus
        let actual: String
        let failureReason: String?

        if let receipt {
            let problems = approvedExecutionReceiptProblems(receipt)
            if problems.isEmpty {
                status = .passed
                actual = expected
                failureReason = nil
            } else {
                status = .failed
                actual = problems.joined(separator: " | ")
                failureReason = actual
            }
        } else {
            status = .failed
            actual = "missingApprovedExecutionReceipt: Run approved plan must emit a redacted execution receipt."
            failureReason = actual
        }

        return SoloPMHarnessStepResult(
            id: "approved-execution-receipt",
            status: status,
            expected: expected,
            actual: actual,
            failureReason: failureReason,
            durationMilliseconds: 0
        )
    }

    private func approvedExecutionReceiptProblems(
        _ receipt: ApprovedAutomationExecutionReceipt
    ) -> [String] {
        var problems: [String] = []
        if receipt.taskID <= 0 {
            problems.append("missingTaskID: approved execution receipt must include the local task id.")
        }
        if receipt.projectID <= 0 {
            problems.append("missingProjectID: approved execution receipt must include the local project id.")
        }
        if receipt.statusBefore == receipt.statusAfter {
            problems.append("statusDidNotChange: approved execution receipt must record a before/after task status transition.")
        }
        if receipt.statusAfter != .inProgress {
            problems.append("unexpectedStatusAfter: first approved local execution should move the task into active work.")
        }
        if receipt.redactedTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("missingTaskTitle: approved execution receipt must include the reviewed task title.")
        }
        // A title-only receipt cannot prove the reviewed task content was executed.
        if receipt.redactedTaskDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("missingTaskDetail: approved execution receipt must include the reviewed task detail.")
        }
        if receipt.reviewReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("missingReviewReason: approved execution receipt must include the review reason.")
        }

        let redactor = DeveloperSecretRedactor()
        let remainingSecretCount = [
            receipt.redactedTaskTitle,
            receipt.redactedTaskDetail,
            receipt.reviewReason
        ].reduce(0) { count, value in
            count + redactor.redact(value).report.replacementCount
        }
        if remainingSecretCount > 0 {
            problems.append("unredactedSecret: approved execution receipt still contains secret-like content.")
        }

        return problems
    }
}

public enum SoloPMHarnessHistoryStorage: String, Codable, Equatable, Sendable {
    case disabled
    case cloudBacked
    case extendedCloudBacked
}

public struct SoloPMHarnessRetentionPolicy: Codable, Equatable, Sendable {
    public var requiredFeature: FeatureGate
    public var historyStorage: SoloPMHarnessHistoryStorage
    public var maxRuns: Int
    public var retentionDays: Int

    public init(
        requiredFeature: FeatureGate,
        historyStorage: SoloPMHarnessHistoryStorage,
        maxRuns: Int,
        retentionDays: Int
    ) {
        self.requiredFeature = requiredFeature
        self.historyStorage = historyStorage
        self.maxRuns = maxRuns
        self.retentionDays = retentionDays
    }

    public static func policy(for plan: SubscriptionPlan) -> SoloPMHarnessRetentionPolicy {
        switch plan {
        case .free, .sync:
            SoloPMHarnessRetentionPolicy(
                requiredFeature: .harnessHistory,
                historyStorage: .disabled,
                maxRuns: 0,
                retentionDays: 0
            )
        case .pro:
            SoloPMHarnessRetentionPolicy(
                requiredFeature: .harnessHistory,
                historyStorage: .cloudBacked,
                maxRuns: 250,
                retentionDays: 30
            )
        case .founder:
            SoloPMHarnessRetentionPolicy(
                requiredFeature: .harnessHistory,
                historyStorage: .extendedCloudBacked,
                maxRuns: 1_000,
                retentionDays: 365
            )
        }
    }
}

public enum SoloPMHarnessRunStoreError: Error, Equatable, Sendable {
    case historyDisabled(requiredPlan: SubscriptionPlan)
}

public struct RedactingSoloPMHarnessRunStore: Sendable {
    public private(set) var runs: [SoloPMHarnessRun]

    public init(runs: [SoloPMHarnessRun] = []) {
        self.runs = runs
    }

    public mutating func save(_ run: SoloPMHarnessRun, plan: SubscriptionPlan) throws {
        let policy = SoloPMHarnessRetentionPolicy.policy(for: plan)
        guard policy.historyStorage != .disabled, policy.maxRuns > 0 else {
            throw SoloPMHarnessRunStoreError.historyDisabled(requiredPlan: policy.requiredFeature.requiredPlan)
        }

        // Harness output is designed for repeatable debugging, but provider and
        // MCP failures often echo credentials; storage always receives redacted runs.
        runs.append(run.redacted())
        if runs.count > policy.maxRuns {
            runs.removeFirst(runs.count - policy.maxRuns)
        }
    }
}
