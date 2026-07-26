import CryptoKit
import Foundation

public struct VoiceTaskContextBudget: Equatable, Sendable {
    public var maximumTurns: Int
    public var maximumCharacters: Int

    public init(maximumTurns: Int, maximumCharacters: Int) {
        self.maximumTurns = maximumTurns
        self.maximumCharacters = maximumCharacters
    }
}

public enum VoiceTaskContextAssemblyError: Error, Equatable, Sendable {
    case invalidBudget
    case invalidScope
    case insufficientCharacterBudget(minimum: Int)
    case serializationFailed
}

public enum VoiceTaskContextScope: Equatable, Sendable {
    case project(Int64)
    case task(id: Int64, projectID: Int64?)
}

public struct VoiceTaskContextScopeIdentity: Codable, Equatable, Sendable {
    public var kind: String
    public var projectID: Int64?
    public var taskID: Int64?

    public init(kind: String, projectID: Int64?, taskID: Int64?) {
        self.kind = kind
        self.projectID = projectID
        self.taskID = taskID
    }
}

public enum VoiceTaskContextTurnKind: String, Codable, Equatable, Sendable {
    case userConfirmed = "user_confirmed"
    case assistantResponse = "assistant_response"
}

public struct VoiceTaskContextTurn: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let scope: VoiceTaskContextScope
    public let kind: VoiceTaskContextTurnKind
    public let text: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        scope: VoiceTaskContextScope,
        kind: VoiceTaskContextTurnKind,
        text: String,
        createdAt: Date
    ) {
        self.id = id
        self.scope = scope
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
    }
}

public struct VoiceTaskContextActionPlan: Equatable, Sendable {
    public let id: String
    public let scope: VoiceTaskContextScope
    public let summary: String
    public let createdAt: Date

    public init(
        id: String,
        scope: VoiceTaskContextScope,
        summary: String,
        createdAt: Date
    ) {
        self.id = id
        self.scope = scope
        self.summary = summary
        self.createdAt = createdAt
    }
}

public struct VoiceTaskContextInput: Equatable, Sendable {
    public var scope: VoiceTaskContextScope
    public var turns: [VoiceTaskContextTurn]
    public var facts: [TaskContextFact]
    public var tasks: [TaskRecord]
    public var currentActionPlan: VoiceTaskContextActionPlan?
    public var providerNeeded: Bool
    public var referenceDate: Date

    public init(
        scope: VoiceTaskContextScope,
        turns: [VoiceTaskContextTurn],
        facts: [TaskContextFact],
        tasks: [TaskRecord],
        currentActionPlan: VoiceTaskContextActionPlan?,
        providerNeeded: Bool,
        referenceDate: Date
    ) {
        self.scope = scope
        self.turns = turns
        self.facts = facts
        self.tasks = tasks
        self.currentActionPlan = currentActionPlan
        self.providerNeeded = providerNeeded
        self.referenceDate = referenceDate
    }
}

public enum VoiceTaskContextSourceKind: String, Codable, Equatable, Sendable {
    case turn
    case fact
    case task
    case actionPlan = "action_plan"
}

public enum VoiceTaskContextExclusionReason: String, Codable, Equatable, Hashable, Sendable {
    case outsideScope = "outside_scope"
    case emptyContent = "empty_content"
    case factNotConfirmed = "fact_not_confirmed"
    case factExpired = "fact_expired"
    case factUnverified = "fact_unverified"
    case factNoLongerCurrent = "fact_no_longer_current"
    case duplicateSource = "duplicate_source"
    case turnBudgetExceeded = "turn_budget_exceeded"
    case characterBudgetExceeded = "character_budget_exceeded"
    case providerNotNeeded = "provider_not_needed"
}

public struct VoiceTaskContextExclusion: Codable, Equatable, Sendable {
    public var sourceID: String
    public var sourceKind: VoiceTaskContextSourceKind
    public var reason: VoiceTaskContextExclusionReason

    public init(
        sourceID: String,
        sourceKind: VoiceTaskContextSourceKind,
        reason: VoiceTaskContextExclusionReason
    ) {
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.reason = reason
    }
}

