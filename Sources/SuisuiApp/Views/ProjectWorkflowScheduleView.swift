import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

private enum ScheduleSurfaceMode: String, CaseIterable, Identifiable {
    case overview
    case timeline
    case workload

    var id: String { rawValue }

    static func visualEvidenceInitialMode(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ScheduleSurfaceMode {
        // Visual evidence launches one mode per isolated process so a hosted
        // screenshot does not depend on timing an intermediate interaction.
        // Requiring the fixed-instant evidence context prevents this override
        // from changing a normal product launch.
        guard environment["SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT"] != nil,
              let rawValue = environment["SUISUI_VISUAL_EVIDENCE_SCHEDULE_MODE"],
              let mode = ScheduleSurfaceMode(rawValue: rawValue) else {
            return .overview
        }
        return mode
    }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .timeline: "Timeline"
        case .workload: "Workload"
        }
    }
}

struct ScheduleWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var workloadReferenceDate = VisualEvidenceRuntimeContext.referenceDate()
    @State private var selectedWorkloadDayKey: String?
    @State private var selectedMode = ScheduleSurfaceMode.visualEvidenceInitialMode()

    var body: some View {
        let scheduleReadModel = viewModel.derivedReadModels.schedule
        let workloadOverview = scheduleReadModel.workloadOverview
        let workloadReferenceDayKey = scheduleDateKey(for: workloadReferenceDate)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        scheduleTitle
                        Spacer(minLength: 12)
                        modePicker
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        scheduleTitle
                        modePicker
                    }
                }

                scheduleWorkflowArea

                // One root-owned week/day navigator keeps every mode on the
                // same temporal context. Mode-specific panels never maintain
                // their own week cursor, which prevents silent draft drift.
                ScheduleMiniCalendarPanel(
                    overview: workloadOverview,
                    selectedDayKey: $selectedWorkloadDayKey,
                    referenceDayKey: workloadReferenceDayKey,
                    previousWeek: moveWorkloadToPreviousWeek,
                    nextWeek: moveWorkloadToNextWeek,
                    jumpToToday: moveWorkloadToToday,
                    selectDay: selectMiniCalendarDay
                )

                Group {
                    switch selectedMode {
                    case .overview:
                        VStack(alignment: .leading, spacing: 12) {
                            WeeklyScheduleAgendaPanel(day: scheduleReadModel.weeklyCockpit.agendaDay)
                            ScheduleStatusBanner(result: viewModel.scheduleApplyResult)
                            HStack(alignment: .top, spacing: 12) {
                                ScheduleDraftPanel(viewModel: viewModel)
                                ScheduleUnscheduledPanel(
                                    tasks: scheduleReadModel.unscheduledTasks,
                                    viewModel: viewModel,
                                    referenceDate: workloadReferenceDate
                                )
                            }
                        }
                    case .timeline:
                        WeeklyScheduleTimelinePanel(cockpit: scheduleReadModel.weeklyCockpit)
                    case .workload:
                        VStack(alignment: .leading, spacing: 12) {
                            DailyWorkloadPanel(
                                overview: workloadOverview,
                                selectedDayKey: $selectedWorkloadDayKey,
                                referenceDayKey: workloadReferenceDayKey,
                                selectDay: selectMiniCalendarDay
                            )
                            WeeklyScheduleReminderPanel(
                                cockpit: scheduleReadModel.weeklyCockpit,
                                queueReminderDraft: { task, day in
                                    viewModel.enqueueScheduleReminderDraft(
                                        for: task.id,
                                        sourceTranscript: "Schedule smart reminder draft",
                                        on: day.date
                                    )
                                }
                            )
                        }
                    }
                }
                .accessibilityIdentifier("schedule-mode-\(selectedMode.rawValue)")

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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-workflow")
        .accessibilityLabel("Schedule")
        .accessibilityHint("Reviews workload and approval-ready schedule drafts from Review.")
    }

    private var scheduleTitle: some View {
        Label("Schedule", systemImage: "calendar")
            .font(.title2.weight(.semibold))
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(ScheduleSurfaceMode.allCases) { mode in
                Button { selectedMode = mode } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(selectedMode == mode ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .background(
                        selectedMode == mode ? SuisuiSurface.elevatedSelection : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: SuisuiRadius.control - 2)
                    )
                    .accessibilityIdentifier("schedule-mode-option-\(mode.rawValue)")
                    .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.control)
                .stroke(SuisuiBorder.subtle, lineWidth: 1)
        }
        .frame(maxWidth: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule View")
        .accessibilityIdentifier("schedule-mode-picker")
        .accessibilityHint("Switches the visible schedule detail while preserving the selected week and day.")
    }

    private var scheduleWorkflowArea: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                generateDraftButton
                ScheduleDraftApprovalControls(
                    hasDraft: viewModel.scheduleDraft != nil,
                    queueCalendarApply: queueCalendarApply
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                generateDraftButton
                ScheduleDraftApprovalControls(
                    hasDraft: viewModel.scheduleDraft != nil,
                    queueCalendarApply: queueCalendarApply
                )
            }
        }
        .padding(10)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityIdentifier("schedule-workflow-area")
    }

    private var generateDraftButton: some View {
        Button {
            // Use the root-owned date so every mode drafts the week the user sees.
            _ = viewModel.prepareScheduleDraft(on: workloadReferenceDate)
        } label: {
            Label("Generate Draft", systemImage: "wand.and.stars")
        }
        .accessibilityIdentifier("schedule-generate-draft")
        .accessibilityHint("Combines the visible day's local time blocks and unscheduled tasks without writing to Calendar.")
    }

    private func queueCalendarApply() {
        _ = viewModel.enqueueScheduleDraftCalendarApply(on: workloadReferenceDate)
    }

    private func moveWorkloadToPreviousWeek() {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let nextDate = calendar.date(byAdding: .day, value: -7, to: workloadReferenceDate) ?? workloadReferenceDate
        workloadReferenceDate = nextDate
        selectedWorkloadDayKey = nil
        viewModel.refreshScheduleReadModel(around: nextDate)
    }

    private func moveWorkloadToNextWeek() {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let nextDate = calendar.date(byAdding: .day, value: 7, to: workloadReferenceDate) ?? workloadReferenceDate
        workloadReferenceDate = nextDate
        selectedWorkloadDayKey = nil
        viewModel.refreshScheduleReadModel(around: nextDate)
    }

    private func moveWorkloadToToday() {
        let nextDate = VisualEvidenceRuntimeContext.referenceDate()
        workloadReferenceDate = nextDate
        selectedWorkloadDayKey = nil
        viewModel.refreshScheduleReadModel(around: nextDate)
    }

    private func selectMiniCalendarDay(_ day: DailyWorkloadDay) {
        workloadReferenceDate = day.date
        selectedWorkloadDayKey = day.dateKey
        viewModel.refreshScheduleReadModel(around: day.date)
    }

    private func scheduleDateKey(for date: Date) -> String {
        SuisuiTimestampDisplay.dayKey(
            date,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
        )
    }
}

