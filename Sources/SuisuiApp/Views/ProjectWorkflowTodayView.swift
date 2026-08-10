import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

struct TodayWorkflowView: View {
    @StateObject private var viewModel: TodayFeatureViewModel
    @StateObject private var weatherModel: TodayWeatherModel
    var selectTodayTask: (ProjectBoardTask) -> Void = { _ in }
    var openInspectorForTodayRailTask: (Int64) -> Void = { _ in }
    var playDailyPlanningReadout: () -> Void = {}
    var openReview: () -> Void = {}
    let dashboardDisplayName: String
    let dashboardDailyCapacityMinutes: Int
    let dashboardWeatherState: TodayWeatherState?
    let initiallyExpandsCatchUp: Bool
    var catchUpFocusRevision: Int? = nil
    var onCatchUpFocusConsumed: (Int) -> Bool = { _ in true }
    @State private var commandTitle = ""
    @State private var isCatchUpExpanded = false
    @AccessibilityFocusState private var isCatchUpFocused: Bool

    init(
        viewModel: ProjectBoardViewModel,
        selectTodayTask: @escaping (ProjectBoardTask) -> Void = { _ in },
        openInspectorForTodayRailTask: @escaping (Int64) -> Void = { _ in },
        playDailyPlanningReadout: @escaping () -> Void = {},
        openReview: @escaping () -> Void = {},
        dashboardDisplayName: String = "",
        dashboardDailyCapacityMinutes: Int = AppSettings.default.dailyWorkCapacityMinutes,
        dashboardWeatherState: TodayWeatherState? = nil,
        weatherModel: TodayWeatherModel? = nil,
        initiallyExpandsCatchUp: Bool = false,
        catchUpFocusRevision: Int? = nil,
        onCatchUpFocusConsumed: @escaping (Int) -> Bool = { _ in true }
    ) {
        _viewModel = StateObject(wrappedValue: TodayFeatureViewModel(board: viewModel))
        _weatherModel = StateObject(wrappedValue: weatherModel ?? AppRuntimeFactory.makeTodayWeatherModel())
        self.selectTodayTask = selectTodayTask
        self.openInspectorForTodayRailTask = openInspectorForTodayRailTask
        self.playDailyPlanningReadout = playDailyPlanningReadout
        self.openReview = openReview
        self.dashboardDisplayName = dashboardDisplayName
        self.dashboardDailyCapacityMinutes = dashboardDailyCapacityMinutes
        self.dashboardWeatherState = dashboardWeatherState
        self.initiallyExpandsCatchUp = initiallyExpandsCatchUp
        self.catchUpFocusRevision = catchUpFocusRevision
        self.onCatchUpFocusConsumed = onCatchUpFocusConsumed
        _isCatchUpExpanded = State(initialValue: initiallyExpandsCatchUp)
    }

    private func subtitle(for snapshot: TodayWorkflowSnapshot) -> String {
        let count = snapshot.plan.tasks.count
        if viewModel.showsCompletedWorkflowTasks {
            return localizedCount(
                count,
                one: "%d due or completed task",
                other: "%d due or completed tasks"
            )
        }
        return localizedCount(
            count,
            one: "%d open due or overdue task",
            other: "%d open due or overdue tasks"
        )
    }

    var body: some View {
        let snapshot = viewModel.snapshot
        TodayDashboardView(
            snapshot: snapshot,
            schedule: viewModel.schedule,
            projectTitlesByTaskID: viewModel.projectTitlesByTaskID,
            viewModel: viewModel,
            commandTitle: $commandTitle,
            displayName: dashboardDisplayName,
            dailyCapacityMinutes: dashboardDailyCapacityMinutes,
            weatherState: dashboardWeatherState ?? weatherModel.state,
            integrationsState: viewModel.integrationStates,
            selectTodayTask: selectTodayTask,
            openInspectorForTodayRailTask: openInspectorForTodayRailTask,
            playDailyPlanningReadout: playDailyPlanningReadout,
            openCatchUp: {
                isCatchUpExpanded = true
                isCatchUpFocused = true
            },
            openReview: openReview
        ) {
            catchUpSection
        }
        .task {
            await weatherModel.refreshIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-workflow")
    }

    private var catchUpSection: some View {
        Group {
            if viewModel.catchUpCount > 0 {
                DisclosureGroup(isExpanded: $isCatchUpExpanded) {
                    CatchUpWorkflowView(viewModel: viewModel)
                        .frame(minHeight: 360)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: String(localized: "Catch Up (%d)"), viewModel.catchUpCount))
                            Text("Review overdue work, then complete, reschedule, or defer one item.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                    }
                }
                .accessibilityIdentifier("today-catch-up-section")
                .accessibilityHint("Expands overdue and missed work actions without leaving Today.")
                .accessibilityFocused($isCatchUpFocused)
            }
        }
        .onAppear {
            if initiallyExpandsCatchUp,
               viewModel.catchUpCount > 0 {
                DispatchQueue.main.async {
                    isCatchUpFocused = true
                }
            }
            applyCatchUpFocusIfNeeded(catchUpFocusRevision)
        }
        .onChange(of: catchUpFocusRevision) { _, revision in
            applyCatchUpFocusIfNeeded(revision)
        }
        .onChange(of: initiallyExpandsCatchUp) { _, shouldExpand in
            guard shouldExpand,
                  viewModel.catchUpCount > 0 else {
                return
            }
            isCatchUpExpanded = true
            DispatchQueue.main.async {
                isCatchUpFocused = true
            }
        }
        .onChange(of: viewModel.catchUpCount) { _, _ in
            // Restoration can publish its one-shot focus before the first
            // derived read-model load finishes. Retrying on count publication
            // keeps the intent pending without showing an empty section.
            applyCatchUpFocusIfNeeded(catchUpFocusRevision)
        }
    }

