import SuisuiCore
import SwiftUI

struct ActionReviewPanel: View {
    @StateObject private var viewModel: ReviewSessionViewModel
    private let onExecutionFinished: () -> Void

    init(viewModel: ReviewSessionViewModel, onExecutionFinished: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onExecutionFinished = onExecutionFinished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActionReviewHeader(
                summary: viewModel.session.originalPlan.summary,
                approvalLabel: approvalLabel,
                riskLevel: viewModel.session.originalPlan.riskLevel
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.session.items) { item in
                        ReviewActionRow(item: item, viewModel: viewModel)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 260)

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.danger.color)
            }
            if let message = viewModel.auditErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
            }
            if let message = viewModel.executionReceiptErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
            }
            if let receipt = viewModel.lastExecutionReceipt {
                ExecutionReceiptSummaryView(receipt: receipt)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    actionButtons
                }
            }
        }
        .accessibilityIdentifier("voice-action-review-panel")
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            viewModel.approveOrReportError()
        } label: {
            Label("Approve", systemImage: "checkmark.seal")
        }
        .disabled(!viewModel.canApprove)
        .accessibilityIdentifier("voice-action-review-approve")

        Button {
            if viewModel.executeOrReportError(), viewModel.session.executionStatus == .completed {
                onExecutionFinished()
            }
        } label: {
            Label("Execute", systemImage: "play.circle")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canExecute)
        .accessibilityIdentifier("voice-action-review-execute")

        Button {
            viewModel.cancel()
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
        }
        .disabled(viewModel.session.executionStatus == .completed || viewModel.session.executionStatus == .canceled)
        .accessibilityIdentifier("voice-action-review-cancel")
    }

    private var approvalLabel: String {
        switch viewModel.session.approvalState {
        case .notRequired:
            "No approval required"
        case .pending:
            "Approval required before execution"
        case .approved:
            "Approved"
        case .blocked(let reason):
            reason
        }
    }
}

private struct ExecutionReceiptSummaryView: View {
    let receipt: ExecutionReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label(localizedSettingsDisplay("Execution receipt"), systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                    statusLabel
                    Spacer(minLength: 8)
                    usageLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(localizedSettingsDisplay("Execution receipt"), systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                    HStack(spacing: 8) {
                        statusLabel
                        usageLabel
                    }
                }
            }

            Text(receipt.outputSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voice-execution-receipt-output")

            if !receipt.actions.isEmpty {
                Text(String(format: localizedSettingsDisplay("%d actions recorded"), receipt.actions.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-execution-receipt")
        .accessibilityLabel(localizedSettingsDisplay("Execution receipt"))
        .accessibilityValue(accessibilityValue)
    }

    private var statusLabel: some View {
        Text(localizedSettingsDisplay(statusText))
            .font(.caption2)
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .accessibilityIdentifier("voice-execution-receipt-status")
    }

    private var usageLabel: some View {
        Text(localizedSettingsDisplay(usageText))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("voice-execution-receipt-cost")
    }

    private var statusText: String {
        switch receipt.status {
        case .notStarted:
            "Not started"
        case .running:
            "Running"
        case .succeeded:
            "Succeeded"
        case .failed:
            "Failed"
        case .skipped:
            "Skipped"
        case .canceled:
            "Canceled"
        }
    }

    private var statusColor: Color {
        switch receipt.status {
        case .succeeded:
            SuisuiTone.positive.color
        case .failed:
            SuisuiTone.danger.color
        case .canceled, .skipped:
            SuisuiTone.attention.color
        case .notStarted, .running:
            .secondary
        }
    }

    private var usageText: String {
        switch receipt.usage.state {
        case .measured:
            if let totalTokens = receipt.usage.totalTokens {
                return String(format: localizedSettingsDisplay("%d tokens"), totalTokens)
            }
            return "Measured cost"
        case .estimated:
            if let totalTokens = receipt.usage.totalTokens {
                return String(format: localizedSettingsDisplay("%d tokens estimated"), totalTokens)
            }
            return "Estimated cost"
        case .unknown:
            return "Cost unknown"
        case .unavailable:
            return "Cost unavailable"
        }
    }

    private var accessibilityValue: String {
        "\(localizedSettingsDisplay(statusText)). \(receipt.outputSummary)"
    }
}

private struct ActionReviewHeader: View {
    let summary: String
    let approvalLabel: String
    let riskLevel: RiskLevel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                titleBlock
                Spacer(minLength: 8)
                riskBadge
            }

            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                riskBadge
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(summary)
            Text(localizedSettingsDisplay(approvalLabel))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(localizedSettingsDisplay(approvalLabel))
        }
    }

