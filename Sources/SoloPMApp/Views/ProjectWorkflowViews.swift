import SoloPMCore
import SwiftUI

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
    @State private var commandTitle = ""

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
                TodayCommandPanel(commandTitle: $commandTitle, plan: plan, viewModel: viewModel)
            },
            footer: {
                TodaySuggestionPanel(plan: plan, viewModel: viewModel)
            }
        )
    }
}

struct ScheduleWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var approvalToken = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label("Schedule", systemImage: "calendar")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        _ = viewModel.prepareScheduleDraft()
                    } label: {
                        Label("Generate Draft", systemImage: "wand.and.stars")
                    }
                    .accessibilityIdentifier("schedule-generate-draft")
                    .accessibilityHint("Combines today's local time blocks and unscheduled tasks without writing to Calendar.")
                }

                ScheduleStatusBanner(result: viewModel.scheduleApplyResult)

                HStack(alignment: .top, spacing: 12) {
                    ScheduleDraftPanel(viewModel: viewModel)
                    ScheduleUnscheduledPanel(tasks: viewModel.unscheduledScheduleTasks())
                }

                HStack(spacing: 8) {
                    SecureField("Approval token", text: $approvalToken)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("schedule-approval-token")
                        .accessibilityLabel("Schedule approval token")
                        .accessibilityHint("Required before writing reviewed schedule blocks to Calendar.")
                    Button {
                        _ = viewModel.applyScheduleDraftToCalendar(approvalToken: approvalToken)
                    } label: {
                        Label("Apply to Calendar", systemImage: "calendar.badge.checkmark")
                    }
                    .disabled(viewModel.scheduleDraft == nil)
                    .accessibilityIdentifier("schedule-apply-calendar")
                    .accessibilityHint("Requires approval and a configured Calendar backend before any external write.")
                }

                if let feedback = viewModel.todayCommandFeedback {
                    Label(feedback, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("schedule-feedback")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("schedule-workflow")
    }
}

