import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

struct AssistantQueueWorkflowView: View {
    private enum WorkflowFocus: Hashable {
        case triageControls
    }

    @ObservedObject var viewModel: ProjectBoardViewModel
    @FocusState private var keyboardWorkflowFocus: WorkflowFocus?
    @AccessibilityFocusState private var accessibilityWorkflowFocus: WorkflowFocus?

    private var snapshot: AssistantQueueSnapshot {
        viewModel.assistantQueueSnapshot
    }

    // "waiting" and "blocked" are adjectives, so this needs no plural form —
    // only the app-language-aware lookup the rest of the surface uses.
    private var subtitle: String {
        localizedDisplay(
            "%d waiting, %d blocked",
            snapshot.waitingReviewCount,
            snapshot.blockedCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                WorkflowHeader(
                    title: "Pending Actions",
                    subtitle: subtitle,
                    systemImage: "tray.full"
                )
                Spacer(minLength: 12)
                AssistantQueueCountStrip(snapshot: snapshot)
            }

            Text("Review proposed changes before anything runs. Approval records intent; Run uses the existing execution gate and creates a receipt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistant-queue-boundary-note")

            // Keep triage reachable when the selected filter has no matches;
            // otherwise the user cannot switch back to a populated view.
            if snapshot.totalCount > 0 {
                AssistantQueueTriageControls(viewModel: viewModel)
                    .focusable()
                    .focused($keyboardWorkflowFocus, equals: .triageControls)
                    .accessibilityFocused($accessibilityWorkflowFocus, equals: .triageControls)
                if !viewModel.assistantQueueSelectedItemIDs.isEmpty {
                    AssistantQueueBatchToolbar(viewModel: viewModel)
                }
            }

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
                Group {
                    if snapshot.totalCount > 0 {
                        ContentUnavailableView(
                            "No matching tasks",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Choose another filter to see queued work.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Pending Actions is clear",
                            systemImage: "tray.full",
                            description: Text("Voice plans, automation drafts, and connector writes appear here before execution.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Keep all triage rows in the AX tree. LazyVStack omitted the
                    // failed landmark until scroll materialization, which broke
                    // visual evidence for the last queue state.
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.rows) { row in
                            AssistantQueueRow(
                                row: row,
                                viewModel: viewModel,
                                focusWorkflowControls: focusTriageControls
                            )
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
        .accessibilityLabel("Pending Actions")
        .accessibilityValue(subtitle)
        .accessibilityHint("Reviews proposed changes before execution.")
    }

    private func focusTriageControls() {
        Task { @MainActor in
            await Task.yield()
            keyboardWorkflowFocus = .triageControls
            accessibilityWorkflowFocus = .triageControls
        }
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
                Text(LocalizedStringKey(filter.title))
                    .tag(filter)
                    .accessibilityIdentifier(
                        "assistant-queue-filter-option-\(filter.rawValue)"
                    )
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
            Text(localizedDisplay("%d selected", selectedCount))
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
    private enum ActionFocus: Hashable {
        case editReason
        case primary
        case more
    }

    let row: AssistantQueueReadModelRow
    @ObservedObject var viewModel: ProjectBoardViewModel
    let focusWorkflowControls: () -> Void
    @State private var isEditing = false
    @State private var draftReviewReason = ""
    @State private var draftRedactedSummary = ""
    @State private var expectedMutationRevision: String?
    @State private var hasEditConflict = false
    @FocusState private var keyboardActionFocus: ActionFocus?
    @AccessibilityFocusState private var accessibilityActionFocus: ActionFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: selectionBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("assistant-queue-select-\(row.id)")
                    .accessibilityLabel("Select Assistant Queue item")
                    .accessibilityValue(viewModel.assistantQueueSelectedItemIDs.contains(row.id) ? "Selected" : "Not selected")
                    .disabled(!isBatchSelectable)

                Image(systemName: stateSystemImage)
                    .foregroundStyle(stateTint)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("assistant-queue-row-heading-\(row.id)")

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
                                .focused($keyboardActionFocus, equals: .editReason)
                                .accessibilityFocused($accessibilityActionFocus, equals: .editReason)
                                .accessibilityIdentifier("assistant-queue-edit-reason-\(row.id)")
                                .accessibilityHint("Updates the review reason and requires approval again.")
                                .disabled(!row.canEdit)

                            TextField("Redacted summary", text: $draftRedactedSummary, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("assistant-queue-edit-summary-\(row.id)")
                                .accessibilityHint("Updates only the redacted queue summary shown for review.")
                                .disabled(!row.canEdit)

                            HStack(spacing: 8) {
                                Button {
                                    guard let expectedMutationRevision else {
                                        hasEditConflict = true
                                        focusAction(afterYieldOn: .editReason)
                                        return
                                    }
                                    if viewModel.editAssistantQueueItem(
                                        id: row.id,
                                        expectedMutationRevision: expectedMutationRevision,
                                        reviewReason: draftReviewReason,
                                        redactedSummary: draftRedactedSummary
                                    ) {
                                        hasEditConflict = false
                                        isEditing = false
                                        if viewModel.assistantQueueViewFilter.states.contains(.waitingReview) {
                                            focusAfterEditing()
                                        } else {
                                            focusWorkflowControls()
                                        }
                                    } else {
                                        // Keeping the failed edit visible and focused prevents
                                        // users from losing review context before retrying.
                                        let latestRevision = viewModel.assistantQueueSnapshot.rows
                                            .first { $0.id == row.id }?
                                            .mutationRevision
                                        hasEditConflict = latestRevision != expectedMutationRevision
                                        keyboardActionFocus = .editReason
                                        accessibilityActionFocus = .editReason
                                    }
                                } label: {
                                    Label("Save", systemImage: "checkmark")
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("assistant-queue-edit-save-\(row.id)")
                                .accessibilityHint("Saves edited review details and clears any prior queue approval.")
                                .disabled(
                                    hasEditConflict
                                        || !row.canEdit
                                        || expectedMutationRevision == nil
                                )

                                Button {
                                    draftReviewReason = row.reviewReason
                                    draftRedactedSummary = row.redactedSummary
                                    expectedMutationRevision = row.mutationRevision
                                    hasEditConflict = false
                                    isEditing = false
                                    focusAfterEditing()
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                                .controlSize(.small)
                                .accessibilityIdentifier("assistant-queue-edit-cancel-\(row.id)")
                                .accessibilityHint("Discards local edits to this review form.")
                            }

                            if !row.canEdit {
                                Label(
                                    "This item can no longer be edited. Cancel to keep the latest queue state.",
                                    systemImage: "lock"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            } else if hasEditConflict {
                                HStack(spacing: 8) {
                                    Label(
                                        "This item changed in another window. Reload the latest details before saving.",
                                        systemImage: "arrow.triangle.2.circlepath"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.orange)

                                    Button("Reload latest") {
                                        draftReviewReason = row.reviewReason
                                        draftRedactedSummary = row.redactedSummary
                                        expectedMutationRevision = row.mutationRevision
                                        hasEditConflict = false
                                        focusAction(afterYieldOn: .editReason)
                                    }
                                    .controlSize(.small)
                                    .accessibilityIdentifier("assistant-queue-edit-reload-\(row.id)")
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                if let primary = actionPresentation.primaryAction {
                    primaryAction(primary)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .focused($keyboardActionFocus, equals: .primary)
                        .accessibilityFocused($accessibilityActionFocus, equals: .primary)
                }

                if actionPresentation.primaryAction == .approve && row.canApproveAndRun {
                    approveAndRunButton
                }

                if !actionPresentation.secondaryActions.isEmpty {
                    Menu {
                        ForEach(actionPresentation.secondaryActions, id: \.self) { action in
                            secondaryAction(action)
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .controlSize(.small)
                    .focused($keyboardActionFocus, equals: .more)
                    .accessibilityFocused($accessibilityActionFocus, equals: .more)
                    .help("More Assistant Queue actions")
                    .accessibilityIdentifier("assistant-queue-more-\(row.id)")
                }
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
        .accessibilityHint("Review this pending action before execution.")
        .onChange(of: row.state) { _, _ in
            markEditConflictIfNeeded()
        }
        .onChange(of: actionPresentation) { _, _ in
            markEditConflictIfNeeded()
        }
        .onChange(of: row.mutationRevision) { _, _ in
            markEditConflictIfNeeded()
        }
    }

    // Stage-specific presentation keeps the regular approval/run controls
    // constrained; the combined action below still uses the same revision gate.
    private var actionPresentation: AssistantQueueRowActionPresentation {
        AssistantQueueRowActionPresentation.make(for: row)
    }

    @ViewBuilder
    private func primaryAction(
        _ action: AssistantQueueRowActionPresentation.Action
    ) -> some View {
        switch action {
        case .approve:
            approveButton
        case .run:
            runButton
        case .reopen:
            reopenButton
        case .edit, .defer, .reject:
            EmptyView()
        }
    }

    @ViewBuilder
    private func secondaryAction(
        _ action: AssistantQueueRowActionPresentation.Action
    ) -> some View {
        switch action {
        case .approve, .run, .reopen:
            EmptyView()
        case .edit:
            editButton
        case .defer:
            deferButton
        case .reject:
            Button(role: .destructive) {
                guard let mutationRevision = row.mutationRevision else {
                    return
                }
                _ = viewModel.rejectAssistantQueueItem(
                    id: row.id,
                    expectedMutationRevision: mutationRevision
                )
            } label: {
                Label("Reject", systemImage: "xmark.circle")
            }
            .disabled(row.mutationRevision == nil)
            .help("Reject this queue item")
            .accessibilityIdentifier("assistant-queue-reject-\(row.id)")
            .accessibilityHint("Marks this generated work rejected without running it.")
        }
    }

    private var approveButton: some View {
        Button {
            guard let mutationRevision = row.mutationRevision else {
                return
            }
            _ = viewModel.approveAssistantQueueItem(
                id: row.id,
                expectedMutationRevision: mutationRevision
            )
        } label: {
            Label("Approve", systemImage: "checkmark.seal")
        }
        .help("Approve this queue item without running it")
        .disabled(row.mutationRevision == nil)
        .accessibilityIdentifier("assistant-queue-approve-\(row.id)")
        .accessibilityHint("Records approval intent. Execution still requires the review gate.")
    }

    private var approveAndRunButton: some View {
        Button {
            guard let mutationRevision = row.mutationRevision else {
                return
            }
            _ = viewModel.approveAndRunAssistantQueueItem(
                id: row.id,
                expectedMutationRevision: mutationRevision
            )
        } label: {
            Label("Approve & Run", systemImage: "checkmark.seal.fill")
        }
        .help("Approve this pending action and run it through the execution gate")
        .disabled(row.mutationRevision == nil)
        .accessibilityIdentifier("assistant-queue-approve-and-run-\(row.id)")
        .accessibilityHint("Records approval, then runs the reviewed action through the execution gate and records a receipt.")
    }

    private var runButton: some View {
        Button {
            guard let mutationRevision = row.mutationRevision else {
                return
            }
            _ = viewModel.runAssistantQueueItem(
                id: row.id,
                expectedMutationRevision: mutationRevision
            )
        } label: {
            Label("Run", systemImage: "play.fill")
        }
        .disabled(row.mutationRevision == nil)
        .help("Run this approved item through the execution gate")
        .accessibilityIdentifier("assistant-queue-run-\(row.id)")
        .accessibilityHint("Executes approved generated work through the review gate and records a receipt.")
    }

    private var reopenButton: some View {
        Button {
            guard let mutationRevision = row.mutationRevision else {
                return
            }
            _ = viewModel.retryAssistantQueueItem(
                id: row.id,
                expectedMutationRevision: mutationRevision
            )
        } label: {
            Label("Reopen", systemImage: "arrow.clockwise")
        }
        .disabled(row.mutationRevision == nil)
        .help("Reopen this failed item for review before running it again")
        .accessibilityIdentifier("assistant-queue-retry-\(row.id)")
        .accessibilityHint("Returns failed generated work to review. It does not run until approved again.")
    }

    private var editButton: some View {
        Button {
            openEditForm()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .help("Edit review details before approving this queue item")
        .accessibilityIdentifier("assistant-queue-edit-\(row.id)")
        .accessibilityHint("Edits the review reason and redacted summary without changing raw action arguments.")
    }

    private var deferButton: some View {
        Button {
            guard let mutationRevision = row.mutationRevision else {
                return
            }
            _ = viewModel.deferAssistantQueueItem(
                id: row.id,
                expectedMutationRevision: mutationRevision
            )
        } label: {
            Label("Defer", systemImage: "clock")
        }
        .disabled(row.mutationRevision == nil)
        .help("Review this queue item later")
        .accessibilityIdentifier("assistant-queue-defer-\(row.id)")
        .accessibilityHint("Keeps this generated work in the local queue for later review.")
    }

    private func openEditForm() {
        if !isEditing {
            draftReviewReason = row.reviewReason
            draftRedactedSummary = row.redactedSummary
            expectedMutationRevision = row.mutationRevision
            hasEditConflict = false
            isEditing = true
        }
        focusAction(afterYieldOn: .editReason)
    }

    private func focusAction(afterYieldOn action: ActionFocus) {
        Task { @MainActor in
            await Task.yield()
            keyboardActionFocus = action
            accessibilityActionFocus = action
        }
    }

    private func focusAfterEditing() {
        if !actionPresentation.secondaryActions.isEmpty {
            focusAction(afterYieldOn: .more)
        } else if actionPresentation.primaryAction != nil {
            focusAction(afterYieldOn: .primary)
        } else {
            // State-changing saves can remove this row from the active filter.
            // Move focus to a stable workflow control instead of a stale row.
            focusWorkflowControls()
        }
    }

    private func markEditConflictIfNeeded() {
        guard isEditing else {
            return
        }
        // Preserve local draft text when another window updates the same item;
        // only an explicit reload may replace reviewer input with durable data.
        hasEditConflict = true
        focusAction(afterYieldOn: .editReason)
    }

    private var isBatchSelectable: Bool {
        (row.canDefer || row.canReject) && row.mutationRevision != nil
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
