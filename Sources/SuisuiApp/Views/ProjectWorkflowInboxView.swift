import Foundation
import SuisuiCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct InboxWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    var selectInboxTask: (ProjectBoardTask) -> Void = { _ in }
    let requestsQuickAddFocus: Bool
    let onQuickAddFocusConsumed: () -> Void
    @State private var quickTitle = ""
    @State private var voiceMemoDraft = ""
    @State private var voiceMemoCaptureID: Int64?
    // Sorting stays view-local so reviewing the same Inbox from another window
    // does not rewrite the shared capture order or persistence model.
    @State private var sortOrder: InboxSortOrder = .newest
    @State private var isQuickAddExpanded = false
    @State private var lastReviewRefreshMinute: Date?
    @FocusState private var isQuickAddFocused: Bool

    init(
        viewModel: ProjectBoardViewModel,
        selectInboxTask: @escaping (ProjectBoardTask) -> Void = { _ in },
        requestsQuickAddFocus: Bool,
        onQuickAddFocusConsumed: @escaping () -> Void
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.selectInboxTask = selectInboxTask
        self.requestsQuickAddFocus = requestsQuickAddFocus
        self.onQuickAddFocusConsumed = onQuickAddFocusConsumed
    }

    init(
        viewModel: ProjectBoardViewModel,
        selectInboxTask: @escaping (ProjectBoardTask) -> Void = { _ in }
    ) {
        self.init(
            viewModel: viewModel,
            selectInboxTask: selectInboxTask,
            requestsQuickAddFocus: false,
            onQuickAddFocusConsumed: {}
        )
    }

    private var tasks: [ProjectBoardTask] {
        switch sortOrder {
        case .newest:
            sortByCaptureDate(viewModel.filteredInboxTasks, descending: true)
        case .oldest:
            sortByCaptureDate(viewModel.filteredInboxTasks, descending: false)
        case .title:
            sortByTitle(viewModel.filteredInboxTasks)
        }
    }

    private func sortByTitle(_ tasks: [ProjectBoardTask]) -> [ProjectBoardTask] {
        // Localized comparison can tie for equivalent titles; the ID tie-break
        // keeps the row order stable across SwiftUI redraws and reloads.
        tasks.sorted { lhs, rhs in
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            return comparison == .orderedAscending
                || (comparison == .orderedSame && lhs.id < rhs.id)
        }
    }

    private func sortByCaptureDate(
        _ tasks: [ProjectBoardTask],
        descending: Bool
    ) -> [ProjectBoardTask] {
        tasks.sorted { lhs, rhs in
            let lhsDate = captureDate(for: lhs)
            let rhsDate = captureDate(for: rhs)
            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return descending ? lhsDate > rhsDate : lhsDate < rhsDate
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return descending ? lhs.id > rhs.id : lhs.id < rhs.id
        }
    }

    private func captureDate(for task: ProjectBoardTask) -> Date? {
        task.createdAt.flatMap { SuisuiTimestampDisplay.parse($0)?.date }
    }

    private var subtitle: String {
        if viewModel.showsCompletedWorkflowTasks {
            return localizedDisplay(
                "%@, including %d done",
                localizedCount(tasks.count, one: "%d inbox item", other: "%d inbox items"),
                viewModel.completedInboxTaskCount
            )
        }
        return localizedCount(
            tasks.count,
            one: "%d unprocessed captured item",
            other: "%d unprocessed captured items"
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
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
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 440)
                        .padding(.vertical, 18)
                        .padding(.trailing, 18)
                }

                ScrollView(.vertical) {
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
                .defaultScrollAnchor(.top)
                .scrollIndicators(.visible)
                .accessibilityIdentifier("inbox-compact-workflow-scroll")
            }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-workflow")
            .onAppear {
                refreshInboxReviewAvailability(at: timeline.date)
                viewModel.ensureSelectedInboxTaskIsVisible()
                consumeQuickAddFocusRequestIfNeeded()
            }
            .onChange(of: timeline.date) { _, date in
                refreshInboxReviewAvailability(at: date)
            }
            .onChange(of: requestsQuickAddFocus) { _, _ in
                consumeQuickAddFocusRequestIfNeeded()
            }
            .onChange(of: tasks.map(\.id)) { _, _ in
                viewModel.ensureSelectedInboxTaskIsVisible()
            }
            .onChange(of: viewModel.selectedTaskID) { _, _ in
                // Hydrate from the newly selected capture so this parent observer
                // and the child capture observer converge regardless of call order.
                let capture = viewModel.selectedInboxCaptureRecords.first
                voiceMemoCaptureID = capture?.id
                voiceMemoDraft = capture?.memo ?? ""
            }
        }
    }

    private func refreshInboxReviewAvailability(at date: Date) {
        let minute = Calendar.autoupdatingCurrent.dateInterval(of: .minute, for: date)?.start ?? date
        guard lastReviewRefreshMinute != minute else {
            return
        }
        lastReviewRefreshMinute = minute
        viewModel.refreshInboxReviewAvailability(at: date)
    }

    private var mainSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            InboxReferenceHeader(
                subtitle: subtitle,
                sortOrder: $sortOrder,
                viewModel: viewModel
            )
            InboxReferenceTaskList(
                tasks: tasks,
                viewModel: viewModel,
                referenceDate: Date(),
                onSelectTask: selectInboxTask,
                quickTitle: $quickTitle,
                isQuickAddExpanded: $isQuickAddExpanded,
                isQuickAddFocused: $isQuickAddFocused,
                addInboxTask: addInboxTask
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func addInboxTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }
        guard viewModel.createInboxTask(title: title) != nil else {
            isQuickAddExpanded = true
            isQuickAddFocused = true
            return
        }
        quickTitle = ""
        isQuickAddExpanded = false
    }

    private func consumeQuickAddFocusRequestIfNeeded() {
        guard requestsQuickAddFocus else {
            return
        }
        isQuickAddExpanded = true
        isQuickAddFocused = true
        onQuickAddFocusConsumed()
    }
}

