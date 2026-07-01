import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

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
    var selectTodayTask: (ProjectBoardTask) -> Void = { _ in }
    var openInspectorForTodayRailTask: (Int64) -> Void = { _ in }
    var playDailyPlanningReadout: () -> Void = {}
    @State private var commandTitle = ""

    private var plan: TodayWorkflowPlan {
        viewModel.todayPlan()
    }

    private var assistantContext: TodayAssistantRailContext {
        viewModel.todayAssistantRailContext()
    }

    private var subtitle: String {
        if viewModel.showsCompletedWorkflowTasks {
            return String(format: String(localized: "%d due or completed tasks"), plan.tasks.count)
        }
        return String(format: String(localized: "%d open due or overdue tasks"), plan.tasks.count)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                mainSurface
                TodayAssistantRail(
                    commandTitle: $commandTitle,
                    context: assistantContext,
                    viewModel: viewModel,
                    openInspector: openInspectorForTodayRailTask
                )
                .frame(minWidth: 300, idealWidth: 320, maxWidth: 340)
                .padding(.vertical, 18)
                .padding(.trailing, 18)
            }

            VStack(alignment: .leading, spacing: 0) {
                mainSurface
                TodayAssistantRail(
                    commandTitle: $commandTitle,
                    context: assistantContext,
                    viewModel: viewModel,
                    openInspector: openInspectorForTodayRailTask
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-workflow")
    }

    private var mainSurface: some View {
        WorkflowTaskSurface(
            title: "Today",
            subtitle: subtitle,
            systemImage: "sun.max",
            tasks: plan.tasks,
            emptyTitle: "No tasks due today",
            emptyDescription: "Captured work remains in Inbox until it is scheduled or moved to a project.",
            viewModel: viewModel,
            onSelectTask: selectTodayTask,
            headerAccessory: {
                TodayCommandPanel(
                    commandTitle: $commandTitle,
                    plan: plan,
                    viewModel: viewModel,
                    playDailyPlanningReadout: playDailyPlanningReadout
                )
            },
            footer: {
                TodaySuggestionPanel(plan: plan, viewModel: viewModel)
            }
        )
    }
}

