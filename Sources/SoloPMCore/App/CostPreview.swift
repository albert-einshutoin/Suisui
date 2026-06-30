import Foundation

public enum AssistantQueueCostBillingMode: String, Codable, Equatable, Sendable {
    case localOnly = "local_only"
    case userProviderBilled = "user_provider_billed"
    case soloPMManaged = "solopm_managed"
}

public enum AssistantQueueCostPreviewState: String, Codable, Equatable, Sendable {
    case estimated
    case unknown
    case unavailable
}

public enum AssistantQueueCostCapStatus: String, Codable, Equatable, Sendable {
    case notConfigured = "not_configured"
    case withinLimit = "within_limit"
    case wouldExceedLimit = "would_exceed_limit"
}

public struct AssistantQueueCostUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens.map { max(0, $0) }
        self.outputTokens = outputTokens.map { max(0, $0) }
    }

    public var totalTokens: Int? {
        switch (inputTokens, outputTokens) {
        case (.some(let input), .some(let output)):
            input + output
        case (.some(let input), .none):
            input
        case (.none, .some(let output)):
            output
        case (.none, .none):
            nil
        }
    }
}

public struct AssistantQueueCostRateCard: Codable, Equatable, Sendable {
    public var provider: String
    public var modelName: String
    public var currencyCode: String
    public var inputTokenCentsPerMillion: Double
    public var outputTokenCentsPerMillion: Double

    public init(
        provider: String,
        modelName: String,
        currencyCode: String,
        inputTokenCentsPerMillion: Double,
        outputTokenCentsPerMillion: Double
    ) {
        self.provider = Self.normalized(provider, fallback: "unknown")
        self.modelName = Self.normalized(modelName, fallback: "unknown")
        self.currencyCode = Self.normalized(currencyCode, fallback: "USD").uppercased()
        self.inputTokenCentsPerMillion = max(0, inputTokenCentsPerMillion)
        self.outputTokenCentsPerMillion = max(0, outputTokenCentsPerMillion)
    }

    public func preview(
        inputTokens: Int?,
        outputTokens: Int?,
        hardCapCents: Double? = nil
    ) -> AssistantQueueCostPreview {
        let usage = AssistantQueueCostUsage(inputTokens: inputTokens, outputTokens: outputTokens)
        let estimatedCostCents = Self.estimatedCostCents(
            usage: usage,
            inputTokenCentsPerMillion: inputTokenCentsPerMillion,
            outputTokenCentsPerMillion: outputTokenCentsPerMillion
        )
        return AssistantQueueCostPreview(
            billingMode: .soloPMManaged,
            state: .estimated,
            usage: usage,
            estimatedCostCents: estimatedCostCents,
            currencyCode: currencyCode,
            model: ExecutionReceiptModel(provider: provider, name: modelName),
            capStatus: Self.capStatus(estimatedCostCents: estimatedCostCents, hardCapCents: hardCapCents)
        )
    }

    private static func estimatedCostCents(
        usage: AssistantQueueCostUsage,
        inputTokenCentsPerMillion: Double,
        outputTokenCentsPerMillion: Double
    ) -> Double {
        // Rate cards are injected instead of hardcoded because vendor pricing
        // changes independently from app releases and must be auditable per run.
        let inputCost = Double(usage.inputTokens ?? 0) * inputTokenCentsPerMillion / 1_000_000
        let outputCost = Double(usage.outputTokens ?? 0) * outputTokenCentsPerMillion / 1_000_000
        return inputCost + outputCost
    }

    private static func capStatus(estimatedCostCents: Double, hardCapCents: Double?) -> AssistantQueueCostCapStatus {
        guard let hardCapCents, hardCapCents >= 0 else {
            return .notConfigured
        }
        return estimatedCostCents <= hardCapCents ? .withinLimit : .wouldExceedLimit
    }

