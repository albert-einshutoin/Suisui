import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

private enum ScheduleSurfaceMode: String, CaseIterable, Identifiable {
    case overview
    case timeline
    case agenda
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
        case .overview: "Week"
        case .timeline: "Day"
        case .agenda: "Schedule"
        case .workload: "Workload"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .overview: "w"
        case .timeline: "d"
        case .agenda: "a"
        case .workload: "l"
        }
    }
}

private enum ScheduleContentFilter: String, CaseIterable, Identifiable {
    case all
    case local
    case google

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All events"
        case .local: "Suisui"
        case .google: "Google"
        }
    }
}

private enum ScheduleLayoutMetrics {
    static let standardViewportWidth = CGFloat(CockpitLayoutPolicy.splitMinimumContentWidth)
    static let outerPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 10
    static let calendarMinimumWidth: CGFloat = 360
    static let railWidth = CGFloat(CockpitLayoutPolicy.scheduleRailMinimumWidth)
    static let dayHeaderHeight: CGFloat = 44
    static let allDayRowHeight: CGFloat = 30
    static let hourRowHeight: CGFloat = 52

    static func visibleHourRowCount(for viewportHeight: CGFloat) -> Int {
        if viewportHeight < 680 { return 5 }
        if viewportHeight < 820 { return 6 }
        if viewportHeight < 980 { return 8 }
        return 10
    }

    static func railWidth(for viewportWidth: CGFloat) -> CGFloat {
        CGFloat(CockpitLayoutPolicy.scheduleRailWidth(contentWidth: Double(viewportWidth)))
    }
}

private struct ScheduleQuickDraftSelection: Identifiable {
    let id = UUID()
    var startAt: Date
    var endAt: Date
    var taskID: Int64?
    var isExistingDraft: Bool
}