private enum InboxSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case title

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .newest:
            "Newest First"
        case .oldest:
            "Oldest First"
        case .title:
            "Title"
        }
    }
}

private struct InboxReferenceHeader: View {
    let subtitle: String
    @Binding var sortOrder: InboxSortOrder
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inbox")
                        .font(.largeTitle.weight(.bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(InboxSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("inbox-sort-menu")

                Menu("Filter", systemImage: "line.3.horizontal.decrease") {
                    Picker("Inbox Filter", selection: filterBinding) {
                        ForEach(InboxTriageFilter.allCases) { filter in
                            Text(filterTitle(filter)).tag(filter)
                        }
                    }
                    Divider()
                    Toggle("Show Done", isOn: Binding(
                        get: { viewModel.showsCompletedWorkflowTasks },
                        set: { viewModel.setShowsCompletedWorkflowTasks($0) }
                    ))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("inbox-filter-menu")
            }

            Divider()

            HStack(alignment: .center, spacing: 8) {
                Picker("Inbox Filter", selection: filterBinding) {
                    ForEach(InboxTriageFilter.allCases) { filter in
                        Text(filterTitle(filter))
                            .tag(filter)
                            .accessibilityLabel(filterAccessibilityLabel(filter))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inbox-triage-filter")
                .accessibilityLabel("Inbox filter")
                .accessibilityHint("Filters Inbox items by source and interpretation status.")

                Text(viewModel.showsCompletedWorkflowTasks ? "Including Done" : "Unprocessed only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-reference-header")
    }

    private var filterBinding: Binding<InboxTriageFilter> {
        Binding(
            get: { viewModel.inboxTriageFilter },
            set: { viewModel.setInboxTriageFilter($0) }
        )
    }

    private func filterTitle(_ filter: InboxTriageFilter) -> String {
        "\(String(localized: String.LocalizationValue(filter.title))) (\(viewModel.inboxTriageCount(for: filter)))"
    }

    private func filterAccessibilityLabel(_ filter: InboxTriageFilter) -> String {
        "\(String(localized: String.LocalizationValue(filter.title))), \(viewModel.inboxTriageCount(for: filter))"
    }
}

private struct InboxReferenceTaskList: View {
    let tasks: [ProjectBoardTask]
    @ObservedObject var viewModel: ProjectBoardViewModel
    let referenceDate: Date
    let onSelectTask: (ProjectBoardTask) -> Void
    @Binding var quickTitle: String
    @Binding var isQuickAddExpanded: Bool
    @FocusState.Binding var isQuickAddFocused: Bool
    let addInboxTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "Inbox is clear",
                    systemImage: "tray",
                    description: Text("Voice notes, manual captures, and unassigned tasks land here before classification.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            InboxReferenceTaskRow(
                                task: task,
                                summary: viewModel.inboxTriageSummary(for: task),
                                triageRecord: viewModel.inboxTriageRecord(for: task),
                                referenceDate: referenceDate,
                                projectTitle: viewModel.projectTitle(for: task),
                                isSelected: viewModel.selectedTaskID == task.id,
                                onSelect: { onSelectTask(task) },
                                onToggleCompletion: { viewModel.toggleTaskCompletion(id: task.id) }
                            )
                            if index < tasks.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }

            Divider()
            InboxQuickAddRow(
                title: $quickTitle,
                isExpanded: $isQuickAddExpanded,
                isFocused: $isQuickAddFocused,
                onAdd: addInboxTask
            )
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.20))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-reference-task-list")
    }
}

private struct InboxReferenceTaskRow: View {
    let task: ProjectBoardTask
    let summary: InboxTriageSummary
    let triageRecord: InboxTriageRecord?
    let referenceDate: Date
    let projectTitle: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleCompletion: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : summary.systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(iconTint)
                    .frame(width: 34, height: 34)
                    .background(iconTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workflow-task-completion-\(task.id)")
            .accessibilityLabel(task.status == .done ? "Reopen task \(task.title)" : "Complete task \(task.title)")
            .accessibilityHint("Updates the task status in the local Suisui database without opening the inspector.")

            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .help(task.title)
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(LocalizedStringKey(summary.interpretationLabel))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                        .accessibilityIdentifier("inbox-row-triage-summary-\(task.id)")

                    InboxTriageStateBadge(taskID: task.id, record: triageRecord, referenceDate: referenceDate)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open task \(task.title)")
            .accessibilityValue(
                "\(summary.accessibilityValue), \(triageAccessibilityValue), Project: \(projectTitle)"
            )
            .accessibilityIdentifier("workflow-task-row-\(task.id)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    private var metadata: String {
        let date = task.todayDueDisplayLabel() ?? task.updatedAt ?? String(localized: "Unscheduled")
        return "\(String(localized: String.LocalizationValue(summary.sourceLabel))) · \(date)"
    }

    private var triageAccessibilityValue: String {
        InboxTriageStatePresentation.label(for: triageRecord, referenceDate: referenceDate)
    }

    private var iconTint: Color {
        switch summary.tintName {
        case "blue":
            .blue
        case "red":
            .red
        default:
            .secondary
        }
    }
}

private enum InboxTriageStatePresentation {
    static func label(for record: InboxTriageRecord?, referenceDate: Date) -> String {
        switch record?.disposition {
        case .task:
            return String(localized: "Processed task")
        case .scheduled:
            return String(localized: "Inbox scheduled")
        case .project:
            return String(localized: "Inbox project")
        case .reviewLater:
            guard let rawReviewAt = record?.reviewAt,
                  let parsed = SuisuiTimestampDisplay.parse(rawReviewAt) else {
                return String(localized: "Review due")
            }
            let display = SuisuiTimestampDisplay.absolute(parsed, calendar: .autoupdatingCurrent)
            if parsed.date <= referenceDate {
                return String(localized: "Review due")
            }
            return String(format: String(localized: "Review tomorrow at %@"), display)
        case .unprocessed, nil:
            return String(localized: "Unprocessed")
        }
    }
}

private struct InboxTriageStateBadge: View {
    let taskID: Int64
    let record: InboxTriageRecord?
    let referenceDate: Date

