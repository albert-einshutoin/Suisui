import SoloPMCore
import SwiftUI

enum ProjectBoardSidebarDestination: Hashable {
    case inbox
    case today
    case project(Int64)

    var title: String {
        switch self {
        case .inbox:
            "Inbox"
        case .today:
            "Today"
        case .project:
            "Project"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox:
            "tray"
        case .today:
            "sun.max"
        case .project:
            "folder"
        }
    }

    var accessibilityIdentifierSuffix: String {
        switch self {
        case .inbox:
            "inbox"
        case .today:
            "today"
        case .project(let projectID):
            "project-\(projectID)"
        }
    }

    func accessibilityLabel(count: Int) -> String {
        "\(title), \(count) item\(count == 1 ? "" : "s")"
    }
}

enum ProjectBoardSelectionPersistence {
    static let storageKey = "solopm.projectBoard.selectedDestination"
    static let environmentOverrideKey = "SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION"
    static let defaultRawValue = "today"

    static var environmentOverrideRawValue: String? {
        let rawValue = ProcessInfo.processInfo.environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawValue?.isEmpty == false ? rawValue : nil
    }

    static func rawValue(for destination: ProjectBoardSidebarDestination) -> String {
        switch destination {
        case .inbox:
            return "inbox"
        case .today:
            return "today"
        case .project(let projectID):
            return "project:\(projectID)"
        }
    }

    static func destination(
        from rawValue: String,
        availableProjects: [ProjectBoardProject]
    ) -> ProjectBoardSidebarDestination {
        switch rawValue {
        case "inbox":
            return .inbox
        case "today":
            return .today
        default:
            let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return .today
            }
            switch parts[0] {
            case "project":
                guard let projectID = Int64(parts[1]),
                      availableProjects.contains(where: { $0.id == projectID }) else {
                    return .today
                }
                return .project(projectID)
            default:
                return .today
            }
        }
    }
}

struct ProjectBoardSidebarDestinationRow: View {
    let destination: ProjectBoardSidebarDestination
    let count: Int

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(destination.title))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: destination.systemImage)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.accessibilityLabel(count: count))
        .accessibilityIdentifier("sidebar-destination-\(destination.accessibilityIdentifierSuffix)")
    }
}

struct TodayWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var plan: TodayWorkflowPlan {
        viewModel.todayPlan()
    }

    private var subtitle: String {
        if viewModel.showsCompletedWorkflowTasks {
            return String(format: String(localized: "%d due or completed tasks"), plan.tasks.count)
        }
        return String(format: String(localized: "%d open due or overdue tasks"), plan.tasks.count)
    }

    var body: some View {
        WorkflowTaskSurface(
            title: "Today",
            subtitle: subtitle,
            systemImage: "sun.max",
            tasks: plan.tasks,
            emptyTitle: "No tasks due today",
            emptyDescription: "Captured work remains in Inbox until it is scheduled or moved to a project.",
            viewModel: viewModel,
            headerAccessory: {
                WorkflowDoneToggle(viewModel: viewModel)
            },
            footer: {
                TodaySuggestionPanel(plan: plan, viewModel: viewModel)
            }
        )
    }
}