    private var riskBadge: some View {
        Text(localizedRiskLevel(riskLevel))
            .font(.caption)
            .foregroundStyle(riskLevel >= .write ? SuisuiTone.attention.color : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ReviewActionRow: View {
    let item: ReviewActionItem
    @ObservedObject var viewModel: ReviewSessionViewModel

    /// Anything that writes outside Suisui is shown in full. Collapsing a
    /// destination path, a calendar, or a recipient behind "+2 more" asks the
    /// user to approve text they cannot see.
    private var showsEveryFieldInFull: Bool {
        viewModel.session.originalPlan.riskLevel >= .write
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReviewActionTitleRow(
                item: item,
                viewModel: viewModel,
                statusLabel: statusLabel,
                statusColor: statusColor
            )

            if item.editedAction.arguments["title"]?.stringValue != nil {
                TextField(
                    "Title",
                    text: Binding(
                        get: { currentStringArgument("title") },
                        set: { viewModel.updateStringArgument(actionID: item.id, key: "title", value: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .help(currentStringArgument("title"))
            }

            ReviewActionFieldList(
                fields: item.argumentDisplayFields(),
                showsEveryFieldInFull: showsEveryFieldInFull
            )

            ForEach(viewModel.validationIssues(for: item.id), id: \.message) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
                    .lineLimit(2)
            }

            if let result = item.result {
                Text(result.summary)
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.positive.color)
            }
            if let error = item.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.danger.color)
                    .lineLimit(2)
            }
            if let failureRecovery = item.failureRecovery {
                Label(localizedSettingsDisplay(failureRecoveryLabel(failureRecovery)), systemImage: failureRecovery == .retryable ? "arrow.clockwise" : "lock")
                    .font(.caption)
                    .foregroundStyle(failureRecoveryColor(failureRecovery))
            }
        }
    }

    private var statusLabel: String {
        switch item.executionStatus {
        case .pending:
            "Pending"
        case .executing:
            "Executing"
        case .succeeded:
            "Done"
        case .failed:
            "Failed"
        case .skipped:
            "Skipped"
        }
    }

    private var statusColor: Color {
        switch item.executionStatus {
        case .succeeded:
            SuisuiTone.positive.color
        case .failed:
            SuisuiTone.danger.color
        case .skipped:
            .secondary
        default:
            .secondary
        }
    }

    private func currentStringArgument(_ key: String) -> String {
        viewModel.session.items
            .first(where: { $0.id == item.id })?
            .editedAction
            .arguments[key]?
            .stringValue ?? ""
    }

    private func failureRecoveryLabel(_ recovery: ReviewActionFailureRecovery) -> String {
        switch recovery {
        case .retryable:
            "Retry available after review"
        case .notRetryable:
            "Requires edit or Settings"
        }
    }

    private func failureRecoveryColor(_ recovery: ReviewActionFailureRecovery) -> Color {
        switch recovery {
        case .retryable:
            .secondary
        case .notRetryable:
            SuisuiTone.attention.color
        }
    }
}

/// Renders plan arguments as labelled rows.
///
/// This replaced a single `"key: value, key: value"` blob that was clipped to
/// three lines with the remainder reachable only through a mouse-hover
/// tooltip — unusable with a keyboard or VoiceOver, on the one surface whose
/// whole job is informed consent.
private struct ReviewActionFieldList: View {
    let fields: [ReviewActionField]
    let showsEveryFieldInFull: Bool

    private static let compactFieldLimit = 4

    private var visibleFields: [ReviewActionField] {
        showsEveryFieldInFull ? fields : Array(fields.prefix(Self.compactFieldLimit))
    }

    private var hiddenFieldCount: Int {
        fields.count - visibleFields.count
    }

    private var localizedFullText: String {
        fields
            .map { "\(localizedReviewFieldLabel($0)): \(localizedReviewFieldValue($0))" }
            .joined(separator: ", ")
    }

    var body: some View {
        if fields.isEmpty {
            Text("No arguments")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("voice-action-review-no-arguments")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(visibleFields) { field in
                    fieldRow(field)
                }

                if hiddenFieldCount > 0 {
                    Text(localizedDisplay("+%d more", hiddenFieldCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The visual rows are per-field, but assistive technology should
            // hear the whole proposal as one uninterrupted statement.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(localizedSettingsDisplay("Proposed values"))
            .accessibilityValue(localizedFullText)
            // The tooltip stays as a pointer convenience, but it is no longer
            // the only way to read a clipped value.
            .help(localizedFullText)
            .accessibilityIdentifier("voice-action-review-arguments")
        }
    }

    private func fieldRow(_ field: ReviewActionField) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(localizedReviewFieldLabel(field))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 68, alignment: .leading)

            Text(localizedReviewFieldValue(field))
                .font(.caption)
                // Write-risk values are never clipped; low-risk reads stay
                // compact so a long plan is still scannable.
                .lineLimit(showsEveryFieldInFull ? nil : 2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReviewActionTitleRow: View {
    let item: ReviewActionItem
    @ObservedObject var viewModel: ReviewSessionViewModel
    let statusLabel: String
    let statusColor: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                enabledToggle
                Spacer(minLength: 8)
                statusBadge
            }

            VStack(alignment: .leading, spacing: 6) {
                enabledToggle
                statusBadge
            }
        }
    }

    private var enabledToggle: some View {
        Toggle(
            isOn: Binding(
                get: { item.isEnabled },
                set: { viewModel.setActionEnabled(actionID: item.id, isEnabled: $0) }
            )
        ) {
            Label {
                Text(localizedActionTool(item.editedAction.tool))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: reviewIconName(for: item.editedAction.actionType))
            }
            .font(.subheadline)
            .help(localizedActionTool(item.editedAction.tool))
        }
    }

    private var statusBadge: some View {
        Text(localizedSettingsDisplay(statusLabel))
            .font(.caption)
            .foregroundStyle(statusColor)
            .lineLimit(1)
    }
}

private func reviewIconName(for actionType: ActionType) -> String {
    switch actionType {
    case .project:
        "folder"
    case .task:
        "checkmark.circle"
    case .notification:
        "bell"
    case .calendar:
        "calendar"
    case .reminder:
        "list.bullet"
    case .filesystem:
        "doc"
    case .knowledgeFrame:
        "text.book.closed"
    case .mailDraft:
        "envelope"
    case .developer:
        "terminal"
    }
}