    var body: some View {
        Text(stateLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.08), in: Capsule())
            .accessibilityIdentifier("inbox-row-disposition-\(taskID)")
    }

    private var stateLabel: String {
        InboxTriageStatePresentation.label(for: record, referenceDate: referenceDate)
    }
}

private struct InboxQuickAddRow: View {
    @Binding var title: String
    @Binding var isExpanded: Bool
    @FocusState.Binding var isFocused: Bool
    let onAdd: () -> Void

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 8) {
                    TextField("Capture an inbox item", text: $title)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit(onAdd)
                        .accessibilityIdentifier("inbox-quick-add-title")
                        .accessibilityLabel("Inbox quick add title")
                    Button("Add", systemImage: "plus", action: onAdd)
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .accessibilityIdentifier("inbox-quick-add-button")
                    Button("Cancel") {
                        title = ""
                        isExpanded = false
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Button("Add New Item", systemImage: "plus") {
                    isExpanded = true
                    isFocused = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityIdentifier("inbox-quick-add-button")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InboxTriageRail: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel
    @Binding var memoDraft: String
    @Binding var memoCaptureID: Int64?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                InboxActionPanel(
                    task: task,
                    viewModel: viewModel,
                    memoDraft: $memoDraft,
                    memoCaptureID: $memoCaptureID
                )
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("inbox-reference-detail")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.20))
        }
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
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InboxSelectedItemContext(
                task: task,
                viewModel: viewModel,
                // Voice intake owns capture metadata below, so only manual
                // items repeat their lightweight source and interpretation.
                manualSummary: task != nil && viewModel.selectedInboxCaptureRecords.isEmpty
                    ? task.map { viewModel.inboxTriageSummary(for: $0) }
                    : nil
            )