struct ScheduleWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var workloadReferenceDate = VisualEvidenceRuntimeContext.referenceDate()
    @State private var selectedWorkloadDayKey: String?
    @State private var selectedMode = ScheduleSurfaceMode.visualEvidenceInitialMode()
    @State private var quickDraftSelection: ScheduleQuickDraftSelection?
    @State private var scheduleSearchText = ""
    @State private var contentFilter: ScheduleContentFilter = .all
    @FocusState private var isScheduleSearchFocused: Bool
    @Environment(\.cockpitAuthoritativeContentWidth) private var authoritativeContentWidth

    var body: some View {
        GeometryReader { viewport in
            let scheduleReadModel = viewModel.derivedReadModels.schedule
            let workloadOverview = scheduleReadModel.workloadOverview
            let workloadReferenceDayKey = scheduleDateKey(for: workloadReferenceDate)
            let visibleHourRowCount = ScheduleLayoutMetrics.visibleHourRowCount(for: viewport.size.height)
            let visibleCockpit = filteredCockpit(scheduleReadModel.weeklyCockpit)
            let visibleExternalEvents = filteredExternalEvents
            let visibleUnscheduledTasks = filteredTasks(scheduleReadModel.unscheduledTasks)
            let hasVisibleCalendarItems = visibleExternalEvents.isEmpty == false
                || visibleCockpit.days.contains { $0.blocks.isEmpty == false }
            let hasVisibleItems = hasVisibleCalendarItems
                || (selectedMode == .overview && visibleUnscheduledTasks.isEmpty == false)
            ScrollView {
                VStack(alignment: .leading, spacing: ScheduleLayoutMetrics.sectionSpacing) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            scheduleTitle
                            Spacer(minLength: 12)
                            scheduleSearchAndRefresh
                            modePicker
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            scheduleTitle
                            scheduleSearchAndRefresh
                            modePicker
                        }
                    }

                    scheduleWorkflowArea

                    // One root-owned week/day navigator keeps every mode on the
                    // same temporal context. Mode-specific panels never maintain
                    // their own week cursor, which prevents silent draft drift.
                    ScheduleMiniCalendarPanel(
                        overview: workloadOverview,
                        selectedDate: workloadReferenceDate,
                        showsSingleDay: selectedMode == .timeline,
                        previousWeek: moveWorkloadToPreviousWeek,
                        nextWeek: moveWorkloadToNextWeek,
                        jumpToToday: moveWorkloadToToday,
                        jumpToDate: moveWorkload
                    )

                    if selectedMode != .workload,
                       (scheduleSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || contentFilter != .all),
                       hasVisibleItems == false {
                        Label("No matching schedule items.", systemImage: "magnifyingglass")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
                            .accessibilityIdentifier("schedule-search-empty")
                    }

                    Group {
                        switch selectedMode {
                        case .overview:
                            ScheduleOverviewCalendar(
                                cockpit: visibleCockpit,
                                unscheduledTasks: visibleUnscheduledTasks,
                                externalEvents: visibleExternalEvents,
                                externalEventLoadState: viewModel.externalScheduleEventLoadState,
                                viewModel: viewModel,
                                referenceDate: workloadReferenceDate,
                                selectedDayKey: $selectedWorkloadDayKey,
                                selectDay: { selectMiniCalendarDay($0.workload) },
                                quickDraftSelection: $quickDraftSelection,
                                viewportWidth: viewport.size.width,
                                visibleHourRowCount: visibleHourRowCount
                            )
                        case .timeline:
                            WeeklyScheduleTimelinePanel(
                                cockpit: selectedDayCockpit(from: visibleCockpit),
                                externalEvents: visibleExternalEvents,
                                selectedDayKey: $selectedWorkloadDayKey,
                                selectDay: { selectMiniCalendarDay($0.workload) },
                                quickDraftSelection: $quickDraftSelection,
                                moveTask: moveTask,
                                resizeTask: resizeTask,
                                title: "Daily schedule",
                                visibleHourRowCount: visibleHourRowCount
                            )
                        case .agenda:
                            ScheduleAgendaPanel(
                                cockpit: visibleCockpit,
                                externalEvents: visibleExternalEvents,
                                openBlock: openBlock
                            )
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
                .padding(ScheduleLayoutMetrics.outerPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .popover(item: $quickDraftSelection) { selection in
            ScheduleQuickDraftComposer(
                selection: selection,
                tasks: scheduleTaskCandidates,
                save: placeTask,
                remove: removeTask
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-workflow")
        .accessibilityLabel("Schedule")
        .accessibilityHint("Reviews workload and approval-ready schedule drafts from Review.")
        .onAppear {
            viewModel.refreshExternalScheduleEvents(around: workloadReferenceDate)
            prepareScheduleDraftForVisualEvidenceIfNeeded()
        }
    }

    /// Evidence captures pin a dense week desk. Timed dues already paint the
    /// grid at wall-clock hours; remapping them into sequential draft slots
    /// would hide T10/T14 density and collapse multi-hue priority colors into
    /// caution drafts. Keep Calendar writes approval-gated (no synced badge).
    private func prepareScheduleDraftForVisualEvidenceIfNeeded() {
        guard VisualEvidenceRuntimeContext() != nil else {
            return
        }
        // Intentionally no-op: densify via seeder timed dues + priority tints.
    }

    private var scheduleTitle: some View {
        Label("Schedule", systemImage: "calendar")
            .font(.title2.weight(.semibold))
    }

    private var scheduleSearchAndRefresh: some View {
        HStack(spacing: 6) {
            Button { isScheduleSearchFocused = true } label: {
                Label("Search schedule", systemImage: "magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .disabled(selectedMode == .workload)
            .help("Search schedule")
            .accessibilityIdentifier("schedule-search-focus")

            TextField("Search schedule", text: $scheduleSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150, idealWidth: 210, maxWidth: 240)
                .focused($isScheduleSearchFocused)
                .onKeyPress(.escape) {
                    if scheduleSearchText.isEmpty {
                        isScheduleSearchFocused = false
                    } else {
                        scheduleSearchText = ""
                    }
                    return .handled
                }
                .disabled(selectedMode == .workload)
                .accessibilityIdentifier("schedule-search")
                .accessibilityHint("Filters visible local tasks and read-only Google Calendar events by title or project.")

            if scheduleSearchText.isEmpty == false {
                Button { scheduleSearchText = "" } label: {
                    Label("Clear search", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(selectedMode == .workload)
                .help("Clear search")
                .accessibilityIdentifier("schedule-search-clear")
            }

            Picker("Event source", selection: $contentFilter) {
                ForEach(ScheduleContentFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 100)
            .disabled(selectedMode == .workload)
            .accessibilityLabel("Event source")
            .accessibilityIdentifier("schedule-content-filter")

            Button {
                viewModel.refreshExternalScheduleEvents(around: workloadReferenceDate, force: true)
            } label: {
                Label("Refresh Google Calendar", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help("Refresh Google Calendar")
            .disabled(viewModel.externalScheduleEventLoadState == .loading)
            .accessibilityIdentifier("schedule-refresh-external-events")
        }
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
                .keyboardShortcut(mode.keyboardShortcut, modifiers: [.command, .option])
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
                quickCreateButton
                generateDraftButton
                ScheduleDraftApprovalControls(
                    hasDraft: viewModel.scheduleDraft != nil,
                    queueCalendarApply: queueCalendarApply
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                quickCreateButton
                generateDraftButton
                ScheduleDraftApprovalControls(
                    hasDraft: viewModel.scheduleDraft != nil,
                    queueCalendarApply: queueCalendarApply
                )
            }
        }
        .padding(10)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
    }

    private var quickCreateButton: some View {
        Button {
            quickDraftSelection = defaultQuickDraftSelection()
        } label: {
            Label("Create", systemImage: "plus")
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .accessibilityIdentifier("schedule-quick-create")
        .accessibilityHint("Creates a reviewable task block at the selected date and time without writing Calendar.")
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
        let nextDate = calendar.date(byAdding: .day, value: -navigationDayStride, to: workloadReferenceDate) ?? workloadReferenceDate
        workloadReferenceDate = nextDate
        selectedWorkloadDayKey = nil
        viewModel.refreshScheduleReadModel(around: nextDate)
    }

    private func moveWorkloadToNextWeek() {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let nextDate = calendar.date(byAdding: .day, value: navigationDayStride, to: workloadReferenceDate) ?? workloadReferenceDate
        workloadReferenceDate = nextDate
        selectedWorkloadDayKey = nil
        viewModel.refreshScheduleReadModel(around: nextDate)
    }

    private func moveWorkloadToToday() {
        let nextDate = VisualEvidenceRuntimeContext.referenceDate()
        moveWorkload(nextDate)
    }

    private func moveWorkload(_ nextDate: Date) {
        workloadReferenceDate = nextDate
        selectedWorkloadDayKey = nil
        viewModel.refreshScheduleReadModel(around: nextDate)
    }

    private var navigationDayStride: Int {
        selectedMode == .timeline ? 1 : 7
    }

    private func selectMiniCalendarDay(_ day: DailyWorkloadDay) {
        workloadReferenceDate = day.date
        selectedWorkloadDayKey = day.dateKey
        viewModel.refreshScheduleReadModel(around: day.date)
    }

    private var scheduleTaskCandidates: [ProjectBoardTask] {
        let schedule = viewModel.derivedReadModels.schedule
        var seenTaskIDs: Set<Int64> = []
        return (schedule.unscheduledTasks + schedule.weeklyCockpit.days.flatMap(\.blocks).map(\.task))
            .filter { seenTaskIDs.insert($0.id).inserted && $0.status != .done }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return priorityRank(lhs.priority) < priorityRank(rhs.priority)
                }
                return lhs.id > rhs.id
            }
    }

    private func defaultQuickDraftSelection() -> ScheduleQuickDraftSelection {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let selectedDate = viewModel.derivedReadModels.schedule.weeklyCockpit.days
            .first { $0.dateKey == selectedWorkloadDayKey }?.date ?? workloadReferenceDate
        let now = VisualEvidenceRuntimeContext.referenceDate()
        let sameDay = calendar.isDate(selectedDate, inSameDayAs: now)
        let start: Date
        if sameDay {
            let dayStart = calendar.startOfDay(for: now)
            let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let nextQuarterHour = ((currentMinutes + 14) / 15) * 15
            start = calendar.date(byAdding: .minute, value: nextQuarterHour, to: dayStart) ?? now
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        }
        return ScheduleQuickDraftSelection(
            startAt: start,
            endAt: calendar.date(byAdding: .minute, value: 30, to: start) ?? start,
            taskID: nil,
            isExistingDraft: false
        )
    }

    private func placeTask(_ taskID: Int64, _ startAt: Date, _ endAt: Date) {
        if viewModel.placeTaskInScheduleDraft(
            taskID: taskID,
            startAt: startAt,
            endAt: endAt,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
        ) {
            workloadReferenceDate = startAt
            selectedWorkloadDayKey = scheduleDateKey(for: startAt)
            quickDraftSelection = nil
        }
    }

    private func moveTask(_ taskID: Int64, _ startAt: Date) {
        let currentBlock = viewModel.derivedReadModels.schedule.weeklyCockpit.days
            .flatMap(\.blocks)
            .first { $0.task.id == taskID }
        let duration = max(TimeInterval(30 * 60), currentBlock.flatMap { block in
            guard let oldStart = block.startAt, let oldEnd = block.endAt else { return nil }
            return oldEnd.timeIntervalSince(oldStart)
        } ?? TimeInterval(30 * 60))
        placeTask(taskID, startAt, startAt.addingTimeInterval(duration))
    }

    private func resizeTask(_ taskID: Int64, _ startAt: Date, _ endAt: Date) {
        placeTask(taskID, startAt, endAt)
    }

    private func openBlock(_ block: WeeklyScheduleBlock) {
        guard let startAt = block.startAt else { return }
        quickDraftSelection = ScheduleQuickDraftSelection(
            startAt: startAt,
            endAt: block.endAt ?? startAt.addingTimeInterval(30 * 60),
            taskID: block.task.id,
            isExistingDraft: block.source == .scheduleDraft
        )
    }

    private func selectedDayCockpit(from cockpit: WeeklyScheduleCockpit) -> WeeklyScheduleCockpit {
        let day = cockpit.days.first { $0.dateKey == selectedWorkloadDayKey }
            ?? cockpit.days.first { VisualEvidenceRuntimeContext.runtimeCalendar().isDate($0.date, inSameDayAs: workloadReferenceDate) }
            ?? cockpit.agendaDay
            ?? cockpit.days.first
        return WeeklyScheduleCockpit(
            days: day.map { [$0] } ?? [],
            unscheduledTasks: cockpit.unscheduledTasks,
            agendaDay: day,
            focusForecast: cockpit.focusForecast
        )
    }

    private var filteredExternalEvents: [ExternalScheduleEvent] {
        guard contentFilter != .local else { return [] }
        return viewModel.externalScheduleEvents.filter {
            ScheduleTimelineGeometry.matchesSearch(scheduleSearchText, values: [$0.title, $0.location ?? ""])
        }
    }

    private func filteredTasks(_ tasks: [ProjectBoardTask]) -> [ProjectBoardTask] {
        guard contentFilter != .google else { return [] }
        return tasks.filter {
            ScheduleTimelineGeometry.matchesSearch(scheduleSearchText, values: [$0.title])
        }
    }

    private func filteredCockpit(_ cockpit: WeeklyScheduleCockpit) -> WeeklyScheduleCockpit {
        var result = cockpit
        result.days = cockpit.days.map { day in
            var day = day
            if contentFilter == .google {
                day.blocks = []
            } else {
                day.blocks = day.blocks.filter {
                    ScheduleTimelineGeometry.matchesSearch(
                        scheduleSearchText,
                        values: [$0.task.title, $0.projectTitle]
                    )
                }
            }
            return day
        }
        result.unscheduledTasks = filteredTasks(cockpit.unscheduledTasks)
        result.agendaDay = result.days.first { $0.dateKey == cockpit.agendaDay?.dateKey }
        return result
    }

    private func removeTask(_ taskID: Int64, _ referenceDate: Date) {
        if viewModel.removeTaskFromScheduleDraft(
            taskID: taskID,
            around: referenceDate,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
        ) {
            quickDraftSelection = nil
        }
    }

    private func priorityRank(_ priority: ProjectTaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
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
    let selectedDate: Date
    let showsSingleDay: Bool
    let previousWeek: () -> Void
    let nextWeek: () -> Void
    let jumpToToday: () -> Void
    let jumpToDate: (Date) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: jumpToToday) {
                Text("Today")
            }
            .help("Jump to Today")
            .keyboardShortcut("t", modifiers: [.command, .option])
            .accessibilityIdentifier("schedule-mini-calendar-today")
            .accessibilityHint("Selects the current week without writing Calendar.")

            Button(action: previousWeek) {
                Label(previousLabel, systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .help(previousLabel)
            .accessibilityIdentifier("schedule-mini-calendar-previous-week")
            .accessibilityLabel(previousLabel)
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

            Button(action: nextWeek) {
                Label(nextLabel, systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .help(nextLabel)
            .accessibilityIdentifier("schedule-mini-calendar-next-week")
            .accessibilityLabel(nextLabel)
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

            Text(rangeLabel)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            DatePicker(
                "Go to Date",
                selection: Binding(get: { selectedDate }, set: { jumpToDate($0) }),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 118)
            .accessibilityIdentifier("schedule-go-to-date")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-mini-calendar")
        .accessibilityLabel(showsSingleDay ? "Schedule day navigation" : "Schedule week navigation")
        .accessibilityHint(showsSingleDay ? "Moves the visible Schedule day without writing Calendar." : "Moves the visible Schedule week without writing Calendar.")
    }

    private var rangeLabel: String {
        if showsSingleDay {
            return SuisuiTimestampDisplay.absolute(
                selectedDate,
                calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
                locale: localizedDisplayLocale()
            )
        }
        guard let first = overview.days.first?.date, let last = overview.days.last?.date else {
            return String(localized: "Schedule")
        }
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let locale = localizedDisplayLocale()
        return "\(SuisuiTimestampDisplay.absolute(first, calendar: calendar, locale: locale)) – \(SuisuiTimestampDisplay.absolute(last, calendar: calendar, locale: locale))"
    }

    private var previousLabel: String {
        showsSingleDay ? String(localized: "Previous Day") : String(localized: "Previous Week")
    }

    private var nextLabel: String {
        showsSingleDay ? String(localized: "Next Day") : String(localized: "Next Week")
    }
}

private struct ScheduleOverviewCalendar: View {
    let cockpit: WeeklyScheduleCockpit
    let unscheduledTasks: [ProjectBoardTask]
    let externalEvents: [ExternalScheduleEvent]
    let externalEventLoadState: ExternalScheduleEventLoadState
    @ObservedObject var viewModel: ProjectBoardViewModel
    let referenceDate: Date
    @Binding var selectedDayKey: String?
    let selectDay: (WeeklyScheduleDay) -> Void
    @Binding var quickDraftSelection: ScheduleQuickDraftSelection?
    let viewportWidth: CGFloat
    let visibleHourRowCount: Int
    @Environment(\.cockpitAuthoritativeContentWidth) private var authoritativeContentWidth

    var body: some View {
        let layoutWidth = CockpitSplitLayout.layoutWidth(measuredWidth: viewportWidth, authoritativeContentWidth: authoritativeContentWidth)
        let isWide = CockpitSplitLayout.presentsSplitRail(
            measuredWidth: viewportWidth,
            authoritativeContentWidth: authoritativeContentWidth
        )
        let railWidth = CockpitSplitLayout.railWidth(for: .schedule, contentWidth: layoutWidth)
        if isWide {
            HStack(alignment: .top, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                calendar
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                rail(itemLimit: nil)
                    .cockpitSplitSecondaryRail(width: railWidth)
            }
            .frame(width: layoutWidth, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                calendar
                rail(itemLimit: 1)
            }
        }
    }

    private var calendar: some View {
        WeeklyScheduleTimelinePanel(
            cockpit: cockpit,
            externalEvents: externalEvents,
            selectedDayKey: $selectedDayKey,
            selectDay: selectDay,
            quickDraftSelection: $quickDraftSelection,
            moveTask: moveTask,
            resizeTask: resizeTask,
            title: "Weekly schedule",
            visibleHourRowCount: visibleHourRowCount
        )
    }

    private func rail(itemLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScheduleAdjustmentPanel(cockpit: cockpit, itemLimit: itemLimit ?? 2, selectDay: selectDay)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            ScheduleAvailabilityPanel(
                cockpit: cockpit,
                externalEvents: externalEvents,
                externalEventLoadState: externalEventLoadState,
                referenceDate: referenceDate,
                itemLimit: itemLimit ?? 3,
                selectTimeRange: { startAt, endAt in
                    selectTimeRange(startAt, endAt)
                }
            )
            .frame(maxHeight: .infinity, alignment: .topLeading)
            ScheduleSuggestionsPanel(
                tasks: unscheduledTasks,
                applyResult: viewModel.scheduleApplyResult,
                itemLimit: itemLimit ?? 2,
                suggestTask: suggestTask
            )
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func selectTimeRange(_ startAt: Date, _ endAt: Date, taskID: Int64? = nil, isExistingDraft: Bool = false) {
        quickDraftSelection = ScheduleQuickDraftSelection(
            startAt: startAt,
            endAt: endAt,
            taskID: taskID,
            isExistingDraft: isExistingDraft
        )
    }

    private func moveTask(_ taskID: Int64, _ startAt: Date) {
        let block = cockpit.days.flatMap(\.blocks).first { $0.task.id == taskID }
        let duration = max(TimeInterval(30 * 60), block.flatMap { block in
            guard let oldStart = block.startAt, let oldEnd = block.endAt else { return nil }
            return oldEnd.timeIntervalSince(oldStart)
        } ?? TimeInterval(30 * 60))
        _ = viewModel.placeTaskInScheduleDraft(
            taskID: taskID,
            startAt: startAt,
            endAt: startAt.addingTimeInterval(duration),
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
        )
    }

    private func resizeTask(_ taskID: Int64, _ startAt: Date, _ endAt: Date) {
        _ = viewModel.placeTaskInScheduleDraft(
            taskID: taskID,
            startAt: startAt,
            endAt: endAt,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
        )
    }

    private func suggestTask(_ task: ProjectBoardTask) {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let now = VisualEvidenceRuntimeContext.referenceDate()
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let today = calendar.startOfDay(for: now)
        let start: Date
        if referenceDay > today {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: referenceDate) ?? referenceDate
        } else {
            let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let nextHalfHour = max(9 * 60, ((currentMinutes + 29) / 30) * 30)
            if nextHalfHour < 18 * 60 {
                start = calendar.date(
                    byAdding: .minute,
                    value: nextHalfHour,
                    to: today
                ) ?? now
            } else {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
                start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            }
        }
        selectTimeRange(
            start,
            calendar.date(byAdding: .minute, value: 30, to: start) ?? start,
            taskID: task.id
        )
    }
}

private struct WeeklyScheduleTimelinePanel: View {
    let cockpit: WeeklyScheduleCockpit
    let externalEvents: [ExternalScheduleEvent]
    @Binding var selectedDayKey: String?
    let selectDay: (WeeklyScheduleDay) -> Void
    @Binding var quickDraftSelection: ScheduleQuickDraftSelection?
    let moveTask: (Int64, Date) -> Void
    let resizeTask: (Int64, Date, Date) -> Void
    let title: LocalizedStringKey
    let visibleHourRowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Label(title, systemImage: "calendar")
                    .font(.headline)
                Spacer(minLength: 8)
                Label(focusForecastSummary, systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("schedule-focus-forecast")
            }

            WeeklyScheduleTimeAxisGrid(
                cockpit: cockpit,
                externalEvents: externalEvents,
                selectedDayKey: $selectedDayKey,
                selectDay: selectDay,
                quickDraftSelection: $quickDraftSelection,
                moveTask: moveTask,
                resizeTask: resizeTask,
                visibleHourRowCount: visibleHourRowCount
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-week-cockpit")
        .accessibilityLabel(title)
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
    let externalEvents: [ExternalScheduleEvent]
    @Binding var selectedDayKey: String?
    let selectDay: (WeeklyScheduleDay) -> Void
    @Binding var quickDraftSelection: ScheduleQuickDraftSelection?
    let moveTask: (Int64, Date) -> Void
    let resizeTask: (Int64, Date, Date) -> Void
    let visibleHourRowCount: Int
    @Environment(\.displayScale) private var displayScale

    private var slotHours: [Int] {
        Array(0...23)
    }

    private var currentDate: Date {
        VisualEvidenceRuntimeContext.referenceDate()
    }

    private var currentDayKey: String {
        SuisuiTimestampDisplay.dayKey(
            currentDate,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
        )
    }

    private var currentHour: Int {
        VisualEvidenceRuntimeContext.runtimeCalendar().component(.hour, from: currentDate)
    }

    private var currentMinute: Int {
        VisualEvidenceRuntimeContext.runtimeCalendar().component(.minute, from: currentDate)
    }

    private var showsCurrentTime: Bool {
        cockpit.days.contains { $0.dateKey == currentDayKey } && slotHours.contains(currentHour)
    }

    var body: some View {
        VStack(spacing: 0) {
            dayHeaderRow
            allDayRow
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        LazyVStack(spacing: 0) {
                            ForEach(slotHours, id: \.self) { hour in
                                hourRow(hour)
                                    .id(hour)
                            }
                        }
                        timedBlockLayer
                        currentTimeLine
                    }
                }
                .frame(height: ScheduleLayoutMetrics.hourRowHeight * CGFloat(visibleHourRowCount))
                .onAppear {
                    proxy.scrollTo(initialScrollHour, anchor: .top)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("schedule-week-grid")
            .accessibilityLabel("Weekly schedule grid")
            .accessibilityHint("Shows local schedule blocks and read-only Google Calendar events. It does not write Calendar events.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-week-time-axis-grid")
        .accessibilityLabel("Schedule time axis grid")
        .accessibilityHint("Shows the visible week by hour without horizontal scrolling.")
        .clipShape(RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .overlay {
            dayColumnSeparators
        }
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(SuisuiBorder.subtle, lineWidth: 1)
        }
    }

    private var dayColumnSeparators: some View {
        GeometryReader { proxy in
            let scale = max(displayScale, 1)
            let pixel = 1 / scale
            let dayWidth = max(0, proxy.size.width - 52) / CGFloat(max(cockpit.days.count, 1))
            ZStack(alignment: .topLeading) {
                ForEach(0..<cockpit.days.count, id: \.self) { index in
                    let position = 52 + dayWidth * CGFloat(index)
                    Rectangle()
                        .fill(SuisuiTone.neutral.color.opacity(0.35))
                        .frame(width: pixel)
                        .offset(x: (position * scale).rounded() / scale - pixel / 2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("schedule-day-column-separators")
    }

    @ViewBuilder
    private var currentTimeLine: some View {
        if showsCurrentTime {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Circle()
                        .fill(SuisuiTone.danger.color)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(SuisuiTone.danger.color)
                        .frame(height: 1.5)
                }
                .frame(width: max(0, proxy.size.width - 49))
                .offset(
                    x: 49,
                    y: CGFloat(currentHour * 60 + currentMinute) / 60 * ScheduleLayoutMetrics.hourRowHeight
                )
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current time")
            .accessibilityIdentifier("schedule-current-time-line")
        }
    }

    private var initialScrollHour: Int {
        if showsCurrentTime {
            return max(0, min(23, currentHour - 2))
        }
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let firstEventHour = cockpit.days
            .flatMap(\.blocks)
            .compactMap(\.startAt)
            + externalEvents.filter { !$0.isAllDay }.map(\.startAt)
        return max(0, min(23, (firstEventHour.map { calendar.component(.hour, from: $0) }.min() ?? 9) - 1))
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 52, height: ScheduleLayoutMetrics.dayHeaderHeight)
            ForEach(cockpit.days) { day in
                WeeklyScheduleDayHeaderButton(
                    day: day,
                    selectedDayKey: $selectedDayKey,
                    isToday: day.dateKey == currentDayKey,
                    selectDay: selectDay
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var allDayRow: some View {
        HStack(spacing: 0) {
            Text("All day")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .topLeading)
                .frame(minHeight: ScheduleLayoutMetrics.allDayRowHeight, alignment: .topLeading)
                .padding(.top, 5)
            ForEach(cockpit.days) { day in
                WeeklyScheduleTimeAxisSlot(
                    day: day,
                    hour: nil,
                    label: String(localized: "All day"),
                    blocks: allDayBlocks(for: day),
                    externalEvents: allDayExternalEvents(for: day),
                    emptyLabel: String(localized: "No all-day blocks"),
                    minimumHeight: ScheduleLayoutMetrics.allDayRowHeight,
                    isSelected: day.dateKey == selectedDayKey,
                    selectDay: selectDay,
                    selectTimeRange: selectTimeRange,
                    openBlock: openBlock,
                    moveTask: moveTask
                )
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("schedule-week-time-axis-all-day-slot-\(day.dateKey)")
            }
        }
    }

    private func hourRow(_ hour: Int) -> some View {
        HStack(spacing: 0) {
            Text(hourLabel(hour))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .topLeading)
                .frame(minHeight: ScheduleLayoutMetrics.hourRowHeight, alignment: .topLeading)
                .padding(.top, 5)
            ForEach(cockpit.days) { day in
                WeeklyScheduleTimeAxisSlot(
                    day: day,
                    hour: hour,
                    label: hourLabel(hour),
                    blocks: [],
                    externalEvents: [],
                    emptyLabel: String(localized: "No timed blocks"),
                    minimumHeight: ScheduleLayoutMetrics.hourRowHeight,
                    isSelected: day.dateKey == selectedDayKey,
                    selectDay: selectDay,
                    selectTimeRange: selectTimeRange,
                    openBlock: openBlock,
                    moveTask: moveTask
                )
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("schedule-week-time-axis-slot-\(day.dateKey)-\(hour)")
            }
        }
    }

    private func allDayBlocks(for day: WeeklyScheduleDay) -> [WeeklyScheduleBlock] {
        day.blocks.filter { $0.startAt == nil }
    }

    private func allDayExternalEvents(for day: WeeklyScheduleDay) -> [ExternalScheduleEvent] {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let dayStart = calendar.startOfDay(for: day.date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return externalEvents.filter {
            $0.isAllDay && ScheduleTimelineGeometry.allDayEvent(
                $0,
                occursOn: day.dateKey,
                fallback: dayStart..<dayEnd
            )
        }
    }

    private var timedBlockLayer: some View {
        GeometryReader { proxy in
            ForEach(Array(cockpit.days.enumerated()), id: \.offset) { dayIndex, day in
                ForEach(timelineItems(for: day)) { item in
                    let frame = itemFrame(item, day: day, dayIndex: dayIndex, gridWidth: proxy.size.width)
                    switch item.content {
                    case let .local(block):
                        WeeklySchedulePositionedBlock(
                            block: block,
                            frame: frame,
                            hourHeight: ScheduleLayoutMetrics.hourRowHeight,
                            open: { openBlock(block) },
                            moveTask: moveTask,
                            resizeTask: resizeTask
                        )
                    case let .external(event):
                        ExternalSchedulePositionedEvent(event: event, frame: frame)
                    }
                }
            }
        }
    }

    private func itemFrame(
        _ item: ScheduleTimelineItem,
        day: WeeklyScheduleDay,
        dayIndex: Int,
        gridWidth: CGFloat
    ) -> CGRect {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let dayStart = calendar.startOfDay(for: day.date)
        let startMinute = calendar.dateComponents([.minute], from: dayStart, to: item.startAt).minute ?? 0
        let durationMinutes = calendar.dateComponents([.minute], from: item.startAt, to: item.endAt).minute ?? 30
        return ScheduleTimelineGeometry.blockFrame(
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            dayIndex: dayIndex,
            dayCount: cockpit.days.count,
            overlapLane: item.overlapLane,
            overlapGroupSize: item.overlapGroupSize,
            gridWidth: gridWidth,
            timeAxisWidth: 52,
            hourHeight: ScheduleLayoutMetrics.hourRowHeight
        )
    }

    private func timelineItems(for day: WeeklyScheduleDay) -> [ScheduleTimelineItem] {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let dayStart = calendar.startOfDay(for: day.date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let localItems = day.blocks.compactMap { block -> ScheduleTimelineItem? in
            guard let startAt = block.startAt, let endAt = block.endAt else { return nil }
            return ScheduleTimelineItem(content: .local(block), startAt: startAt, endAt: endAt)
        }
        let externalItems = externalEvents.compactMap { event -> ScheduleTimelineItem? in
            guard event.isAllDay == false, event.endAt > dayStart, event.startAt < dayEnd else { return nil }
            return ScheduleTimelineItem(
                content: .external(event),
                startAt: max(event.startAt, dayStart),
                endAt: min(event.endAt, dayEnd)
            )
        }
        return ScheduleTimelineItem.assignOverlapLanes(to: localItems + externalItems)
    }

    private func hourLabel(_ hour: Int) -> String {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: currentDate) else {
            return String(format: "%02d:00", hour)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = localizedDisplayLocale()
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }

    private func selectTimeRange(_ day: WeeklyScheduleDay, _ startAt: Date, _ endAt: Date) {
        selectedDayKey = day.dateKey
        selectDay(day)
        quickDraftSelection = ScheduleQuickDraftSelection(
            startAt: startAt,
            endAt: endAt,
            taskID: nil,
            isExistingDraft: false
        )
    }

    private func openBlock(_ block: WeeklyScheduleBlock) {
        guard let startAt = block.startAt else { return }
        let endAt = block.endAt ?? startAt.addingTimeInterval(30 * 60)
        quickDraftSelection = ScheduleQuickDraftSelection(
            startAt: startAt,
            endAt: endAt,
            taskID: block.task.id,
            isExistingDraft: block.source == .scheduleDraft
        )
    }
}

private struct WeeklyScheduleDayHeaderButton: View {
    let day: WeeklyScheduleDay
    @Binding var selectedDayKey: String?
    let isToday: Bool
    let selectDay: (WeeklyScheduleDay) -> Void

    var body: some View {
        let isSelected = day.dateKey == selectedDayKey
        Button {
            selectedDayKey = day.dateKey
            selectDay(day)
        } label: {
            WeeklyScheduleDayHeader(
                day: day,
                isSelected: isSelected,
                isToday: isToday
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("schedule-mini-calendar-day-\(day.dateKey)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WeeklyScheduleTimeAxisSlot: View {
    let day: WeeklyScheduleDay
    let hour: Int?
    let label: String
    let blocks: [WeeklyScheduleBlock]
    let externalEvents: [ExternalScheduleEvent]
    let emptyLabel: String
    let minimumHeight: CGFloat
    let isSelected: Bool
    let selectDay: (WeeklyScheduleDay) -> Void
    let selectTimeRange: (WeeklyScheduleDay, Date, Date) -> Void
    let openBlock: (WeeklyScheduleBlock) -> Void
    let moveTask: (Int64, Date) -> Void
    @State private var isHovering = false
    @State private var dragStartMinute: Int?
    @State private var dragEndMinute: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: minimumHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: selectSlot)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(blocks) { block in
                    WeeklyScheduleTimeAxisBlock(
                        block: block,
                        open: { openBlock(block) },
                        moveBy: nil,
                        resizeBy: nil
                    )
                }
                ForEach(externalEvents) { event in
                    ExternalScheduleAllDayEvent(event: event)
                }
            }
            .padding(2)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard hour != nil else { return }
                    dragStartMinute = snappedMinutes(value.startLocation.y)
                    dragEndMinute = snappedMinutes(value.location.y)
                }
                .onEnded { value in
                    selectDraggedRange(value)
                    dragStartMinute = nil
                    dragEndMinute = nil
                }
        )
        .dropDestination(for: String.self) { taskIDs, location in
            guard let hour,
                  let taskID = taskIDs.first.flatMap(Int64.init),
                  let startAt = date(hour: hour, minute: snappedMinutes(location.y)) else {
                return false
            }
            moveTask(taskID, startAt)
            return true
        }
        .background(SuisuiSurface.groupedContent)
        .overlay {
            if isHovering && hour != nil {
                SuisuiBrand.soloBlue.opacity(0.06)
            }
        }
        .onHover { isHovering = $0 }
        .overlay(alignment: .topLeading) {
            dragSelectionPreview
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SuisuiTone.neutral.color.opacity(0.35))
                .frame(height: 0.5)
        }
        .accessibilityLabel("Time axis slot")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(hour == nil ? "Selects this day." : "Creates a reviewable block at this time without writing Calendar.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: String(localized: "Add to Schedule Draft")) {
            selectSlot()
        }
    }

    @ViewBuilder
    private var dragSelectionPreview: some View {
        if let dragStartMinute, let dragEndMinute, hour != nil {
            let lower = min(dragStartMinute, dragEndMinute)
            let upper = max(dragStartMinute, dragEndMinute)
            let duration = max(15, upper - lower)
            RoundedRectangle(cornerRadius: SuisuiRadius.control)
                .fill(SuisuiBrand.soloBlue.opacity(0.2))
                .overlay(alignment: .topLeading) {
                    Text("\(duration) min")
                        .font(.caption2.monospacedDigit())
                        .padding(3)
                }
                .frame(height: max(10, CGFloat(duration) / 60 * minimumHeight))
                .offset(y: CGFloat(lower) / 60 * minimumHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func selectSlot() {
        guard let hour,
              let startAt = date(hour: hour, minute: 0),
              let endAt = date(hour: hour, minute: 30) else {
            selectDay(day)
            return
        }
        selectTimeRange(day, startAt, endAt)
    }

    private func selectDraggedRange(_ value: DragGesture.Value) {
        guard let hour else { return }
        let startMinutes = snappedMinutes(value.startLocation.y)
        let endMinutes = snappedMinutes(value.location.y)
        let lowerMinutes = min(startMinutes, endMinutes)
        let upperMinutes = max(startMinutes, endMinutes)
        let duration = max(30, upperMinutes - lowerMinutes)
        guard let startAt = date(hour: hour, minute: lowerMinutes),
              let endAt = VisualEvidenceRuntimeContext.runtimeCalendar().date(
                byAdding: .minute,
                value: duration,
                to: startAt
              ) else {
            return
        }
        selectTimeRange(day, startAt, endAt)
    }

    private func snappedMinutes(_ y: CGFloat) -> Int {
        let rawMinutes = Int((y / max(minimumHeight, 1) * 60).rounded())
        let snapped = Int((Double(rawMinutes) / 15).rounded()) * 15
        let baseHour = hour ?? 0
        return max(-baseHour * 60, min((24 - baseHour) * 60, snapped))
    }

    private func date(hour: Int, minute: Int) -> Date? {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        guard let dayStart = calendar.dateInterval(of: .day, for: day.date)?.start else { return nil }
        return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: dayStart)
    }

    private var accessibilityValue: String {
        let localSummary = blocks.isEmpty
            ? emptyLabel
            : blocks.map { block in
                let source = block.source == .scheduleDraft ? String(localized: "Schedule draft") : String(localized: "Due task")
                if block.overlapGroupSize > 1 {
                    return "\(block.timeLabel), \(block.task.title), \(block.projectTitle), \(source), \(String(format: String(localized: "Lane %d of %d"), block.overlapLane + 1, block.overlapGroupSize))"
                }
                return "\(block.timeLabel), \(block.task.title), \(block.projectTitle), \(source)"
            }.joined(separator: ", ")
        let externalSummary = externalEvents.map { "\($0.title), \(String(localized: "Google Calendar event"))" }
            .joined(separator: ", ")
        return "\(day.dateKey), \(label), \([localSummary, externalSummary].filter { !$0.isEmpty }.joined(separator: ", "))"
    }
}

private struct ScheduleTimelineItem: Identifiable {
    enum Content {
        case local(WeeklyScheduleBlock)
        case external(ExternalScheduleEvent)
    }

    let content: Content
    let startAt: Date
    let endAt: Date
    var overlapLane = 0
    var overlapGroupSize = 1

    var id: String {
        switch content {
        case let .local(block): "local-\(block.id)"
        case let .external(event): "google-\(event.id)"
        }
    }

    static func assignOverlapLanes(to items: [ScheduleTimelineItem]) -> [ScheduleTimelineItem] {
        var assigned = items.sorted(by: { $0.startAt < $1.startAt })
        let positions = ScheduleTimelineGeometry.overlapPositions(
            for: assigned.map { DateInterval(start: $0.startAt, end: $0.endAt) }
        )
        for index in assigned.indices {
            assigned[index].overlapLane = positions[index].lane
            assigned[index].overlapGroupSize = positions[index].groupSize
        }
        return assigned
    }
}

private struct ExternalScheduleAllDayEvent: View {
    let event: ExternalScheduleEvent
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            Label(event.title, systemImage: "g.circle.fill")
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(SuisuiBrand.soloBlue)
                .background(SuisuiBrand.soloBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsDetails) {
            ExternalScheduleEventDetails(event: event)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(String(localized: "Google Calendar event")), \(String(localized: "All day"))")
        .accessibilityHint("Shows read-only event details.")
    }
}

private struct ExternalSchedulePositionedEvent: View {
    let event: ExternalScheduleEvent
    let frame: CGRect
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                Text(timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(4)
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .foregroundStyle(SuisuiBrand.soloBlue)
            .background(SuisuiBrand.soloBlue.opacity(event.blocksAvailability ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
            .overlay(alignment: .leading) {
                Rectangle().fill(SuisuiBrand.soloBlue).frame(width: 3)
            }
        }
        .buttonStyle(.plain)
        .offset(x: frame.minX, y: frame.minY)
        .popover(isPresented: $showsDetails) {
            ExternalScheduleEventDetails(event: event)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(String(localized: "Google Calendar event"))")
        .accessibilityValue(timeLabel)
        .accessibilityHint("Shows read-only event details.")
        .zIndex(1)
    }

    private var timeLabel: String {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let locale = localizedDisplayLocale()
        return "\(SuisuiTimestampDisplay.time(event.startAt, calendar: calendar, locale: locale))–\(SuisuiTimestampDisplay.time(event.endAt, calendar: calendar, locale: locale))"
    }
}

private struct ExternalScheduleEventDetails: View {
    let event: ExternalScheduleEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Google Calendar", systemImage: "g.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SuisuiBrand.soloBlue)
            Text(event.title)
                .font(.headline)
                .textSelection(.enabled)
            Label(externalScheduleEventDateLabel(event), systemImage: "clock")
                .font(.subheadline)
            if let location = event.location, location.isEmpty == false {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
            Label(
                event.blocksAvailability ? String(localized: "Busy time") : String(localized: "Available time"),
                systemImage: event.blocksAvailability ? "circle.fill" : "circle.dashed"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            Label("Read-only Google Calendar event", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-external-event-details")
    }
}

private struct WeeklySchedulePositionedBlock: View {
    let block: WeeklyScheduleBlock
    let frame: CGRect
    let hourHeight: CGFloat
    let open: () -> Void
    let moveTask: (Int64, Date) -> Void
    let resizeTask: (Int64, Date, Date) -> Void
    @State private var resizeTranslation: CGFloat = 0

    var body: some View {
        WeeklyScheduleTimeAxisBlock(
            block: block,
            open: open,
            moveBy: move,
            resizeBy: resize
        )
        .frame(width: frame.width, height: max(18, frame.height + resizeTranslation), alignment: .topLeading)
        .offset(x: frame.minX, y: frame.minY)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(SuisuiTone.neutral.color)
                .frame(width: 24, height: 3)
                .padding(.bottom, 2)
                .contentShape(Rectangle().inset(by: -8))
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { resizeTranslation = $0.translation.height }
                        .onEnded { value in
                            let minutes = ScheduleTimelineGeometry.snappedDelta(
                                for: value.translation.height,
                                hourHeight: hourHeight
                            )
                            resize(minutes)
                            resizeTranslation = 0
                        }
                )
                .accessibilityHidden(true)
        }
        .zIndex(resizeTranslation == 0 ? 1 : 10)
    }

    private func move(_ minutes: Int) {
        guard let startAt = block.startAt else { return }
        moveTask(block.task.id, startAt.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    private func resize(_ minutes: Int) {
        guard let startAt = block.startAt, let endAt = block.endAt else { return }
        let nextEnd = max(startAt.addingTimeInterval(15 * 60), endAt.addingTimeInterval(TimeInterval(minutes * 60)))
        resizeTask(block.task.id, startAt, nextEnd)
    }
}

private struct WeeklyScheduleTimeAxisBlock: View {
    let block: WeeklyScheduleBlock
    let open: () -> Void
    let moveBy: ((Int) -> Void)?
    let resizeBy: ((Int) -> Void)?

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.task.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Text(block.timeLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                blockAccent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: SuisuiRadius.control)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(blockAccent)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.plain)
        .draggable(String(block.task.id))
        .contextMenu {
            if let moveBy {
                Button("Move 15 Minutes Earlier") { moveBy(-15) }
                Button("Move 15 Minutes Later") { moveBy(15) }
            }
            if moveBy != nil, resizeBy != nil {
                Divider()
            }
            if let resizeBy {
                Button("Shorten 15 Minutes") { resizeBy(-15) }
                Button("Extend 15 Minutes") { resizeBy(15) }
            }
        }
        .help(String(localized: "Open, move, or resize this schedule block"))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-week-block-\(block.id)")
        .accessibilityLabel("\(block.task.title), \(sourceLabel)")
        .accessibilityValue(accessibilityValue)
        .accessibilityActions {
            if let moveBy {
                Button("Move 15 Minutes Earlier") { moveBy(-15) }
                Button("Move 15 Minutes Later") { moveBy(15) }
            }
            if let resizeBy {
                Button("Shorten 15 Minutes") { resizeBy(-15) }
                Button("Extend 15 Minutes") { resizeBy(15) }
            }
        }
    }

    /// Local due blocks tint by priority/status so the week desk reads denser
    /// without inventing Google Calendar “synced” chrome.
    private var blockAccent: Color {
        if block.source == .scheduleDraft {
            return SuisuiTone.caution.color
        }
        switch block.task.status {
        case .blocked:
            return SuisuiTone.danger.color
        case .inProgress:
            return SuisuiTone.positive.color
        default:
            break
        }
        switch block.task.priority {
        case .high:
            return SuisuiBrand.soloBlue
        case .medium:
            return SuisuiBrand.soloBlue.opacity(0.72)
        case .low:
            return SuisuiTone.neutral.color
        }
    }

    private var accessibilityValue: String {
        var values = [
            block.timeLabel,
            block.projectTitle,
            sourceLabel
        ]
        if block.overlapGroupSize > 1 {
            values.append(String(
                format: String(localized: "Lane %d of %d"),
                block.overlapLane + 1,
                block.overlapGroupSize
            ))
        }
        return values.joined(separator: ", ")
    }

    private var sourceLabel: String {
        block.source == .scheduleDraft ? String(localized: "Schedule draft") : String(localized: "Due task")
    }
}

private struct WeeklyScheduleDayHeader: View {
    let day: WeeklyScheduleDay
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(weekdayLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            dayNumberBadge
        }
        .frame(maxWidth: .infinity, minHeight: ScheduleLayoutMetrics.dayHeaderHeight)
        .contentShape(Rectangle())
        .background(
            isSelected
                ? AnyShapeStyle(SuisuiBrand.soloBlue.opacity(0.06))
                : AnyShapeStyle(SuisuiSurface.groupedContent.opacity(0.001))
        )
        .overlay(alignment: .topTrailing) {
            if day.completionHistoryCount > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(SuisuiTone.positive.color)
                    .padding(4)
                    .accessibilityIdentifier("schedule-week-completion-history-\(day.dateKey)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-week-day-column-\(day.dateKey)")
        .accessibilityLabel(String(format: String(localized: "Schedule day %@"), day.dateKey))
        .accessibilityValue(String(
            format: String(localized: "%d blocks, %d reminder proposals, %d completed tasks"),
            day.blocks.count,
            day.reminderProposalCount,
            day.completionHistoryCount
        ))
    }

    private var dayNumberBadge: some View {
        Text(dayNumber)
            .font(.headline.monospacedDigit())
            .foregroundStyle(isToday ? Color.white : Color.primary)
            .frame(width: 28, height: 28)
            .background(dayBackground, in: Circle())
            .overlay {
                if isSelected && !isToday {
                    Circle().stroke(SuisuiBrand.soloBlue, lineWidth: 1.5)
                }
            }
            .accessibilityIdentifier(isSelected ? "schedule-mini-calendar-selected-day" : "schedule-week-day-number-\(day.dateKey)")
    }

    private var dayBackground: AnyShapeStyle {
        isToday
            ? AnyShapeStyle(SuisuiBrand.soloBlue)
            : AnyShapeStyle(SuisuiSurface.groupedContent.opacity(0.001))
    }

    private var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        formatter.locale = localizedDisplayLocale()
        formatter.dateFormat = "EEE"
        return formatter.string(from: day.date)
    }

    private var dayNumber: String {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        return String(calendar.component(.day, from: day.date))
    }
}

private enum ScheduleAgendaItem: Identifiable {
    case local(WeeklyScheduleBlock)
    case external(ExternalScheduleEvent)

    var id: String {
        switch self {
        case let .local(block): "local-\(block.id)"
        case let .external(event): "external-\(event.id)"
        }
    }

    var startAt: Date {
        switch self {
        case let .local(block): block.startAt ?? .distantPast
        case let .external(event): event.startAt
        }
    }

    var isAllDay: Bool {
        switch self {
        case let .local(block): block.startAt == nil
        case let .external(event): event.isAllDay
        }
    }
}

private struct ScheduleAgendaPanel: View {
    let cockpit: WeeklyScheduleCockpit
    let externalEvents: [ExternalScheduleEvent]
    let openBlock: (WeeklyScheduleBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Schedule", systemImage: "list.bullet")
                .font(.headline)

            if agendaDays.isEmpty {
                Text("No schedule blocks this week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(agendaDays) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dayLabel(day.date))
                            .font(.subheadline.weight(.semibold))
                        ForEach(agendaItems(for: day)) { item in
                            switch item {
                            case let .local(block):
                                Button { openBlock(block) } label: {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: SuisuiRadius.control)
                                            .fill(block.source == .scheduleDraft ? SuisuiTone.caution.color : SuisuiBrand.soloBlue)
                                            .frame(width: 4, height: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(block.task.title)
                                                .font(.caption.weight(.semibold))
                                            Text("\(block.timeLabel) · \(block.projectTitle)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                    }
                                    .padding(8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(block.startAt == nil)
                                .accessibilityIdentifier("schedule-agenda-block-\(block.id)")
                            case let .external(event):
                                ExternalScheduleAgendaEvent(event: event)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-agenda")
    }

    private var agendaDays: [WeeklyScheduleDay] {
        cockpit.days.filter { agendaItems(for: $0).isEmpty == false }
    }

    private func agendaItems(for day: WeeklyScheduleDay) -> [ScheduleAgendaItem] {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        guard let interval = calendar.dateInterval(of: .day, for: day.date) else {
            return day.blocks.map(ScheduleAgendaItem.local)
        }
        let externalItems = externalEvents
            .filter {
                ScheduleTimelineGeometry.eventOccurs(
                    $0,
                    on: day.dateKey,
                    during: interval.start..<interval.end
                )
            }
            .map(ScheduleAgendaItem.external)
        return (day.blocks.map(ScheduleAgendaItem.local) + externalItems).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.startAt < rhs.startAt
        }
    }

    private func dayLabel(_ date: Date) -> String {
        SuisuiTimestampDisplay.weekdayAndDay(
            date,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
            locale: localizedDisplayLocale()
        )
    }

}

private struct ExternalScheduleAgendaEvent: View {
    let event: ExternalScheduleEvent
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: SuisuiRadius.control)
                    .fill(SuisuiBrand.soloBlue)
                    .frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                    Text("\(externalScheduleEventDateLabel(event)) · \(String(localized: "Google Calendar"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(SuisuiBrand.soloBlue.opacity(0.06), in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsDetails) {
            ExternalScheduleEventDetails(event: event)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-agenda-external-event-\(event.id)")
        .accessibilityHint("Shows read-only event details.")
    }
}

private func externalScheduleEventDateLabel(_ event: ExternalScheduleEvent) -> String {
    let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
    let locale = localizedDisplayLocale()
    if event.isAllDay {
        let start = event.allDayStartDateKey.flatMap(scheduleDate(from:)) ?? event.startAt
        let exclusiveEnd = event.allDayEndDateKey.flatMap(scheduleDate(from:)) ?? event.endAt
        let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? start
        let startLabel = SuisuiTimestampDisplay.weekdayAndDay(start, calendar: calendar, locale: locale)
        let endLabel = SuisuiTimestampDisplay.weekdayAndDay(inclusiveEnd, calendar: calendar, locale: locale)
        let range = calendar.isDate(start, inSameDayAs: inclusiveEnd) ? startLabel : "\(startLabel)–\(endLabel)"
        return "\(range) · \(String(localized: "All day"))"
    }
    let day = SuisuiTimestampDisplay.weekdayAndDay(event.startAt, calendar: calendar, locale: locale)
    let start = SuisuiTimestampDisplay.time(event.startAt, calendar: calendar, locale: locale)
    let end = SuisuiTimestampDisplay.time(event.endAt, calendar: calendar, locale: locale)
    return "\(day) \(start)–\(end)"
}

private func scheduleDate(from dateKey: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = formatter.calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: dateKey)
}

private struct ScheduleAdjustmentPanel: View {
    let cockpit: WeeklyScheduleCockpit
    let itemLimit: Int
    let selectDay: (WeeklyScheduleDay) -> Void

    private var daysNeedingAttention: [WeeklyScheduleDay] {
        cockpit.days
            .filter { $0.workload.blockedTaskCount > 0 || $0.workload.overdueTaskCount > 0 }
    }

    private var visibleDaysNeedingAttention: [WeeklyScheduleDay] {
        daysNeedingAttention
            .prefix(itemLimit)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Needs Adjustment", systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(daysNeedingAttention.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(SuisuiTone.danger.color)
            }

            if daysNeedingAttention.isEmpty {
                Text("No schedule conflicts need attention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleDaysNeedingAttention) { day in
                    Button { selectDay(day) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: day.workload.overdueTaskCount > 0 ? "clock.badge.exclamationmark" : "pause.circle")
                                .foregroundStyle(day.workload.overdueTaskCount > 0 ? SuisuiTone.danger.color : SuisuiTone.caution.color)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dayLabel(day.date))
                                    .font(.caption.weight(.semibold))
                                Text(issueLabel(for: day))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(
                            (day.workload.overdueTaskCount > 0 ? SuisuiTone.danger.color : SuisuiTone.caution.color).opacity(0.09),
                            in: RoundedRectangle(cornerRadius: SuisuiRadius.control)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Shows this day in the calendar grid.")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(SuisuiBorder.subtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-adjustments")
    }

    private func dayLabel(_ date: Date) -> String {
        SuisuiTimestampDisplay.weekdayAndDay(
            date,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
            locale: localizedDisplayLocale()
        )
    }

    private func issueLabel(for day: WeeklyScheduleDay) -> String {
        if day.workload.overdueTaskCount > 0 {
            return String(format: String(localized: "%d overdue tasks"), day.workload.overdueTaskCount)
        }
        return String(format: String(localized: "%d blocked tasks"), day.workload.blockedTaskCount)
    }
}

private struct ScheduleAvailabilitySlot: Identifiable {
    let day: Date
    let start: Date
    let end: Date

    var id: Date { start }
}

private struct ScheduleAvailabilityPanel: View {
    let cockpit: WeeklyScheduleCockpit
    let externalEvents: [ExternalScheduleEvent]
    let externalEventLoadState: ExternalScheduleEventLoadState
    let referenceDate: Date
    let itemLimit: Int
    let selectTimeRange: (Date, Date) -> Void

    private var availableSlots: [ScheduleAvailabilitySlot] {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        return cockpit.days.flatMap { day in
            availability(on: day, calendar: calendar)
        }
        .prefix(itemLimit)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Available Time", systemImage: "clock")
                .font(.subheadline.weight(.semibold))

            Text(availabilitySourceLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if availableSlots.isEmpty {
                Text("No open one-hour windows this week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableSlots) { slot in
                    Button { selectTimeRange(slot.start, slot.end) } label: {
                        HStack(spacing: 8) {
                            Text("\(dayLabel(slot.day))  \(timeLabel(slot.start))–\(timeLabel(slot.end))")
                                .font(.caption.weight(.medium))
                            Spacer(minLength: 4)
                            Text(durationLabel(slot))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "plus.circle")
                                .foregroundStyle(SuisuiBrand.soloBlue)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("schedule-availability-slot-\(slot.id.timeIntervalSince1970)")
                    .accessibilityHint("Opens a reviewable schedule draft for this available time.")
                    if slot.id != availableSlots.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(SuisuiBorder.subtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-availability")
    }

    private func availability(on day: WeeklyScheduleDay, calendar: Calendar) -> [ScheduleAvailabilitySlot] {
        guard let workdayStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day.date),
              let workdayEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day.date) else {
            return []
        }
        let nextHour = calendar.dateInterval(of: .hour, for: referenceDate)?.end ?? referenceDate
        let availableStart = max(workdayStart, nextHour)
        guard availableStart < workdayEnd else {
            return []
        }
        let localOccupied = day.blocks.compactMap { block -> DateInterval? in
            guard let start = block.startAt, let end = block.endAt, end > availableStart, start < workdayEnd else {
                return nil
            }
            return DateInterval(start: max(start, availableStart), end: min(end, workdayEnd))
        }
        let externalOccupied = externalEvents.compactMap { event -> DateInterval? in
            guard event.blocksAvailability else {
                return nil
            }
            if event.isAllDay,
               ScheduleTimelineGeometry.allDayEvent(
                   event,
                   occursOn: day.dateKey,
                   fallback: workdayStart..<workdayEnd
               ) {
                return DateInterval(start: availableStart, end: workdayEnd)
            }
            guard event.isAllDay == false,
                  event.endAt > availableStart,
                  event.startAt < workdayEnd else {
                return nil
            }
            return DateInterval(start: max(event.startAt, availableStart), end: min(event.endAt, workdayEnd))
        }
        let occupied = (localOccupied + externalOccupied)
        .sorted { $0.start < $1.start }

        var cursor = availableStart
        var slots: [ScheduleAvailabilitySlot] = []
        for interval in occupied {
            if interval.start.timeIntervalSince(cursor) >= 3_600 {
                slots.append(ScheduleAvailabilitySlot(day: day.date, start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if workdayEnd.timeIntervalSince(cursor) >= 3_600 {
            slots.append(ScheduleAvailabilitySlot(day: day.date, start: cursor, end: workdayEnd))
        }
        return slots
    }

    private var availabilitySourceLabel: String {
        switch externalEventLoadState {
        case .loaded:
            String(localized: "Includes Google Calendar events.")
        case .loading:
            String(localized: "Checking Google Calendar…")
        case .failed:
            String(localized: "Google Calendar is unavailable. Showing local tasks only.")
        case .unavailable:
            String(localized: "Connect Google Calendar to include external events.")
        }
    }

    private func dayLabel(_ date: Date) -> String {
        SuisuiTimestampDisplay.weekdayAndDay(
            date,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
            locale: localizedDisplayLocale()
        )
    }

    private func timeLabel(_ date: Date) -> String {
        SuisuiTimestampDisplay.time(
            date,
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
            locale: localizedDisplayLocale()
        )
    }

    private func durationLabel(_ slot: ScheduleAvailabilitySlot) -> String {
        let hours = slot.end.timeIntervalSince(slot.start) / 3_600
        if hours.rounded() == hours {
            return String(format: String(localized: "%d h"), Int(hours))
        }
        return String(format: String(localized: "%.1f h"), hours)
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

            Text(day.loadLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("schedule-workload-load-label-\(day.dateKey)")

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

private struct ScheduleQuickDraftComposer: View {
    let selection: ScheduleQuickDraftSelection
    let tasks: [ProjectBoardTask]
    let save: (Int64, Date, Date) -> Void
    let remove: (Int64, Date) -> Void

    @State private var selectedTaskID: Int64?
    @State private var startAt: Date
    @State private var endAt: Date

    init(
        selection: ScheduleQuickDraftSelection,
        tasks: [ProjectBoardTask],
        save: @escaping (Int64, Date, Date) -> Void,
        remove: @escaping (Int64, Date) -> Void
    ) {
        self.selection = selection
        self.tasks = tasks
        self.save = save
        self.remove = remove
        _selectedTaskID = State(initialValue: selection.taskID ?? tasks.first?.id)
        _startAt = State(initialValue: selection.startAt)
        _endAt = State(initialValue: selection.endAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(selection.isExistingDraft ? "Edit Schedule Draft" : "Add to Schedule Draft", systemImage: "calendar.badge.plus")
                .font(.headline)

            if tasks.isEmpty {
                Text("Create an active task before placing work on the calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Task", selection: $selectedTaskID) {
                    ForEach(tasks) { task in
                        Text(task.title).tag(Optional(task.id))
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Task")
            }

            DatePicker("Starts", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
            DatePicker("Ends", selection: $endAt, in: startAt..., displayedComponents: [.date, .hourAndMinute])

            HStack(spacing: 8) {
                ForEach([30, 60, 90], id: \.self) { minutes in
                    Button(String(format: String(localized: "%d min"), minutes)) {
                        endAt = startAt.addingTimeInterval(TimeInterval(minutes * 60))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Duration")

            Divider()

            HStack {
                if selection.isExistingDraft, let taskID = selection.taskID {
                    Button(role: .destructive) {
                        remove(taskID, startAt)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .accessibilityIdentifier("schedule-quick-draft-remove")
                }
                Spacer()
                Button(selection.isExistingDraft ? "Save" : "Add to Draft") {
                    guard let selectedTaskID else { return }
                    save(selectedTaskID, startAt, endAt)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedTaskID == nil || endAt <= startAt)
                .accessibilityIdentifier("schedule-quick-draft-save")
            }

            Label("Calendar is updated only after review in Assistant Queue.", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-quick-draft-composer")
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

private struct ScheduleSuggestionsPanel: View {
    let tasks: [ProjectBoardTask]
    let applyResult: ScheduleApplyResult?
    let itemLimit: Int
    let suggestTask: (ProjectBoardTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Today's Suggestions", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            if tasks.isEmpty {
                Text("No unscheduled tasks to suggest today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks.prefix(itemLimit)) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(SuisuiBrand.soloBlue)
                                .accessibilityHidden(true)
                            Text(task.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .accessibilityIdentifier("schedule-unscheduled-task-\(task.id)")
                            Spacer(minLength: 0)
                        }
                        Text(suggestionReason(for: task))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button {
                            suggestTask(task)
                        } label: {
                            Label("Add", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("schedule-unscheduled-add-draft-\(task.id)")
                        .accessibilityLabel(String(format: String(localized: "Add %@ to Draft"), task.title))
                        .accessibilityHint("Opens a reviewable time selection without writing Calendar.")
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SuisuiSurface.assistantSignal, in: RoundedRectangle(cornerRadius: SuisuiRadius.control))
                    .accessibilityElement(children: .contain)
                }
            }
            ScheduleStatusBanner(result: applyResult)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: SuisuiRadius.card)
                .stroke(SuisuiBorder.subtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-suggestions")
    }

    private func suggestionReason(for task: ProjectBoardTask) -> String {
        if task.status == .blocked {
            return String(localized: "Blocked work needs a local slot before more planning.")
        }
        if task.priority == .high {
            return String(localized: "High-priority open work is still unscheduled.")
        }
        return String(localized: "This open task has not been placed on the calendar yet.")
    }
}

private struct ScheduleStatusBanner: View {
    let result: ScheduleApplyResult?

    var body: some View {
        let label = message
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(label)
            Spacer(minLength: 0)
        }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
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