public struct VoiceTaskProviderContext: Equatable, Sendable {
    public let scopeIdentity: VoiceTaskContextScopeIdentity
    public let selectedSourceIDs: [String]
    /// Valid, sorted-key JSON. This remains separate from the system message so
    /// user-authored task detail cannot become an instruction by concatenation.
    public let json: String
    public let characterCount: Int

    fileprivate init(
        scopeIdentity: VoiceTaskContextScopeIdentity,
        selectedSourceIDs: [String],
        json: String,
        characterCount: Int
    ) {
        self.scopeIdentity = scopeIdentity
        self.selectedSourceIDs = selectedSourceIDs
        self.json = json
        self.characterCount = characterCount
    }

    public var fencedJSON: String {
        let fenceSafeJSON = json.replacingOccurrences(of: "`", with: "\\u0060")
        return "```json\n\(fenceSafeJSON)\n```"
    }
}

public struct VoiceTaskContextAssembly: Equatable, Sendable {
    public var scopeIdentity: VoiceTaskContextScopeIdentity
    public var selectedSourceIDs: [String]
    public var exclusions: [VoiceTaskContextExclusion]
    public var providerContext: VoiceTaskProviderContext?
    public var includedTurnCount: Int
    public var includedFactCount: Int
    public var includedTaskCount: Int
    public var includedActionPlanCount: Int
    public var characterCount: Int
    public var isTruncated: Bool

    public init(
        scopeIdentity: VoiceTaskContextScopeIdentity,
        selectedSourceIDs: [String],
        exclusions: [VoiceTaskContextExclusion],
        providerContext: VoiceTaskProviderContext?,
        includedTurnCount: Int,
        includedFactCount: Int,
        includedTaskCount: Int,
        includedActionPlanCount: Int,
        characterCount: Int,
        isTruncated: Bool
    ) {
        self.scopeIdentity = scopeIdentity
        self.selectedSourceIDs = selectedSourceIDs
        self.exclusions = exclusions
        self.providerContext = providerContext
        self.includedTurnCount = includedTurnCount
        self.includedFactCount = includedFactCount
        self.includedTaskCount = includedTaskCount
        self.includedActionPlanCount = includedActionPlanCount
        self.characterCount = characterCount
        self.isTruncated = isTruncated
    }

    public var redactedFencedJSON: String? {
        providerContext?.fencedJSON
    }
}

public struct VoiceTaskContextAssembler: Sendable {
    private let redactor: ExecutionReceiptRedactor

    public init(
        redactor: ExecutionReceiptRedactor = ExecutionReceiptRedactor()
    ) {
        self.redactor = redactor
    }