struct CatchUpWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var summary: MissedTaskReviewSummary {
        viewModel.missedTaskReview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                WorkflowHeader(
                    title: "Catch Up",
                    subtitle: String(format: String(localized: "%d missed tasks need review"), summary.newlyMissedCount),
                    systemImage: "clock.badge.exclamationmark"
                )
                Spacer(minLength: 12)
                CatchUpCountStrip(summary: summary)
            }

            CatchUpMissedTaskReviewPanel(summary: summary, viewModel: viewModel)

            if let stateErrorMessage = summary.stateErrorMessage {
                Label(stateErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("catch-up-state-error")
            }

            if let feedback = viewModel.todayCommandFeedback {
                Label(feedback, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("catch-up-feedback")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-workflow")
        .accessibilityLabel("Catch Up")
        .accessibilityHint("Reviews overdue, blocked, stale, and unscheduled local tasks.")
    }
}

struct ScheduleWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var workloadReferenceDate = Date()
    @State private var selectedWorkloadDayKey: String?

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

                DailyWorkloadPanel(
                    overview: viewModel.dailyWorkloadOverview(around: workloadReferenceDate),
                    selectedDayKey: $selectedWorkloadDayKey,
                    previousWeek: moveWorkloadToPreviousWeek,
                    nextWeek: moveWorkloadToNextWeek
                )

                ScheduleStatusBanner(result: viewModel.scheduleApplyResult)

                HStack(alignment: .top, spacing: 12) {
                    ScheduleDraftPanel(viewModel: viewModel)
                    ScheduleUnscheduledPanel(tasks: viewModel.unscheduledScheduleTasks())
                }

                HStack(spacing: 8) {
                    Button {
                        _ = viewModel.enqueueScheduleDraftCalendarApply()
                    } label: {
                        Label("Queue Calendar Apply", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(viewModel.scheduleDraft == nil)
                    .accessibilityIdentifier("schedule-apply-calendar")
                    .accessibilityHint("Adds reviewed schedule blocks to Assistant Queue before any external Calendar write.")
                    Text("External Calendar writes run from Assistant Queue after approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("schedule-queue-approval-note")
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

    private func moveWorkloadToPreviousWeek() {
        workloadReferenceDate = Calendar.current.date(byAdding: .day, value: -7, to: workloadReferenceDate) ?? workloadReferenceDate
        selectedWorkloadDayKey = nil
    }

    private func moveWorkloadToNextWeek() {
        workloadReferenceDate = Calendar.current.date(byAdding: .day, value: 7, to: workloadReferenceDate) ?? workloadReferenceDate
        selectedWorkloadDayKey = nil
    }
}

private struct DailyWorkloadPanel: View {
    let overview: DailyWorkloadOverview
    @Binding var selectedDayKey: String?
    let previousWeek: () -> Void
    let nextWeek: () -> Void

    private var selectedDay: DailyWorkloadDay? {
        overview.days.first { $0.dateKey == selectedDayKey }
            ?? overview.days.first { $0.totalTaskCount > 0 }
            ?? overview.days.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("Daily Workload", systemImage: "calendar.day.timeline.left")
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: previousWeek) {
                    Label("Previous Week", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .help("Previous Week")
                .accessibilityIdentifier("schedule-workload-previous-week")
                .accessibilityLabel("Previous Week")

                Button(action: nextWeek) {
                    Label("Next Week", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
                .help("Next Week")
                .accessibilityIdentifier("schedule-workload-next-week")
                .accessibilityLabel("Next Week")
            }

            Text("Local task counts and progress. External Calendar writes require review approval.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(overview.days) { day in
                    Button {
                        selectedDayKey = day.dateKey
                    } label: {
                        DailyWorkloadDayCell(day: day, isSelected: day.dateKey == selectedDay?.dateKey)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("schedule-workload-day-cell-\(day.dateKey)")
                    .accessibilityLabel(String(format: String(localized: "Workload for %@"), day.dateKey))
                    .accessibilityValue(String(format: String(localized: "%d tasks, %d percent complete"), day.totalTaskCount, Int((day.progress * 100).rounded())))
                }
            }

            if let selectedDay {
                DailyWorkloadDayDetail(day: selectedDay)
            }

            HStack(alignment: .top, spacing: 12) {
                DailyWorkloadUnscheduledBucket(
                    title: "Unscheduled",
                    count: overview.unscheduledTasks.count,
                    tasks: overview.unscheduledTasks,
                    systemImage: "tray.full"
                )
                DailyWorkloadInboxBucket(count: overview.inboxUntriagedCount)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-workload-dashboard")
        .accessibilityLabel("Daily Workload")
        .accessibilityHint("Shows local per-day task counts, progress, unscheduled tasks, and Inbox triage without writing Calendar.")
    }
}

private struct DailyWorkloadDayCell: View {
    let day: DailyWorkloadDay
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(shortDateLabel)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                if day.overdueTaskCount > 0 {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
            }

            ProgressView(value: day.progress)
                .accessibilityIdentifier("schedule-workload-progress-\(day.dateKey)")
                .accessibilityLabel("Daily progress")
                .accessibilityValue("\(Int((day.progress * 100).rounded()))%")

            HStack(spacing: 6) {
                metric("Total", value: day.totalTaskCount)
                    .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-total")
                metric("Open", value: day.openTaskCount)
                    .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-open")
                metric("Done", value: day.doneTaskCount)
                    .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-done")
            }
            HStack(spacing: 6) {
                metric("Blocked", value: day.blockedTaskCount)
                metric("Missed", value: day.overdueTaskCount)
            }
        }
        .padding(10)
        .frame(minHeight: 118, maxHeight: 132, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.14))
        }
    }

    private var shortDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E d"
        return formatter.string(from: day.date)
    }

    private func metric(_ title: LocalizedStringKey, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 34, alignment: .leading)
    }
}

private struct DailyWorkloadDayDetail: View {
    let day: DailyWorkloadDay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Selected Day", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))

            if day.projectContributions.isEmpty {
                Text("No scheduled tasks for this day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(day.projectContributions) { contribution in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(contribution.projectTitle)
                                .font(.caption.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(String(format: String(localized: "%d open / %d done"), contribution.openTaskCount, contribution.doneTaskCount))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(contribution.tasks) { task in
                            HStack(spacing: 8) {
                                Image(systemName: task.status.systemImage)
                                    .foregroundStyle(task.status.tint)
                                    .frame(width: 18)
                                    .accessibilityHidden(true)
                                Text(task.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(LocalizedStringKey(task.status.title))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("schedule-workload-detail-task-\(task.id)")
                            .accessibilityLabel(String(format: String(localized: "%@ task %@"), task.status.title, task.title))
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-workload-day-detail")
        .accessibilityLabel("Selected workload day detail")
    }
}

private struct DailyWorkloadUnscheduledBucket: View {
    let title: LocalizedStringKey
    let count: Int
    let tasks: [ProjectBoardTask]
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(String(format: String(localized: "%d tasks"), count))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(tasks.prefix(4)) { task in
                Text(task.title)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-workload-unscheduled-bucket")
        .accessibilityLabel("Unscheduled tasks")
        .accessibilityValue("\(count)")
    }
}

private struct DailyWorkloadInboxBucket: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Inbox Triage", systemImage: "tray")
                .font(.subheadline.weight(.semibold))
            Text(String(format: String(localized: "%d captures waiting"), count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Inbox captures are shown separately until moved into a project.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-workload-inbox-bucket")
        .accessibilityLabel("Inbox triage captures")
        .accessibilityValue("\(count)")
    }
}

private struct CatchUpMissedTaskReviewPanel: View {
    let summary: MissedTaskReviewSummary
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Missed Review", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(String(format: String(localized: "%d new"), summary.newlyMissedCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if summary.immediateQueue.isEmpty {
                ContentUnavailableView(
                    "No missed work",
                    systemImage: "checkmark.circle",
                    description: Text("Overdue, blocked, stale, and unscheduled tasks will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.immediateQueue) { item in
                            CatchUpMissedTaskRow(item: item, viewModel: viewModel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-missed-review-panel")
        .accessibilityLabel("Missed task review")
        .accessibilityHint("Shows newly missed local tasks and recovery actions.")
    }
}

private struct CatchUpCountStrip: View {
    let summary: MissedTaskReviewSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                badgeRow
            }
            VStack(alignment: .leading, spacing: 8) {
                badgeRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-count-strip")
        .accessibilityLabel("Catch Up counts")
    }

    private var badgeRow: some View {
        Group {
            CatchUpCountBadge(label: "Missed", value: summary.newlyMissedCount, tint: .red)
            CatchUpCountBadge(label: "Due Today", value: summary.dueTodayCount, tint: .green)
            CatchUpCountBadge(label: "Overdue", value: summary.overdueCount, tint: .orange)
            CatchUpCountBadge(label: "Blocked", value: summary.blockedCount, tint: .purple)
            CatchUpCountBadge(label: "Unscheduled", value: summary.unscheduledCount, tint: .blue)
            CatchUpCountBadge(label: "Stale", value: summary.staleCount, tint: .gray)
        }
    }
}

private struct CatchUpCountBadge: View {
    let label: String
    let value: Int
    let tint: Color

    private var identifierSuffix: String {
        label.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private var localizedLabel: String {
        switch label {
        case "Missed":
            String(localized: "Missed")
        case "Due Today":
            String(localized: "Due Today")
        case "Overdue":
            String(localized: "Overdue")
        case "Blocked":
            String(localized: "Blocked")
        case "Unscheduled":
            String(localized: "Unscheduled")
        case "Stale":
            String(localized: "Stale")
        default:
            label
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 72, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("catch-up-missed-count-badge-\(identifierSuffix)")
        .accessibilityLabel(String(format: String(localized: "%@ tasks"), localizedLabel))
        .accessibilityValue("\(value)")
    }
}

private struct CatchUpMissedTaskRow: View {
    let item: MissedTaskReviewItem
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.task.status.systemImage)
                    .foregroundStyle(item.task.status.tint)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.task.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.task.title)
                    HStack(spacing: 8) {
                        Label(item.projectTitle, systemImage: "folder")
                        Label(LocalizedStringKey(item.task.priority.label), systemImage: "flag")
                        if let dueAt = item.task.dueAt {
                            Label(dueAt, systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                CatchUpReasonPills(reasons: item.reasons)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.completeMissedTask(id: item.task.id)
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
                .controlSize(.small)
                .accessibilityIdentifier("catch-up-missed-complete-\(item.task.id)")
                .accessibilityHint("Completes this local task and removes it from the missed queue.")

                Button {
                    viewModel.rescheduleMissedTaskForToday(id: item.task.id)
                } label: {
                    Label("Today", systemImage: "calendar.badge.clock")
                }
                .controlSize(.small)
                .accessibilityIdentifier("catch-up-missed-reschedule-\(item.task.id)")
                .accessibilityHint("Reschedules this local task for today without writing external Calendar.")

                Button {
                    viewModel.deferMissedTaskForLater(id: item.task.id)
                } label: {
                    Label("Later", systemImage: "clock")
                }
                .controlSize(.small)
                .accessibilityIdentifier("catch-up-missed-defer-\(item.task.id)")
                .accessibilityHint("Marks this local task reviewed for today without changing its task fields.")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-missed-review-row-\(item.task.id)")
    }
}

private struct CatchUpReasonPills: View {
    let reasons: [MissedTaskReviewReason]

    private var localizedReasonTitles: [String] {
        reasons.map { reason in
            switch reason {
            case .overdue:
                String(localized: "Overdue")
            case .dueToday:
                String(localized: "Due Today")
            case .blocked:
                String(localized: "Blocked")
            case .unscheduled:
                String(localized: "Unscheduled")
            case .stale:
                String(localized: "Stale")
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reasons, id: \.rawValue) { reason in
                Text(LocalizedStringKey(reason.title))
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reasons")
        .accessibilityValue(localizedReasonTitles.joined(separator: ", "))
    }
}

struct DoneWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var isExportingExecutionReceipts = false
    @State private var executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: Data())

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

                VStack(alignment: .leading, spacing: 10) {
                    Label("Recent AI Receipts", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    HStack(spacing: 8) {
                        TextField(
                            "Search receipts",
                            text: Binding(
                                get: { viewModel.executionReceiptHistorySearchText },
                                set: { viewModel.setExecutionReceiptHistorySearchText($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("execution-receipt-search-field")

                        Menu {
                            Button("All Statuses") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(nil)
                            }
                            Divider()
                            Button("Succeeded") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.succeeded)
                            }
                            Button("Failed") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.failed)
                            }
                            Button("Canceled") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.canceled)
                            }
                            Button("Running") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.running)
                            }
                        } label: {
                            Label(receiptStatusFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityIdentifier("execution-receipt-status-filter")

                        Menu {
                            Button("All References") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(nil)
                            }
                            Divider()
                            Button("Task") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.task)
                            }
                            Button("Project") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.project)
                            }
                            Button("Document") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.document)
                            }
                            Button("Reminder") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.reminder)
                            }
                            Button("Calendar Event") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.calendarEvent)
                            }
                            Button("Development Branch") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.developmentBranch)
                            }
                            Button("Pull Request") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.pullRequest)
                            }
                        } label: {
                            Label(receiptReferenceFilterLabel, systemImage: "tag")
                        }
                        .accessibilityIdentifier("execution-receipt-reference-filter")

                        Button {
                            viewModel.prepareExecutionReceiptHistoryExport()
                            guard let data = viewModel.executionReceiptHistoryExportData else {
                                return
                            }
                            executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: data)
                            isExportingExecutionReceipts = true
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.executionReceiptHistorySnapshot.rows.isEmpty)
                        .accessibilityIdentifier("execution-receipt-export-button")
                    }
                    .font(.caption)

                    if let exportMessage = viewModel.executionReceiptHistoryExportMessage {
                        Label(exportMessage, systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("execution-receipt-export-message")
                    }
                    if let unavailableMessage = viewModel.executionReceiptHistorySnapshot.unavailableMessage {
                        ContentUnavailableView(
                            "Execution receipts are unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(unavailableMessage)
                        )
                    } else if viewModel.executionReceiptHistorySnapshot.rows.isEmpty {
                        ContentUnavailableView(
                            "No AI receipts yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Receipts appear here after approved AI work runs.")
                        )
                    } else {
                        ForEach(viewModel.executionReceiptHistorySnapshot.rows) { row in
                            ExecutionReceiptHistoryRowView(row: row)
                        }
                    }
                }
                .accessibilityIdentifier("recent-ai-receipts")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("done-workflow")
        .fileExporter(
            isPresented: $isExportingExecutionReceipts,
            document: executionReceiptExportDocument,
            contentType: .json,
            defaultFilename: executionReceiptDefaultExportFilename
        ) { result in
            switch result {
            case .success:
                viewModel.recordExecutionReceiptHistoryExportCompleted()
                executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: Data())
            case .failure(let error):
                viewModel.recordExecutionReceiptHistoryFileFailure(error)
            }
        }
    }

    private var receiptStatusFilterLabel: LocalizedStringKey {
        guard let status = viewModel.executionReceiptHistoryStatusFilter else {
            return "All Statuses"
        }
        switch status {
        case .notStarted:
            return "Not Started"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        case .canceled:
            return "Canceled"
        }
    }

    private var receiptReferenceFilterLabel: LocalizedStringKey {
        guard let referenceKind = viewModel.executionReceiptHistoryReferenceKindFilter else {
            return "All References"
        }
        switch referenceKind {
        case .unknown:
            return "Unknown"
        case .assistantQueue:
            return "Assistant Queue"
        case .actionPlan:
            return "Action Plan"
        case .reviewSession:
            return "Review Session"
        case .task:
            return "Task"
        case .project:
            return "Project"
        case .document:
            return "Document"
        case .calendarEvent:
            return "Calendar Event"
        case .notification:
            return "Notification"
        case .reminder:
            return "Reminder"
        case .developmentBranch:
            return "Development Branch"
        case .developmentCommit:
            return "Development Commit"
        case .file:
            return "File"
        case .pullRequest:
            return "Pull Request"
        case .externalMCP:
            return "External MCP"
        }
    }

    private var executionReceiptDefaultExportFilename: String {
        "solopm-receipts-\(Self.exportDateFormatter.string(from: Date())).json"
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct ExecutionReceiptHistoryFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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

struct ExecutionReceiptHistoryRowView: View {
    let row: ExecutionReceiptHistoryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(row.statusLabel, systemImage: statusSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(row.toolLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.occurredAtLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(row.outcomeSummary)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(row.usageLabel)
                Text(row.referenceSummary)
                Text(row.sourceSummary)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)

            Text(row.receiptIDLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("execution-receipt-row-\(row.id)")
        .accessibilityLabel("Execution receipt")
        .accessibilityValue(row.accessibilityValue)
        .accessibilityHint("Shows the redacted outcome, usage state, references, sources, and receipt identifier for approved AI work.")
    }

    private var statusSystemImage: String {
        switch row.status {
        case .notStarted:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .skipped:
            return "forward.end.circle"
        case .canceled:
            return "stop.circle"
        }
    }

    private var statusTint: Color {
        switch row.status {
        case .notStarted, .skipped, .canceled:
            return .secondary
        case .running:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
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

private struct TodayDailyPlanningReviewPanel: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    let playDailyPlanningReadout: () -> Void

    private var review: DailyPlanningReview {
        viewModel.dailyPlanningReview
            ?? viewModel.makeDailyPlanningReview(transcript: String(localized: "Today daily planning review"))
    }

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

            HStack(spacing: 8) {
                Button {
                    playDailyPlanningReadout()
                } label: {
                    Label("Read Aloud", systemImage: "speaker.wave.2")
                }
                .controlSize(.small)
                .help("Reads this daily planning review with the configured local TTS provider.")
                .accessibilityIdentifier("today-daily-planning-readout")
                .accessibilityHint("Uses local TTS to read the review without changing tasks or writing Calendar.")

                Button {
                    viewModel.enqueueDailyPlanningActionDraft(kind: .startRecommended)
                } label: {
                    Label("Draft Start", systemImage: "play.circle")
                }
                .controlSize(.small)
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
                .disabled(review.recommendedTaskID == nil)
                .help("Queue a tomorrow due-date update for review.")
                .accessibilityIdentifier("today-daily-planning-draft-defer")
                .accessibilityHint("Creates an Assistant Queue approval item without writing Calendar.")
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
    @ObservedObject var viewModel: ProjectBoardViewModel
    let playDailyPlanningReadout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayDailyPlanningReviewPanel(
                viewModel: viewModel,
                playDailyPlanningReadout: playDailyPlanningReadout
            )
            TodayBriefingPanel(commandTitle: $commandTitle, plan: plan, viewModel: viewModel)
        }
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
        .frame(minWidth: 320, maxWidth: 540, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-briefing-panel")
        .accessibilityLabel("Today briefing")
        .accessibilityHint("Captures work into Inbox and offers the next reviewed Today action.")
    }

    private var commonActionRail: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                commonActionButtons
            }

            VStack(alignment: .leading, spacing: 6) {
                commonActionButtons
            }
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
    let onSelectTask: ((ProjectBoardTask) -> Void)?
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
        onSelectTask: ((ProjectBoardTask) -> Void)? = nil,
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
        self.onSelectTask = onSelectTask
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
                                onSelect: { selectTask(task) },
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

    private func selectTask(_ task: ProjectBoardTask) {
        if let onSelectTask {
            onSelectTask(task)
            return
        }
        viewModel.selectedTaskID = task.id
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
                            if let dueLabel = task.todayDueDisplayLabel() {
                                Label(
                                    dueLabel,
                                    systemImage: isOverdue ? "calendar.badge.exclamationmark" : "calendar"
                                )
                                .foregroundStyle(isOverdue ? .red : .secondary)
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
        if let dueLabel = task.todayDueDisplayLabel() {
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

    private var isOverdue: Bool {
        task.isOverdueForToday()
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
        .accessibilityHint("Shows the selected or recommended Today task details and local next actions.")
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
            detailRow(title: "Subtasks", value: context.subtaskSummary, systemImage: "checklist")
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
