import Foundation

public struct ExecutionUsageMeterSnapshot: Equatable, Sendable {
    public var summary: ExecutionUsageMeterSummary
    public var dailyRows: [ExecutionUsageMeterBucketRow]
    public var monthlyRows: [ExecutionUsageMeterBucketRow]
    public var projectRows: [ExecutionUsageMeterBucketRow]
    public var scopeLabel: String
    public var unavailableMessage: String?

    public init(
        summary: ExecutionUsageMeterSummary = .empty,
        dailyRows: [ExecutionUsageMeterBucketRow] = [],
        monthlyRows: [ExecutionUsageMeterBucketRow] = [],
        projectRows: [ExecutionUsageMeterBucketRow] = [],
        scopeLabel: String = String(localized: "Recent audit receipts"),
        unavailableMessage: String? = nil
    ) {
        self.summary = summary
        self.dailyRows = dailyRows
        self.monthlyRows = monthlyRows
        self.projectRows = projectRows
        self.scopeLabel = ExecutionUsageMeterReadModel.redactedDisplayText(scopeLabel, fallback: String(localized: "Recent audit receipts"))
        self.unavailableMessage = unavailableMessage
    }

    public static let empty = ExecutionUsageMeterSnapshot()

    public var summaryLabel: String {
        "\(summary.totalTokenLabel), \(summary.receiptCountLabel), \(summary.costLabel)"
    }

    public var accessibilityValue: String {
        [
            scopeLabel,
            summary.totalTokenLabel,
            summary.inputTokenLabel,
            summary.outputTokenLabel,
            summary.receiptCountLabel,
            summary.costLabel
        ].joined(separator: ", ")
    }
}

public struct ExecutionUsageMeterSummary: Equatable, Sendable {
    public var trackedReceiptCount: Int
    public var measuredReceiptCount: Int
    public var estimatedReceiptCount: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var costTotals: [ExecutionUsageMeterCostTotal]

    public init(
        trackedReceiptCount: Int,
        measuredReceiptCount: Int,
        estimatedReceiptCount: Int,
        inputTokens: Int,
        outputTokens: Int,
        costTotals: [ExecutionUsageMeterCostTotal] = []
    ) {
        self.trackedReceiptCount = max(0, trackedReceiptCount)
        self.measuredReceiptCount = max(0, measuredReceiptCount)
        self.estimatedReceiptCount = max(0, estimatedReceiptCount)
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.costTotals = costTotals.sorted { $0.currencyCode < $1.currencyCode }
    }

    public static let empty = ExecutionUsageMeterSummary(
        trackedReceiptCount: 0,
        measuredReceiptCount: 0,
        estimatedReceiptCount: 0,
        inputTokens: 0,
        outputTokens: 0
    )

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public var totalTokenLabel: String {
        String(format: String(localized: "%@ tokens"), Self.formattedInteger(totalTokens))
    }

    public var inputTokenLabel: String {
        String(format: String(localized: "%@ input"), Self.formattedInteger(inputTokens))
    }

    public var outputTokenLabel: String {
        String(format: String(localized: "%@ output"), Self.formattedInteger(outputTokens))
    }

    public var receiptCountLabel: String {
        String(format: String(localized: "%d tracked receipts"), trackedReceiptCount)
    }

    public var costLabel: String {
        guard !costTotals.isEmpty else {
            return String(localized: "No cost recorded")
        }
        return costTotals.map(\.displayLabel).joined(separator: ", ")
    }

    fileprivate static func formattedInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

public struct ExecutionUsageMeterCostTotal: Equatable, Sendable {
    public var currencyCode: String
    public var measuredCostCents: Double
    public var estimatedCostCents: Double

    public init(currencyCode: String, measuredCostCents: Double = 0, estimatedCostCents: Double = 0) {
        self.currencyCode = Self.normalizedCurrencyCode(currencyCode)
        self.measuredCostCents = max(0, measuredCostCents)
        self.estimatedCostCents = max(0, estimatedCostCents)
    }

    public var displayLabel: String {
        let measured = Self.majorCurrencyLabel(fromCents: measuredCostCents)
        let estimated = Self.majorCurrencyLabel(fromCents: estimatedCostCents)
        return String(format: String(localized: "%@ %@ measured / %@ estimated"), currencyCode, measured, estimated)
    }

    private static func normalizedCurrencyCode(_ value: String) -> String {
        let redacted = AssistantQueueCostPreview.redactedMetadataText(value)
        let trimmed = redacted.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "USD" : trimmed
    }

    private static func majorCurrencyLabel(fromCents cents: Double) -> String {
        let value = cents / 100
        let format = value > 0 && value < 0.01 ? "%.4f" : "%.2f"
        return String(format: format, value)
    }
}

public struct ExecutionUsageMeterBucketRow: Identifiable, Equatable, Sendable {
    public var id: String { bucketKey }
    public var bucketKey: String
    public var title: String
    public var summary: ExecutionUsageMeterSummary

    public init(bucketKey: String, title: String, summary: ExecutionUsageMeterSummary) {
        self.bucketKey = ExecutionUsageMeterReadModel.redactedDisplayText(bucketKey, fallback: "unknown")
        self.title = ExecutionUsageMeterReadModel.redactedDisplayText(title, fallback: "Unknown")
        self.summary = summary
    }

