import Foundation

public struct ManagedAIBillingSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var perRunCapCents: Int?
    public var dailyCapCents: Int?
    public var monthlyCapCents: Int?
    public var workspaceCapCents: Int?

    public init(
        isEnabled: Bool = false,
        perRunCapCents: Int? = nil,
        dailyCapCents: Int? = nil,
        monthlyCapCents: Int? = nil,
        workspaceCapCents: Int? = nil
    ) {
        self.isEnabled = isEnabled
        self.perRunCapCents = perRunCapCents
        self.dailyCapCents = dailyCapCents
        self.monthlyCapCents = monthlyCapCents
        self.workspaceCapCents = workspaceCapCents
    }

    public static let `default` = ManagedAIBillingSettings()

    public var hardCapCentsForPreview: Double? {
        guard isEnabled else {
            return nil
        }
        guard let perRunCapCents, perRunCapCents > 0 else {
            return nil
        }
        // Previews evaluate the run in isolation. Daily/monthly/workspace caps
        // are enforced later against the Suisui-managed usage ledger so BYOK and
        // local-only telemetry cannot affect managed billing decisions.
        return Double(perRunCapCents)
    }

    public static func usageLedgerCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public var hasLedgerBackedUsageCap: Bool {
        guard isEnabled else {
            return false
        }
        return [dailyCapCents, monthlyCapCents, workspaceCapCents].contains { cap in
            (cap ?? 0) > 0
        }
    }

    public func firstExceededUsageCap(
        totals: ManagedAIUsageLedgerTotals,
        pendingCostPreview: AssistantQueueCostPreview
    ) -> ManagedAIUsageCapProjection? {
        guard isEnabled,
              pendingCostPreview.billingMode == .suisuiManaged,
              let pendingCostCents = pendingCostPreview.estimatedCostCents,
              let previewCurrencyCode = pendingCostPreview.currencyCode
        else {
            return nil
        }

        let currencyCode = ManagedAIUsageLedgerTotals.normalizedCurrencyCode(previewCurrencyCode)
        guard totals.currencyCode == currencyCode else {
            return nil
        }

        return [
            capProjection(
                scope: .daily,
                usedCents: totals.dailyCostCents,
                pendingCostCents: pendingCostCents,
                capCents: dailyCapCents,
                currencyCode: currencyCode
            ),
            capProjection(
                scope: .monthly,
                usedCents: totals.monthlyCostCents,
                pendingCostCents: pendingCostCents,
                capCents: monthlyCapCents,
                currencyCode: currencyCode
            ),
            capProjection(
                scope: .workspace,
                usedCents: totals.workspaceCostCents,
                pendingCostCents: pendingCostCents,
                capCents: workspaceCapCents,
                currencyCode: currencyCode
            )
        ].compactMap { $0 }.first { $0.projectedCents > Double($0.capCents) }
    }

    public func usageThresholdRows(for snapshot: ExecutionUsageMeterSnapshot, currencyCode: String = "USD") -> [ManagedAIUsageThresholdRow] {
        guard isEnabled else {
            return []
        }
        var rows: [ManagedAIUsageThresholdRow] = []
        if let dailyCapCents, dailyCapCents > 0 {
            rows.append(
                ManagedAIUsageThresholdRow(
                    scope: .daily,
                    title: String(localized: "Latest Daily Usage"),
                    usedCents: snapshot.dailyRows.first?.summary.totalCostCents(currencyCode: currencyCode) ?? 0,
                    capCents: dailyCapCents,
                    currencyCode: currencyCode
                )
            )
        }
        if let monthlyCapCents, monthlyCapCents > 0 {
            rows.append(
                ManagedAIUsageThresholdRow(
                    scope: .monthly,
                    title: String(localized: "Latest Monthly Usage"),
                    usedCents: snapshot.monthlyRows.first?.summary.totalCostCents(currencyCode: currencyCode) ?? 0,
                    capCents: monthlyCapCents,
                    currencyCode: currencyCode
                )
            )
        }
        if let workspaceCapCents, workspaceCapCents > 0 {
            rows.append(
                ManagedAIUsageThresholdRow(
                    scope: .workspace,
                    title: String(localized: "Workspace Receipt Usage"),
                    usedCents: snapshot.summary.totalCostCents(currencyCode: currencyCode),
                    capCents: workspaceCapCents,
                    currencyCode: currencyCode
                )
            )
        }
        return rows
    }

    public var normalized: ManagedAIBillingSettings {
        var copy = self
        copy.perRunCapCents = Self.normalizedCap(perRunCapCents)
        copy.dailyCapCents = Self.normalizedCap(dailyCapCents)
        copy.monthlyCapCents = Self.normalizedCap(monthlyCapCents)
        copy.workspaceCapCents = Self.normalizedCap(workspaceCapCents)
        return copy
    }

    public func validationIssues() -> [ValidationIssue] {
        guard isEnabled else {
            return []
        }

        var issues: [ValidationIssue] = []
        appendCapIssue(
            perRunCapCents,
            field: "managedAIBilling.perRunCapCents",
            label: "per-run",
            to: &issues
        )
        appendCapIssue(
            dailyCapCents,
            field: "managedAIBilling.dailyCapCents",
            label: "daily",
            to: &issues
        )
        appendCapIssue(
            monthlyCapCents,
            field: "managedAIBilling.monthlyCapCents",
            label: "monthly",
            to: &issues
        )
        appendCapIssue(
            workspaceCapCents,
            field: "managedAIBilling.workspaceCapCents",
            label: "workspace",
            to: &issues
        )
        if perRunCapCents == nil, dailyCapCents == nil, monthlyCapCents == nil, workspaceCapCents == nil {
            issues.append(
                ValidationIssue(
                    field: "managedAIBilling",
                    message: "Managed AI billing requires at least one configured cap.",
                    severity: .error
                )
            )
        }
        return issues
    }

    private static func normalizedCap(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }
        return max(0, value)
    }

    private func appendCapIssue(
        _ value: Int?,
        field: String,
        label: String,
        to issues: inout [ValidationIssue]
    ) {
        guard let value, value <= 0 else {
            return
        }
        issues.append(
            ValidationIssue(
                field: field,
                message: "Managed AI \(label) cap must be greater than 0 cents.",
                severity: .error
            )
        )
    }

    private func capProjection(
        scope: ManagedAIUsageThresholdScope,
        usedCents: Double,
        pendingCostCents: Double,
        capCents: Int?,
        currencyCode: String
    ) -> ManagedAIUsageCapProjection? {
        guard let capCents, capCents > 0 else {
            return nil
        }
        return ManagedAIUsageCapProjection(
            scope: scope,
            usedCents: usedCents,
            pendingCostCents: pendingCostCents,
            capCents: capCents,
            currencyCode: currencyCode
        )
    }
}

