import CryptoKit
import Foundation

/// Closed, versioned routes used before any model provider is considered.
public enum LocalExecutionRoute: String, Codable, CaseIterable, Sendable {
    case deterministic
    case localRanker
    case localSLM
    case frontierFast
    case frontierDeep
    case specialistAgent
    case clarification
    case prohibited
}

public enum RequestSource: String, Codable, CaseIterable, Sendable {
    case voice
    case text
    case inbox
    case menuBar = "menu_bar"
    case shortcut
    case api
}

public enum TriageScope: String, Codable, CaseIterable, Sendable {
    case task
    case project
    case workspace
    case inbox
    case today
    case schedule
    case external
    case unknown
}

public enum LocalTriageDataZone: String, Codable, CaseIterable, Sendable {
    case standard
    case localOnly = "local_only"
}

public enum PersonalCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case taskRead = "task.read"
    case taskWrite = "task.write"
    case projectRead = "project.read"
    case projectWrite = "project.write"
    case scheduleRead = "schedule.read"
    case scheduleWrite = "schedule.write"
    case calendarRead = "calendar.read"
    case calendarWrite = "calendar.write"
    case notificationWrite = "notification.write"
    case documentResearch = "document.research"
    case documentDraft = "document.draft"
    case repositoryRead = "repository.read"
    case repositoryWrite = "repository.write"
}

public struct ProviderID: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = trimmed.isEmpty ? "unknown" : trimmed
    }

    public init(rawValue: String) {
        self.init(rawValue)
    }

    public static func < (lhs: ProviderID, rhs: ProviderID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ProviderReadinessReference: Codable, Equatable, Sendable {
    public let providerID: ProviderID
    public let isReady: Bool
    public let isLocal: Bool
    public let allowsLocalData: Bool
    public let requiresNetwork: Bool
    public let capabilities: Set<PersonalCapability>

    public init(
        providerID: ProviderID,
        isReady: Bool,
        isLocal: Bool,
        allowsLocalData: Bool,
        requiresNetwork: Bool,
        capabilities: Set<PersonalCapability>
    ) {
        self.providerID = providerID
        self.isReady = isReady
        self.isLocal = isLocal
        self.allowsLocalData = allowsLocalData
        self.requiresNetwork = requiresNetwork
        self.capabilities = capabilities
    }

    public var id: ProviderID { providerID }
    public var ready: Bool { isReady }
}

/// Reasons are deliberately closed so authority never depends on model-provided
/// prose. The raw values are stable rule IDs for metrics and future adapters.
public enum TriageReason: String, Codable, CaseIterable, Sendable {
    case invalidInput = "input.invalid"
    case inputTooLarge = "input.too_large"
    case routerUnavailable = "router.unavailable"
    case destructiveOperation = "operation.destructive"
    case unsupportedOperation = "operation.unsupported"
    case exactDeterministicOperation = "operation.deterministic"
    case readOnly = "operation.read_only"
    case missingRequiredField = "clarification.missing_field"
    case ambiguousReference = "clarification.ambiguous_reference"
    case scopeConflict = "clarification.scope_conflict"
    case manualOnly = "policy.manual_only"
    case dataPolicyConflict = "policy.data_zone"
    case policyUnavailable = "policy.unavailable"
    case capabilityUnavailable = "capability.unavailable"
    case providerUnavailable = "provider.unavailable"
    case networkUnavailable = "network.unavailable"
    case externalWriteRequiresApproval = "approval.external_write"
    case frontierCandidate = "candidate.frontier"
    case localCandidate = "candidate.local"
    case userOverrideRejected = "override.rejected"
}

public enum ClarificationField: String, Codable, CaseIterable, Sendable {
    case operation
    case taskReference = "task_reference"
    case projectReference = "project_reference"
    case taskTitle = "task_title"
    case project = "project"
    case person
    case deadline
    case scope
    case provider
    case confirmation
}

public enum CostClass: String, Codable, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high
    case unknown
}