private struct ScheduleMiniCalendarPanel: View {
    let overview: DailyWorkloadOverview
    @Binding var selectedDayKey: String?
    let referenceDayKey: String
    let previousWeek: () -> Void
    let nextWeek: () -> Void
    let jumpToToday: () -> Void
    let selectDay: (DailyWorkloadDay) -> Void

    private var selectedDay: DailyWorkloadDay? {
        overview.days.first { $0.dateKey == selectedDayKey }
            ?? overview.days.first { $0.dateKey == referenceDayKey }
            ?? overview.days.first { $0.totalTaskCount > 0 }
            ?? overview.days.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Label("Mini Calendar", systemImage: "calendar")
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: previousWeek) {
                    Label("Previous Week", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .help("Previous Week")
                .accessibilityIdentifier("schedule-mini-calendar-previous-week")
                .accessibilityLabel("Previous Week")

                Button(action: jumpToToday) {
                    Label("Today", systemImage: "calendar.badge.clock")
                }
                .help("Jump to Today")
                .accessibilityIdentifier("schedule-mini-calendar-today")
                .accessibilityHint("Selects the current day in the Schedule mini calendar.")

                Button(action: nextWeek) {
                    Label("Next Week", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
                .help("Next Week")
                .accessibilityIdentifier("schedule-mini-calendar-next-week")
                .accessibilityLabel("Next Week")
            }

            if let selectedDay {
                Label(selectedSummary(for: selectedDay), systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("schedule-mini-calendar-selected-day")
            }

            // Seven flexible chips share the row instead of scrolling
            // horizontally, so the trailing day is never cut at the panel
            // edge at the canonical 1024pt viewport (~744pt of panel width).
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .top)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(overview.days) { day in
                    Button {
                        selectDay(day)
                    } label: {
                        ScheduleMiniCalendarDayChip(day: day, isSelected: day.dateKey == selectedDay?.dateKey)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("schedule-mini-calendar-day-\(day.dateKey)")
                    .accessibilityLabel(String(format: String(localized: "Workload for %@"), day.dateKey))
                    .accessibilityValue(dayAccessibilityValue(day, isSelected: day.dateKey == selectedDay?.dateKey))
                    .accessibilityHint("Selects this day as the Schedule agenda without writing Calendar.")
                    .accessibilityAddTraits(day.dateKey == selectedDay?.dateKey ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-mini-calendar")
        .accessibilityLabel("Mini Calendar")
        .accessibilityHint("Selects the Schedule agenda day without writing Calendar.")
    }

    private func selectedSummary(for day: DailyWorkloadDay) -> String {
        // `dateKey` is the machine grouping key (`2026-07-10`); the header is
        // read by a person, so it gets the locale-formatted day and singular
        // noun forms instead of "Selected 2026-07-10 with 1 open tasks".
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let openCount = day.openTaskCount
        let attentionCount = day.overdueTaskCount + day.blockedTaskCount
        return localizedDisplay(
            "Selected %@ with %@ and %@.",
            SuisuiTimestampDisplay.absolute(
                day.date,
                calendar: calendar,
                locale: localizedDisplayLocale()
            ),
            localizedCount(openCount, one: "%d open task", other: "%d open tasks"),
            localizedCount(
                attentionCount,
                one: "%d attention signal",
                other: "%d attention signals"
            )
        )
    }

    private func dayAccessibilityValue(_ day: DailyWorkloadDay, isSelected: Bool) -> String {
        let summary = String(
            format: String(localized: "%d tasks, %d open, %d done, %d blocked, %d missed"),
            day.totalTaskCount,
            day.openTaskCount,
            day.doneTaskCount,
            day.blockedTaskCount,
            day.overdueTaskCount
        )
        if isSelected {
            return String(format: String(localized: "Selected, %@"), summary)
        }
        return String(format: String(localized: "Not selected, %@"), summary)
    }
}

private struct ScheduleMiniCalendarDayChip: View {
    let day: DailyWorkloadDay
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(shortDateLabel)
                    .font(.caption.weight(.semibold))
                if day.overdueTaskCount > 0 {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(SuisuiTone.danger.color)
                        .accessibilityHidden(true)
                }
            }

            Text(day.loadLabel)
                .font(.caption2)
                .foregroundStyle(loadTint)

            // Only non-zero counts earn a line; an open day shows just its
            // load label instead of "0 open 0 done" noise.
            if day.openTaskCount > 0 || day.doneTaskCount > 0 {
                HStack(spacing: 6) {
                    if day.openTaskCount > 0 {
                        miniMetric(String(format: String(localized: "%d open"), day.openTaskCount))
                    }
                    if day.doneTaskCount > 0 {
                        miniMetric(String(format: String(localized: "%d done"), day.doneTaskCount))
                    }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(background, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(isSelected ? SuisuiBrand.soloBlue.opacity(0.6) : loadTint.opacity(0.2))
        }
    }

    private var shortDateLabel: String {
        // `"E d"` is a fixed English pattern; the shared helper resolves the
        // locale-correct weekday/day order instead and reuses one cached
        // formatter rather than allocating one per row per redraw.
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        return SuisuiTimestampDisplay.weekdayAndDay(
            day.date,
            calendar: calendar,
            locale: localizedDisplayLocale()
        )
    }

    private var loadTint: Color {
        if day.overdueTaskCount > 0 || day.blockedTaskCount > 0 {
            return SuisuiTone.danger.color
        }
        if day.openTaskCount > 2 {
            return SuisuiBrand.soloBlue
        }
        return .secondary
    }

    private var background: Color {
        if isSelected {
            return SuisuiBrand.soloBlue.opacity(0.12)
        }
        if day.overdueTaskCount > 0 || day.blockedTaskCount > 0 {
            return SuisuiTone.danger.color.opacity(0.08)
        }
        if day.totalTaskCount > 0 {
            return SuisuiBrand.soloBlue.opacity(0.06)
        }
        return Color.secondary.opacity(0.05)
    }

    private func miniMetric(_ label: String) -> some View {
        Text(label)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private extension DailyWorkloadDay {
    var loadLabel: String {
        if overdueTaskCount > 0 {
            return String(localized: "Missed work")
        }
        if blockedTaskCount > 0 {
            return String(localized: "Blocked work")
        }
        if openTaskCount > 2 {
            return String(localized: "Focused day")
        }
        if totalTaskCount > 0 {
            return String(localized: "Light day")
        }
        return String(localized: "Open day")
    }
}

private struct WeeklyScheduleTimelinePanel: View {
    let cockpit: WeeklyScheduleCockpit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Label("Weekly workload", systemImage: "calendar")
                    .font(.headline)
                Spacer(minLength: 8)
                Label(focusForecastSummary, systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("schedule-focus-forecast")
            }

            // The seven day columns share the panel width instead of scrolling
            // horizontally: at the canonical 1024pt viewport the panel offers
            // ~744pt, so adaptive 96pt-minimum columns render one row of seven
            // (~99pt each) with no card cut at the trailing edge. Narrower
            // windows wrap to a second row rather than clipping mid-card.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .top)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(cockpit.days) { day in
                    WeeklyScheduleDayColumn(day: day)
                }
            }
            .padding(.vertical, 1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("schedule-week-grid")
            .accessibilityLabel("Weekly schedule grid")
            .accessibilityHint("Shows local schedule draft and due-task blocks. It does not write Calendar events.")

            WeeklyScheduleTimeAxisGrid(cockpit: cockpit)

        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-week-cockpit")
        .accessibilityLabel("Weekly workload")
    }

    private var focusForecastSummary: String {
        let base = switch cockpit.focusForecast.state {
        case .overloaded:
            String(
                format: String(localized: "%d overloaded days. Review reminders and unscheduled work before applying Calendar changes."),
                cockpit.focusForecast.overloadedDayKeys.count
            )
        case .heavy:
            String(
                format: String(localized: "%d heavy days. Keep schedule drafts reviewable before Calendar writes."),
                cockpit.focusForecast.heavyDayKeys.count
            )
        case .open:
            String(localized: "Week has no overloaded days.")
        }
        guard cockpit.focusForecast.completionHistoryCount > 0 else {
            return base
        }
        return base + " " + String(
            format: String(localized: "%d completed this week."),
            cockpit.focusForecast.completionHistoryCount
        )
    }
}

private struct WeeklyScheduleTimeAxisGrid: View {
    let cockpit: WeeklyScheduleCockpit

    private var slotHours: [Int] {
        let hours = cockpit.days
            .flatMap(\.blocks)
            .compactMap(hour(for:))
        guard !hours.isEmpty else {
            return [9, 12, 15, 18]
        }
        return Array(Set(hours)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Time Axis", systemImage: "clock")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("All day")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .topLeading)
                            .frame(minHeight: 34, alignment: .topLeading)
                        ForEach(cockpit.days) { day in
                            WeeklyScheduleTimeAxisSlot(
                                day: day,
                                label: String(localized: "All day"),
                                blocks: allDayBlocks(for: day),
                                emptyLabel: String(localized: "No all-day blocks")
                            )
                            .accessibilityIdentifier("schedule-week-time-axis-all-day-slot-\(day.dateKey)")
                        }
                    }
                    ForEach(slotHours, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 6) {
                            Text(hourLabel(hour))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .topLeading)
                                .frame(minHeight: 34, alignment: .topLeading)
                            ForEach(cockpit.days) { day in
                                WeeklyScheduleTimeAxisSlot(
                                    day: day,
                                    label: hourLabel(hour),
                                    blocks: timedBlocks(for: day, hour: hour),
                                    emptyLabel: String(localized: "No timed blocks")
                                )
                                .accessibilityIdentifier("schedule-week-time-axis-slot-\(day.dateKey)-\(hour)")
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-week-time-axis-grid")
        .accessibilityLabel("Schedule time axis grid")
        .accessibilityHint("Shows the same weekly blocks by hour so empty days and overlapping blocks are easier to scan.")
    }

    private func allDayBlocks(for day: WeeklyScheduleDay) -> [WeeklyScheduleBlock] {
        day.blocks.filter { $0.startAt == nil }
    }

    private func timedBlocks(for day: WeeklyScheduleDay, hour: Int) -> [WeeklyScheduleBlock] {
        day.blocks.filter { block in
            guard block.startAt != nil else {
                return false
            }
            return self.hour(for: block) == hour
        }
    }

    private func hour(for block: WeeklyScheduleBlock) -> Int? {
        block.startHour
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

private struct WeeklyScheduleTimeAxisSlot: View {
    let day: WeeklyScheduleDay
    let label: String
    let blocks: [WeeklyScheduleBlock]
    let emptyLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if blocks.isEmpty {
                Text(emptyLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(0.65)
            } else {
                ForEach(blocks) { block in
                    WeeklyScheduleTimeAxisBlock(block: block)
                }
            }
        }
        .padding(6)
        .frame(width: 132, alignment: .topLeading)
        .frame(minHeight: 34, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time axis slot")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let blockSummary = blocks.isEmpty
            ? emptyLabel
            : blocks.map { block in
                let source = block.source == .scheduleDraft ? String(localized: "Schedule draft") : String(localized: "Due task")
                if block.overlapGroupSize > 1 {
                    return "\(block.timeLabel), \(block.task.title), \(block.projectTitle), \(source), \(String(format: String(localized: "Lane %d of %d"), block.overlapLane + 1, block.overlapGroupSize))"
                }
                return "\(block.timeLabel), \(block.task.title), \(block.projectTitle), \(source)"
            }.joined(separator: ", ")
        return "\(day.dateKey), \(label), \(blockSummary)"
    }
}

private struct WeeklyScheduleTimeAxisBlock: View {
    let block: WeeklyScheduleBlock

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: block.source == .scheduleDraft ? "wand.and.stars" : "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(block.task.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            if block.overlapGroupSize > 1 {
                Text(String(format: String(localized: "Lane %d/%d"), block.overlapLane + 1, block.overlapGroupSize))
                    .font(.caption2)
                    .foregroundStyle(SuisuiTone.neutral.color)
                    .lineLimit(1)
            }
        }
    }
}

private struct WeeklyScheduleDayColumn: View {
    let day: WeeklyScheduleDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(shortDateLabel)
                        .font(.caption.weight(.semibold))
                    Text(LocalizedStringKey(day.loadLevel.title))
                        .font(.caption2)
                        .foregroundStyle(loadTint)
                }
                Spacer(minLength: 4)
                // Capacity signal only when there is load; a zero here would
                // just repeat what the "Open time" placeholder already says.
                if day.workload.openTaskCount > 0 {
                    Text("\(day.workload.openTaskCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Open task count")
                }
            }
            if day.completionHistoryCount > 0 {
                Label(
                    String(format: String(localized: "%d schedule completions"), day.completionHistoryCount),
                    systemImage: "checkmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(SuisuiTone.positive.color)
                .lineLimit(1)
                .accessibilityIdentifier("schedule-week-completion-history-\(day.dateKey)")
                .accessibilityLabel("Completion history count")
                .accessibilityValue(String(
                    format: String(localized: "%d completed tasks on this day"),
                    day.completionHistoryCount
                ))
            }

            if day.blocks.isEmpty {
                Text("Open time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                    .padding(8)
                    .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(day.blocks.prefix(4)) { block in
                        WeeklyScheduleBlockRow(block: block)
                    }
                    if day.blocks.count > 4 {
                        Text(String(format: String(localized: "+%d more"), day.blocks.count - 4))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 78, alignment: .topLeading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(dayBackground, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(loadTint.opacity(0.25))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-week-day-column-\(day.dateKey)")
        .accessibilityLabel(String(format: String(localized: "Schedule day %@"), day.dateKey))
        .accessibilityValue(String(
            format: String(localized: "%d blocks, %d reminder proposals, %d completed tasks"),
            day.blocks.count,
            day.reminderProposalCount,
            day.completionHistoryCount
        ))
    }

    private var shortDateLabel: String {
        // `"E d"` is a fixed English pattern; the shared helper resolves the
        // locale-correct weekday/day order instead and reuses one cached
        // formatter rather than allocating one per row per redraw.
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        return SuisuiTimestampDisplay.weekdayAndDay(
            day.date,
            calendar: calendar,
            locale: localizedDisplayLocale()
        )
    }

    private var loadTint: Color {
        switch day.loadLevel {
        case .open:
            .secondary
        case .focused:
            SuisuiBrand.soloBlue
        case .heavy:
            SuisuiTone.neutral.color
        case .overloaded:
            SuisuiTone.danger.color
        }
    }

    private var dayBackground: Color {
        switch day.loadLevel {
        case .open:
            Color.secondary.opacity(0.04)
        case .focused:
            SuisuiBrand.soloBlue.opacity(0.06)
        case .heavy:
            SuisuiTone.neutral.color.opacity(0.08)
        case .overloaded:
            SuisuiTone.danger.color.opacity(0.08)
        }
    }
}

private struct WeeklyScheduleBlockRow: View {
    let block: WeeklyScheduleBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: block.source == .scheduleDraft ? "wand.and.stars" : "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(block.timeLabel))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if block.overlapGroupSize > 1 {
                    Text(String(format: String(localized: "Lane %d/%d"), block.overlapLane + 1, block.overlapGroupSize))
                        .font(.caption2)
                        .foregroundStyle(SuisuiTone.neutral.color)
                }
            }
            Text(block.task.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(block.projectTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-week-block-\(block.id)")
        .accessibilityLabel(block.task.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        [
            block.timeLabel,
            block.projectTitle,
            block.source == .scheduleDraft ? "Schedule draft" : "Due task",
            String(format: String(localized: "Lane %d of %d"), block.overlapLane + 1, block.overlapGroupSize)
        ].joined(separator: ", ")
    }
}

private struct WeeklyScheduleAgendaPanel: View {
    let day: WeeklyScheduleDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Agenda", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
            if let day, !day.blocks.isEmpty {
                ForEach(day.blocks.prefix(5)) { block in
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(block.timeLabel))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)
                        Text(block.task.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(block.projectTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("No agenda blocks for the selected week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityIdentifier("schedule-agenda")
    }
}

private struct WeeklyScheduleReminderPanel: View {
    let cockpit: WeeklyScheduleCockpit
    let queueReminderDraft: (ProjectBoardTask, WeeklyScheduleDay) -> Void

    private var topDays: [WeeklyScheduleDay] {
        cockpit.days
            .filter { $0.reminderProposalCount > 0 }
            .sorted { lhs, rhs in
                if lhs.reminderProposalCount != rhs.reminderProposalCount {
                    return lhs.reminderProposalCount > rhs.reminderProposalCount
                }
                return lhs.date < rhs.date
            }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Smart Reminders", systemImage: "bell.badge")
                .font(.subheadline.weight(.semibold))
            Text(String(format: String(localized: "%d proposals from local due and blocked tasks"), cockpit.focusForecast.reminderProposalCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(topDays) { day in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(day.dateKey)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "%d reminders"), day.reminderProposalCount))
                            .font(.caption)
                    }
                    ForEach(reminderProposalTasks(for: day), id: \.id) { task in
                        HStack(spacing: 6) {
                            Text(task.title)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Button {
                                queueReminderDraft(task, day)
                            } label: {
                                Label("Queue Reminder Draft", systemImage: "bell.badge")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("Queue Reminder Draft")
                            .accessibilityIdentifier("schedule-smart-reminder-draft-\(task.id)")
                            .accessibilityLabel(String(format: String(localized: "Queue reminder draft for %@"), task.title))
                            .accessibilityHint("Queues a Reminders draft for approval before any external write.")
                        }
                    }
                }
            }
            if !cockpit.unscheduledTasks.isEmpty {
                Label(String(format: String(localized: "%d unscheduled tasks need placement"), cockpit.unscheduledTasks.count), systemImage: "tray.full")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-smart-reminders")
        .accessibilityLabel("Smart reminder proposals")
    }

    private func reminderProposalTasks(for day: WeeklyScheduleDay) -> [ProjectBoardTask] {
        day.workload.projectContributions
            .flatMap(\.tasks)
            .filter { $0.status != .done }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return priorityRank(lhs.priority) < priorityRank(rhs.priority)
                }
                return lhs.id < rhs.id
            }
    }

    private func priorityRank(_ priority: ProjectTaskPriority) -> Int {
        switch priority {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
    }
}

private struct DailyWorkloadPanel: View {
    let overview: DailyWorkloadOverview
    @Binding var selectedDayKey: String?
    let referenceDayKey: String
    let selectDay: (DailyWorkloadDay) -> Void

    private var selectedDay: DailyWorkloadDay? {
        overview.days.first { $0.dateKey == selectedDayKey }
            ?? overview.days.first { $0.dateKey == referenceDayKey }
            ?? overview.days.first { $0.totalTaskCount > 0 }
            ?? overview.days.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("Daily Workload", systemImage: "calendar.day.timeline.left")
                    .font(.headline)
            }

            Text("Local task counts and progress. External Calendar writes require review approval.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DailyWorkloadAttentionBanner(overview: overview)

            // Adaptive 96pt-minimum columns keep all seven day cards on one
            // row inside the ~744pt panel at the canonical 1024pt viewport
            // (7 x ~99pt + 6 x 8pt spacing), so no card is cut at the right
            // edge and no second row gets clipped mid-content.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .top)], spacing: 8) {
                ForEach(overview.days) { day in
                    Button {
                        selectDay(day)
                    } label: {
                        DailyWorkloadDayCell(day: day, isSelected: day.dateKey == selectedDay?.dateKey)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("schedule-workload-day-cell-\(day.dateKey)")
                    .accessibilityLabel(String(format: String(localized: "Workload for %@"), day.dateKey))
                    .accessibilityValue(
                        String(
                            format: String(localized: "%d tasks, %d open, %d in progress, %d blocked, %d done, %d missed, %d percent complete"),
                            day.totalTaskCount,
                            day.openTaskCount,
                            day.inProgressTaskCount,
                            day.blockedTaskCount,
                            day.doneTaskCount,
                            day.overdueTaskCount,
                            Int((day.progress * 100).rounded())
                        )
                    )
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
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-workload-dashboard")
        .accessibilityLabel("Daily Workload")
        .accessibilityHint("Shows local per-day task counts, progress, unscheduled tasks, and Inbox triage without writing Calendar.")
    }
}

private struct DailyWorkloadAttentionBanner: View {
    let overview: DailyWorkloadOverview

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: overview.attentionSignalCount > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(overview.attentionSignalCount > 0 ? SuisuiTone.danger.color : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-workload-attention-banner")
        .accessibilityLabel("Workload attention")
        .accessibilityValue(detail)
    }

    private var headline: String {
        if overview.attentionSignalCount > 0 {
            return String(localized: "Review workload risks")
        }
        return String(localized: "No workload risks")
    }

    private var detail: String {
        String(
            format: String(localized: "Missed %d, blocked %d, unscheduled %d, Inbox %d"),
            overview.missedTaskCount,
            overview.blockedTaskCount,
            overview.unscheduledTasks.count,
            overview.inboxUntriagedCount
        )
    }
}

private struct DailyWorkloadDayCell: View {
    let day: DailyWorkloadDay
    let isSelected: Bool

    var body: some View {
        // One headline number per day (open tasks) plus a status line that
        // only names non-zero secondary metrics. A quiet day renders as
        // "0 Open" — never a grid of six labeled zeros. The cell has no
        // fixed maximum height, so content is never cut mid-line.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(shortDateLabel)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                if day.overdueTaskCount > 0 {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(SuisuiTone.danger.color)
                        .accessibilityHidden(true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(day.openTaskCount)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-open")
                Text("Open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                // Avoid repeating the same count in a 96pt day card. Show the
                // total only when completed work makes it meaningfully
                // different from the open count.
                if day.totalTaskCount > 0, day.totalTaskCount != day.openTaskCount {
                    Text(String(format: String(localized: "%d tasks"), day.totalTaskCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-total")
                }
            }

            if day.totalTaskCount > 0 {
                ProgressView(value: day.progress)
                    .accessibilityIdentifier("schedule-workload-progress-\(day.dateKey)")
                    .accessibilityLabel("Daily progress")
                    .accessibilityValue("\(Int((day.progress * 100).rounded()))%")
            }

            if hasSecondaryMetrics {
                HStack(spacing: 6) {
                    if day.inProgressTaskCount > 0 {
                        secondaryMetric(
                            String(format: String(localized: "%d doing"), day.inProgressTaskCount),
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: SuisuiBrand.soloBlue
                        )
                            .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-in-progress")
                    }
                    if day.blockedTaskCount > 0 {
                        secondaryMetric(
                            String(format: String(localized: "%d blocked"), day.blockedTaskCount),
                            systemImage: "exclamationmark.octagon.fill",
                            tint: SuisuiTone.danger.color
                        )
                            .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-blocked")
                    }
                    if day.overdueTaskCount > 0 {
                        secondaryMetric(
                            String(format: String(localized: "%d missed"), day.overdueTaskCount),
                            systemImage: "clock.badge.exclamationmark",
                            tint: SuisuiTone.danger.color
                        )
                            .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-missed")
                    }
                    if day.doneTaskCount > 0 {
                        secondaryMetric(
                            String(format: String(localized: "%d done"), day.doneTaskCount),
                            systemImage: "checkmark.circle",
                            tint: .secondary
                        )
                            .accessibilityIdentifier("schedule-workload-count-badge-\(day.dateKey)-done")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(
            isSelected ? SuisuiSurface.elevatedSelection : SuisuiSurface.groupedContent,
            in: RoundedRectangle(cornerRadius: SuisuiRadius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(isSelected ? SuisuiBorder.selected : SuisuiBorder.subtle)
        }
    }

    private var hasSecondaryMetrics: Bool {
        day.inProgressTaskCount > 0
            || day.blockedTaskCount > 0
            || day.overdueTaskCount > 0
            || day.doneTaskCount > 0
    }

    private var shortDateLabel: String {
        // `"E d"` is a fixed English pattern; the shared helper resolves the
        // locale-correct weekday/day order instead and reuses one cached
        // formatter rather than allocating one per row per redraw.
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        return SuisuiTimestampDisplay.weekdayAndDay(
            day.date,
            calendar: calendar,
            locale: localizedDisplayLocale()
        )
    }

    private func secondaryMetric(_ label: String, systemImage: String, tint: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(SuisuiTypography.compactLabel.monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
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
                    .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
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
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
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
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-workload-inbox-bucket")
        .accessibilityLabel("Inbox triage captures")
        .accessibilityValue("\(count)")
    }
}

private struct ScheduleDraftApprovalControls: View {
    let hasDraft: Bool
    let queueCalendarApply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                queueCalendarApply()
            } label: {
                Label("Queue Calendar Apply", systemImage: "tray.and.arrow.down")
            }
            .disabled(!hasDraft)
            .accessibilityIdentifier("schedule-apply-calendar")
            .accessibilityHint(
                hasDraft
                    ? "Adds reviewed schedule blocks to Assistant Queue before any external Calendar write."
                    : "Create a schedule draft first."
            )

            Text(hasDraft ? "External Calendar writes run from Assistant Queue after approval." : "Create a schedule draft first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("schedule-queue-approval-note")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-draft-approval-controls")
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
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
    }
}

private struct ScheduleUnscheduledPanel: View {
    let tasks: [ProjectBoardTask]
    @ObservedObject var viewModel: ProjectBoardViewModel
    let referenceDate: Date

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
                    HStack(spacing: 8) {
                        Label(task.title, systemImage: "circle")
                            .font(.caption)
                            .lineLimit(1)
                            .accessibilityIdentifier("schedule-unscheduled-task-\(task.id)")
                        Spacer(minLength: 8)
                        Button {
                            _ = viewModel.addUnscheduledTaskToScheduleDraft(
                                taskID: task.id,
                                on: referenceDate
                            )
                        } label: {
                            Label("Add to Draft", systemImage: "calendar.badge.plus")
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("schedule-unscheduled-add-draft-\(task.id)")
                        .accessibilityLabel(String(format: String(localized: "Add %@ to Draft"), task.title))
                        .accessibilityHint("Adds this local task to the reviewable schedule draft without writing Calendar.")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
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
            .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
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