struct InboxWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var quickTitle = ""

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
        WorkflowTaskSurface(
            title: "Inbox",
            subtitle: subtitle,
            systemImage: "tray",
            tasks: tasks,
            emptyTitle: "Inbox is clear",
            emptyDescription: "Voice notes, manual captures, and unassigned tasks land here before classification.",
            viewModel: viewModel,
            headerAccessory: {
                InboxHeaderControls(quickTitle: $quickTitle, viewModel: viewModel, addInboxTask: addInboxTask)
            },
            footer: {
                InboxActionPanel(task: viewModel.selectedTask, viewModel: viewModel)
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

private struct WorkflowTaskSurface<HeaderAccessory: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tasks: [ProjectBoardTask]
    let emptyTitle: String
    let emptyDescription: String
    @ObservedObject var viewModel: ProjectBoardViewModel
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @ViewBuilder var footer: () -> Footer

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tasks: [ProjectBoardTask],
        emptyTitle: String,
        emptyDescription: String,
        viewModel: ProjectBoardViewModel,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tasks = tasks
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.viewModel = viewModel
        self.headerAccessory = headerAccessory
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    WorkflowHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                    Spacer(minLength: 12)
                    headerAccessory()
                }

                VStack(alignment: .leading, spacing: 10) {
                    WorkflowHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                    headerAccessory()
                }
            }

            if tasks.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey(emptyTitle),
                    systemImage: systemImage,
                    description: Text(LocalizedStringKey(emptyDescription))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            WorkflowTaskRow(
                                task: task,
                                projectTitle: viewModel.projectTitle(for: task),
                                isSelected: viewModel.selectedTaskID == task.id,
                                onSelect: { viewModel.selectedTaskID = task.id },
                                onToggleCompletion: { viewModel.toggleTaskCompletion(id: task.id) }
                            )
                            .draggable(String(task.id))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            footer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WorkflowDoneToggle: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        Toggle(isOn: Binding(
            get: { viewModel.showsCompletedWorkflowTasks },
            set: { viewModel.setShowsCompletedWorkflowTasks($0) }
        )) {
            Label("Show Done", systemImage: viewModel.showsCompletedWorkflowTasks ? "checkmark.square" : "square")
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help("Show completed tasks in Inbox and Today")
        .accessibilityIdentifier("workflow-show-completed-toggle")
        .accessibilityLabel("Show completed tasks")
        .accessibilityValue(viewModel.showsCompletedWorkflowTasks ? "On" : "Off")
    }
}

private struct WorkflowHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .font(.title2)
        }
    }
}

private struct WorkflowTaskRow: View {
    let task: ProjectBoardTask
    let projectTitle: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleCompletion: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggleCompletion) {
                Label {
                    Text(LocalizedStringKey(toggleCompletionTitle))
                } icon: {
                    Image(systemName: task.status == .done ? "checkmark.square.fill" : "square")
                }
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(task.status.tint)
            .help(LocalizedStringKey(toggleCompletionTitle))
            .accessibilityLabel(toggleCompletionAccessibilityLabel)
            .accessibilityHint("Updates the task status in the local SoloPM database without opening the inspector.")
            .accessibilityIdentifier("workflow-task-completion-\(task.id)")

            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(task.title)
                        HStack(spacing: 8) {
                            Label(projectTitle, systemImage: "folder")
                            Label {
                                Text(LocalizedStringKey(task.status.title))
                            } icon: {
                                Image(systemName: task.status.systemImage)
                            }
                            if let dueLabel = task.dueLabel {
                                Label(dueLabel, systemImage: "calendar")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Label {
                        Text(LocalizedStringKey(task.priority.label))
                    } icon: {
                        Image(systemName: "flag")
                    }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(task.priority.color)
                        .labelStyle(.iconOnly)
                        .help(LocalizedStringKey(task.priority.label))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open task \(task.title)")
            .accessibilityValue(workflowAccessibilityValue)
            .accessibilityHint("Selects this task so Inbox actions or task inspector edits can use it.")
            .accessibilityIdentifier("workflow-task-row-\(task.id)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
    }

    private var workflowAccessibilityValue: String {
        var values = [
            "Project: \(projectTitle)",
            "\(String(localized: "Status")): \(String(localized: String.LocalizationValue(task.status.title)))",
            "\(String(localized: "Priority")): \(String(localized: String.LocalizationValue(task.priority.label)))"
        ]
        if let dueLabel = task.dueLabel {
            values.append("\(String(localized: "Due")): \(dueLabel)")
        }
        return values.joined(separator: ", ")
    }

    private var toggleCompletionTitle: String {
        task.status == .done ? "Reopen task" : "Complete task"
    }

    private var toggleCompletionAccessibilityLabel: String {
        if task.status == .done {
            return localizedDisplay("Reopen task %@", task.title)
        }
        return localizedDisplay("Complete task %@", task.title)
    }
}

private struct InboxActionPanel: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Classify Selected Item")
                .font(.headline)
            InboxCaptureMetadataPanel(captures: viewModel.selectedInboxCaptureRecords)
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
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("inbox-classification-feedback")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    actionButtons
                }
            }
            .disabled(task == nil)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-action-panel")
        .accessibilityLabel("Inbox classification actions")
        .accessibilityHint("Choose how to classify the selected Inbox item.")
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