    public func assemble(
        _ input: VoiceTaskContextInput,
        budget: VoiceTaskContextBudget
    ) throws -> VoiceTaskContextAssembly {
        guard budget.maximumTurns > 0, budget.maximumCharacters > 0 else {
            throw VoiceTaskContextAssemblyError.invalidBudget
        }
        let scopeIdentity = try identity(for: input.scope)

        guard input.providerNeeded else {
            return VoiceTaskContextAssembly(
                scopeIdentity: scopeIdentity,
                selectedSourceIDs: [],
                exclusions: providerNotNeededExclusions(input),
                providerContext: nil,
                includedTurnCount: 0,
                includedFactCount: 0,
                includedTaskCount: 0,
                includedActionPlanCount: 0,
                characterCount: 0,
                isTruncated: false
            )
        }

        var exclusions: [VoiceTaskContextExclusion] = []
        var turns = scopedTurns(input.turns, currentScope: input.scope, exclusions: &exclusions)
        var facts = scopedFacts(
            input.facts,
            currentScope: input.scope,
            referenceDate: input.referenceDate,
            exclusions: &exclusions
        )
        var tasks = scopedTasks(input.tasks, currentScope: input.scope, exclusions: &exclusions)
        var actionPlan = scopedActionPlan(
            input.currentActionPlan,
            currentScope: input.scope,
            exclusions: &exclusions
        )

        let currentConfirmedTurnID = turns
            .filter { $0.kind == .userConfirmed }
            .max(by: stableTurnLessThan)?
            .id
        if turns.count > budget.maximumTurns {
            let selectedIDs = selectedTurnIDs(
                from: turns,
                maximumTurns: budget.maximumTurns,
                protectedTurnID: currentConfirmedTurnID
            )
            let removed = turns.filter { !selectedIDs.contains($0.id) }
            exclusions.append(contentsOf: removed.map {
                exclusion(for: $0, reason: .turnBudgetExceeded)
            })
            turns.removeAll { !selectedIDs.contains($0.id) }
        }

        var payload = makePayload(
            scopeIdentity: scopeIdentity,
            turns: turns,
            facts: facts,
            tasks: tasks,
            actionPlan: actionPlan
        )
        var json = try serialize(payload)
        let minimumJSON = try serialize(
            makePayload(
                scopeIdentity: scopeIdentity,
                turns: [],
                facts: [],
                tasks: [],
                actionPlan: nil
            )
        )
        guard minimumJSON.count <= budget.maximumCharacters else {
            throw VoiceTaskContextAssemblyError.insufficientCharacterBudget(
                minimum: minimumJSON.count
            )
        }

        while json.count > budget.maximumCharacters {
            if let removalIndex = unprotectedTurnRemovalIndex(
                in: turns,
                protectedTurnID: currentConfirmedTurnID
            ) {
                exclusions.append(
                    exclusion(
                        for: turns.remove(at: removalIndex),
                        reason: .characterBudgetExceeded
                    )
                )
            } else if !tasks.isEmpty {
                let removed = tasks.removeLast()
                exclusions.append(
                    VoiceTaskContextExclusion(
                        sourceID: taskSourceID(removed.id),
                        sourceKind: .task,
                        reason: .characterBudgetExceeded
                    )
                )
            } else if !facts.isEmpty {
                let removed = facts.removeFirst()
                exclusions.append(
                    VoiceTaskContextExclusion(
                        sourceID: removed.id.uuidString,
                        sourceKind: .fact,
                        reason: .characterBudgetExceeded
                    )
                )
            } else if let removed = actionPlan {
                actionPlan = nil
                exclusions.append(
                    VoiceTaskContextExclusion(
                        sourceID: actionPlanSourceID(removed.id),
                        sourceKind: .actionPlan,
                        reason: .characterBudgetExceeded
                    )
                )
            } else if let removalIndex = turns.indices.first {
                exclusions.append(
                    exclusion(
                        for: turns.remove(at: removalIndex),
                        reason: .characterBudgetExceeded
                    )
                )
            } else {
                throw VoiceTaskContextAssemblyError.insufficientCharacterBudget(
                    minimum: minimumJSON.count
                )
            }

            payload = makePayload(
                scopeIdentity: scopeIdentity,
                turns: turns,
                facts: facts,
                tasks: tasks,
                actionPlan: actionPlan
            )
            json = try serialize(payload)
        }

        let turnSourceIDs = turns.map { $0.id.uuidString }
        let factSourceIDs = facts.map { $0.id.uuidString }
        let taskSourceIDs = tasks.map { taskSourceID($0.id) }
        let actionPlanSourceIDs = actionPlan.map {
            [actionPlanSourceID($0.id)]
        } ?? []
        let selectedSourceIDs =
            turnSourceIDs + factSourceIDs + taskSourceIDs + actionPlanSourceIDs
        let stableExclusions = exclusions.sorted(by: stableExclusionLessThan)
        let providerContext = VoiceTaskProviderContext(
            scopeIdentity: scopeIdentity,
            selectedSourceIDs: selectedSourceIDs,
            json: json,
            characterCount: json.count
        )
        return VoiceTaskContextAssembly(
            scopeIdentity: scopeIdentity,
            selectedSourceIDs: selectedSourceIDs,
            exclusions: stableExclusions,
            providerContext: providerContext,
            includedTurnCount: turns.count,
            includedFactCount: facts.count,
            includedTaskCount: tasks.count,
            includedActionPlanCount: actionPlan == nil ? 0 : 1,
            characterCount: json.count,
            isTruncated: stableExclusions.contains {
                [.turnBudgetExceeded, .characterBudgetExceeded].contains($0.reason)
            }
        )
    }