    private func applyCatchUpFocusIfNeeded(_ revision: Int?) {
        guard let revision,
              viewModel.catchUpCount > 0 else {
            return
        }
        isCatchUpExpanded = true
        // SwiftUI needs one layout pass to publish the expanded AX subtree.
        // Moving AX focus then also scrolls the containing workflow surface to
        // the disclosure without adding persistent layout state.
        DispatchQueue.main.async {
            guard onCatchUpFocusConsumed(revision) else {
                return
            }
            isCatchUpFocused = true
        }
    }

}

private struct TodayDailyPlanningReviewPanel: View {
    @ObservedObject var viewModel: TodayFeatureViewModel
    let review: DailyPlanningReview?
    let playDailyPlanningReadout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label("Daily Planning Review", systemImage: "sparkles")
                    .font(SuisuiTypography.sectionTitle)
                Spacer(minLength: 8)
                Text("Suggestion only")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SuisuiSurface.groupedContent, in: Capsule())
            }

            if let review {
                Text(review.headline)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(review.spokenSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !review.focusItems.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(review.focusItems.prefix(3)) { item in
                            HStack(spacing: 7) {
                                Image(systemName: "target")
                                    .font(.caption)
                                    .foregroundStyle(SuisuiBrand.soloBlue)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    Text(item.reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("today-daily-planning-focus-\(item.taskID)")
                        }
                    }
                }

                Menu {
                    Button {
                        playDailyPlanningReadout()
                    } label: {
                        Label("Read Aloud", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("today-daily-planning-readout")
                    .accessibilityHint("Uses local TTS to read the review without changing tasks or writing Calendar.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .startRecommended)
                    } label: {
                        Label("Draft Start", systemImage: "play.circle")
                    }
                    .disabled(review.recommendedTaskID == nil)
                    .accessibilityIdentifier("today-daily-planning-draft-start")
                    .accessibilityHint("Creates an Assistant Queue approval item without changing the task.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .deferRecommendedToTomorrow)
                    } label: {
                        Label("Draft Defer", systemImage: "calendar.badge.clock")
                    }
                    .disabled(review.recommendedTaskID == nil)
                    .accessibilityIdentifier("today-daily-planning-draft-defer")
                    .accessibilityHint("Creates an Assistant Queue approval item without writing Calendar.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .moveRecommendedDueDateToToday)
                    } label: {
                        Label("Draft Move to Today", systemImage: "arrow.right.circle")
                    }
                    .disabled(review.recommendedTaskID == nil)
                    .accessibilityIdentifier("today-daily-planning-draft-move-today")
                    .accessibilityHint("Creates an Assistant Queue approval item; task due date and Calendar stay unchanged until approval.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .splitRecommendedTask)
                    } label: {
                        Label("Draft Split", systemImage: "square.split.2x1")
                    }
                    .disabled(review.recommendedTaskID == nil)
                    .accessibilityIdentifier("today-daily-planning-draft-split")
                    .accessibilityHint("Creates an Assistant Queue approval item; no tasks are created until approval.")
                } label: {
                    Label("Review actions…", systemImage: "ellipsis.circle")
                }
                .controlSize(.small)
                .help("Read the review or prepare a reviewable task draft.")
                .accessibilityIdentifier("today-daily-planning-actions-menu")
                .accessibilityLabel("Daily planning review actions")
                .accessibilityHint("Opens read aloud and draft actions without changing tasks, Calendar, or Reminders.")
            } else {
                Text("Preparing Daily Planning Review…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .soloAssistantSignal()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-daily-planning-review")
        .accessibilityLabel("Daily Planning Review")
        .accessibilityHint("Shows a local proposal for today's focus without changing tasks or writing Calendar.")
    }
}

struct TodayCommandPanel: View {
    @Binding var commandTitle: String
    let plan: TodayWorkflowPlan
    let recommendationChips: [TodayRecommendationChip]
    @ObservedObject var viewModel: TodayFeatureViewModel
    let dailyPlanningReview: DailyPlanningReview?
    let playDailyPlanningReadout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayBriefingPanel(
                commandTitle: $commandTitle,
                plan: plan,
                recommendationChips: recommendationChips,
                viewModel: viewModel
            )
            TodayDailyPlanningReviewPanel(
                viewModel: viewModel,
                review: dailyPlanningReview,
                playDailyPlanningReadout: playDailyPlanningReadout
            )
        }
    }
}

