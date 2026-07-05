import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

struct InboxWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    var selectInboxTask: (ProjectBoardTask) -> Void = { _ in }
    @State private var quickTitle = ""
    @State private var voiceMemoDraft = ""
    @State private var voiceMemoCaptureID: Int64?

    private var tasks: [ProjectBoardTask] {
        viewModel.filteredInboxTasks
    }

    private var subtitle: String {
        if viewModel.showsCompletedWorkflowTasks {
            return String(
                format: String(localized: "%d inbox items, including %d done"),
                tasks.count,
                viewModel.completedInboxTaskCount
            )
        }
        return String(format: String(localized: "%d unprocessed captured items"), tasks.count)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                mainSurface
                Divider()
                    .padding(.vertical, 18)
                InboxTriageRail(
                    task: viewModel.selectedTask,
                    viewModel: viewModel,
                    memoDraft: $voiceMemoDraft,
                    memoCaptureID: $voiceMemoCaptureID
                )
                    .frame(minWidth: 300, idealWidth: 320, maxWidth: 360)
                    .padding(.vertical, 18)
                    .padding(.trailing, 18)
            }

            VStack(alignment: .leading, spacing: 0) {
                mainSurface
                InboxTriageRail(
                    task: viewModel.selectedTask,
                    viewModel: viewModel,
                    memoDraft: $voiceMemoDraft,
                    memoCaptureID: $voiceMemoCaptureID
                )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-workflow")
        .onAppear {
            viewModel.ensureSelectedInboxTaskIsVisible()
        }
        .onChange(of: tasks.map(\.id)) { _, _ in
            viewModel.ensureSelectedInboxTaskIsVisible()
        }
    }

    private var mainSurface: some View {
        WorkflowTaskSurface(
            title: "Inbox",
            subtitle: subtitle,
            systemImage: "tray",
            tasks: tasks,
            emptyTitle: "Inbox is clear",
            emptyDescription: "Voice notes, manual captures, and unassigned tasks land here before classification.",
            viewModel: viewModel,
            onSelectTask: selectInboxTask,
            triageSummary: { task in
                viewModel.inboxTriageSummary(for: task)
            },
            headerAccessory: {
                InboxHeaderControls(quickTitle: $quickTitle, viewModel: viewModel, addInboxTask: addInboxTask)
            },
            footer: {
                EmptyView()
            }
        )
    }

    private func addInboxTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let inboxID = viewModel.inboxProject?.id else {
            return
        }
        _ = viewModel.createTask(title: title, projectID: inboxID, status: .backlog)
        quickTitle = ""
    }
}

private struct InboxHeaderControls: View {
    @Binding var quickTitle: String
    @ObservedObject var viewModel: ProjectBoardViewModel
    let addInboxTask: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                WorkflowDoneToggle(viewModel: viewModel)
                TextField("Capture an inbox item", text: $quickTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addInboxTask)
                    .accessibilityIdentifier("inbox-quick-add-title")
                    .accessibilityLabel("Inbox quick add title")
                    .accessibilityHint("Creates a local Inbox item when submitted.")
                Button(action: addInboxTask) {
                    Label("Quick Add", systemImage: "plus")
                }
                .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Add this item to Inbox")
                .accessibilityIdentifier("inbox-quick-add-button")
                .accessibilityHint("Adds the typed item to the local Inbox.")
            }

            Picker("Inbox Filter", selection: Binding(
                get: { viewModel.inboxTriageFilter },
                set: { viewModel.setInboxTriageFilter($0) }
            )) {
                ForEach(InboxTriageFilter.allCases) { filter in
                    Text(filterTitle(filter))
                        .tag(filter)
                        .accessibilityLabel(filterAccessibilityLabel(filter))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)
            .accessibilityIdentifier("inbox-triage-filter")
            .accessibilityLabel("Inbox filter")
            .accessibilityHint("Filters Inbox items by source and interpretation status.")
        }
    }

    private func filterTitle(_ filter: InboxTriageFilter) -> String {
        "\(String(localized: String.LocalizationValue(filter.title))) (\(viewModel.inboxTriageCount(for: filter)))"
    }

    private func filterAccessibilityLabel(_ filter: InboxTriageFilter) -> String {
        "\(String(localized: String.LocalizationValue(filter.title))), \(viewModel.inboxTriageCount(for: filter))"
    }
}