private struct InboxCaptureMetadataPanel: View {
    let captures: [InboxCaptureRecord]

    var body: some View {
        if let capture = captures.first {
            VStack(alignment: .leading, spacing: 6) {
                Label("Voice Capture", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 6) {
                    metadataRow(title: "Source", value: capture.sourceKind.rawValue)
                    metadataRow(title: "Duration", value: capture.durationLabel)
                    metadataRow(title: "Classification", value: capture.classificationStatus.rawValue)
                    metadataRow(title: "Transcription", value: capture.transcriptionStatus.rawValue)
                }
                metadataRow(title: "Transcript", value: capture.transcript ?? "No transcript yet")
                if let interpretationSummary = capture.interpretationSummary {
                    metadataRow(title: "Interpretation", value: interpretationSummary)
                }
                if let memo = capture.memo {
                    metadataRow(title: "Memo", value: memo)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inbox-capture-metadata")
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
}

private struct TodaySuggestionPanel: View {
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayPlanSummary(plan: plan, viewModel: viewModel)
            TodayTimeBlockList(plan: plan)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-suggestion-panel")
        .accessibilityLabel("Today planning")
        .accessibilityHint("Shows the recommended focus task, due counts, and local time blocks.")
    }
}

private struct TodayPlanSummary: View {
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                recommendation
                Spacer(minLength: 12)
                dueCounts
            }

            VStack(alignment: .leading, spacing: 10) {
                recommendation
                dueCounts
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-plan-summary")
    }

    private var recommendation: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(recommendationTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(recommendationTitle)
                Text(LocalizedStringKey(plan.recommendationReason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-focus-recommendation")
        .accessibilityLabel(recommendationTitle)
        .accessibilityHint(LocalizedStringKey(plan.recommendationReason))
    }

    private var dueCounts: some View {
        HStack(spacing: 8) {
            TodayCountBadge(label: "Overdue", value: plan.overdueCount, tint: .red)
            TodayCountBadge(label: "Today", value: plan.dueTodayCount, tint: .blue)
        }
    }

    private var recommendationTitle: String {
        guard let task = plan.recommendedTask else {
            return "No focus task"
        }
        return String(
            format: String(localized: "Start with %@ in %@"),
            task.title,
            viewModel.projectTitle(for: task)
        )
    }
}

private struct TodayCountBadge: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 68, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-count-badge-\(label.lowercased())")
        .accessibilityLabel("\(label) tasks")
        .accessibilityValue("\(value)")
    }
}

private struct TodayTimeBlockList: View {
    let plan: TodayWorkflowPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Blocks")
                .font(.subheadline.weight(.semibold))

            if plan.timeBlocks.isEmpty {
                Text("No scheduled blocks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plan.timeBlocks) { block in
                    HStack(spacing: 8) {
                        Text(block.label)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .leading)
                        Text(block.task.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(block.task.title)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today-time-block-row-\(block.id)")
                    .accessibilityLabel("\(block.label), \(block.task.title)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-time-block-list")
        .accessibilityLabel("Today time blocks")
        .accessibilityHint("Lists local focus blocks generated from due and overdue tasks.")
    }
}