struct DoneWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var analytics: DoneAnalyticsSummary {
        viewModel.doneAnalytics()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label("Done", systemImage: "checkmark.circle")
                        .font(.title2.weight(.semibold))
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    DoneStatTile(title: "Completed Tasks", value: analytics.completedTaskCount, systemImage: "checkmark.square")
                    DoneStatTile(title: "Completed Projects", value: analytics.completedProjectCount, systemImage: "folder.badge.checkmark")
                    DoneStatTile(title: "Today", value: analytics.completedTodayCount, systemImage: "sun.max")
                    DoneStatTile(title: "7 Days", value: analytics.completedThisWeekCount, systemImage: "calendar")
                    DoneStatTile(title: "Streak", value: analytics.streakDays, systemImage: "flame")
                }

                Label {
                    Text(LocalizedStringKey(analytics.localRuleInsight))
                } icon: {
                    Image(systemName: "lock.doc")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("done-local-rule-insight")

                VStack(alignment: .leading, spacing: 10) {
                    Label("Recent Completed", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    if analytics.recentTasks.isEmpty {
                        ContentUnavailableView(
                            "No completed tasks yet",
                            systemImage: "checkmark.circle",
                            description: Text("Tasks appear here after they are completed.")
                        )
                    } else {
                        ForEach(analytics.recentTasks) { task in
                            DoneTaskHistoryRow(task: task, viewModel: viewModel)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("done-workflow")
    }
}

private struct DoneStatTile: View {
    let title: LocalizedStringKey
    let value: Int
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DoneTaskHistoryRow: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                .foregroundStyle(task.status == .done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(doneMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if task.status == .done {
                Button {
                    viewModel.reopenCompletedTask(id: task.id)
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("done-reopen-task-\(task.id)")
            }
        }
        .padding(.vertical, 6)
    }

    private var doneMetadata: String {
        let projectTitle = viewModel.projectTitle(for: task)
        if let completedAt = task.completedAt {
            return String(format: String(localized: "%@ completed at %@"), projectTitle, completedAt)
        }
        return String(format: String(localized: "%@ completed"), projectTitle)
    }
}

private struct ScheduleDraftPanel: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Draft Blocks", systemImage: "clock")
                .font(.headline)
            if let draft = viewModel.scheduleDraft, !draft.timeBlocks.isEmpty {
                ForEach(draft.timeBlocks) { block in
                    HStack(spacing: 8) {
                        Text(block.label)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        Text(block.task.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(format: String(localized: "Schedule block %@"), block.task.title))
                }
            } else {
                Text("Generate a draft from Today time blocks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ScheduleUnscheduledPanel: View {
    let tasks: [ProjectBoardTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unscheduled Tasks", systemImage: "tray.full")
                .font(.headline)
            if tasks.isEmpty {
                Text("No unscheduled open tasks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks.prefix(8)) { task in
                    Label(task.title, systemImage: "circle")
                        .font(.caption)
                        .lineLimit(1)
                        .accessibilityIdentifier("schedule-unscheduled-task-\(task.id)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ScheduleStatusBanner: View {
    let result: ScheduleApplyResult?

    var body: some View {
        let label = message
        Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("schedule-status-banner")
    }

    private var systemImage: String {
        switch result {
        case .applied:
            "checkmark.circle"
        case .approvalRequired, .calendarNotConfigured, .failed, .noDraft:
            "exclamationmark.triangle"
        case .none:
            "lock.shield"
        }
    }

    private var message: String {
        switch result {
        case .approvalRequired:
            String(localized: "Approval is required before Calendar write.")
        case .calendarNotConfigured:
            String(localized: "Calendar is not configured.")
        case .noDraft:
            String(localized: "Create a schedule draft first.")
        case .applied(let eventCount):
            String(format: String(localized: "Applied %d Calendar events."), eventCount)
        case .failed:
            String(localized: "Calendar apply failed.")
        case .none:
            String(localized: "External Calendar writes require review approval.")
        }
    }
}

private struct TodayCommandPanel: View {
    @Binding var commandTitle: String
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        TodayBriefingPanel(commandTitle: $commandTitle, plan: plan, viewModel: viewModel)
    }
}

private struct TodayBriefingPanel: View {
    @Binding var commandTitle: String
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mic.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("What should move next?", text: $commandTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addInboxItem)
                    .accessibilityIdentifier("today-command-capture-field")
                    .accessibilityLabel("Today command title")
                    .accessibilityHint("Adds a local Inbox item without changing today's existing task statuses.")
                Button(action: addInboxItem) {
                    Label("Add to Inbox", systemImage: "plus.circle.fill")
                }
                .disabled(commandTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add this command to Inbox")
                .accessibilityIdentifier("today-command-add")
                .accessibilityHint("Creates a local Inbox item from the command text.")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    WorkflowDoneToggle(viewModel: viewModel)
                    suggestionRail
                    startFocusButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    WorkflowDoneToggle(viewModel: viewModel)
                    suggestionRail
                    startFocusButton
                }
            }

            TodayFlowStrip(plan: plan, viewModel: viewModel)
        }
        .frame(minWidth: 360, maxWidth: 540, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-briefing-panel")
        .accessibilityLabel("Today briefing")
        .accessibilityHint("Captures work into Inbox and offers the next reviewed Today action.")
    }

    private var suggestionRail: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.todayRecommendationChips()) { chip in
                Button {
                    viewModel.startFocus(taskID: chip.taskID)
                } label: {
                    Label(chip.title, systemImage: chip.systemImage)
                }
                .controlSize(.small)
                .help(chip.reason)
                .accessibilityIdentifier("today-suggestion-chip-\(chip.kind.rawValue)")
                .accessibilityLabel(chip.title)
                .accessibilityHint("Starts this recommended task as local focus without changing task status.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-suggestion-rail")
        .accessibilityLabel("Quick focus suggestions")
    }

    private var startFocusButton: some View {
        Button {
            if let task = plan.recommendedTask {
                viewModel.startFocus(taskID: task.id)
            }
        } label: {
            Label("Start Focus", systemImage: "play.circle")
        }
        .controlSize(.small)
        .disabled(plan.recommendedTask == nil)
        .help("Start focusing without changing task status")
        .accessibilityIdentifier("today-start-focus")
        .accessibilityHint("Marks the recommended task as the current local focus without writing Calendar or task status changes.")
    }

    private func addInboxItem() {
        let title = commandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }
        _ = viewModel.submitTodayCommand(title)
        commandTitle = ""
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
            triageSummary: { task in
                viewModel.inboxTriageSummary(for: task)
            },
            headerAccessory: {
                InboxHeaderControls(quickTitle: $quickTitle, viewModel: viewModel, addInboxTask: addInboxTask)
            },
            footer: {
                InboxActionPanel(task: viewModel.selectedTask, viewModel: viewModel)
            }
        )
        .onAppear {
            viewModel.ensureSelectedInboxTaskIsVisible()
        }
        .onChange(of: tasks.map(\.id)) { _, _ in
            viewModel.ensureSelectedInboxTaskIsVisible()
        }
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
    let triageSummary: (ProjectBoardTask) -> InboxTriageSummary?
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
        triageSummary: @escaping (ProjectBoardTask) -> InboxTriageSummary? = { _ in nil },
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
        self.triageSummary = triageSummary
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
                                triageSummary: triageSummary(task),
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
    let triageSummary: InboxTriageSummary?
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
                        if let triageSummary {
                            InboxTriagePill(summary: triageSummary)
                                .accessibilityIdentifier("inbox-row-triage-summary-\(task.id)")
                        }
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
        if let triageSummary {
            values.append(triageSummary.accessibilityValue)
        }
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

private struct InboxTriagePill: View {
    let summary: InboxTriageSummary

    var body: some View {
        Label {
            Text("\(summary.sourceLabel) · \(summary.interpretationLabel)")
        } icon: {
            Image(systemName: summary.systemImage)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inbox source and interpretation")
        .accessibilityValue(summary.accessibilityValue)
    }

    private var tint: Color {
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

private struct InboxActionPanel: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Classify Selected Item")
                .font(.headline)
            InboxVoiceIntakeDetail(
                captures: viewModel.selectedInboxCaptureRecords,
                taskTitle: task?.title ?? "Selected Inbox item",
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
    let onSaveMemo: (String) -> Void
    @State private var memoDraft = ""
    @State private var memoCaptureID: Int64?

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
            Button {} label: {
                Label("Play", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .disabled(true)
            .frame(width: 28, height: 28)
            .accessibilityLabel("Voice playback")
            .accessibilityValue("Playback unavailable")

            Text("00:00")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

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
        .accessibilityIdentifier("inbox-voice-playback")
        .accessibilityLabel("Voice playback")
        .accessibilityValue("Playback unavailable in this MVP, duration \(capture.durationLabel), waveform preview placeholder")
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

private struct TodaySuggestionPanel: View {
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayAISuggestionCard(plan: plan, viewModel: viewModel)
            TodayTimeBlockList(plan: plan)
            HStack(spacing: 8) {
                Button {
                    _ = viewModel.prepareTodayScheduleDraft()
                } label: {
                    Label("Schedule Draft", systemImage: "calendar.badge.clock")
                }
                .disabled(plan.timeBlocks.isEmpty)
                .help("Prepare local time blocks for schedule review")
                .accessibilityIdentifier("today-schedule-draft-button")
                .accessibilityHint("Creates a local schedule draft without writing to an external calendar.")

                if let draft = viewModel.todayScheduleDraft {
                    Text(String(format: String(localized: "%d blocks ready"), draft.timeBlocks.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("today-schedule-draft-status")
                }
            }
            if let feedback = viewModel.todayCommandFeedback {
                Label(feedback, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today-command-feedback")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-suggestion-panel")
        .accessibilityLabel("Today planning")
        .accessibilityHint("Shows the recommended focus task, due counts, and local time blocks.")
    }
}

private struct TodayAISuggestionCard: View {
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("AI suggestion", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button {
                    if let task = plan.recommendedTask {
                        viewModel.startFocus(taskID: task.id)
                    }
                } label: {
                    Label("Start Focus", systemImage: "play.circle")
                }
                .controlSize(.small)
                .disabled(plan.recommendedTask == nil)
                .help("Start focus from recommendation")
                .accessibilityIdentifier("today-ai-suggestion-start-focus")
                .accessibilityHint("Marks the recommended task as the current local focus without writing Calendar or task status changes.")
            }

            TodayPlanSummary(plan: plan, viewModel: viewModel)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-ai-suggestion-card")
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

private struct TodayFlowStrip: View {
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var visibleBlocks: [TodayTimeBlock] {
        Array(plan.timeBlocks.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label("Today Flow", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Button {
                    _ = viewModel.prepareTodayScheduleDraft()
                } label: {
                    Label("Optimize Flow", systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .disabled(plan.timeBlocks.isEmpty)
                .accessibilityIdentifier("today-flow-optimize")
                .accessibilityHint("Generates a local schedule draft from the visible Today flow without writing Calendar.")
            }

            if visibleBlocks.isEmpty {
                Text("No flow blocks yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(visibleBlocks) { block in
                        Button {
                            viewModel.startFocus(taskID: block.task.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.label)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(block.task.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .help(block.task.title)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("today-flow-chip-\(block.id)")
                        .accessibilityLabel("Focus block")
                        .accessibilityValue(block.task.title)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-flow-strip")
        .accessibilityLabel("Today Flow")
        .accessibilityHint("Shows a compact route through the first local Today time blocks.")
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