    private static func normalized(_ value: String, fallback: String) -> String {
        let redacted = DeveloperSecretRedactor().redact(value).text
        let trimmed = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

public struct AssistantQueueCostPreview: Codable, Equatable, Sendable {
    public var billingMode: AssistantQueueCostBillingMode
    public var state: AssistantQueueCostPreviewState
    public var usage: AssistantQueueCostUsage
    public var estimatedCostCents: Double?
    public var currencyCode: String?
    public var model: ExecutionReceiptModel?
    public var capStatus: AssistantQueueCostCapStatus
    public var note: String?

    public init(
        billingMode: AssistantQueueCostBillingMode,
        state: AssistantQueueCostPreviewState,
        usage: AssistantQueueCostUsage = AssistantQueueCostUsage(),
        estimatedCostCents: Double? = nil,
        currencyCode: String? = nil,
        model: ExecutionReceiptModel? = nil,
        capStatus: AssistantQueueCostCapStatus = .notConfigured,
        note: String? = nil
    ) {
        self.billingMode = billingMode
        self.state = state
        self.usage = usage
        self.estimatedCostCents = estimatedCostCents.map { max(0, $0) }
        self.currencyCode = currencyCode.map(Self.normalizedCurrencyCode)
        self.model = model.map(Self.redactedModel)
        self.capStatus = capStatus
        self.note = note.map(Self.redactedText)
    }

    public static func localOnly(note: String? = "Local-only execution. SoloPM managed charge unavailable.") -> Self {
        AssistantQueueCostPreview(
            billingMode: .localOnly,
            state: .unavailable,
            capStatus: .notConfigured,
            note: note
        )
    }

    public static func userProviderBilled(
        provider: String,
        modelName: String,
        note: String? = "BYOK or user-provider billing. SoloPM managed charge unavailable."
    ) -> Self {
        AssistantQueueCostPreview(
            billingMode: .userProviderBilled,
            state: .unavailable,
            model: ExecutionReceiptModel(
                provider: redactedText(provider),
                name: redactedText(modelName)
            ),
            capStatus: .notConfigured,
            note: note
        )
    }

    public var executionReceiptUsage: ExecutionReceiptUsage {
        switch state {
        case .estimated:
            return ExecutionReceiptUsage(
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                estimatedCostCents: estimatedCostCents,
                currencyCode: currencyCode,
                state: .estimated
            )
        case .unknown:
            return .unknown
        case .unavailable:
            return .unavailable
        }
    }

    public var allowsApprovalAndRun: Bool {
        switch billingMode {
        case .localOnly, .userProviderBilled:
            return true
        case .soloPMManaged:
            return state == .estimated && capStatus != .wouldExceedLimit
        }
    }

    public var reviewLabel: String {
        switch (billingMode, state) {
        case (.soloPMManaged, .estimated):
            return estimatedReviewLabel
        case (.soloPMManaged, .unknown):
            return "Preview only: managed cost unknown, not charged yet"
        case (.soloPMManaged, .unavailable):
            return "Preview only: managed cost unavailable, not charged yet"
        case (.localOnly, _):
            return "Preview only: local execution, no SoloPM managed charge"
        case (.userProviderBilled, _):
            return "Preview only: BYOK/user-provider billed, no SoloPM managed charge"
        }
    }

    private var estimatedReviewLabel: String {
        var parts = ["Preview only: estimated before run", "not charged yet", "SoloPM managed"]
        if let estimatedCostCents, let currencyCode {
            parts.append("\(currencyCode) \(Self.formattedMajorCurrency(fromCents: estimatedCostCents))")
        }
        if let totalTokens = usage.totalTokens {
            parts.append("\(Self.formattedInteger(totalTokens)) tokens")
        }
        switch capStatus {
        case .withinLimit:
            parts.append("cap OK")
        case .wouldExceedLimit:
            parts.append("cap exceeded")
        case .notConfigured:
            break
        }
        return parts.joined(separator: ", ")
    }

    private static func redactedModel(_ model: ExecutionReceiptModel) -> ExecutionReceiptModel {
        ExecutionReceiptModel(
            provider: redactedText(model.provider),
            name: redactedText(model.name)
        )
    }

    private static func redactedText(_ value: String) -> String {
        let redacted = DeveloperSecretRedactor().redact(value).text
        let trimmed = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func normalizedCurrencyCode(_ value: String) -> String {
        let trimmed = redactedText(value).uppercased()
        return trimmed.isEmpty ? "USD" : trimmed
    }

    private static func formattedMajorCurrency(fromCents cents: Double) -> String {
        let value = cents / 100
        let format = value > 0 && value < 0.01 ? "%.4f" : "%.2f"
        return String(format: format, value)
    }

    private static func formattedInteger(_ value: Int) -> String {
        let digits = Array(String(abs(value)).reversed())
        let grouped = stride(from: 0, to: digits.count, by: 3)
            .map { start -> String in
                let end = min(start + 3, digits.count)
                return String(digits[start..<end].reversed())
            }
            .reversed()
            .joined(separator: ",")
        return value < 0 ? "-\(grouped)" : grouped
    }
}