            HStack(spacing: 8) {
                Button {
                    viewModel.markSelectedTaskAsTask()
                } label: {
                    Label("Make Task", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("inbox-detail-make-task")

                Button("Review Later") {
                    viewModel.deferSelectedTaskForLater()
                }
                .buttonStyle(.bordered)

                Button("Delete", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .buttonStyle(.bordered)
            }
            .disabled(task == nil)

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

            Text("Suggested Actions")
                .font(.headline)

            LazyVGrid(columns: actionGridColumns, alignment: .leading, spacing: 8) {
                actionButtons
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inbox-action-grid")
            .disabled(task == nil)

            Text("Details")
                .font(.headline)

            InboxReferenceDetails(
                task: task,
                summary: task.map { viewModel.inboxTriageSummary(for: $0) },
                capture: viewModel.selectedInboxCaptureRecords.first
            )
        }
        .padding(18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-action-panel")
        .accessibilityLabel("Inbox classification actions")
        .accessibilityHint("Choose how to classify the selected Inbox item.")
        .confirmationDialog(
            "Delete Inbox Item?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteSelectedTask()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected Inbox item. You can undo the deletion from the Edit menu.")
        }
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
        .keyboardShortcut("1", modifiers: [.command, .control])
        .help("Make selected Inbox item a task (Control-Command-1)")
        .accessibilityIdentifier("inbox-action-make-task")
        .accessibilityHint("Classifies the selected Inbox item as a task in the local database.")
        Button {
            viewModel.convertSelectedTaskToProject()
        } label: {
            Label("Make Project", systemImage: "folder.badge.plus")
        }
        .keyboardShortcut("2", modifiers: [.command, .control])
        .help("Make selected Inbox item a project (Control-Command-2)")
        .accessibilityIdentifier("inbox-action-make-project")
        .accessibilityHint("Creates a local project from the selected Inbox item.")
        Button {
            viewModel.scheduleSelectedTaskForToday()
        } label: {
            Label("Schedule Today", systemImage: "calendar.badge.plus")
        }
        .keyboardShortcut("3", modifiers: [.command, .control])
        .help("Schedule selected Inbox item for today (Control-Command-3)")
        .accessibilityIdentifier("inbox-action-schedule-today")
        .accessibilityHint("Sets the selected Inbox item due date to today.")
        Button {
            viewModel.deferSelectedTaskForLater()
        } label: {
            Label("Review Later", systemImage: "clock")
        }
        .keyboardShortcut("4", modifiers: [.command, .control])
        .help("Review selected Inbox item later (Control-Command-4)")
        .accessibilityIdentifier("inbox-action-review-later")
        .accessibilityHint("Leaves the selected Inbox item for later review.")
    }
}

private struct InboxSelectedItemContext: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel
    let manualSummary: InboxTriageSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let task {
                HStack(alignment: .center, spacing: 8) {
                    Text(LocalizedStringKey(manualSummary?.sourceLabel ?? "Voice"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer(minLength: 8)
                    Menu("More", systemImage: "ellipsis") {
                        Button("Schedule Today", systemImage: "calendar.badge.plus") {
                            viewModel.scheduleSelectedTaskForToday()
                        }
                        Button("Review Later", systemImage: "clock") {
                            viewModel.deferSelectedTaskForLater()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton)
                }

                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                let detail = normalizedInboxDetail(task.detail)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(detail)
                }

                if let manualSummary {
                    Text("\(String(localized: String.LocalizationValue(manualSummary.interpretationLabel))) · \(task.updatedAt ?? String(localized: "Unscheduled"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select an Inbox item to classify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox-selected-context")
    }
}

private struct InboxReferenceDetails: View {
    let task: ProjectBoardTask?
    let summary: InboxTriageSummary?
    let capture: InboxCaptureRecord?

    var body: some View {
        VStack(spacing: 0) {
            detailRow("Received", value: capture?.createdAt ?? task?.createdAt ?? task?.updatedAt ?? String(localized: "Unknown"))
            Divider()
            detailRow("Source", value: source)
            Divider()
            detailRow("Status", value: summary.map {
                String(localized: String.LocalizationValue($0.interpretationLabel))
            } ?? String(localized: "Unselected"))
            Divider()
            detailRow("Related", value: task == nil ? String(localized: "Unassigned") : String(localized: "Inbox"))
        }
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-detail-metadata")
    }

    private var source: String {
        if let capture {
            return localizedInboxCaptureSource(capture.sourceKind)
        }
        return summary.map { String(localized: String.LocalizationValue($0.sourceLabel)) }
            ?? String(localized: "Unknown")
    }

    private func detailRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private func normalizedInboxDetail(_ detail: String) -> String {
    detail.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private struct InboxVoiceIntakeDetail: View {
    let captures: [InboxCaptureRecord]
    let taskTitle: String
    @Binding var memoDraft: String
    @Binding var memoCaptureID: Int64?
    let onSaveMemo: (String) -> Void

    var body: some View {
        if let capture = captures.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Voice Memo")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(localizedInboxCaptureSource(capture.sourceKind))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.10), in: Capsule())
                }

                voicePlayback(capture)

                HStack(spacing: 8) {
                    Text(localizedInboxCaptureDuration(capture.durationSeconds))
                    Text(verbatim: "·")
                    Text(localizedInboxCaptureClassification(capture.classificationStatus))
                    Text(verbatim: "·")
                    Text(localizedInboxCaptureTranscription(capture.transcriptionStatus))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("inbox-voice-source-metadata")

                HStack {
                    Text("Transcript")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Button("Copy") {
                        copyTranscript(transcriptReviewText(for: capture))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("inbox-voice-transcript-copy")
                }

                Text(transcriptReviewText(for: capture))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Transcript")
                    .accessibilityValue(transcriptReviewText(for: capture))
                .accessibilityIdentifier("inbox-voice-transcript")

                Text("AI Interpretation")
                    .font(.headline)

                detailSection(
                    title: "Interpretation",
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inbox-voice-intake-detail")
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

    private func copyTranscript(_ transcript: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        #endif
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

            Text(localizedInboxCaptureDuration(capture.durationSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-voice-transcript-preview")
        .accessibilityLabel("Voice transcript preview")
        .accessibilityValue(localizedDisplay(
            "Transcript-only voice capture, duration %@, waveform preview",
            localizedInboxCaptureDuration(capture.durationSeconds)
        ))
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
                .accessibilityValue(normalizedMemo(memoDraft).isEmpty ? localizedDisplay("No memo yet.") : normalizedMemo(memoDraft))

            HStack {
                Text(localizedDisplay(normalizedMemo(capture.memo).isEmpty ? "No memo yet." : "Saved note available."))
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
            localizedDisplay("Source: %@", localizedInboxCaptureSource(capture.sourceKind)),
            localizedDisplay("Duration: %@", localizedInboxCaptureDuration(capture.durationSeconds)),
            localizedDisplay("Classification: %@", localizedInboxCaptureClassification(capture.classificationStatus)),
            localizedDisplay("Transcription: %@", localizedInboxCaptureTranscription(capture.transcriptionStatus)),
            localizedDisplay("Transcript: %@", transcriptReviewText(for: capture)),
            localizedDisplay("Interpretation: %@", interpretationReviewText(for: capture)),
            localizedDisplay("Review: %@", reviewStatusText(for: capture))
        ]
        if let memo = capture.memo {
            values.append(localizedDisplay("Memo: %@", memo))
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
            return localizedDisplay("Transcript failed. Review the original voice memo before converting.")
        case .pending:
            return localizedDisplay("Transcript pending.")
        case .succeeded:
            let transcript = capture.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return transcript.isEmpty ? localizedDisplay("Transcript is empty.") : transcript
        }
    }

    private func interpretationReviewText(for capture: InboxCaptureRecord) -> String {
        guard capture.transcriptionStatus != .failed else {
            return localizedDisplay("AI interpretation unavailable because transcription failed.")
        }
        let interpretation = capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return interpretation.isEmpty ? localizedDisplay("No AI interpretation yet.") : interpretation
    }

    private func reviewStatusText(for capture: InboxCaptureRecord) -> String {
        switch capture.transcriptionStatus {
        case .failed:
            return localizedDisplay("Needs transcript review")
        case .pending:
            return localizedDisplay("Waiting for transcription")
        case .succeeded:
            return capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? localizedDisplay("Ready for triage")
                : localizedDisplay("Transcript ready")
        }
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