private struct InboxTriageRail: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel
    @Binding var memoDraft: String
    @Binding var memoCaptureID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Triage Station")
                        .font(.headline)
                    Text("Review the selected Inbox capture and classify it without opening the task inspector.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.blue)
            }

            InboxActionPanel(
                task: task,
                viewModel: viewModel,
                memoDraft: $memoDraft,
                memoCaptureID: $memoCaptureID
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-triage-rail")
        .accessibilityLabel("Inbox triage station")
        .accessibilityHint("Keeps selected Inbox item review and classification actions visible without opening the task inspector.")
    }
}

private struct InboxActionPanel: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel
    @Binding var memoDraft: String
    @Binding var memoCaptureID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Classify Selected Item")
                .font(.headline)
            InboxVoiceIntakeDetail(
                captures: viewModel.selectedInboxCaptureRecords,
                taskTitle: task?.title ?? "Selected Inbox item",
                memoDraft: $memoDraft,
                memoCaptureID: $memoCaptureID,
                onSaveMemo: { memo in
                    viewModel.updateSelectedInboxCaptureMemo(memo)
                }
            )
            if let feedback = viewModel.inboxClassificationFeedback {
                HStack(spacing: 8) {
                    Label(feedback.message, systemImage: feedback.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    if feedback.canUndo {
                        Button {
                            viewModel.undoLastInboxClassification()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .controlSize(.small)
                        .help("Undo the last Inbox classification")
                        .accessibilityIdentifier("inbox-classification-undo")
                        .accessibilityHint("Restores the last classified Inbox item when possible.")
                    }
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inbox-classification-feedback")
            }
            LazyVGrid(columns: actionGridColumns, alignment: .leading, spacing: 8) {
                actionButtons
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inbox-action-grid")
            .disabled(task == nil)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-action-panel")
        .accessibilityLabel(panelAccessibilityLabel)
        .accessibilityValue(panelAccessibilityValue)
        .accessibilityHint(panelAccessibilityHint)
    }

    private var panelAccessibilityLabel: String {
        var values = ["Inbox classification actions"]
        if let task {
            values.append("Selected Inbox item \(task.title)")
            if viewModel.selectedInboxCaptureRecords.first != nil {
                values.append("Voice capture metadata available for \(task.title)")
            }
        }
        return values.joined(separator: ", ")
    }

    private var panelAccessibilityValue: String {
        guard let task else {
            return "No Inbox item selected"
        }
        var values = ["Selected Inbox item: \(task.title)"]
        if let capture = viewModel.selectedInboxCaptureRecords.first {
            // The release screenshot marker needs one stable AX node that proves
            // both selection and capture metadata; child metadata panels can be
            // omitted from macOS AX traversal when the workflow footer is dense.
            values.append("Voice capture metadata available for \(task.title)")
            values.append("Transcript: \(capture.transcript ?? "No transcript yet")")
            if let interpretationSummary = capture.interpretationSummary {
                values.append("Interpretation: \(interpretationSummary)")
            }
        }
        return values.joined(separator: ", ")
    }

    private var panelAccessibilityHint: String {
        let base = "Choose how to classify the selected Inbox item."
        guard let task, viewModel.selectedInboxCaptureRecords.first != nil else {
            return base
        }
        return "\(base) Voice capture metadata available for \(task.title)."
    }

    private var actionGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 150), spacing: 8)
        ]
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            viewModel.markSelectedTaskAsTask()
        } label: {
            Label("Make Task", systemImage: "checkmark.circle")
        }
        .keyboardShortcut("1", modifiers: [.command])
        .help("Make selected Inbox item a task")
        .accessibilityIdentifier("inbox-action-make-task")
        .accessibilityHint("Classifies the selected Inbox item as a task in the local database.")
        Button {
            viewModel.convertSelectedTaskToProject()
        } label: {
            Label("Make Project", systemImage: "folder.badge.plus")
        }
        .keyboardShortcut("2", modifiers: [.command])
        .help("Make selected Inbox item a project")
        .accessibilityIdentifier("inbox-action-make-project")
        .accessibilityHint("Creates a local project from the selected Inbox item.")
        Button {
            viewModel.scheduleSelectedTaskForToday()
        } label: {
            Label("Schedule Today", systemImage: "calendar.badge.plus")
        }
        .keyboardShortcut("3", modifiers: [.command])
        .help("Schedule selected Inbox item for today")
        .accessibilityIdentifier("inbox-action-schedule-today")
        .accessibilityHint("Sets the selected Inbox item due date to today.")
        Button {
            viewModel.deferSelectedTaskForLater()
        } label: {
            Label("Review Later", systemImage: "clock")
        }
        .keyboardShortcut("4", modifiers: [.command])
        .help("Review selected Inbox item later")
        .accessibilityIdentifier("inbox-action-review-later")
        .accessibilityHint("Leaves the selected Inbox item for later review.")
    }
}

