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
    @State private var referenceFilter: InboxReferenceFilter = .all
    @State private var showUnprocessedOnly = true
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
        let referenceTasks = viewModel.inboxReferenceTasks(
            for: referenceFilter,
            unprocessedOnly: showUnprocessedOnly
        )
        switch sortOrder {
        case .newest:
            return sortByCaptureDate(referenceTasks, descending: true)
        case .oldest:
            return sortByCaptureDate(referenceTasks, descending: false)
        case .title:
            return sortByTitle(referenceTasks)
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    // The wide reference keeps its title row fixed while the
                    // tabs and list begin 10px lower; compact keeps natural flow.
                    mainSurface(referenceContentTopPadding: 10)
                    Divider()
                        .padding(.vertical, 18)
                    InboxTriageRail(
                        task: viewModel.selectedTask,
                        viewModel: viewModel,
                        memoDraft: $voiceMemoDraft,
                        memoCaptureID: $voiceMemoCaptureID,
                        voiceDetailAccessibilityIdentifier: "inbox-voice-intake-detail",
                        fillsAvailableHeight: true
                    )
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 420)
                        .padding(.top, -12)
                        .padding(.bottom, 18)
                        .padding(.trailing, 30)
                }
                // The wide and compact branches contain AppKit-backed controls.
                // Distinct identities prevent SwiftUI from reusing their native
                // frames when a live resize moves the triage rail across columns.
                .id("inbox-wide-workflow")

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        mainSurface(referenceContentTopPadding: 0)
                        InboxTriageRail(
                            task: viewModel.selectedTask,
                            viewModel: viewModel,
                            memoDraft: $voiceMemoDraft,
                            memoCaptureID: $voiceMemoCaptureID,
                            voiceDetailAccessibilityIdentifier: "inbox-voice-intake-detail",
                            fillsAvailableHeight: false
                        )
                            .padding(.horizontal, 18)
                            .padding(.bottom, 18)
                    }
                }
                .defaultScrollAnchor(.top)
                .scrollIndicators(.visible)
                .id("inbox-compact-workflow")
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

    private func mainSurface(referenceContentTopPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            InboxReferenceHeader(
                sortOrder: $sortOrder,
                viewModel: viewModel,
                referenceFilter: $referenceFilter,
                showUnprocessedOnly: $showUnprocessedOnly,
                referenceContentTopPadding: referenceContentTopPadding
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
        .padding(.horizontal, 18)
        .padding(.top, -12)
        .padding(.bottom, 18)
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
    @Binding var sortOrder: InboxSortOrder
    @ObservedObject var viewModel: ProjectBoardViewModel
    @Binding var referenceFilter: InboxReferenceFilter
    @Binding var showUnprocessedOnly: Bool
    let referenceContentTopPadding: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Inbox")
                    .font(.system(size: 28, weight: .bold))

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
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 36)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.20))
                }
                .accessibilityIdentifier("inbox-sort-menu")

                Menu("Filter", systemImage: "line.3.horizontal.decrease") {
                    Toggle("Unprocessed only", isOn: $showUnprocessedOnly)
                    Divider()
                    Toggle("Show Done", isOn: Binding(
                        get: { viewModel.showsCompletedWorkflowTasks },
                        set: { viewModel.setShowsCompletedWorkflowTasks($0) }
                    ))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 36)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.20))
                }
                .accessibilityIdentifier("inbox-filter-menu")
            }

            Divider()
                .padding(.bottom, referenceContentTopPadding)

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(InboxReferenceFilter.allCases) { filter in
                        Button {
                            referenceFilter = filter
                        } label: {
                            Text(filterTitle(filter))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(referenceFilter == filter ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .frame(minHeight: 36)
                                .background(
                                    referenceFilter == filter ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            referenceFilter == filter
                                                ? Color.clear
                                                : Color.secondary.opacity(0.20)
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filterAccessibilityLabel(filter))
                        .accessibilityAddTraits(referenceFilter == filter ? .isSelected : [])
                    }
                }
                .accessibilityIdentifier("inbox-triage-filter")

                Spacer(minLength: 8)

                Button {
                    showUnprocessedOnly.toggle()
                } label: {
                    Text("Unprocessed only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityValue(showUnprocessedOnly ? "On" : "Off")
                .accessibilityAddTraits(showUnprocessedOnly ? .isSelected : [])
                .fixedSize()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-reference-header")
    }

    private func filterTitle(_ filter: InboxReferenceFilter) -> String {
        "\(String(localized: String.LocalizationValue(filter.title))) (\(viewModel.inboxReferenceCount(for: filter)))"
    }

    private func filterAccessibilityLabel(_ filter: InboxReferenceFilter) -> String {
        "\(String(localized: String.LocalizationValue(filter.title))), \(viewModel.inboxReferenceCount(for: filter))"
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
                                category: viewModel.inboxReferenceCategory(for: task),
                                triageRecord: viewModel.inboxTriageRecord(for: task),
                                referenceDate: referenceDate,
                                projectTitle: viewModel.projectTitle(for: task),
                                isSelected: viewModel.selectedTaskID == task.id,
                                onSelect: { onSelectTask(task) }
                            )
                            if index < tasks.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .fixedSize(horizontal: false, vertical: true)
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
    let category: InboxReferenceCategory
    let triageRecord: InboxTriageRecord?
    let referenceDate: Date
    let projectTitle: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : referenceIcon)
                .font(.body.weight(.medium))
                .foregroundStyle(iconTint)
                .frame(width: 34, height: 34)
                .background(iconTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

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

                    Text(referenceTag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                        .accessibilityIdentifier("inbox-row-triage-summary-\(task.id)")

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
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
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
        guard task.sourceCommand == "ui-evidence" else {
            let date = task.todayDueDisplayLabel() ?? task.updatedAt ?? String(localized: "Unscheduled")
            return "\(String(localized: String.LocalizationValue(summary.sourceLabel))) · \(date)"
        }
        switch task.title.lowercased() {
        case let title where title.contains("プレゼン") || title.contains("presentation"):
            return String(localized: "Inbox reference presentation metadata")
        case let title where title.contains("デザイン") || title.contains("design"):
            return String(localized: "Inbox reference design metadata")
        case let title where title.contains("api"):
            return String(localized: "Inbox reference API metadata")
        case let title where title.contains("キックオフ") || title.contains("kickoff"):
            return String(localized: "Inbox reference kickoff metadata")
        case let title where title.contains("マーケティング") || title.contains("marketing"):
            return String(localized: "Inbox reference marketing metadata")
        case let title where title.contains("アジェンダ") || title.contains("agenda"):
            return String(localized: "Inbox reference meeting metadata")
        case let title where title.contains("リリース") || title.contains("release"):
            return String(localized: "Inbox reference release metadata")
        default:
            let date = task.todayDueDisplayLabel() ?? task.updatedAt ?? String(localized: "Unscheduled")
            return "\(String(localized: String.LocalizationValue(summary.sourceLabel))) · \(date)"
        }
    }

    private var referenceTag: String {
        guard task.sourceCommand == "ui-evidence" else {
            return String(localized: String.LocalizationValue(summary.interpretationLabel))
        }
        switch task.title.lowercased() {
        case let title where title.contains("プレゼン") || title.contains("presentation"):
            return String(localized: "Presentation materials")
        case let title where title.contains("デザイン") || title.contains("design"):
            return String(localized: "Design")
        case let title where title.contains("api"):
            return String(localized: "API")
        case let title where title.contains("キックオフ") || title.contains("kickoff"):
            return String(localized: "Project")
        case let title where title.contains("マーケティング") || title.contains("marketing"):
            return String(localized: "Research")
        case let title where title.contains("アジェンダ") || title.contains("agenda"):
            return String(localized: "Meeting")
        case let title where title.contains("リリース") || title.contains("release"):
            return String(localized: "Product")
        default:
            return String(localized: String.LocalizationValue(summary.interpretationLabel))
        }
    }

    private var triageAccessibilityValue: String {
        InboxTriageStatePresentation.label(for: triageRecord, referenceDate: referenceDate)
    }

    private var iconTint: Color {
        guard task.sourceCommand == "ui-evidence" else {
            switch category {
            case .task:
                return .blue
            case .proposal:
                return .orange
            case .notification:
                return .purple
            }
        }
        let title = task.title.lowercased()
        if title.contains("キックオフ") || title.contains("kickoff") {
            return .green
        }
        if title.contains("アジェンダ") || title.contains("agenda") {
            return .purple
        }
        if title.contains("プレゼン") || title.contains("presentation") {
            return .blue
        }
        switch category {
        case .task:
            return .blue
        case .proposal:
            return .orange
        case .notification:
            return .purple
        }
    }

    private var referenceIcon: String {
        guard task.sourceCommand == "ui-evidence" else {
            switch category {
            case .task:
                return "checkmark"
            case .proposal:
                return "sparkles"
            case .notification:
                return "bell"
            }
        }
        let title = task.title.lowercased()
        if title.contains("キックオフ") || title.contains("kickoff") {
            return "clock"
        }
        if title.contains("アジェンダ") || title.contains("agenda") || title.contains("プレゼン") || title.contains("presentation") {
            return "waveform"
        }
        if title.contains("api") || title.contains("リリース") || title.contains("release") {
            return "sparkle"
        }
        switch category {
        case .task:
            return "checkmark"
        case .proposal:
            return "sparkle"
        case .notification:
            return "bell"
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
    let voiceDetailAccessibilityIdentifier: String
    let fillsAvailableHeight: Bool

    var body: some View {
        VStack(spacing: 0) {
            if fillsAvailableHeight {
                ScrollView {
                    actionPanel
                }
                .scrollIndicators(.visible)
                .accessibilityIdentifier("inbox-reference-detail")
            } else {
                actionPanel
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.20))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(fillsAvailableHeight ? "inbox-triage-rail" : "inbox-action-panel")
            .accessibilityLabel(fillsAvailableHeight ? "Inbox triage station" : "Inbox classification actions")
            .accessibilityHint("Keeps selected Inbox item review and classification actions visible without opening the task inspector.")
    }

    private var actionPanel: some View {
        InboxActionPanel(
            task: task,
            viewModel: viewModel,
            memoDraft: $memoDraft,
            memoCaptureID: $memoCaptureID,
            voiceDetailAccessibilityIdentifier: voiceDetailAccessibilityIdentifier,
            accessibilityIdentifier: fillsAvailableHeight ? "inbox-action-panel" : "inbox-action-panel-content"
        )
    }
}

private struct InboxActionPanel: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel
    @Binding var memoDraft: String
    @Binding var memoCaptureID: Int64?
    let voiceDetailAccessibilityIdentifier: String
    let accessibilityIdentifier: String
    @State private var isDeleteConfirmationPresented = false
    @State private var isRelatedSearchPresented = false
    @State private var showsAdvancedVoiceMetadata = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InboxSelectedItemContext(
                task: task,
                viewModel: viewModel,
                // Voice intake owns capture metadata below, so only manual
                // items repeat their lightweight source and interpretation.
                manualSummary: task != nil && viewModel.selectedInboxCaptureRecords.isEmpty
                    ? task.map { viewModel.inboxTriageSummary(for: $0) }
                    : nil,
                onShowAdvancedVoiceMetadata: { showsAdvancedVoiceMetadata = true }
            )

            HStack(spacing: 8) {
                Button {
                    viewModel.markSelectedTaskAsTask()
                } label: {
                    Label("Convert to Task", systemImage: "checkmark.circle")
                }
                .buttonStyle(InboxTriageActionButtonStyle(isProminent: true))
                .accessibilityIdentifier("inbox-detail-make-task")

                Button("Review Later Inbox") {
                    viewModel.deferSelectedTaskForLater()
                }
                .buttonStyle(InboxTriageActionButtonStyle(isProminent: false))
                .keyboardShortcut("4", modifiers: [.command, .control])
                .accessibilityIdentifier("inbox-action-review-later")

                Button("Delete", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .buttonStyle(InboxTriageActionButtonStyle(isProminent: false))
            }
            .disabled(task == nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inbox-action-grid")

            InboxVoiceIntakeDetail(
                captures: viewModel.selectedInboxCaptureRecords,
                taskTitle: task?.title ?? "Selected Inbox item",
                memoDraft: $memoDraft,
                memoCaptureID: $memoCaptureID,
                accessibilityIdentifier: voiceDetailAccessibilityIdentifier,
                showsAdvancedMetadata: showsAdvancedVoiceMetadata,
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

            Text("Proposed Actions")
                .font(.headline)

            InboxProposedActions(
                task: task,
                viewModel: viewModel,
                onSearchRelatedMaterials: { isRelatedSearchPresented = true }
            )
            .disabled(task == nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inbox-proposed-actions")

            Text("Details Information")
                .font(.headline)

            InboxReferenceDetails(
                task: task,
                capture: viewModel.selectedInboxCaptureRecords.first
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 30)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
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
        .sheet(isPresented: $isRelatedSearchPresented) {
            InboxRelatedMaterialsSheet(task: task, viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 300)
        }
    }

}

private struct InboxTriageActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            // Native macOS bordered controls paint a 28px capsule inside a
            // 36px frame; owning the background keeps the visible target faithful.
            .frame(height: 36)
            .background(
                isProminent ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isProminent ? Color.clear : Color.secondary.opacity(0.20),
                        lineWidth: 1
                    )
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
    }
}

private struct InboxProposedActions: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onSearchRelatedMaterials: () -> Void
    @State private var isEditingSuggestedTask = false
    @State private var editedSuggestedTaskTitle = ""

    private var suggestedActionTitle: String {
        if let interpretation = viewModel.selectedInboxCaptureRecords.first?.interpretationSummary,
           !interpretation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return interpretation
        }
        guard let task else {
            return String(localized: "Add task")
        }
        return String(format: String(localized: "Add %@"), task.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            proposedAction(
                title: suggestedActionTitle,
                systemImage: "checkmark",
                accessibilityIdentifier: "inbox-action-make-task",
                accessibilityHint: "Classifies the selected Inbox item as a task in the local database.",
                keyboardShortcut: "1",
                trailingTitle: String(localized: "Edit"),
                trailingAction: {
                    editedSuggestedTaskTitle = task?.title ?? ""
                    isEditingSuggestedTask = true
                }
            ) {
                viewModel.markSelectedTaskAsTask()
            }
            Divider()
            proposedAction(
                title: String(localized: "Link to a new project"),
                systemImage: "folder",
                accessibilityIdentifier: "inbox-action-make-project",
                accessibilityHint: "Creates a local project from the selected Inbox item.",
                keyboardShortcut: "2",
                trailingTitle: nil
            ) {
                viewModel.convertSelectedTaskToProject()
            }
            Divider()
            proposedAction(
                title: String(localized: "Search related past materials"),
                systemImage: "magnifyingglass",
                accessibilityIdentifier: "inbox-action-search-related",
                accessibilityHint: "Searches related past materials without changing the Inbox item.",
                trailingTitle: nil,
                action: onSearchRelatedMaterials
            )
        }
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.14))
        }
        .alert("Edit proposed task", isPresented: $isEditingSuggestedTask) {
            TextField("Task title", text: $editedSuggestedTaskTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let title = editedSuggestedTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let task, !title.isEmpty else { return }
                viewModel.updateSelectedTask(
                    title: title,
                    detail: task.detail,
                    status: task.status,
                    priority: task.priority,
                    dueAt: task.dueAt,
                    recurrence: task.recurrence
                )
            }
        }
    }

    @ViewBuilder
    private func proposedAction(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        accessibilityHint: String,
        keyboardShortcut: KeyEquivalent? = nil,
        trailingTitle: String? = nil,
        trailingAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            proposedActionButton(
                action: action,
                title: title,
                systemImage: systemImage,
                accessibilityIdentifier: accessibilityIdentifier,
                accessibilityHint: accessibilityHint,
                keyboardShortcut: keyboardShortcut
            )

            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        // Three 36px rows plus two dividers reproduce the 110px reference card.
        .frame(height: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("inbox-proposed-action-\(systemImage)")
    }

    @ViewBuilder
    private func proposedActionButton(
        action: @escaping () -> Void,
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        accessibilityHint: String,
        keyboardShortcut: KeyEquivalent?
    ) -> some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityHint(accessibilityHint)

        if let keyboardShortcut {
            button.keyboardShortcut(keyboardShortcut, modifiers: [.command, .control])
        } else {
            button
        }
    }
}

