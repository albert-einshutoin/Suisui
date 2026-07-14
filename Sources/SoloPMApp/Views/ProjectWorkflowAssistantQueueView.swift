import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

struct AssistantQueueWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var snapshot: AssistantQueueSnapshot {
        viewModel.assistantQueueSnapshot
    }

    private var subtitle: String {
        String(
            format: String(localized: "%d waiting, %d blocked"),
            snapshot.waitingReviewCount,
            snapshot.blockedCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                WorkflowHeader(
                    title: "Assistant Queue",
                    subtitle: subtitle,
                    systemImage: "tray.full"
                )
                Spacer(minLength: 12)
                AssistantQueueCountStrip(snapshot: snapshot)
            }

            Text("Review AI-generated work before anything runs. Approval records intent; Run uses the existing execution gate and creates a receipt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistant-queue-boundary-note")

            AssistantQueueTriageControls(viewModel: viewModel)
            AssistantQueueBatchToolbar(viewModel: viewModel)

            if viewModel.openRescheduleSuggestionIDs.count >= 2 {
                Button {
                    _ = viewModel.approveAllRescheduleSuggestions()
                } label: {
                    Label("Approve all reschedules", systemImage: "checkmark.seal.fill")
                }
                .disabled(viewModel.isApprovingAllRescheduleSuggestions)
                .controlSize(.small)
                .help("Approve every open reschedule suggestion one by one")
                .accessibilityIdentifier("assistant-queue-approve-all-reschedules")
                .accessibilityHint("Approves each open reschedule suggestion through the same per-item review path. Nothing runs until each item passes the execution gate.")
            }

            if snapshot.rows.isEmpty {
                ContentUnavailableView(
                    "Assistant Queue is clear",
                    systemImage: "tray.full",
                    description: Text("Voice plans, automation drafts, and connector writes appear here before execution.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.rows) { row in
                            AssistantQueueRow(row: row, viewModel: viewModel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-queue-workflow")
        .accessibilityLabel("Assistant Queue")
        .accessibilityValue(subtitle)
        .accessibilityHint("Reviews AI-generated drafts before execution.")
    }
}

private struct AssistantQueueTriageControls: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filterPicker
                sortPicker
            }

            VStack(alignment: .leading, spacing: 8) {
                filterPicker
                sortPicker
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-queue-triage-controls")
    }

    private var filterPicker: some View {
        Picker("Filter", selection: filterBinding) {
            ForEach(AssistantQueueViewFilter.allCases) { filter in
                Text(LocalizedStringKey(filter.title)).tag(filter)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("assistant-queue-filter")
        .accessibilityHint("Filters Assistant Queue rows without changing stored queue state.")
    }

    private var sortPicker: some View {
        Picker("Sort", selection: sortBinding) {
            ForEach(AssistantQueueSort.allCases) { sort in
                Text(LocalizedStringKey(sort.title)).tag(sort)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("assistant-queue-sort")
        .accessibilityHint("Sorts visible Assistant Queue rows.")
    }

    private var filterBinding: Binding<AssistantQueueViewFilter> {
        Binding(
            get: { viewModel.assistantQueueViewFilter },
            set: { viewModel.setAssistantQueueViewFilter($0) }
        )
    }

    private var sortBinding: Binding<AssistantQueueSort> {
        Binding(
            get: { viewModel.assistantQueueSort },
            set: { viewModel.setAssistantQueueSort($0) }
        )
    }
}

private struct AssistantQueueBatchToolbar: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var selectedCount: Int {
        viewModel.assistantQueueSelectedItemIDs.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: String(localized: "%d selected"), selectedCount))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                _ = viewModel.deferSelectedAssistantQueueItems()
            } label: {
                Label("Defer selected", systemImage: "clock")
            }
            .disabled(selectedCount == 0)
            .controlSize(.small)
            .accessibilityIdentifier("assistant-queue-batch-defer")
            .accessibilityHint("Defers selected reviewable Assistant Queue items without approving or running them.")

            Button {
                _ = viewModel.rejectSelectedAssistantQueueItems()
            } label: {
                Label("Reject selected", systemImage: "xmark.circle")
            }
            .disabled(selectedCount == 0)
            .controlSize(.small)
            .accessibilityIdentifier("assistant-queue-batch-reject")
            .accessibilityHint("Rejects selected Assistant Queue items that are still rejectable.")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-queue-batch-toolbar")
        .accessibilityLabel("Assistant Queue batch toolbar")
    }
}

private struct AssistantQueueCountStrip: View {
    let snapshot: AssistantQueueSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                badge(title: "Total", value: snapshot.totalCount, tint: .secondary)
                badge(title: "Waiting", value: snapshot.waitingReviewCount, tint: .orange)
                badge(title: "Blocked", value: snapshot.blockedCount, tint: .red)
                badge(title: "Failed", value: snapshot.failedCount, tint: .red)
            }

            VStack(alignment: .leading, spacing: 8) {
                badge(title: "Total", value: snapshot.totalCount, tint: .secondary)
                badge(title: "Waiting", value: snapshot.waitingReviewCount, tint: .orange)
                badge(title: "Blocked", value: snapshot.blockedCount, tint: .red)
                badge(title: "Failed", value: snapshot.failedCount, tint: .red)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-queue-count-strip")
        .accessibilityLabel("Assistant Queue counts")
    }

    private func badge(title: LocalizedStringKey, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 72, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AssistantQueueRow: View {
    let row: AssistantQueueReadModelRow
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var isEditing = false
    @State private var draftReviewReason = ""
    @State private var draftRedactedSummary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: selectionBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("assistant-queue-select-\(row.id)")
                    .accessibilityLabel("Select Assistant Queue item")
                    .accessibilityValue(viewModel.assistantQueueSelectedItemIDs.contains(row.id) ? "Selected" : "Not selected")

                Image(systemName: stateSystemImage)
                    .foregroundStyle(stateTint)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(row.stateLabel))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stateTint)
                        Label(row.riskLabel, systemImage: "shield")
                        if !row.capabilityLabels.isEmpty {
                            Label(row.capabilityLabels.joined(separator: ", "), systemImage: "key")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                    Text(row.reviewReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sourcePreview = row.sourcePreview, !sourcePreview.isEmpty {
                        Label(sourcePreview, systemImage: "quote.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let costPreviewLabel = row.costPreviewLabel, !costPreviewLabel.isEmpty {
                        Label(costPreviewLabel, systemImage: "chart.bar.doc.horizontal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let blockingReason = row.blockingReason {
                        Label(blockingReason, systemImage: "exclamationmark.octagon")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let receipt = row.latestReceipt {
                        Divider()
                            .padding(.vertical, 2)

                        AssistantQueueReceiptSummaryView(receipt: receipt)
                            .accessibilityIdentifier("assistant-queue-receipt-\(row.id)")
                    }

                    if isEditing {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Review reason", text: $draftReviewReason, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("assistant-queue-edit-reason-\(row.id)")
                                .accessibilityHint("Updates the review reason and requires approval again.")

                            TextField("Redacted summary", text: $draftRedactedSummary, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("assistant-queue-edit-summary-\(row.id)")
                                .accessibilityHint("Updates only the redacted queue summary shown for review.")

                            HStack(spacing: 8) {
                                Button {
                                    if viewModel.editAssistantQueueItem(
                                        id: row.id,
                                        reviewReason: draftReviewReason,
                                        redactedSummary: draftRedactedSummary
                                    ) {
                                        isEditing = false
                                    }
                                } label: {
                                    Label("Save", systemImage: "checkmark")
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("assistant-queue-edit-save-\(row.id)")
                                .accessibilityHint("Saves edited review details and clears any prior queue approval.")

                                Button {
                                    isEditing = false
                                    draftReviewReason = row.reviewReason
                                    draftRedactedSummary = row.redactedSummary
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("assistant-queue-edit-cancel-\(row.id)")
                                .accessibilityHint("Discards local edits to this review form.")
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button {
                    _ = viewModel.runAssistantQueueItem(id: row.id)
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(!row.canRun)
                .controlSize(.small)
                .help("Run this approved item through the execution gate")
                .accessibilityIdentifier("assistant-queue-run-\(row.id)")
                .accessibilityHint("Executes approved generated work through the review gate and records a receipt.")

                Button {
                    _ = viewModel.approveAssistantQueueItem(id: row.id)
                } label: {
                    Label("Approve", systemImage: "checkmark.seal")
                }
                .disabled(!row.canApprove)
                .controlSize(.small)
                .help("Approve this queue item without running it")
                .accessibilityIdentifier("assistant-queue-approve-\(row.id)")
                .accessibilityHint("Records approval intent. Execution still requires the review gate.")

                Button {
                    _ = viewModel.deferAssistantQueueItem(id: row.id)
                } label: {
                    Label("Defer", systemImage: "clock")
                }
                .disabled(!row.canDefer)
                .controlSize(.small)
                .help("Review this queue item later")
                .accessibilityIdentifier("assistant-queue-defer-\(row.id)")
                .accessibilityHint("Keeps this generated work in the local queue for later review.")

                Button {
                    draftReviewReason = row.reviewReason
                    draftRedactedSummary = row.redactedSummary
                    isEditing.toggle()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(!row.canEdit)
                .controlSize(.small)
                .help("Edit review details before approving this queue item")
                .accessibilityIdentifier("assistant-queue-edit-\(row.id)")
                .accessibilityHint("Edits the review reason and redacted summary without changing raw action arguments.")

                Button {
                    _ = viewModel.retryAssistantQueueItem(id: row.id)
                } label: {
                    Label("Reopen", systemImage: "arrow.clockwise")
                }
                .disabled(!row.canRetry)
                .controlSize(.small)
                .help("Reopen this failed item for review before running it again")
                .accessibilityIdentifier("assistant-queue-retry-\(row.id)")
                .accessibilityHint("Returns failed generated work to review. It does not run until approved again.")

                Button {
                    _ = viewModel.rejectAssistantQueueItem(id: row.id)
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .disabled(!row.canReject)
                .controlSize(.small)
                .help("Reject this queue item")
                .accessibilityIdentifier("assistant-queue-reject-\(row.id)")
                .accessibilityHint("Marks this generated work rejected without running it.")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(row.state == .blocked ? Color.red.opacity(0.35) : Color.secondary.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-queue-row-\(row.id)")
        .accessibilityLabel(row.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Review this Assistant Queue item before execution.")
    }

    private var stateSystemImage: String {
        switch row.state {
        case .blocked:
            "exclamationmark.octagon"
        case .failed:
            "exclamationmark.triangle"
        case .approved:
            "checkmark.seal"
        case .rejected:
            "xmark.circle"
        case .deferred:
            "clock"
        case .done:
            "checkmark.circle"
        case .running:
            "arrow.triangle.2.circlepath"
        case .captured, .interpreted, .drafted, .waitingReview:
            "tray.full"
        }
    }

    private var stateTint: Color {
        switch row.state {
        case .blocked, .failed:
            .red
        case .approved:
            .green
        case .rejected:
            .secondary
        case .deferred:
            .blue
        case .done:
            .green
        case .running:
            .orange
        case .captured, .interpreted, .drafted, .waitingReview:
            .orange
        }
    }

    private var accessibilityValue: String {
        var values = [
            "State: \(row.stateLabel)",
            "Risk: \(row.riskLabel)",
            "Reason: \(row.reviewReason)"
        ]
        if let sourcePreview = row.sourcePreview {
            values.append("Source: \(sourcePreview)")
        }
        if !row.capabilityLabels.isEmpty {
            values.append("Capabilities: \(row.capabilityLabels.joined(separator: ", "))")
        }
        if let blockingReason = row.blockingReason {
            values.append("Blocked: \(blockingReason)")
        }
        if let receipt = row.latestReceipt {
            values.append(localizedDisplay("Receipt: %@", localizedDisplay(receipt.statusLabel)))
            values.append(receipt.outputSummary)
        }
        return values.joined(separator: ", ")
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.assistantQueueSelectedItemIDs.contains(row.id) },
            set: { selected in
                _ = viewModel.setAssistantQueueSelection(id: row.id, selected: selected)
            }
        )
    }
}

private struct AssistantQueueReceiptSummaryView: View {
    let receipt: AssistantQueueReceiptSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(localizedDisplay("Receipt: %@", localizedDisplay(receipt.statusLabel)), systemImage: receiptSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(receiptTint)
                Text(String(format: String(localized: "%d actions recorded"), receipt.actionCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(receipt.usageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(receipt.outputSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(localizedDisplay("Receipt ID: %@", receipt.id))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Assistant Queue execution receipt")
        .accessibilityValue(accessibilityValue)
    }

    private var receiptSystemImage: String {
        switch receipt.status {
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .running:
            "arrow.triangle.2.circlepath"
        case .canceled:
            "stop.circle"
        case .skipped:
            "forward.end"
        case .notStarted:
            "circle"
        }
    }

    private var receiptTint: Color {
        switch receipt.status {
        case .succeeded:
            .green
        case .failed:
            .red
        case .running:
            .orange
        case .canceled, .skipped, .notStarted:
            .secondary
        }
    }

    private var accessibilityValue: String {
        [
            localizedDisplay("Receipt: %@", localizedDisplay(receipt.statusLabel)),
            String(format: String(localized: "%d actions recorded"), receipt.actionCount),
            localizedDisplay(receipt.usageLabel),
            receipt.outputSummary,
            localizedDisplay("Receipt ID: %@", receipt.id)
        ].joined(separator: ", ")
    }
}