public struct ManagedAICostRateCardConfiguration: Equatable, Sendable {
    public static let providerIDEnvironmentKey = "SUISUI_MANAGED_AI_PROVIDER_ID"
    public static let modelNameEnvironmentKey = "SUISUI_MANAGED_AI_MODEL_NAME"
    public static let currencyCodeEnvironmentKey = "SUISUI_MANAGED_AI_CURRENCY_CODE"
    public static let inputTokenCentsPerMillionEnvironmentKey = "SUISUI_MANAGED_AI_INPUT_CENTS_PER_MILLION"
    public static let outputTokenCentsPerMillionEnvironmentKey = "SUISUI_MANAGED_AI_OUTPUT_CENTS_PER_MILLION"

    public var providerID: String
    public var modelName: String
    public var currencyCode: String
    public var inputTokenCentsPerMillion: Double
    public var outputTokenCentsPerMillion: Double

    public init(
        providerID: String,
        modelName: String,
        currencyCode: String = "USD",
        inputTokenCentsPerMillion: Double,
        outputTokenCentsPerMillion: Double
    ) {
        self.providerID = Self.normalized(providerID)
        self.modelName = Self.normalized(modelName)
        self.currencyCode = Self.normalized(currencyCode).uppercased()
        self.inputTokenCentsPerMillion = inputTokenCentsPerMillion
        self.outputTokenCentsPerMillion = outputTokenCentsPerMillion
    }

    public static func fromEnvironment(_ environment: [String: String]) -> ManagedAICostRateCardConfiguration? {
        guard
            let providerID = normalizedEnvironmentValue(environment[providerIDEnvironmentKey]),
            let modelName = normalizedEnvironmentValue(environment[modelNameEnvironmentKey]),
            let inputRate = positiveDouble(environment[inputTokenCentsPerMillionEnvironmentKey]),
            let outputRate = positiveDouble(environment[outputTokenCentsPerMillionEnvironmentKey])
        else {
            return nil
        }
        return ManagedAICostRateCardConfiguration(
            providerID: providerID,
            modelName: modelName,
            currencyCode: normalizedEnvironmentValue(environment[currencyCodeEnvironmentKey]) ?? "USD",
            inputTokenCentsPerMillion: inputRate,
            outputTokenCentsPerMillion: outputRate
        )
    }

    public func matches(response: PlanningResponse) -> Bool {
        let normalizedProviderID = Self.normalized(response.providerID).lowercased()
        let normalizedModelProvider = response.model.map { Self.normalized($0.provider).lowercased() }
        let normalizedModelName = response.model.map { Self.normalized($0.name).lowercased() }
        let configuredProvider = providerID.lowercased()
        let configuredModel = modelName.lowercased()
        let providerMatches = normalizedProviderID == configuredProvider || normalizedModelProvider == configuredProvider
        return providerMatches && normalizedModelName == configuredModel
    }

    public var rateCard: AssistantQueueCostRateCard {
        AssistantQueueCostRateCard(
            provider: providerID,
            modelName: modelName,
            currencyCode: currencyCode,
            inputTokenCentsPerMillion: inputTokenCentsPerMillion,
            outputTokenCentsPerMillion: outputTokenCentsPerMillion
        )
    }