private struct InboxVoiceIntakeDetail: View {
    let captures: [InboxCaptureRecord]
    let taskTitle: String
    @Binding var memoDraft: String
    @Binding var memoCaptureID: Int64?
    let onSaveMemo: (String) -> Void

    var body: some View {
        if let capture = captures.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Label("Voice Intake", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(capture.sourceKind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.10), in: Capsule())
                }

                voicePlayback(capture)

                LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 6) {
                    metadataRow(title: "Source", value: capture.sourceKind.rawValue)
                    metadataRow(title: "Duration", value: capture.durationLabel)
                    metadataRow(title: "Classification", value: capture.classificationStatus.rawValue)
                    metadataRow(title: "Transcription", value: capture.transcriptionStatus.rawValue)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("inbox-voice-source-metadata")

                detailSection(
                    title: "Transcript",
                    value: transcriptReviewText(for: capture),
                    systemImage: transcriptSystemImage(for: capture)
                )
                .accessibilityIdentifier("inbox-voice-transcript")

                detailSection(
                    title: "AI Interpretation",
                    value: interpretationReviewText(for: capture),
                    systemImage: interpretationSystemImage(for: capture)
                )
                .accessibilityIdentifier("inbox-voice-interpretation")

                memoEditor(for: capture)

                Text(reviewStatusText(for: capture))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reviewStatusColor(for: capture))
                    .accessibilityIdentifier("inbox-voice-review-status")
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("inbox-voice-intake-detail")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Voice intake detail for \(taskTitle)")
            .accessibilityValue(captureAccessibilityValue(capture))
            .accessibilityHint("Summarizes the selected Inbox capture metadata for review.")
            .onAppear {
                resetMemoDraft(for: capture)
            }
            .onChange(of: capture.id) { _, _ in
                resetMemoDraft(for: capture)
            }
        }
    }

    private var metadataColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 120), spacing: 8)
        ]
    }

    private func voicePlayback(_ capture: InboxCaptureRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.quote")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text("Transcript only")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(alignment: .center, spacing: 3) {
                ForEach(waveformBars.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: 3, height: waveformBars[index])
                }
            }
            .frame(height: 28)
            .accessibilityIdentifier("inbox-voice-waveform")
            .accessibilityLabel("Voice waveform")
            .accessibilityValue("Waveform preview")

            Spacer(minLength: 8)

            Text(capture.durationLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-voice-transcript-preview")
        .accessibilityLabel("Voice transcript preview")
        .accessibilityValue("Transcript-only voice capture, duration \(capture.durationLabel), waveform preview")
    }

    private var waveformBars: [CGFloat] {
        [8, 14, 10, 20, 12, 18, 9, 16, 22, 11, 15, 19, 10, 17, 13, 21]
    }

    private func memoEditor(for capture: InboxCaptureRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Note")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $memoDraft)
                .font(.caption)
                .frame(minHeight: 56, maxHeight: 76)
                .padding(4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("inbox-voice-memo-editor")
                .accessibilityLabel("Inbox voice note")
                .accessibilityValue(normalizedMemo(memoDraft).isEmpty ? "No memo yet." : normalizedMemo(memoDraft))

            HStack {
                Text(normalizedMemo(capture.memo).isEmpty ? "No memo yet." : "Saved note available.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    onSaveMemo(memoDraft)
                } label: {
                    Label("Save Note", systemImage: "checkmark.circle")
                }
                .controlSize(.small)
                .disabled(!memoHasChanges(for: capture))
                .help("Save the note on this Inbox voice capture")
                .accessibilityIdentifier("inbox-voice-memo-save")
                .accessibilityHint("Stores this note locally on the selected voice capture.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-voice-memo")
    }

    private func captureAccessibilityValue(_ capture: InboxCaptureRecord) -> String {
        // Keep a parent summary for release marker scans while preserving child
        // identifiers for transcript, interpretation, playback, and memo controls.
        var values = [
            "Source: \(capture.sourceKind.rawValue)",
            "Duration: \(capture.durationLabel)",
            "Classification: \(capture.classificationStatus.rawValue)",
            "Transcription: \(capture.transcriptionStatus.rawValue)",
            "Transcript: \(transcriptReviewText(for: capture))",
            "Interpretation: \(interpretationReviewText(for: capture))",
            "Review: \(reviewStatusText(for: capture))"
        ]
        if let memo = capture.memo {
            values.append("Memo: \(memo)")
        }
        return values.joined(separator: ", ")
    }

    private func resetMemoDraft(for capture: InboxCaptureRecord) {
        guard memoCaptureID != capture.id else {
            return
        }
        memoCaptureID = capture.id
        memoDraft = capture.memo ?? ""
    }

    private func memoHasChanges(for capture: InboxCaptureRecord) -> Bool {
        normalizedMemo(memoDraft) != normalizedMemo(capture.memo)
    }

    private func normalizedMemo(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func transcriptReviewText(for capture: InboxCaptureRecord) -> String {
        switch capture.transcriptionStatus {
        case .failed:
            return "Transcript failed. Review the original voice memo before converting."
        case .pending:
            return "Transcript pending."
        case .succeeded:
            let transcript = capture.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return transcript.isEmpty ? "Transcript is empty." : transcript
        }
    }

    private func interpretationReviewText(for capture: InboxCaptureRecord) -> String {
        guard capture.transcriptionStatus != .failed else {
            return "AI interpretation unavailable because transcription failed."
        }
        let interpretation = capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return interpretation.isEmpty ? "No AI interpretation yet." : interpretation
    }

    private func reviewStatusText(for capture: InboxCaptureRecord) -> String {
        switch capture.transcriptionStatus {
        case .failed:
            return "Needs transcript review"
        case .pending:
            return "Waiting for transcription"
        case .succeeded:
            return capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? "Ready for triage"
                : "Transcript ready"
        }
    }

    private func transcriptSystemImage(for capture: InboxCaptureRecord) -> String {
        capture.transcriptionStatus == .failed ? "exclamationmark.triangle" : "text.quote"
    }

    private func interpretationSystemImage(for capture: InboxCaptureRecord) -> String {
        capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "sparkles"
            : "questionmark.bubble"
    }

    private func reviewStatusColor(for capture: InboxCaptureRecord) -> Color {
        switch capture.transcriptionStatus {
        case .failed:
            .red
        case .pending:
            .secondary
        case .succeeded:
            .blue
        }
    }

    private func metadataRow(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailSection(title: String, value: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