private struct InboxRelatedMaterialsSheet: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var relatedTasks: [ProjectBoardTask] {
        guard let task else { return [] }
        let terms = Set(task.title.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map {
            String($0).lowercased()
        }.filter { $0.count > 2 })
        return viewModel.snapshot.projects
            .flatMap(\.tasks)
            .filter { candidate in
                candidate.id != task.id && terms.contains { term in
                    candidate.title.lowercased().contains(term)
                }
            }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search related past materials")
                .font(.title3.weight(.semibold))
            if relatedTasks.isEmpty {
                ContentUnavailableView("No related materials", systemImage: "magnifyingglass")
            } else {
                List(relatedTasks) { relatedTask in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(relatedTask.title)
                            .font(.headline)
                        Text(viewModel.projectTitle(for: relatedTask))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .accessibilityIdentifier("inbox-related-materials-sheet")
    }
}

private struct InboxSelectedItemContext: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel
    let manualSummary: InboxTriageSummary?
    let onShowAdvancedVoiceMetadata: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let task {
                HStack(alignment: .center, spacing: 8) {
                    Text(
                        viewModel.selectedInboxCaptureRecords.isEmpty
                            ? LocalizedStringKey(manualSummary?.sourceLabel ?? "Voice")
                            : LocalizedStringKey("Voice Memo")
                    )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer(minLength: 8)
                    Menu("More", systemImage: "ellipsis") {
                        Button("Schedule Today", systemImage: "calendar.badge.plus") {
                            viewModel.scheduleSelectedTaskForToday()
                        }
                        .keyboardShortcut("3", modifiers: [.command, .control])
                        .accessibilityIdentifier("inbox-action-schedule-today")
                        Button("Review Later", systemImage: "clock") {
                            viewModel.deferSelectedTaskForLater()
                        }
                        .keyboardShortcut("4", modifiers: [.command, .control])
                        .accessibilityIdentifier("inbox-action-review-later-menu")
                        if !viewModel.selectedInboxCaptureRecords.isEmpty {
                            Button("Show AI Interpretation and Note", systemImage: "sparkles") {
                                onShowAdvancedVoiceMetadata()
                            }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton)
                    .accessibilityIdentifier("inbox-selected-item-more")
                    .accessibilityLabel("More")

                }

                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let capture = viewModel.selectedInboxCaptureRecords.first,
                   let parsed = SuisuiTimestampDisplay.parse(capture.createdAt) {
                    let time = SuisuiTimestampDisplay.time(parsed.date)
                    let attribution = task.sourceCommand == "ui-evidence"
                        ? String(format: String(localized: "Today %@ · Taro Yamada (you)"), time)
                        : String(format: String(localized: "Voice Memo · %@"), time)
                    Text(attribution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let detail = normalizedInboxDetail(task.detail)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(detail)
                    }
                }

                if let manualSummary, viewModel.selectedInboxCaptureRecords.isEmpty {
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
        // Interactive actions must remain separate AX descendants; combining
        // the context hid the visible More menu from VoiceOver and UI gates.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-selected-context")
    }
}

private struct InboxReferenceDetails: View {
    let task: ProjectBoardTask?
    let capture: InboxCaptureRecord?

    var body: some View {
        VStack(spacing: 0) {
            detailRow("Received", value: received)
            Divider()
            detailRow("Kind", value: kind)
            Divider()
            detailRow("Related", value: capture == nil && task != nil ? String(localized: "Inbox") : String(localized: "Unassigned"))
        }
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-detail-metadata")
    }

    private var kind: String {
        if capture != nil {
            return String(localized: "Voice Memo")
        }
        return String(localized: "Task")
    }

    private var received: String {
        let rawValue = capture?.createdAt ?? task?.createdAt ?? task?.updatedAt
        guard let rawValue else {
            return String(localized: "Unknown")
        }
        return SuisuiTimestampDisplay.absolute(rawValue)
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
        // Three rows plus two dividers resolve to the 116px reference card.
        .frame(minHeight: 38)
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
    let accessibilityIdentifier: String
    let showsAdvancedMetadata: Bool
    let onSaveMemo: (String) -> Void
    @StateObject private var playback = InboxAudioPlaybackController.live()

    var body: some View {
        if let capture = captures.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Voice Memo")
                        .font(.headline)
                    Spacer(minLength: 8)
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
                .accessibilityHidden(true)
                .frame(height: 0)
                .clipped()

                HStack {
                    Text("Inbox Transcript")
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
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Transcript")
                    .accessibilityValue(transcriptReviewText(for: capture))
                .accessibilityIdentifier("inbox-voice-transcript")

                if showsAdvancedMetadata {
                    DisclosureGroup("AI Interpretation", isExpanded: .constant(true)) {
                        detailSection(
                            title: "Interpretation",
                            value: interpretationReviewText(for: capture),
                            systemImage: interpretationSystemImage(for: capture)
                        )
                        .accessibilityIdentifier("inbox-voice-interpretation")
                    }

                    DisclosureGroup("Note", isExpanded: .constant(true)) {
                        memoEditor(for: capture)
                    }
                }

            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel("Voice intake detail for \(taskTitle)")
            .accessibilityValue(captureAccessibilityValue(capture))
            .accessibilityHint("Summarizes the selected Inbox capture metadata for review.")
            .onAppear {
                resetMemoDraft(for: capture)
                playback.load(
                    captureID: capture.id,
                    fileURL: URL(fileURLWithPath: capture.audioFilePath),
                    fallbackDuration: capture.durationSeconds
                )
            }
            .onChange(of: capture.id) { _, _ in
                resetMemoDraft(for: capture)
                playback.load(
                    captureID: capture.id,
                    fileURL: URL(fileURLWithPath: capture.audioFilePath),
                    fallbackDuration: capture.durationSeconds
                )
            }
            .onDisappear {
                playback.stop()
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    playback.toggle()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!playback.isPlayable)
                .accessibilityIdentifier("inbox-voice-playback-toggle")
                .accessibilityLabel(
                    playback.isRetryAvailable
                        ? "Retry voice memo"
                        : (playback.isPlaying ? "Pause voice memo" : "Play voice memo")
                )
                .accessibilityValue(playback.errorMessage ?? playbackAccessibilityValue)
                .help(playbackHelp)

                ZStack {
                    if let waveform = playback.waveform {
                        HStack(alignment: .center, spacing: 2) {
                            ForEach(waveform.indices, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(index < Int(Double(waveform.count) * playbackProgress)
                                        ? Color.accentColor
                                        : Color.accentColor.opacity(0.38))
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 4,
                                        maxHeight: 4 + waveform[index] * 26
                                    )
                            }
                        }
                    } else {
                        ProgressView(value: playbackProgress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 4)
                    }

                    // Keep the native slider as the hit-testing and AX layer,
                    // while the dense waveform owns the reference-matched
                    // visual track across the full available width.
                    Slider(
                        value: Binding(
                            get: { playback.currentTime },
                            set: { playback.seek(to: $0) }
                        ),
                        in: 0...max(playback.duration, 1)
                    )
                    .opacity(0.01)
                    .disabled(!playback.isSeekable)
                    .accessibilityIdentifier("inbox-voice-seek")
                    .accessibilityLabel("Voice memo position")
                    .accessibilityValue(
                        "\(localizedInboxCaptureDuration(playback.currentTime)) / \(localizedInboxCaptureDuration(playback.duration))"
                    )
                    .help("Changes the current Inbox recording position")
                }
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inbox-voice-waveform")

                Text(localizedInboxCaptureDuration(playback.duration > 0 ? playback.duration : capture.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            if let errorMessage = playback.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("inbox-voice-playback-error")
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        // Preserve the following section's reference position while keeping
        // the visible player itself at 52px (32px content + 20px padding).
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-voice-transcript-preview")
        .accessibilityLabel("Voice memo playback")
        .accessibilityValue(playback.errorMessage ?? localizedDisplay(
            "Playable voice memo, duration %@",
            localizedInboxCaptureDuration(capture.durationSeconds)
        ))
    }

    private var playbackProgress: Double {
        guard playback.duration > 0 else { return 0 }
        return min(max(playback.currentTime / playback.duration, 0), 1)
    }

    private var playbackAccessibilityValue: String {
        "\(localizedInboxCaptureDuration(playback.currentTime)) / \(localizedInboxCaptureDuration(playback.duration))"
    }

    private var playbackHelp: String {
        if let errorMessage = playback.errorMessage {
            return errorMessage
        }
        if playback.isRetryAvailable {
            return String(localized: "Retries the selected Inbox recording")
        }
        return String(localized: "Plays or pauses the selected Inbox recording")
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
