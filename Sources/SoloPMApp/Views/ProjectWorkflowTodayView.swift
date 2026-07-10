import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

private enum TodayWorkflowLayoutMetrics {
    static let twoColumnMinimumWidth: CGFloat = 900
}

struct TodayWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    var selectTodayTask: (ProjectBoardTask) -> Void = { _ in }
    var openInspectorForTodayRailTask: (Int64) -> Void = { _ in }
    var playDailyPlanningReadout: () -> Void = {}
    @State private var commandTitle = ""

    private func subtitle(for snapshot: TodayWorkflowSnapshot) -> String {
        if viewModel.showsCompletedWorkflowTasks {
            return String(format: String(localized: "%d due or completed tasks"), snapshot.plan.tasks.count)
        }
        return String(format: String(localized: "%d open due or overdue tasks"), snapshot.plan.tasks.count)
    }

    var body: some View {
        let snapshot = viewModel.derivedReadModels.todayWorkflowSnapshot
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= TodayWorkflowLayoutMetrics.twoColumnMinimumWidth {
                    // The explicit threshold keeps the rail as a stable second
                    // column while both columns have enough room to retain their
                    // existing controls and accessibility order.
                    HStack(alignment: .top, spacing: 0) {
                        mainSurface(snapshot: snapshot, fillsAvailableHeight: true)
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
            emptyStateAction: WorkflowEmptyStateAction(
                title: "Add a task for today",
                systemImage: "plus.circle",
                accessibilityIdentifier: "today-empty-add-task",
                handler: {
                    // Mirrors the Add Task chip: prefill the Today capture
                    // field so the next keystroke creates a local Inbox item.
                    commandTitle = String(localized: "New task: ")
                }
            ),
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
                TodaySuggestionPanel(plan: snapshot.plan, viewModel: viewModel)
            }
        )
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
    @ObservedObject var viewModel: ProjectBoardViewModel
    let review: DailyPlanningReview?
    let playDailyPlanningReadout: () -> Void
    private let actionButtonColumns = [
        GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label("Daily Planning Review", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("Proposal only")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
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
                                    .foregroundStyle(.blue)
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

                LazyVGrid(columns: actionButtonColumns, alignment: .leading, spacing: 8) {
                    Button {
                        playDailyPlanningReadout()
                    } label: {
                        Label("Read Aloud", systemImage: "speaker.wave.2")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Reads this daily planning review with the configured local TTS provider.")
                    .accessibilityIdentifier("today-daily-planning-readout")
                    .accessibilityHint("Uses local TTS to read the review without changing tasks or writing Calendar.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .startRecommended)
                    } label: {
                        Label("Draft Start", systemImage: "play.circle")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(review.recommendedTaskID == nil)
                    .help("Queue the recommended task status update for review.")
                    .accessibilityIdentifier("today-daily-planning-draft-start")
                    .accessibilityHint("Creates an Assistant Queue approval item without changing the task.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .deferRecommendedToTomorrow)
                    } label: {
                        Label("Draft Defer", systemImage: "calendar.badge.clock")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(review.recommendedTaskID == nil)
                    .help("Queue a tomorrow due-date update for review.")
                    .accessibilityIdentifier("today-daily-planning-draft-defer")
                    .accessibilityHint("Creates an Assistant Queue approval item without writing Calendar.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .moveRecommendedDueDateToToday)
                    } label: {
                        Label("Draft Move to Today", systemImage: "arrow.right.circle")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(review.recommendedTaskID == nil)
                    .help("Queue a today due-date update for review without creating a Calendar event.")
                    .accessibilityIdentifier("today-daily-planning-draft-move-today")
                    .accessibilityHint("Creates an Assistant Queue approval item; task due date and Calendar stay unchanged until approval.")

                    Button {
                        viewModel.enqueueDailyPlanningActionDraft(kind: .splitRecommendedTask)
                    } label: {
                        Label("Draft Split", systemImage: "square.split.2x1")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(review.recommendedTaskID == nil)
                    .help("Queue reviewable follow-up task drafts without changing the original task.")
                    .accessibilityIdentifier("today-daily-planning-draft-split")
                    .accessibilityHint("Creates an Assistant Queue approval item; no tasks are created until approval.")
                }
            } else {
                Text("Preparing Daily Planning Review…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
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
    @ObservedObject var viewModel: ProjectBoardViewModel
    let dailyPlanningReview: DailyPlanningReview?
    let playDailyPlanningReadout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayDailyPlanningReviewPanel(
                viewModel: viewModel,
                review: dailyPlanningReview,
                playDailyPlanningReadout: playDailyPlanningReadout
            )
            TodayBriefingPanel(
                commandTitle: $commandTitle,
                plan: plan,
                recommendationChips: recommendationChips,
                viewModel: viewModel
            )
        }
    }
}

private struct TodayBriefingPanel: View {
    @Binding var commandTitle: String
    let plan: TodayWorkflowPlan
    let recommendationChips: [TodayRecommendationChip]
    @ObservedObject var viewModel: ProjectBoardViewModel

    private let actionRowColumns = [
        GridItem(.adaptive(minimum: 180), spacing: 8, alignment: .leading)
    ]

    private let suggestionColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)
    ]

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
                .disabled(!canAddCommand)
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

            commonActionRail

            // Keep the action order in one deterministic container. The
            // adaptive columns wrap controls instead of probing alternate
            // ViewThatFits branches during every width negotiation.
            LazyVGrid(columns: actionRowColumns, alignment: .leading, spacing: 8) {
                WorkflowDoneToggle(viewModel: viewModel)
                suggestionRail
                startFocusButton
            }

            TodayFlowStrip(plan: plan, viewModel: viewModel)
        }
        .frame(minWidth: 320, maxWidth: 540, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-briefing-panel")
        .accessibilityLabel("Today briefing")
        .accessibilityHint("Captures work into Inbox and offers the next reviewed Today action.")
    }

    private var commonActionRail: some View {
        // These four actions have stable order, but their labels vary by
        // locale. An adaptive grid gives each button a bounded proposal and
        // wraps the rail without the recursive branch measurement of
        // ViewThatFits.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            commonActionButtons
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-common-action-rail")
        .accessibilityLabel("Common Today actions")
    }

    @ViewBuilder
    private var commonActionButtons: some View {
        Button {
            commandTitle = String(localized: "New task: ")
        } label: {
            Label("Add Task", systemImage: "plus.circle")
        }
        .controlSize(.small)
        .help("Prepare a new local Inbox task")
        .accessibilityIdentifier("today-common-chip-add-task")
        .accessibilityHint("Prefills the Today command field for a local Inbox task.")

        Button {
            commandTitle = String(localized: "Plan tomorrow: ")
        } label: {
            Label("Plan Tomorrow", systemImage: "calendar.badge.plus")
        }
        .controlSize(.small)
        .help("Prepare a tomorrow planning note")
        .accessibilityIdentifier("today-common-chip-plan-tomorrow")
        .accessibilityHint("Prefills the Today command field without writing Calendar.")

        Button {
            commandTitle = String(localized: "Prepare meeting: ")
        } label: {
            Label("Prepare Meeting", systemImage: "person.2")
        }
        .controlSize(.small)
        .help("Prepare a meeting task")
        .accessibilityIdentifier("today-common-chip-prepare-meeting")
        .accessibilityHint("Prefills the Today command field for a meeting preparation task.")

        Button {
            commandTitle = String(localized: "Draft reply: ")
        } label: {
            Label("Draft Reply", systemImage: "arrowshape.turn.up.left")
        }
        .controlSize(.small)
        .help("Prepare a reply draft task")
        .accessibilityIdentifier("today-common-chip-draft-reply")
        .accessibilityHint("Prefills the Today command field for a reply draft task.")
    }

    private var suggestionRail: some View {
        LazyVGrid(columns: suggestionColumns, alignment: .leading, spacing: 6) {
            ForEach(recommendationChips) { chip in
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
        let title = trimmedCommandTitle
        guard canAddCommand else {
            return
        }
        _ = viewModel.submitTodayCommand(title)
        commandTitle = ""
    }

    private var trimmedCommandTitle: String {
        commandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddCommand: Bool {
        // Quick chips intentionally prefill incomplete drafts; require the user
        // to add concrete content after the prefix before creating an Inbox item.
        !trimmedCommandTitle.isEmpty && !trimmedCommandTitle.hasSuffix(":")
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

private struct TodayAssistantRail: View {
    @Binding var commandTitle: String
    let context: TodayAssistantRailContext
    @ObservedObject var viewModel: ProjectBoardViewModel
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
            detailRow(title: "Due", value: task.todayDueDisplayLabel() ?? String(localized: "No due date"), systemImage: "calendar")
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
            Button {
                viewModel.startFocus(taskID: task.id)
            } label: {
                Label("Focus", systemImage: "play.circle")
            }
            .accessibilityIdentifier("today-rail-focus")
            .accessibilityHint("Starts local focus without changing task status.")

            Button {
                _ = viewModel.prepareTodayScheduleDraft(prioritizing: task.id)
            } label: {
                Label("Schedule Block", systemImage: "calendar.badge.clock")
            }
            .accessibilityIdentifier("today-rail-schedule-block")
            .accessibilityHint("Creates a local schedule draft without writing Calendar.")

            if let draft = viewModel.todayScheduleDraft {
                Text(String(format: String(localized: "%d blocks ready"), draft.timeBlocks.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("today-rail-schedule-draft-status")
            }

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