    private func identity(
        for scope: VoiceTaskContextScope
    ) throws -> VoiceTaskContextScopeIdentity {
        switch scope {
        case .project(let projectID):
            guard projectID > 0 else {
                throw VoiceTaskContextAssemblyError.invalidScope
            }
            return VoiceTaskContextScopeIdentity(
                kind: "project",
                projectID: projectID,
                taskID: nil
            )
        case .task(let taskID, let projectID):
            guard taskID > 0, projectID.map({ $0 > 0 }) ?? true else {
                throw VoiceTaskContextAssemblyError.invalidScope
            }
            return VoiceTaskContextScopeIdentity(
                kind: "task",
                projectID: projectID,
                taskID: taskID
            )
        }
    }

    private func scopedTurns(
        _ candidates: [VoiceTaskContextTurn],
        currentScope: VoiceTaskContextScope,
        exclusions: inout [VoiceTaskContextExclusion]
    ) -> [VoiceTaskContextTurn] {
        var selectedByID: [UUID: VoiceTaskContextTurn] = [:]
        for turn in candidates.sorted(by: stableTurnLessThan) {
            guard scope(turn.scope, isIncludedIn: currentScope) else {
                exclusions.append(exclusion(for: turn, reason: .outsideScope))
                continue
            }
            guard !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                exclusions.append(exclusion(for: turn, reason: .emptyContent))
                continue
            }
            if let previous = selectedByID.updateValue(turn, forKey: turn.id) {
                exclusions.append(exclusion(for: previous, reason: .duplicateSource))
            }
        }
        return selectedByID.values.sorted(by: stableTurnLessThan)
    }

    private func scopedFacts(
        _ candidates: [TaskContextFact],
        currentScope: VoiceTaskContextScope,
        referenceDate: Date,
        exclusions: inout [VoiceTaskContextExclusion]
    ) -> [TaskContextFact] {
        let scopedCandidates = candidates
            .sorted(by: stableFactLessThan)
            .filter { fact in
                guard scope(fact.scope, isIncludedIn: currentScope) else {
                    exclusions.append(exclusion(for: fact, reason: .outsideScope))
                    return false
                }
                return true
            }
        let noLongerCurrentIDs = Set(
            scopedCandidates.compactMap { fact -> UUID? in
                guard [.confirmed, .superseded, .retracted, .expired].contains(fact.state) else {
                    return nil
                }
                return fact.supersedesFactID
            }
        )
        var selected: [TaskContextFact] = []
        for fact in scopedCandidates {
            guard fact.state == .confirmed else {
                exclusions.append(exclusion(for: fact, reason: .factNotConfirmed))
                continue
            }
            guard fact.sourceEvidenceVerified else {
                exclusions.append(exclusion(for: fact, reason: .factUnverified))
                continue
            }
            guard fact.expiresAt.map({ referenceDate < $0 }) ?? true else {
                exclusions.append(exclusion(for: fact, reason: .factExpired))
                continue
            }
            guard !noLongerCurrentIDs.contains(fact.id) else {
                exclusions.append(exclusion(for: fact, reason: .factNoLongerCurrent))
                continue
            }
            selected.append(fact)
        }
        return selected
    }

    private func scopedTasks(
        _ candidates: [TaskRecord],
        currentScope: VoiceTaskContextScope,
        exclusions: inout [VoiceTaskContextExclusion]
    ) -> [TaskRecord] {
        var selected: [TaskRecord] = []
        for task in candidates.sorted(by: { $0.id < $1.id }) {
            guard taskIsIncluded(task, in: currentScope) else {
                exclusions.append(
                    VoiceTaskContextExclusion(
                        sourceID: taskSourceID(task.id),
                        sourceKind: .task,
                        reason: .outsideScope
                    )
                )
                continue
            }
            selected.append(task)
        }
        return selected
    }

    private func scopedActionPlan(
        _ candidate: VoiceTaskContextActionPlan?,
        currentScope: VoiceTaskContextScope,
        exclusions: inout [VoiceTaskContextExclusion]
    ) -> VoiceTaskContextActionPlan? {
        guard let candidate else {
            return nil
        }
        guard scope(candidate.scope, isIncludedIn: currentScope) else {
            exclusions.append(
                VoiceTaskContextExclusion(
                    sourceID: actionPlanSourceID(candidate.id),
                    sourceKind: .actionPlan,
                    reason: .outsideScope
                )
            )
            return nil
        }
        guard !candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            exclusions.append(
                VoiceTaskContextExclusion(
                    sourceID: actionPlanSourceID(candidate.id),
                    sourceKind: .actionPlan,
                    reason: .emptyContent
                )
            )
            return nil
        }
        return candidate
    }

    private func scope(
        _ candidate: VoiceTaskContextScope,
        isIncludedIn current: VoiceTaskContextScope
    ) -> Bool {
        switch (current, candidate) {
        case let (.project(currentProject), .project(candidateProject)):
            currentProject == candidateProject
        case let (
            .project(currentProject),
            .task(_, candidateProject)
        ):
            candidateProject == currentProject
        case let (
            .task(currentTask, currentProject),
            .task(candidateTask, candidateProject)
        ):
            currentTask == candidateTask
                && (currentProject == nil || currentProject == candidateProject)
        case let (
            .task(_, currentProject),
            .project(candidateProject)
        ):
            currentProject == candidateProject
        }
    }

    private func scope(
        _ candidate: TaskContextFactScope,
        isIncludedIn current: VoiceTaskContextScope
    ) -> Bool {
        switch (current, candidate) {
        case let (.project(currentProject), .project(candidateProject)):
            currentProject == candidateProject
        case let (.task(_, currentProject), .project(candidateProject)):
            currentProject == candidateProject
        case let (.task(currentTask, _), .task(candidateTask)):
            currentTask == candidateTask
        case (.project, .task), (_, .session):
            false
        }
    }

    private func taskIsIncluded(
        _ task: TaskRecord,
        in scope: VoiceTaskContextScope
    ) -> Bool {
        switch scope {
        case .project(let projectID):
            task.projectID == projectID
        case .task(let taskID, let projectID):
            task.id == taskID
                && (projectID == nil || task.projectID == projectID)
        }
    }

    private func selectedTurnIDs(
        from turns: [VoiceTaskContextTurn],
        maximumTurns: Int,
        protectedTurnID: UUID?
    ) -> Set<UUID> {
        var selected: Set<UUID> = []
        if let protectedTurnID {
            selected.insert(protectedTurnID)
        }
        for turn in turns.reversed() where selected.count < maximumTurns {
            selected.insert(turn.id)
        }
        return selected
    }

    private func unprotectedTurnRemovalIndex(
        in turns: [VoiceTaskContextTurn],
        protectedTurnID: UUID?
    ) -> Int? {
        turns.firstIndex { $0.id != protectedTurnID }
    }

    private func makePayload(
        scopeIdentity: VoiceTaskContextScopeIdentity,
        turns: [VoiceTaskContextTurn],
        facts: [TaskContextFact],
        tasks: [TaskRecord],
        actionPlan: VoiceTaskContextActionPlan?
    ) -> ProviderPayload {
        ProviderPayload(
            scope: scopeIdentity,
            turns: turns.map {
                ProviderTurn(
                    id: $0.id.uuidString,
                    kind: $0.kind.rawValue,
                    text: redactor.redact($0.text)
                )
            },
            facts: facts.map {
                ProviderFact(
                    id: $0.id.uuidString,
                    kind: $0.kind.rawValue,
                    value: redactor.redact($0.value)
                )
            },
            tasks: tasks.map {
                ProviderTask(
                    id: $0.id,
                    projectID: $0.projectID,
                    title: redactor.redact($0.title, maxLength: 300),
                    detail: $0.detail.map { redactor.redact($0) }
                )
            },
            actionPlan: actionPlan.map {
                ProviderActionPlan(
                    id: actionPlanSourceID($0.id),
                    summary: redactor.redact($0.summary)
                )
            }
        )
    }

    private func serialize(_ payload: ProviderPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let encoded = try? encoder.encode(payload),
              let json = String(data: encoded, encoding: .utf8)
        else {
            throw VoiceTaskContextAssemblyError.serializationFailed
        }
        // A task detail containing Markdown fences must remain one JSON string
        // inside the outer fence. JSON's unicode escape preserves its value
        // without letting literal backticks terminate the data boundary.
        return json.replacingOccurrences(of: "`", with: "\\u0060")
    }

    private func providerNotNeededExclusions(
        _ input: VoiceTaskContextInput
    ) -> [VoiceTaskContextExclusion] {
        let exclusions =
            input.turns.map {
                VoiceTaskContextExclusion(
                    sourceID: $0.id.uuidString,
                    sourceKind: .turn,
                    reason: .providerNotNeeded
                )
            }
            + input.facts.map {
                VoiceTaskContextExclusion(
                    sourceID: $0.id.uuidString,
                    sourceKind: .fact,
                    reason: .providerNotNeeded
                )
            }
            + input.tasks.map {
                VoiceTaskContextExclusion(
                    sourceID: taskSourceID($0.id),
                    sourceKind: .task,
                    reason: .providerNotNeeded
                )
            }
            + (input.currentActionPlan.map {
                [
                    VoiceTaskContextExclusion(
                        sourceID: actionPlanSourceID($0.id),
                        sourceKind: .actionPlan,
                        reason: .providerNotNeeded
                    ),
                ]
            } ?? [])
        return exclusions.sorted(by: stableExclusionLessThan)
    }

    private func exclusion(
        for turn: VoiceTaskContextTurn,
        reason: VoiceTaskContextExclusionReason
    ) -> VoiceTaskContextExclusion {
        VoiceTaskContextExclusion(
            sourceID: turn.id.uuidString,
            sourceKind: .turn,
            reason: reason
        )
    }

    private func exclusion(
        for fact: TaskContextFact,
        reason: VoiceTaskContextExclusionReason
    ) -> VoiceTaskContextExclusion {
        VoiceTaskContextExclusion(
            sourceID: fact.id.uuidString,
            sourceKind: .fact,
            reason: reason
        )
    }

    private func taskSourceID(_ id: Int64) -> String {
        "task:\(id)"
    }

    private func actionPlanSourceID(_ id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "action-plan:sha256:\(digest)"
    }

    private func stableTurnLessThan(
        _ lhs: VoiceTaskContextTurn,
        _ rhs: VoiceTaskContextTurn
    ) -> Bool {
        lhs.createdAt == rhs.createdAt
            ? stableTurnTieBreaker(lhs) < stableTurnTieBreaker(rhs)
            : lhs.createdAt < rhs.createdAt
    }

    private func stableTurnTieBreaker(_ turn: VoiceTaskContextTurn) -> String {
        "\(turn.id.uuidString)|\(turn.kind.rawValue)|\(turn.text)"
    }

    private func stableFactLessThan(
        _ lhs: TaskContextFact,
        _ rhs: TaskContextFact
    ) -> Bool {
        lhs.createdAt == rhs.createdAt
            ? lhs.id.uuidString < rhs.id.uuidString
            : lhs.createdAt < rhs.createdAt
    }

    private func stableExclusionLessThan(
        _ lhs: VoiceTaskContextExclusion,
        _ rhs: VoiceTaskContextExclusion
    ) -> Bool {
        if lhs.sourceKind.rawValue != rhs.sourceKind.rawValue {
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID < rhs.sourceID
        }
        return lhs.reason.rawValue < rhs.reason.rawValue
    }
}

private struct ProviderPayload: Encodable {
    var scope: VoiceTaskContextScopeIdentity
    var turns: [ProviderTurn]
    var facts: [ProviderFact]
    var tasks: [ProviderTask]
    var actionPlan: ProviderActionPlan?
}

private struct ProviderTurn: Encodable {
    var id: String
    var kind: String
    var text: String
}

private struct ProviderFact: Encodable {
    var id: String
    var kind: String
    var value: String
}

private struct ProviderTask: Encodable {
    var id: Int64
    var projectID: Int64?
    var title: String
    var detail: String?
}

private struct ProviderActionPlan: Encodable {
    var id: String
    var summary: String
}
