import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

private enum TodayWorkflowLayoutMetrics {
    static let twoColumnMinimumWidth: CGFloat = 900
}

struct TodayWorkflowView: View {
    @StateObject private var viewModel: TodayFeatureViewModel
    var selectTodayTask: (ProjectBoardTask) -> Void = { _ in }
    var openInspectorForTodayRailTask: (Int64) -> Void = { _ in }
    var playDailyPlanningReadout: () -> Void = {}
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
        initiallyExpandsCatchUp: Bool = false,
        catchUpFocusRevision: Int? = nil,
        onCatchUpFocusConsumed: @escaping (Int) -> Bool = { _ in true }
    ) {
        _viewModel = StateObject(wrappedValue: TodayFeatureViewModel(board: viewModel))
        self.selectTodayTask = selectTodayTask
        self.openInspectorForTodayRailTask = openInspectorForTodayRailTask
        self.playDailyPlanningReadout = playDailyPlanningReadout
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
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= TodayWorkflowLayoutMetrics.twoColumnMinimumWidth {
                    // The explicit threshold keeps the rail as a stable second
                    // column while both columns have enough room to retain their
                    // existing controls and accessibility order.
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView(.vertical) {
                            mainSurface(snapshot: snapshot, fillsAvailableHeight: false)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        todayAssistantRail(context: snapshot.assistantContext)
                    }
                } else {
                    // A vertical scroll container is finite-height safe when
                    // the detail column is narrow: the task surface must measure
                    // to its content instead of requesting the scroll view's
                    // unbounded height.
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            mainSurface(snapshot: snapshot, fillsAvailableHeight: false)
                            todayAssistantRail(context: snapshot.assistantContext)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-workflow")
    }

    private func mainSurface(
        snapshot: TodayWorkflowSnapshot,
        fillsAvailableHeight: Bool
    ) -> some View {
        WorkflowTaskSurface(
            title: "Today",
            subtitle: subtitle(for: snapshot),
            systemImage: "sun.max",
            tasks: snapshot.plan.tasks,
            emptyTitle: "No tasks due today",
            emptyDescription: "Captured work remains in Inbox until it is scheduled or moved to a project.",
            viewModel: viewModel,
            onSelectTask: selectTodayTask,
            fillsAvailableHeight: fillsAvailableHeight,
            headerAccessory: {
                TodayCommandPanel(
                    commandTitle: $commandTitle,
                    plan: snapshot.plan,
                    recommendationChips: snapshot.recommendationChips,
                    viewModel: viewModel,
                    dailyPlanningReview: viewModel.dailyPlanningReview ?? snapshot.dailyPlanningReviewPreview,
                    playDailyPlanningReadout: playDailyPlanningReadout
                )
            },
            footer: {
                VStack(alignment: .leading, spacing: 12) {
                    TodaySuggestionPanel(plan: snapshot.plan, viewModel: viewModel)
                    TodayWaitingPanel(
                        tasks: viewModel.waitingTasks,
                        projectTitlesByTaskID: viewModel.projectTitlesByTaskID,
                        openInspector: openInspectorForTodayRailTask
                    )
                    if viewModel.catchUpCount > 0 {
                        DisclosureGroup(isExpanded: $isCatchUpExpanded) {
                    CatchUpWorkflowView(viewModel: viewModel)
                                .frame(minHeight: 360)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        String(
                                            format: String(localized: "Catch Up (%d)"),
                                            viewModel.catchUpCount
                                        )
                                    )
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
            }
        )
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

    private func todayAssistantRail(context: TodayAssistantRailContext) -> some View {
        TodayAssistantRail(
            commandTitle: $commandTitle,
            context: context,
            viewModel: viewModel,
            openInspector: openInspectorForTodayRailTask
        )
        .frame(minWidth: 300, idealWidth: 320, maxWidth: 340)
        .padding(.vertical, 18)
        .padding(.trailing, 18)
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

private struct TodayCommandPanel: View {
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
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch primaryActionPresentation {
        case let .startFocus(taskID, title):
            Button {
                viewModel.startFocus(taskID: taskID)
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
                        viewModel.startFocus(taskID: chip.taskID)
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

private struct TodaySuggestionPanel: View {
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

private struct TodayAssistantRail: View {
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
        .soloAssistantSignal()
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

/// Work that is stopped because someone else owes something.
///
/// This is the one state a solo operator loses money on and the one state the
/// app could not show: a task waiting on a client reply is not the user's next
/// action, is not overdue, and is not done, so Today, Overdue, and Completed
/// all skipped it. Sorted longest-wait-first, because the oldest silence is
/// the one that needs a nudge.
private struct TodayWaitingPanel: View {
    let tasks: [ProjectBoardTask]
    let projectTitlesByTaskID: [Int64: String]
    let openInspector: (Int64) -> Void

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(localizedCount(tasks.count, one: "Waiting on (%d)", other: "Waiting on (%d)"))
                        .font(SuisuiTypography.sectionTitle)
                } icon: {
                    Image(systemName: "hourglass")
                }

                ForEach(tasks) { task in
                    Button {
                        openInspector(task.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(subtitle(for: task))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if let elapsed = elapsedLabel(for: task) {
                                SuisuiStatusChip(text: elapsed, tone: tone(for: task))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-waiting-task-\(task.id)")
                    .accessibilityLabel(accessibilityLabel(for: task))
                    .accessibilityHint("Opens the task so you can follow up or clear the wait.")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .soloCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-waiting-panel")
        }
    }

    private func subtitle(for task: ProjectBoardTask) -> String {
        let counterparty = task.waitingOn ?? ""
        guard let projectTitle = projectTitlesByTaskID[task.id] else {
            return counterparty
        }
        return "\(counterparty) · \(projectTitle)"
    }

    private func elapsedLabel(for task: ProjectBoardTask) -> String? {
        guard let days = task.waitingDayCount() else {
            return nil
        }
        if days == 0 {
            return localizedDisplay("Today")
        }
        return localizedCount(days, one: "%d day", other: "%d days")
    }

    /// A wait only earns attention once it has actually gone quiet. Flagging a
    /// same-day wait would make the panel cry wolf every time it is used.
    private func tone(for task: ProjectBoardTask) -> SuisuiTone {
        (task.waitingDayCount() ?? 0) >= 3 ? .attention : .neutral
    }

    private func accessibilityLabel(for task: ProjectBoardTask) -> String {
        guard let elapsed = elapsedLabel(for: task) else {
            return "\(task.title), \(subtitle(for: task))"
        }
        return "\(task.title), \(subtitle(for: task)), \(elapsed)"
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