    public var accessibilityValue: String {
        "\(title), \(summary.totalTokenLabel), \(summary.receiptCountLabel), \(summary.costLabel)"
    }
}

public enum ExecutionUsageMeterReadModel {
    public static func snapshot(
        from receipts: [ExecutionReceipt],
        calendar: Calendar = utcCalendar(),
        scopeLabel: String = String(localized: "Recent audit receipts")
    ) -> ExecutionUsageMeterSnapshot {
        let trackedReceipts = receipts
            .filter { $0.visibleSurfaces.contains(.auditLog) }
            .filter { usageIsBillableTelemetry($0.usage) }

        return ExecutionUsageMeterSnapshot(
            summary: summary(from: trackedReceipts),
            dailyRows: bucketRows(
                receipts: trackedReceipts,
                key: { dayKey(for: occurrenceDate(for: $0), calendar: calendar) },
                title: { String(format: String(localized: "%@ UTC"), dayKey(for: occurrenceDate(for: $0), calendar: calendar)) }
            ),
            monthlyRows: bucketRows(
                receipts: trackedReceipts,
                key: { monthKey(for: occurrenceDate(for: $0), calendar: calendar) },
                title: { String(format: String(localized: "%@ UTC"), monthKey(for: occurrenceDate(for: $0), calendar: calendar)) }
            ),
            projectRows: projectRows(from: trackedReceipts),
            scopeLabel: scopeLabel
        )
    }

    public static func redactedDisplayText(_ value: String, fallback: String) -> String {
        let redacted = AssistantQueueCostPreview.redactedMetadataText(value)
        let trimmed = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func summary(from receipts: [ExecutionReceipt]) -> ExecutionUsageMeterSummary {
        let costTotals = Dictionary(grouping: receipts.compactMap(costComponent), by: \.currencyCode)
            .map { currencyCode, components in
                ExecutionUsageMeterCostTotal(
                    currencyCode: currencyCode,
                    measuredCostCents: components.reduce(0) { $0 + $1.measuredCostCents },
                    estimatedCostCents: components.reduce(0) { $0 + $1.estimatedCostCents }
                )
            }
            .sorted { $0.currencyCode < $1.currencyCode }

        return ExecutionUsageMeterSummary(
            trackedReceiptCount: receipts.count,
            measuredReceiptCount: receipts.filter { $0.usage.state == .measured }.count,
            estimatedReceiptCount: receipts.filter { $0.usage.state == .estimated }.count,
            inputTokens: receipts.reduce(0) { $0 + ($1.usage.inputTokens ?? 0) },
            outputTokens: receipts.reduce(0) { $0 + ($1.usage.outputTokens ?? 0) },
            costTotals: costTotals
        )
    }

    private static func bucketRows(
        receipts: [ExecutionReceipt],
        key: (ExecutionReceipt) -> String,
        title: (ExecutionReceipt) -> String
    ) -> [ExecutionUsageMeterBucketRow] {
        Dictionary(grouping: receipts, by: key)
            .map { bucketKey, bucketReceipts in
                ExecutionUsageMeterBucketRow(
                    bucketKey: bucketKey,
                    title: title(bucketReceipts[0]),
                    summary: summary(from: bucketReceipts)
                )
            }
            .sorted { $0.bucketKey > $1.bucketKey }
    }

    private static func projectRows(from receipts: [ExecutionReceipt]) -> [ExecutionUsageMeterBucketRow] {
        var grouped: [String: [ExecutionReceipt]] = [:]
        var labels: [String: String] = [:]
        for receipt in receipts {
            guard let reference = primaryProjectReference(in: receipt) else {
                continue
            }
            grouped[reference.id, default: []].append(receipt)
            if let label = reference.label, labels[reference.id] == nil {
                labels[reference.id] = label
            }
        }
        return grouped.map { projectID, projectReceipts in
            let redactedProjectID = redactedDisplayText(projectID, fallback: "unknown")
            let fallbackTitle = String(format: String(localized: "Project %@"), redactedProjectID)
            let title = labels[projectID].map { redactedDisplayText($0, fallback: fallbackTitle) } ?? fallbackTitle
            return ExecutionUsageMeterBucketRow(
                bucketKey: "project:\(redactedProjectID)",
                title: title,
                summary: summary(from: projectReceipts)
            )
        }
        .sorted { $0.summary.totalTokens == $1.summary.totalTokens ? $0.title < $1.title : $0.summary.totalTokens > $1.summary.totalTokens }
    }

    private static func primaryProjectReference(in receipt: ExecutionReceipt) -> ExecutionReceiptReference? {
        var seenProjectIDs = Set<String>()
        for reference in receipt.references where reference.kind == .project {
            let projectID = redactedDisplayText(reference.id, fallback: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectID.isEmpty, seenProjectIDs.insert(projectID).inserted else {
                continue
            }
            // Avoid double-counting multi-project receipts in the Personal MVP meter.
            // A future billing ledger can introduce explicit allocation rules.
            return reference
        }
        return nil
    }

    private static func usageIsBillableTelemetry(_ usage: ExecutionReceiptUsage) -> Bool {
        switch usage.state {
        case .measured, .estimated:
            return usage.inputTokens != nil || usage.outputTokens != nil || usage.estimatedCostCents != nil
        case .unknown, .unavailable:
            return false
        }
    }

    private static func costComponent(from receipt: ExecutionReceipt) -> ExecutionUsageMeterCostTotal? {
        guard let costCents = receipt.usage.estimatedCostCents,
              let currencyCode = receipt.usage.currencyCode else {
            return nil
        }
        switch receipt.usage.state {
        case .measured:
            return ExecutionUsageMeterCostTotal(currencyCode: currencyCode, measuredCostCents: costCents)
        case .estimated:
            return ExecutionUsageMeterCostTotal(currencyCode: currencyCode, estimatedCostCents: costCents)
        case .unknown, .unavailable:
            return nil
        }
    }

    private static func occurrenceDate(for receipt: ExecutionReceipt) -> Date {
        receipt.finishedAt ?? receipt.startedAt ?? receipt.createdAt
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    public static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
