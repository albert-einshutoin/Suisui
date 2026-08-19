import Foundation
import SuisuiCore
import SwiftUI

enum TodayDashboardLayoutMetrics {
    // Main needs room for task metadata and rail needs room for assistant actions.
    static let primaryMinimumWidth: CGFloat = 480
    static let railMinimumWidth = CGFloat(CockpitLayoutPolicy.railWidth)
    static let columnSpacing = CGFloat(CockpitLayoutPolicy.splitSpacing)
    static let sectionSpacing = SuisuiSpacing.lg
    static let widgetSpacing = SuisuiSpacing.md
    static let railWidgetMinHeight: CGFloat = 168
    static let recommendationCardMinHeight: CGFloat = 102
    static let horizontalInsets: CGFloat = 18
    // 900pt windows leave 864pt after the dashboard's horizontal insets.
    static let compactRailCardsMinimumWidth: CGFloat = 864
    static let twoColumnMinimumWidth = primaryMinimumWidth + railMinimumWidth + columnSpacing

    static func isWide(availableWidth: CGFloat) -> Bool {
        CockpitLayoutPolicy.presentsSplitRail(contentWidth: Double(availableWidth))
    }
}

extension View {
    /// Today uses a denser dashboard card than other product surfaces. Keeping
    /// this treatment local avoids changing established cards elsewhere while
    /// preserving one shared border, inset, and elevation across the dashboard.
    func todayDashboardCard() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(SuisuiSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SuisuiSurface.groupedContent)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SuisuiBorder.subtle.opacity(0.72), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.045), radius: 5, y: 2)
    }

    func todayDashboardFillRow() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TodayDashboardView<CatchUpContent: View>: View {
    let snapshot: TodayWorkflowSnapshot
    let schedule: ProjectBoardScheduleReadModel
    let projectTitlesByTaskID: [Int64: String]
    @ObservedObject var viewModel: TodayFeatureViewModel
    @Binding var commandTitle: String
    let displayName: String
    let dailyCapacityMinutes: Int
    let weatherState: TodayWeatherState
    let integrationsState: TodayIntegrationStates
    let selectTodayTask: (ProjectBoardTask) -> Void
    let openInspectorForTodayRailTask: (Int64) -> Void
    let playDailyPlanningReadout: () -> Void
    let openCatchUp: () -> Void
    @ViewBuilder let catchUpContent: () -> CatchUpContent
    @AccessibilityFocusState private var isReviewFocused: Bool
    @AccessibilityFocusState private var isReviewActionsFocused: Bool
    @State private var focusTaskPendingReplacement: Int64?
    @State private var isWideReviewActionsExpanded = true
    private func makeDashboard(now: Date, calendar: Calendar, locale: Locale) -> TodayDashboardSnapshot {
        TodayDashboardSnapshotBuilder.make(
            today: snapshot,
            schedule: schedule,
            projectTitlesByTaskID: projectTitlesByTaskID,
            displayName: displayName,
            dailyCapacityMinutes: dailyCapacityMinutes,
            now: now,
            calendar: calendar,
            locale: locale,
            weatherState: weatherState,
            integrationsState: integrationsState,
            catchUpCount: viewModel.catchUpCount
        )
    }

    var body: some View {
        let dashboard = makeDashboard(
            now: VisualEvidenceRuntimeContext.referenceDate(),
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
            locale: localizedDisplayLocale()
        )
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    let availableWidth = proxy.size.width
                    let isWide = TodayDashboardLayoutMetrics.isWide(availableWidth: availableWidth)
                    let presentsCompactRailCardsHorizontally = !isWide && availableWidth >= TodayDashboardLayoutMetrics.compactRailCardsMinimumWidth
                    let openReview = {
                        // These summaries come from Today planning and Catch Up,
                        // so keep users in that workflow instead of routing to the
                        // unrelated global Review overview.
                        withAnimation {
                            scrollProxy.scrollTo("today-review-actions", anchor: .top)
                        }
                        DispatchQueue.main.async {
                            isReviewActionsFocused = true
                        }
                    }
                    VStack(alignment: .leading, spacing: TodayDashboardLayoutMetrics.sectionSpacing) {
                        TodayDashboardHeaderView(header: dashboard.header, weather: dashboard.weather)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        if isWide {
                            wideBoard(dashboard: dashboard, openReview: openReview)
                        } else {
                            mainContent(dashboard: dashboard, isWide: isWide, openReview: openReview)
                            reviewActionsCard(isWide: false)
                            rail(
                                dashboard: dashboard,
                                presentsCardsHorizontally: presentsCompactRailCardsHorizontally,
                                showsSecondaryIntegrations: isWide,
                                availableWidth: isWide ? TodayDashboardLayoutMetrics.railMinimumWidth : availableWidth
                            )
                            .frame(
                                width: isWide ? TodayDashboardLayoutMetrics.railMinimumWidth : availableWidth,
                                alignment: .topLeading
                            )
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today-briefing-panel")
                    .accessibilityLabel("Today briefing")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
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
    }

    private func wideBoard(
        dashboard: TodayDashboardSnapshot,
        openReview: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: TodayDashboardLayoutMetrics.widgetSpacing) {
            TodayDashboardAlignedRow {
                TodayDashboardRecommendationCards(
                    recommendations: dashboard.recommendations,
                    onAction: performRecommendationAction
                )
            } rail: {
                TodayWorkloadCard(workload: dashboard.workload)
            }
            TodayDashboardAlignedRow {
                taskList(dashboard: dashboard, isWide: true)
            } rail: {
                focusCard(dashboard: dashboard)
            }
            HStack(alignment: .top, spacing: TodayDashboardLayoutMetrics.columnSpacing) {
                TodayDashboardWeeklyScheduleCard(schedule: dashboard.weeklySchedule)
                    .todayDashboardFillRow()
                TodayDashboardReviewCard(
                    review: dashboard.review,
                    externalActivity: dashboard.externalActivity,
                    openReview: openReview
                )
                .accessibilityFocused($isReviewFocused)
                .todayDashboardFillRow()
                TodayAssistantCard(
                    assistantContext: snapshot.assistantContext,
                    viewModel: viewModel,
                    commandTitle: $commandTitle,
                    openInspector: openInspectorForTodayRailTask
                )
                .frame(width: TodayDashboardLayoutMetrics.railMinimumWidth)
                .todayDashboardFillRow()
            }
            reviewActionsCard(isWide: true)
            HStack(alignment: .top, spacing: TodayDashboardLayoutMetrics.columnSpacing) {
                TodayIntegrationCard(integration: dashboard.integrations.calendar)
                    .todayDashboardFillRow()
                TodayIntegrationCard(integration: dashboard.integrations.slack)
                    .todayDashboardFillRow()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func mainContent(
        dashboard: TodayDashboardSnapshot,
        isWide: Bool,
        openReview: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
            TodayDashboardRecommendationCards(
                recommendations: dashboard.recommendations,
                onAction: performRecommendationAction
            )
            taskList(dashboard: dashboard, isWide: isWide)
            TodayDashboardWeeklyScheduleCard(schedule: dashboard.weeklySchedule)
            TodayDashboardReviewCard(
                review: dashboard.review,
                externalActivity: dashboard.externalActivity,
                openReview: openReview
            )
            .accessibilityFocused($isReviewFocused)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func taskList(dashboard: TodayDashboardSnapshot, isWide: Bool) -> some View {
        TodayDashboardTaskListView(
            tasks: snapshot.plan.tasks,
            rows: dashboard.tasks,
            selectedTaskID: viewModel.selectedTaskID,
            isWide: isWide,
            toggleCompletion: viewModel.toggleTaskCompletion,
            selectTask: selectTodayTask,
            addTask: {
                commandTitle = String(localized: "New task: ")
                isReviewFocused = true
            }
        )
    }

    private func focusCard(dashboard: TodayDashboardSnapshot) -> some View {
        TodayFocusCard(
            session: viewModel.focusSession,
            tasks: dashboard.tasks,
            suggestedTaskID: dashboard.recommendation?.taskID,
            startFocusSession: viewModel.startFocusSession,
            openInspector: openInspectorForTodayRailTask
        )
    }

    private func reviewActionsCard(isWide: Bool) -> some View {
        Group {
            if isWide {
                DisclosureGroup(isExpanded: $isWideReviewActionsExpanded) {
                    reviewActionsContent
                } label: {
                    Label("Planning & commands", systemImage: "checklist")
                        .font(SuisuiTypography.sectionTitle)
                }
            } else {
                VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
                    Label("Review actions", systemImage: "checklist")
                        .font(SuisuiTypography.sectionTitle)
                    reviewActionsContent
                }
            }
        }
        .todayDashboardCard()
        .id("today-review-actions")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-review-actions")
        .accessibilityFocused($isReviewActionsFocused)
    }

    private var reviewActionsContent: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            TodayCommandPanel(
                commandTitle: $commandTitle,
                plan: snapshot.plan,
                recommendationChips: snapshot.recommendationChips,
                viewModel: viewModel,
                dailyPlanningReview: viewModel.dailyPlanningReview ?? snapshot.dailyPlanningReviewPreview,
                playDailyPlanningReadout: playDailyPlanningReadout
            )
            TodaySuggestionPanel(plan: snapshot.plan, viewModel: viewModel)
            catchUpContent()
        }
    }

    private func performRecommendationAction(_ recommendation: TodayRecommendation) {
        guard let taskID = recommendation.taskID else {
            switch recommendation.action {
            case .addTask:
                commandTitle = String(localized: "New task: ")
                isReviewFocused = true
            case .openCatchUp:
                openCatchUp()
            case .suggestBreak:
                viewModel.suggestBreak()
                isReviewFocused = true
            case .startFocus, .selectTask, .openReview, .prepareScheduleDraft:
                break
            }
            return
        }
        switch recommendation.action {
        case .startFocus:
            if case .failure(.requiresReplacement) = viewModel.startFocusSession(taskID: taskID) {
                focusTaskPendingReplacement = taskID
            }
        case .selectTask:
            viewModel.selectTask(id: taskID)
        case .openReview:
            viewModel.selectTask(id: taskID)
            DispatchQueue.main.async {
                isReviewFocused = true
            }
        case .prepareScheduleDraft:
            _ = viewModel.addUnscheduledTaskToScheduleDraft(taskID: taskID)
        case .addTask, .openCatchUp, .suggestBreak:
            break
        }
    }

    private func rail(
        dashboard: TodayDashboardSnapshot,
        presentsCardsHorizontally: Bool,
        showsSecondaryIntegrations: Bool,
        availableWidth: CGFloat
    ) -> some View {
        TodayDashboardRailView(
            dashboard: dashboard,
            assistantContext: snapshot.assistantContext,
            viewModel: viewModel,
            commandTitle: $commandTitle,
            openInspector: openInspectorForTodayRailTask,
            presentsCardsHorizontally: presentsCardsHorizontally,
            showsSecondaryIntegrations: showsSecondaryIntegrations,
            availableWidth: availableWidth
        )
    }
}

private struct TodayDashboardAlignedRow<Primary: View, Rail: View>: View {
    let primary: Primary
    let railContent: Rail

    init(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder rail: () -> Rail
    ) {
        self.primary = primary()
        self.railContent = rail()
    }

    var body: some View {
        HStack(alignment: .top, spacing: TodayDashboardLayoutMetrics.columnSpacing) {
            primary
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            railContent
                .frame(width: TodayDashboardLayoutMetrics.railMinimumWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