    private static func normalizedEnvironmentValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = normalized(value)
        return normalized.isEmpty ? nil : normalized
    }

    private static func positiveDouble(_ value: String?) -> Double? {
        guard let value = normalizedEnvironmentValue(value),
              let number = Double(value),
              number > 0 else {
            return nil
        }
        return number
    }

    private static func normalized(_ value: String) -> String {
        AssistantQueueCostPreview.redactedMetadataText(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ManagedAICostRateCardResolver: Sendable {
    private var configuration: ManagedAICostRateCardConfiguration?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.configuration = ManagedAICostRateCardConfiguration.fromEnvironment(environment)
    }

    public init(configuration: ManagedAICostRateCardConfiguration?) {
        self.configuration = configuration
    }

    public func rateCard(for response: PlanningResponse) -> AssistantQueueCostRateCard? {
        guard let configuration, configuration.matches(response: response) else {
            return nil
        }
        // The managed service price table is injected at runtime because it is
        // commercial policy, not app logic. This keeps OSS builds auditable
        // without baking mutable vendor pricing into source.
        return configuration.rateCard
    }
}

public enum ManagedAIUsageThresholdScope: String, Equatable, Sendable {
    case daily
    case monthly
    case workspace

    public var capDisplayLabel: String {
        switch self {
        case .daily:
            return String(localized: "daily")
        case .monthly:
            return String(localized: "monthly")
        case .workspace:
            return String(localized: "workspace")
        }
    }
}

public enum ManagedAIUsageThresholdStatus: String, Equatable, Sendable {
    case withinLimit = "within_limit"
    case exceeded
}

public struct ManagedAIUsageThresholdRow: Identifiable, Equatable, Sendable {
    public var id: String { scope.rawValue }
    public var scope: ManagedAIUsageThresholdScope
    public var title: String
    public var usedCents: Double
    public var capCents: Int
    public var currencyCode: String

    public init(
        scope: ManagedAIUsageThresholdScope,
        title: String,
        usedCents: Double,
        capCents: Int,
        currencyCode: String
    ) {
        self.scope = scope
        self.title = title
        self.usedCents = max(0, usedCents)
        self.capCents = max(0, capCents)
        self.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public var status: ManagedAIUsageThresholdStatus {
        usedCents > Double(capCents) ? .exceeded : .withinLimit
    }

    public var usedLabel: String {
        String(format: String(localized: "%@ used"), currencyLabel(fromCents: usedCents))
    }

    public var capLabel: String {
        String(format: String(localized: "%@ cap"), currencyLabel(fromCents: Double(capCents)))
    }

    public var statusLabel: String {
        switch status {
        case .withinLimit:
            let remaining = max(0, Double(capCents) - usedCents)
            return String(format: String(localized: "%@ remaining"), currencyLabel(fromCents: remaining))
        case .exceeded:
            let overage = max(0, usedCents - Double(capCents))
            return String(format: String(localized: "%@ exceeded"), currencyLabel(fromCents: overage))
        }
    }

    public var accessibilityValue: String {
        "\(usedLabel), \(capLabel), \(statusLabel)"
    }

    private func currencyLabel(fromCents cents: Double) -> String {
        let major = cents / 100
        let format = major > 0 && major < 0.01 ? "%.4f" : "%.2f"
        return "\(currencyCode) \(String(format: format, major))"
    }
}

public struct ManagedAIUsageCapProjection: Equatable, Sendable {
    public var scope: ManagedAIUsageThresholdScope
    public var usedCents: Double
    public var pendingCostCents: Double
    public var projectedCents: Double
    public var capCents: Int
    public var currencyCode: String

    public init(
        scope: ManagedAIUsageThresholdScope,
        usedCents: Double,
        pendingCostCents: Double,
        capCents: Int,
        currencyCode: String
    ) {
        self.scope = scope
        self.usedCents = Self.normalizedCost(usedCents)
        self.pendingCostCents = Self.normalizedCost(pendingCostCents)
        self.projectedCents = self.usedCents + self.pendingCostCents
        self.capCents = max(0, capCents)
        self.currencyCode = ManagedAIUsageLedgerTotals.normalizedCurrencyCode(currencyCode)
    }

    public var blockingReason: String {
        String(
            format: String(localized: "Managed AI %@ cap would be exceeded. Current %@ plus this run %@ exceeds %@."),
            scope.capDisplayLabel,
            currencyLabel(fromCents: usedCents),
            currencyLabel(fromCents: pendingCostCents),
            currencyLabel(fromCents: Double(capCents))
        )
    }

    private func currencyLabel(fromCents cents: Double) -> String {
        let major = cents / 100
        let format = major > 0 && major < 0.01 ? "%.4f" : "%.2f"
        return "\(currencyCode) \(String(format: format, major))"
    }

    private static func normalizedCost(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}