public enum LocalTriageExecutionPath: String, Codable, CaseIterable, Sendable {
    case none
    case deterministic
    case local
    case frontier
    case review
    case clarification
    case prohibited
}

public struct LocalTriageConfiguration: Codable, Equatable, Sendable {
    static let hardMaximumInputBytes = 4_096

    public let version: String
    public let maximumInputBytes: Int
    public let enabled: Bool

    public init(
        version: String = "local-triage-v0",
        maximumInputBytes: Int = 4_096,
        enabled: Bool = true
    ) {
        self.version = version
        self.maximumInputBytes = min(max(1, maximumInputBytes), Self.hardMaximumInputBytes)
        self.enabled = enabled
    }

    public static let v0 = LocalTriageConfiguration()
}

public struct LocalTriageRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let source: RequestSource
    public let normalizedInput: String
    public let inputByteCount: Int
    public let scope: TriageScope
    public let availableCapabilities: Set<PersonalCapability>
    public let providerReadiness: [ProviderReadinessReference]
    public let dataPolicyVersion: Int
    public let operatingPolicyVersion: Int?
    public let frozenAt: Date
    public let timeZoneID: String
    public let dataZone: LocalTriageDataZone
    public let selectedTaskID: Int64?
    public let selectedProjectID: Int64?
    public let explicitTaskID: Int64?
    public let explicitProjectID: Int64?
    public let networkAvailable: Bool
    public let manualOnly: Bool

    public init(
        requestID: UUID = UUID(),
        source: RequestSource,
        normalizedInput: String,
        scope: TriageScope,
        availableCapabilities: Set<PersonalCapability>,
        providerReadiness: [ProviderReadinessReference],
        dataPolicyVersion: Int,
        operatingPolicyVersion: Int? = nil,
        frozenAt: Date,
        timeZoneID: String,
        dataZone: LocalTriageDataZone = .standard,
        selectedTaskID: Int64? = nil,
        selectedProjectID: Int64? = nil,
        explicitTaskID: Int64? = nil,
        explicitProjectID: Int64? = nil,
        networkAvailable: Bool = true,
        manualOnly: Bool = false
    ) {
        self.requestID = requestID
        self.source = source
        self.inputByteCount = normalizedInput.utf8.count
        self.normalizedInput = inputByteCount <= LocalTriageConfiguration.hardMaximumInputBytes
            ? Self.normalize(normalizedInput)
            : ""
        self.scope = scope
        self.availableCapabilities = availableCapabilities
        self.providerReadiness = providerReadiness
        self.dataPolicyVersion = dataPolicyVersion
        self.operatingPolicyVersion = operatingPolicyVersion
        self.frozenAt = frozenAt
        self.timeZoneID = timeZoneID
        self.dataZone = dataZone
        self.selectedTaskID = selectedTaskID
        self.selectedProjectID = selectedProjectID
        self.explicitTaskID = explicitTaskID
        self.explicitProjectID = explicitProjectID
        self.networkAvailable = networkAvailable
        self.manualOnly = manualOnly
    }

    public static func normalize(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

public struct LocalTriageDecision: Codable, Equatable, Sendable {
    public let route: LocalExecutionRoute
    public let capability: PersonalCapability?
    public let reasons: [TriageReason]
    public let missingFields: [ClarificationField]
    public let eligibleProviderIDs: [ProviderID]
    public let prohibitedProviderIDs: [ProviderID]
    public let estimatedCostClass: CostClass
    public let requiredApproval: ApprovalRequirement
    public let configVersion: String
    public let ruleIDs: [String]
    public let eligibleRoutes: [LocalExecutionRoute]
    public let decisionDigest: String
    public let userOverrideRoute: LocalExecutionRoute?
    public let userOverrideRejected: Bool

    public init(
        route: LocalExecutionRoute,
        capability: PersonalCapability?,
        reasons: [TriageReason],
        missingFields: [ClarificationField],
        eligibleProviderIDs: [ProviderID],
        prohibitedProviderIDs: [ProviderID],
        estimatedCostClass: CostClass,
        requiredApproval: ApprovalRequirement,
        configVersion: String,
        ruleIDs: [String],
        eligibleRoutes: [LocalExecutionRoute],
        decisionDigest: String,
        userOverrideRoute: LocalExecutionRoute? = nil,
        userOverrideRejected: Bool = false
    ) {
        self.route = route
        self.capability = capability
        self.reasons = reasons
        self.missingFields = missingFields
        self.eligibleProviderIDs = eligibleProviderIDs
        self.prohibitedProviderIDs = prohibitedProviderIDs
        self.estimatedCostClass = estimatedCostClass
        self.requiredApproval = requiredApproval
        self.configVersion = configVersion
        self.ruleIDs = ruleIDs
        self.eligibleRoutes = eligibleRoutes
        self.decisionDigest = decisionDigest
        self.userOverrideRoute = userOverrideRoute
        self.userOverrideRejected = userOverrideRejected
    }
}

/// A bounded shadow record for later metrics/evaluation. It intentionally
/// carries digests and closed enums, never transcript, person, path, or secret.
public struct LocalTriageShadowEvent: Codable, Equatable, Sendable {
    public let requestDigest: String
    public let ruleIDs: [String]
    public let selectedRoute: LocalExecutionRoute
    public let eligibleRoutes: [LocalExecutionRoute]
    public let userOverrideRoute: LocalExecutionRoute?
    public let userOverrideRejected: Bool
    public let clarificationResult: Bool?
    public let finalExecutionPath: LocalTriageExecutionPath?
    public let outcomeLinkDigest: String?
    public let latencyMilliseconds: Int?
    public let frontierCallAvoided: Bool

    public init(
        requestDigest: String,
        ruleIDs: [String],
        selectedRoute: LocalExecutionRoute,
        eligibleRoutes: [LocalExecutionRoute],
        userOverrideRoute: LocalExecutionRoute? = nil,
        userOverrideRejected: Bool = false,
        clarificationResult: Bool? = nil,
        finalExecutionPath: LocalTriageExecutionPath? = nil,
        outcomeLink: String? = nil,
        latencyMilliseconds: Int? = nil,
        frontierCallAvoided: Bool
    ) {
        self.requestDigest = requestDigest
        self.ruleIDs = Array(ruleIDs.prefix(32))
        self.selectedRoute = selectedRoute
        self.eligibleRoutes = Array(eligibleRoutes.prefix(8))
        self.userOverrideRoute = userOverrideRoute
        self.userOverrideRejected = userOverrideRejected
        self.clarificationResult = clarificationResult
        self.finalExecutionPath = finalExecutionPath
        self.outcomeLinkDigest = outcomeLink.map(LocalTriageDigest.sha256)
        self.latencyMilliseconds = latencyMilliseconds.map { min(max($0, 0), 60_000) }
        self.frontierCallAvoided = frontierCallAvoided
    }

    public var serializedSummary: String {
        [
            "request=\(requestDigest)",
            "rules=\(ruleIDs.joined(separator: ","))",
            "route=\(selectedRoute.rawValue)",
            "eligible=\(eligibleRoutes.map(\.rawValue).joined(separator: ","))",
            "override=\(userOverrideRoute?.rawValue ?? "none")",
            "overrideRejected=\(userOverrideRejected)",
            "clarification=\(clarificationResult.map(String.init) ?? "unknown")",
            "path=\(finalExecutionPath?.rawValue ?? "none")",
            "outcome=\(outcomeLinkDigest ?? "none")",
            "latencyMs=\(latencyMilliseconds.map(String.init) ?? "unknown")",
            "frontierCallAvoided=\(frontierCallAvoided)"
        ].joined(separator: "|")
    }
}

public protocol LocalTriageRouting: Sendable {
    func evaluate(
        _ request: LocalTriageRequest,
        userOverride: LocalExecutionRoute?
    ) -> LocalTriageDecision
}

public struct LocalTriageRouter: LocalTriageRouting, Sendable {
    public let configuration: LocalTriageConfiguration

    public init(configuration: LocalTriageConfiguration = .v0) {
        self.configuration = configuration
    }

    public func evaluate(
        _ request: LocalTriageRequest,
        userOverride: LocalExecutionRoute? = nil
    ) -> LocalTriageDecision {
        var reasons: [TriageReason] = []
        var missingFields: [ClarificationField] = []
        var route: LocalExecutionRoute = .clarification
        var capability: PersonalCapability?
        var estimatedCost: CostClass = .unknown
        var approval: ApprovalRequirement = .userConfirmation
        var eligibleRoutes: [LocalExecutionRoute] = []
        var eligibleProviders: [ProviderID] = []
        var prohibitedProviders: [ProviderID] = []

        func add(_ reason: TriageReason) {
            if !reasons.contains(reason) {
                reasons.append(reason)
            }
        }

        guard configuration.enabled else {
            add(.routerUnavailable)
            route = .prohibited
            approval = .blocked
            return makeDecision(
                request: request,
                route: route,
                capability: nil,
                reasons: reasons,
                missingFields: missingFields,
                eligibleProviders: eligibleProviders,
                prohibitedProviders: prohibitedProviders,
                estimatedCost: estimatedCost,
                approval: approval,
                eligibleRoutes: eligibleRoutes,
                userOverride: userOverride
            )
        }

        let inputLimit = min(
            max(1, configuration.maximumInputBytes),
            LocalTriageConfiguration.hardMaximumInputBytes
        )
        guard request.inputByteCount >= 0,
              request.inputByteCount <= inputLimit,
              request.normalizedInput.utf8.count <= inputLimit
        else {
            add(.inputTooLarge)
            route = .prohibited
            approval = .blocked
            return makeDecision(
                request: request,
                route: route,
                capability: nil,
                reasons: reasons,
                missingFields: missingFields,
                eligibleProviders: eligibleProviders,
                prohibitedProviders: prohibitedProviders,
                estimatedCost: estimatedCost,
                approval: approval,
                eligibleRoutes: eligibleRoutes,
                userOverride: userOverride
            )
        }

        guard !request.normalizedInput.isEmpty else {
            add(.invalidInput)
            missingFields = [.operation]
            route = .clarification
            return makeDecision(
                request: request,
                route: route,
                capability: nil,
                reasons: reasons,
                missingFields: missingFields,
                eligibleProviders: eligibleProviders,
                prohibitedProviders: prohibitedProviders,
                estimatedCost: estimatedCost,
                approval: approval,
                eligibleRoutes: [.clarification],
                userOverride: userOverride
            )
        }

        guard request.dataPolicyVersion > 0 else {
            add(.policyUnavailable)
            route = .prohibited
            approval = .blocked
            return makeDecision(
                request: request,
                route: route,
                capability: nil,
                reasons: reasons,
                missingFields: missingFields,
                eligibleProviders: eligibleProviders,
                prohibitedProviders: prohibitedProviders,
                estimatedCost: estimatedCost,
                approval: approval,
                eligibleRoutes: eligibleRoutes,
                userOverride: userOverride
            )
        }

        let text = request.normalizedInput
        if containsAny(text, [
            "delete", "remove all", "wipe", "destroy", "deploy production",
            "push to main", "削除", "全削除", "本番反映", "本番へdeploy"
        ]) {
            add(.destructiveOperation)
            route = .prohibited
            approval = .blocked
            return makeDecision(
                request: request,
                route: route,
                capability: nil,
                reasons: reasons,
                missingFields: missingFields,
                eligibleProviders: eligibleProviders,
                prohibitedProviders: prohibitedProviders,
                estimatedCost: estimatedCost,
                approval: approval,
                eligibleRoutes: eligibleRoutes,
                userOverride: userOverride
            )
        }

        if request.manualOnly || containsAny(text, ["manual only", "手動のみ", "手動で"]) {
            add(.manualOnly)
            missingFields = [.confirmation]
            route = .clarification
            return makeDecision(
                request: request,
                route: route,
                capability: nil,
                reasons: reasons,
                missingFields: missingFields,
                eligibleProviders: eligibleProviders,
                prohibitedProviders: prohibitedProviders,
                estimatedCost: estimatedCost,
                approval: approval,
                eligibleRoutes: [.clarification],
                userOverride: userOverride
            )
        }

        let operation = classify(text)
        switch operation {
        case .read:
            capability = readCapability(for: request.scope)
            estimatedCost = .none
            guard let capability else {
                add(.scopeConflict)
                missingFields = [.scope]
                break
            }
            guard request.availableCapabilities.contains(capability) else {
                add(.capabilityUnavailable)
                missingFields = [.confirmation]
                break
            }
            add(.exactDeterministicOperation)
            add(.readOnly)
            route = .deterministic
            approval = .none
            eligibleRoutes = [.deterministic]

        case .taskCreate:
            capability = .taskWrite
            estimatedCost = .low
            guard request.availableCapabilities.contains(.taskWrite) else {
                add(.capabilityUnavailable)
                missingFields = [.confirmation]
                break
            }
            guard hasTaskTitle(text) else {
                add(.missingRequiredField)
                missingFields = [.taskTitle]
                break
            }
            add(.exactDeterministicOperation)
            route = .deterministic
            approval = .explicitApproval
            eligibleRoutes = [.deterministic]

        case .taskStatus:
            capability = .taskWrite
            estimatedCost = .low
            guard request.availableCapabilities.contains(.taskWrite) else {
                add(.capabilityUnavailable)
                missingFields = [.confirmation]
                break
            }
            guard hasTaskReference(in: request, text: text) else {
                add(.ambiguousReference)
                missingFields = [.taskReference]
                break
            }
            add(.exactDeterministicOperation)
            route = .deterministic
            approval = .explicitApproval
            eligibleRoutes = [.deterministic]

        case .projectMove:
            capability = .projectWrite
            estimatedCost = .low
            guard request.availableCapabilities.contains(.projectWrite) else {
                add(.capabilityUnavailable)
                missingFields = [.confirmation]
                break
            }
            guard hasTaskReference(in: request, text: text) else {
                add(.ambiguousReference)
                missingFields = [.taskReference]
                break
            }
            guard request.selectedProjectID != nil || request.explicitProjectID != nil else {
                add(.missingRequiredField)
                missingFields = [.projectReference]
                break
            }
            add(.exactDeterministicOperation)
            route = .deterministic
            approval = .explicitApproval
            eligibleRoutes = [.deterministic]

        case .taskDueDate:
            capability = .taskWrite
            estimatedCost = .low
            guard request.availableCapabilities.contains(.taskWrite) else {
                add(.capabilityUnavailable)
                missingFields = [.confirmation]
                break
            }
            guard hasTaskReference(in: request, text: text) else {
                add(.ambiguousReference)
                missingFields = [.taskReference]
                break
            }
            guard hasDate(text) else {
                add(.missingRequiredField)
                missingFields = [.deadline]
                break
            }
            add(.exactDeterministicOperation)
            route = .deterministic
            approval = .explicitApproval
            eligibleRoutes = [.deterministic]

        case .externalWrite:
            capability = .notificationWrite
            estimatedCost = .low
            guard request.availableCapabilities.contains(.notificationWrite) else {
                add(.capabilityUnavailable)
                missingFields = [.confirmation]
                break
            }
            add(.externalWriteRequiresApproval)
            route = .deterministic
            approval = .explicitApproval
            eligibleRoutes = [.deterministic]

        case .frontier:
            let requiredCapability: PersonalCapability = containsAny(
                text,
                ["document", "brief", "資料", "議事録", "meeting"]
            )
                ? .documentDraft
                : .documentResearch
            capability = requiredCapability
            estimatedCost = containsAny(text, ["research", "競合", "strategy", "戦略", "multi-source"])
                ? .high
                : .medium
            add(.frontierCandidate)
            guard request.availableCapabilities.contains(requiredCapability) else {
                add(.capabilityUnavailable)
                missingFields = [.confirmation]
                break
            }
            let providerResult = providerGate(
                request: request,
                capability: requiredCapability
            )
            eligibleProviders = providerResult.eligible
            prohibitedProviders = providerResult.prohibited
            providerResult.reasons.forEach(add)
            if providerResult.localEligible {
                add(.localCandidate)
                route = .localSLM
                approval = .userConfirmation
                eligibleRoutes = [.localSLM]
            } else if !eligibleProviders.isEmpty {
                route = estimatedCost == .high ? .frontierDeep : .frontierFast
                approval = .userConfirmation
                eligibleRoutes = [.frontierFast, .frontierDeep]
            } else {
                missingFields = [.provider]
                route = .clarification
                eligibleRoutes = [.clarification]
            }

        case .unsupported:
            add(.unsupportedOperation)
            missingFields = [.operation]
        }

        if route == .clarification && missingFields.isEmpty {
            missingFields = [.confirmation]
        }
        if route == .clarification && !reasons.contains(.capabilityUnavailable) {
            if request.scope == .unknown {
                add(.scopeConflict)
            } else if !reasons.contains(.unsupportedOperation) {
                add(.unsupportedOperation)
            }
        }

        return makeDecision(
            request: request,
            route: route,
            capability: capability,
            reasons: reasons,
            missingFields: missingFields,
            eligibleProviders: eligibleProviders,
            prohibitedProviders: prohibitedProviders,
            estimatedCost: estimatedCost,
            approval: approval,
            eligibleRoutes: eligibleRoutes.isEmpty ? [.clarification] : eligibleRoutes,
            userOverride: userOverride
        )
    }

    public func evaluate(_ request: LocalTriageRequest) -> LocalTriageDecision {
        evaluate(request, userOverride: nil)
    }

    public func shadowEvent(
        for request: LocalTriageRequest,
        decision: LocalTriageDecision,
        clarificationResult: Bool? = nil,
        latencyMilliseconds: Int? = nil,
        finalExecutionPath: LocalTriageExecutionPath? = nil,
        outcomeLink: String? = nil
    ) -> LocalTriageShadowEvent {
        return LocalTriageShadowEvent(
            requestDigest: decision.decisionDigest,
            ruleIDs: decision.ruleIDs,
            selectedRoute: decision.route,
            eligibleRoutes: decision.eligibleRoutes,
            userOverrideRoute: decision.userOverrideRoute,
            userOverrideRejected: decision.userOverrideRejected,
            clarificationResult: clarificationResult,
            finalExecutionPath: finalExecutionPath,
            outcomeLink: outcomeLink,
            latencyMilliseconds: latencyMilliseconds,
            frontierCallAvoided: finalExecutionPath.map { $0 != .frontier }
                ?? (decision.route != .frontierFast && decision.route != .frontierDeep)
        )
    }

    private enum Operation {
        case read
        case taskCreate
        case taskStatus
        case projectMove
        case taskDueDate
        case externalWrite
        case frontier
        case unsupported
    }

    private func classify(_ text: String) -> Operation {
        if containsAny(text, ["send now", "post now", "send it", "send to", "今すぐ送信", "送信して", "送って", "投稿して"]) {
            return .externalWrite
        }
        if containsAny(text, [
            "list", "show", "count", "status", "overdue", "期限切れ", "表示", "一覧", "何件", "進捗"
        ]) && !containsAny(text, ["add", "create", "move", "done", "完了", "追加", "作成", "移動"])
        {
            return .read
        }
        if containsAny(text, ["add", "create", "new task", "taskを追加", "タスクを追加", "タスクを作成", "追加して", "作成して"]) {
            return .taskCreate
        }
        if containsAny(text, ["due", "deadline", "期限", "締切"]) {
            return .taskDueDate
        }
        if containsAny(text, ["project", "プロジェクト"])
            && containsAny(text, ["move", "into", "入れて", "移動"])
        {
            return .projectMove
        }
        if containsAny(text, [
            "done", "complete", "completed", "in progress", "move", "set status", "完了", "進行中", "移動"
        ]) {
            return .taskStatus
        }
        if containsAny(text, [
            "research", "strategy", "document", "brief", "meeting", "multi-source", "競合", "戦略", "資料", "議事録", "整理して", "まとめて"
        ]) {
            return .frontier
        }
        return .unsupported
    }

    private func providerGate(
        request: LocalTriageRequest,
        capability: PersonalCapability
    ) -> (eligible: [ProviderID], prohibited: [ProviderID], localEligible: Bool, reasons: [TriageReason]) {
        var eligible: [ProviderID] = []
        var prohibited: [ProviderID] = []
        var reasons: [TriageReason] = []
        var localEligible = false
        let references = request.providerReadiness.sorted { $0.providerID < $1.providerID }
        let duplicateProviderIDs = Set(
            Dictionary(grouping: references, by: \.providerID)
                .compactMap { $0.value.count > 1 ? $0.key : nil }
        )
        for reference in references {
            if duplicateProviderIDs.contains(reference.providerID) {
                if !prohibited.contains(reference.providerID) {
                    prohibited.append(reference.providerID)
                }
                if !reasons.contains(.providerUnavailable) { reasons.append(.providerUnavailable) }
                continue
            }
            let policyAllowed = request.dataZone != .localOnly
                || (reference.isLocal && reference.allowsLocalData)
            let networkAllowed = request.networkAvailable || !reference.requiresNetwork
            let capabilityAllowed = reference.capabilities.contains(capability)
            if reference.isReady && policyAllowed && networkAllowed && capabilityAllowed {
                eligible.append(reference.providerID)
                localEligible = localEligible || reference.isLocal
            } else {
                prohibited.append(reference.providerID)
                if !policyAllowed {
                    if !reasons.contains(.dataPolicyConflict) { reasons.append(.dataPolicyConflict) }
                } else if !networkAllowed {
                    if !reasons.contains(.networkUnavailable) { reasons.append(.networkUnavailable) }
                } else if !reference.isReady || !capabilityAllowed {
                    if !reasons.contains(.providerUnavailable) { reasons.append(.providerUnavailable) }
                }
            }
        }
        return (eligible, prohibited, localEligible, reasons)
    }

    private func makeDecision(
        request: LocalTriageRequest,
        route: LocalExecutionRoute,
        capability: PersonalCapability?,
        reasons: [TriageReason],
        missingFields: [ClarificationField],
        eligibleProviders: [ProviderID],
        prohibitedProviders: [ProviderID],
        estimatedCost: CostClass,
        approval: ApprovalRequirement,
        eligibleRoutes: [LocalExecutionRoute],
        userOverride: LocalExecutionRoute?
    ) -> LocalTriageDecision {
        var normalizedReasons: [TriageReason] = []
        for reason in reasons where !normalizedReasons.contains(reason) {
            normalizedReasons.append(reason)
        }
        var rejectedOverride = false
        if let userOverride {
            rejectedOverride = route == .prohibited || !eligibleRoutes.contains(userOverride)
            if rejectedOverride && !normalizedReasons.contains(.userOverrideRejected) {
                normalizedReasons.append(.userOverrideRejected)
            }
        }
        let effectiveRoute = rejectedOverride ? route : userOverride ?? route
        let canonicalRules = normalizedReasons.map(\.rawValue).sorted()
        let capabilityList = request.availableCapabilities
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        let providerList = request.providerReadiness
            .sorted { $0.providerID < $1.providerID }
            .map(Self.canonicalProviderDescription)
            .joined(separator: ";")
        let digestParts: [String] = [
            configuration.version,
            request.normalizedInput,
            request.source.rawValue,
            request.scope.rawValue,
            request.dataZone.rawValue,
            String(request.inputByteCount),
            capabilityList,
            providerList,
            String(request.dataPolicyVersion),
            request.operatingPolicyVersion.map(String.init) ?? "none",
            String(request.frozenAt.timeIntervalSince1970),
            request.timeZoneID,
            String(request.selectedTaskID ?? -1),
            String(request.selectedProjectID ?? -1),
            String(request.explicitTaskID ?? -1),
            String(request.explicitProjectID ?? -1),
            String(request.networkAvailable),
            String(request.manualOnly),
            effectiveRoute.rawValue,
            capability?.rawValue ?? "none",
            normalizedReasons.map(\.rawValue).joined(separator: ","),
            missingFields.map(\.rawValue).joined(separator: ","),
            eligibleProviders.map(\.rawValue).joined(separator: ","),
            prohibitedProviders.map(\.rawValue).joined(separator: ","),
            userOverride?.rawValue ?? "none"
        ]
        let digest = LocalTriageDigest.sha256(digestParts.joined(separator: "\u{1F}"))
        return LocalTriageDecision(
            route: effectiveRoute,
            capability: capability,
            reasons: normalizedReasons,
            missingFields: missingFields,
            eligibleProviderIDs: Array(Set(eligibleProviders)).sorted(),
            prohibitedProviderIDs: Array(Set(prohibitedProviders)).sorted(),
            estimatedCostClass: estimatedCost,
            requiredApproval: effectiveRoute == .prohibited ? .blocked : approval,
            configVersion: configuration.version,
            ruleIDs: canonicalRules,
            eligibleRoutes: Array(Set(eligibleRoutes)).sorted { $0.rawValue < $1.rawValue },
            decisionDigest: digest,
            userOverrideRoute: userOverride,
            userOverrideRejected: rejectedOverride
        )
    }

    private func hasTaskReference(in request: LocalTriageRequest, text: String) -> Bool {
        request.selectedTaskID != nil
            || request.explicitTaskID != nil
            || text.range(of: #"(?:task|タスク)?\s*#\d+"#, options: .regularExpression) != nil
    }

    private static func canonicalProviderDescription(
        _ provider: ProviderReadinessReference
    ) -> String {
        let capabilityList = provider.capabilities
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return "\(provider.providerID.rawValue):\(provider.isReady):\(provider.isLocal):\(provider.allowsLocalData):\(provider.requiresNetwork):\(capabilityList)"
    }

    private func hasTaskTitle(_ text: String) -> Bool {
        let stripped = text
            .replacingOccurrences(
                of: #"^(?:please\s+)?(?:add|create|new)\b[\s:,-]*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^(?:(?:a|the)\s+)?(?:task|todo)\b[\s:,-]*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "task", with: "")
            .replacingOccurrences(of: "todo", with: "")
            .replacingOccurrences(of: "タスク", with: "")
            .replacingOccurrences(of: "を追加", with: "")
            .replacingOccurrences(of: "を作成", with: "")
            .replacingOccurrences(of: "追加して", with: "")
            .replacingOccurrences(of: "作成して", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.count >= 2
    }

    private func readCapability(for scope: TriageScope) -> PersonalCapability? {
        switch scope {
        case .project:
            .projectRead
        case .schedule:
            .scheduleRead
        case .external:
            .calendarRead
        case .task, .workspace, .inbox, .today:
            .taskRead
        case .unknown:
            nil
        }
    }

    private func hasDate(_ text: String) -> Bool {
        text.range(of: #"\b\d{4}-\d{2}-\d{2}(?:t|\s)"#, options: .regularExpression) != nil
            || text.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) != nil
            || containsAny(text, ["tomorrow", "today", "明日", "今日", "明後日"])
    }

    private func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.contains($0) }
    }
}

private enum LocalTriageDigest {
    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