private struct TodayBriefingPanel: View {
    @Binding var commandTitle: String
    let plan: TodayWorkflowPlan
    let recommendationChips: [TodayRecommendationChip]
    @ObservedObject var viewModel: TodayFeatureViewModel
    @State private var focusTaskPendingReplacement: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayPlanSummary(plan: plan, viewModel: viewModel)

            primaryAction
                .buttonStyle(.borderedProminent)

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
                    Label("Add to Inbox", systemImage: "plus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(!canAddCommand)
                .help("Add this command to Inbox")
                .accessibilityIdentifier("today-command-add")
                .accessibilityLabel("Add to Inbox")
                .accessibilityHint("Creates a local Inbox item while keeping the recommended focus action primary.")
                secondaryActionsMenu
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: SuisuiRadius.card)
                    .stroke(SuisuiBorder.subtle, lineWidth: 1)
            }

            TodayFlowStrip(plan: plan)
        }
        .frame(minWidth: 320, maxWidth: 640, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-briefing-panel")
        .accessibilityLabel("Today briefing")
        .accessibilityHint("Captures work into Inbox and offers the next reviewed Today action.")
        .alert(
            "Replace active Focus?",
            isPresented: Binding(
                get: { focusTaskPendingReplacement != nil },
                set: { isPresented in
                    if !isPresented {
                        focusTaskPendingReplacement = nil
                    }
                }
            )
        ) {
            Button("Replace", role: .destructive) {
                guard let taskID = focusTaskPendingReplacement else { return }
                _ = viewModel.startFocusSession(taskID: taskID, replaceExisting: true)
                focusTaskPendingReplacement = nil
            }
            Button("Cancel", role: .cancel) {
                focusTaskPendingReplacement = nil
            }
        } message: {
            Text("Starting a new Focus ends the active local session. It does not change task status or Calendar.")
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch primaryActionPresentation {
        case let .startFocus(taskID, title):
            Button {
                startFocus(taskID: taskID)
            } label: {
                Label("Start Focus", systemImage: "play.circle.fill")
            }
            .help(String(format: String(localized: "Start focusing on %@"), title))
            .accessibilityIdentifier("today-primary-action")
            .accessibilityLabel("Start Focus")
            .accessibilityValue(title)
            .accessibilityHint("Starts local focus without changing task status, Calendar, or Reminders.")
        case let .addToInbox(text):
            Button(action: addInboxItem) {
                Label("Add to Inbox", systemImage: "plus.circle.fill")
            }
            .help(String(format: String(localized: "Add \"%@\" to Inbox"), text))
            .accessibilityIdentifier("today-primary-action")
            .accessibilityHint("Creates a local Inbox item without changing today's existing tasks.")
        case .addTaskForToday:
            Button {
                commandTitle = String(localized: "New task: ")
            } label: {
                Label("Add a task for today", systemImage: "plus.circle.fill")
            }
            .help("Prepare a new local Inbox task")
            .accessibilityIdentifier("today-primary-action")
            .accessibilityHint("Prefills the capture field so you can describe a task before adding it to Inbox.")
        case let .unavailable(reason):
            Label(LocalizedStringKey(reason), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("today-primary-action-unavailable-reason")
        }
    }

    private var primaryActionPresentation: TodayPrimaryActionPresentation {
        plan.primaryActionPresentation(commandText: commandTitle)
    }

    private var secondaryActionsMenu: some View {
        Menu {
            Button {
                commandTitle = String(localized: "New task: ")
            } label: {
                Label("Add Task", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("today-secondary-add-task")

            Divider()

            Button {
                commandTitle = String(localized: "Plan tomorrow: ")
            } label: {
                Label("Plan Tomorrow", systemImage: "calendar.badge.plus")
            }
            .accessibilityIdentifier("today-common-chip-plan-tomorrow")
            .accessibilityHint("Prefills the Today command field without writing Calendar.")

            Button {
                commandTitle = String(localized: "Prepare meeting: ")
            } label: {
                Label("Prepare Meeting", systemImage: "person.2")
            }
            .accessibilityIdentifier("today-common-chip-prepare-meeting")
            .accessibilityHint("Prefills the Today command field for a meeting preparation task.")

            Button {
                commandTitle = String(localized: "Draft reply: ")
            } label: {
                Label("Draft Reply", systemImage: "arrowshape.turn.up.left")
            }
            .accessibilityIdentifier("today-common-chip-draft-reply")
            .accessibilityHint("Prefills the Today command field for a reply draft task.")

            if !recommendationChips.isEmpty {
                Divider()
                ForEach(recommendationChips) { chip in
                    Button {
                        startFocus(taskID: chip.taskID)
                    } label: {
                        Label(chip.title, systemImage: chip.systemImage)
                    }
                    .help(chip.reason)
                    .accessibilityIdentifier("today-suggestion-chip-\(chip.kind.rawValue)")
                    .accessibilityHint("Starts this alternative local focus without changing task status.")
                }
            }

            Divider()

            Button {
                _ = viewModel.prepareTodayScheduleDraft()
            } label: {
                Label("Schedule Draft", systemImage: "calendar.badge.clock")
            }
            .disabled(plan.timeBlocks.isEmpty)
            .accessibilityIdentifier("today-schedule-draft-button")
            .accessibilityHint("Creates a local schedule draft without writing Calendar.")

            Toggle(isOn: Binding(
                get: { viewModel.showsCompletedWorkflowTasks },
                set: { viewModel.setShowsCompletedWorkflowTasks($0) }
            )) {
                Label("Show Done", systemImage: viewModel.showsCompletedWorkflowTasks ? "checkmark.square" : "square")
            }
            .accessibilityIdentifier("workflow-show-completed-toggle")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .controlSize(.small)
        .help("Open Today capture, planning, and display actions.")
        .accessibilityIdentifier("today-secondary-actions-menu")
        .accessibilityLabel("More Today actions")
        .accessibilityHint("Opens secondary actions after the recommended task and primary action.")
    }

    private func startFocus(taskID: Int64) {
        if case .failure(.requiresReplacement) = viewModel.startFocusSession(taskID: taskID) {
            focusTaskPendingReplacement = taskID
        }
    }

    private func addInboxItem() {
        let title = trimmedCommandTitle
        guard canAddCommand else {
            return
        }
        _ = viewModel.submitCommand(title)
        commandTitle = ""
    }

    private var trimmedCommandTitle: String {
        commandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddCommand: Bool {
        // Quick actions intentionally prefill incomplete drafts. A trailing
        // prefix marker keeps the primary action on safe capture preparation
        // until the user provides concrete content.
        !trimmedCommandTitle.isEmpty && !trimmedCommandTitle.hasSuffix(":")
    }
}

struct TodaySuggestionPanel: View {
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: TodayFeatureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A fourth "AI suggestion" card used to sit here. Today already
            // points at the same single next task from the header
            // recommendation, the Daily Planning Review card, and the assistant
            // rail; this card added no suggestion of its own and only said that
            // more options live in the More menu. A secretary's value is
            // narrowing to one thing, so the pointer-to-a-menu card is gone and
            // the rail stays the one focal surface.
            TodayTimeBlockList(plan: plan)
            if let draft = viewModel.scheduleDraft {
                Text(localizedCount(draft.timeBlocks.count, one: "%d block ready", other: "%d blocks ready"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("today-schedule-draft-status")
            }
            if let feedback = viewModel.commandFeedback {
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

struct TodayAssistantRail: View {
    @Binding var commandTitle: String
    let context: TodayAssistantRailContext
    @ObservedObject var viewModel: TodayFeatureViewModel
    let openInspector: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next Action", systemImage: "sparkles")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(context.nextActionTitle))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(context.nextActionReason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-rail-next-action")

            Divider()

            if let task = context.task {
                taskDetail(task)
                railActions(task)
            } else {
                emptyDetail
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-assistant-rail")
        .accessibilityLabel("Today assistant rail")
        .accessibilityHint("Shows focused, selected, or recommended Today task details and local next actions.")
    }

    private func taskDetail(_ task: ProjectBoardTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(task.title)

            detailRow(title: "Project", value: context.projectTitle, systemImage: "folder")
            detailRow(title: "Status", value: String(localized: String.LocalizationValue(task.status.title)), systemImage: task.status.systemImage)
            detailRow(title: "Priority", value: String(localized: String.LocalizationValue(task.priority.label)), systemImage: "flag")
            detailRow(
                title: "Due",
                value: task.todayDueDisplayLabel(locale: localizedDisplayLocale())
                    ?? localizedDisplay("No due date"),
                systemImage: "calendar"
            )
            detailRow(title: "Time Block", value: context.nextBlockLabel ?? String(localized: "No block drafted"), systemImage: "clock")
            detailRow(title: "Notes", value: context.notes, systemImage: "note.text")
            detailRow(title: "Today Progress", value: context.subtaskSummary, systemImage: "checklist")
            detailRow(title: "Reminder", value: context.reminderSummary, systemImage: "bell")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-rail-task-detail")
    }

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No due task selected", systemImage: "tray")
                .font(.subheadline.weight(.semibold))
            Text(LocalizedStringKey(context.notes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-rail-task-detail")
    }

    private func railActions(_ task: ProjectBoardTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Button {
                    _ = viewModel.prepareTodayScheduleDraft(prioritizing: task.id)
                } label: {
                    Label("Schedule Block", systemImage: "calendar.badge.clock")
                }
                .accessibilityIdentifier("today-rail-schedule-block")
                .accessibilityHint("Creates a local schedule draft without writing Calendar.")

                Button {
                    openInspector(task.id)
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("today-rail-edit-task")
                .accessibilityHint("Opens the selected task in the inspector for manual edits.")

                Button {
                    commandTitle = String(format: String(localized: "Subtask for %@: "), task.title)
                } label: {
                    Label("Add Subtask", systemImage: "checklist")
                }
                .accessibilityIdentifier("today-rail-add-subtask")
                .accessibilityHint("Prefills the Today command field for a local subtask draft.")

                Button {
                    viewModel.enqueueTodayReminderDraft(for: task.id)
                } label: {
                    Label("Add Reminder Draft", systemImage: "bell.badge")
                }
                .accessibilityIdentifier("today-rail-reminder-draft")
                .accessibilityHint("Queues a Reminders draft for approval before any external write.")
            } label: {
                Label("Task actions…", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("today-rail-actions-menu")
            .accessibilityHint("Opens edit, subtask, schedule, and reminder draft actions for this task.")

            if let draft = viewModel.scheduleDraft {
                Text(localizedCount(draft.timeBlocks.count, one: "%d block ready", other: "%d blocks ready"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("today-rail-schedule-draft-status")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func detailRow(title: LocalizedStringKey, value: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TodayPlanSummary: View {
    let plan: TodayWorkflowPlan
    @ObservedObject var viewModel: TodayFeatureViewModel

    var body: some View {
        // The recommendation and counts remain readable at the minimum
        // detail width when they own separate vertical rows. This avoids
        // ViewThatFits measuring a wide and narrow tree on every update.
        VStack(alignment: .leading, spacing: 10) {
            recommendation
            dueCounts
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
                .foregroundStyle(SuisuiBrand.soloBlue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-focus-recommendation")
        .accessibilityLabel(recommendationTitle)
        .accessibilityHint(LocalizedStringKey(plan.recommendationReason))
    }

    private var dueCounts: some View {
        HStack(spacing: 8) {
            TodayCountBadge(
                label: "Overdue",
                value: plan.overdueCount,
                systemImage: "clock.badge.exclamationmark",
                tint: SuisuiTone.danger.color
            )
            TodayCountBadge(
                label: "Today",
                value: plan.dueTodayCount,
                systemImage: "calendar",
                tint: SuisuiBrand.soloBlue
            )
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
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Label(LocalizedStringKey(label), systemImage: systemImage)
                .font(SuisuiTypography.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 68, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-count-badge-\(label.lowercased())")
        .accessibilityLabel("\(label) tasks")
        .accessibilityValue("\(value)")
    }
}

private struct TodayFlowStrip: View {
    let plan: TodayWorkflowPlan

    private var visibleBlocks: [TodayTimeBlock] {
        Array(plan.timeBlocks.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Today Flow", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.caption.weight(.semibold))

            if visibleBlocks.isEmpty {
                Text("No flow blocks yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(visibleBlocks) { block in
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
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
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
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
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
