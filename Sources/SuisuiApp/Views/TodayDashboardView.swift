import Foundation
import SuisuiCore
import SwiftUI

enum TodayDashboardLayoutMetrics {
    // Main needs room for task metadata and rail needs room for assistant actions.
    static let primaryMinimumWidth: CGFloat = 840
    static let railMinimumWidth: CGFloat = 320
    static let columnSpacing: CGFloat = 16
    static let horizontalInsets: CGFloat = 36
    // 900pt windows leave 864pt after the dashboard's horizontal insets.
    static let compactRailCardsMinimumWidth: CGFloat = 864
    static let twoColumnMinimumWidth = primaryMinimumWidth + railMinimumWidth + columnSpacing

    static func isWide(availableWidth: CGFloat) -> Bool {
        availableWidth >= twoColumnMinimumWidth
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
    @ViewBuilder let catchUpContent: () -> CatchUpContent
    @AccessibilityFocusState private var isReviewFocused: Bool
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
            integrationsState: integrationsState
        )
    }

    var body: some View {
        let dashboard = makeDashboard(
            now: VisualEvidenceRuntimeContext.referenceDate(),
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
            locale: localizedDisplayLocale()
        )
        GeometryReader { proxy in
            ScrollView(.vertical) {
                let availableWidth = proxy.size.width - TodayDashboardLayoutMetrics.horizontalInsets
                let isWide = TodayDashboardLayoutMetrics.isWide(availableWidth: availableWidth)
                let presentsCompactRailCardsHorizontally = !isWide && availableWidth >= TodayDashboardLayoutMetrics.compactRailCardsMinimumWidth
                let layout: AnyLayout = isWide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: TodayDashboardLayoutMetrics.columnSpacing))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: SuisuiSpacing.lg))
                layout {
                    mainContent(dashboard: dashboard, isWide: isWide)
                        .frame(
                            minWidth: isWide ? TodayDashboardLayoutMetrics.primaryMinimumWidth : nil,
                            maxWidth: .infinity,
                            alignment: .topLeading
                        )
                    rail(dashboard: dashboard, presentsCardsHorizontally: presentsCompactRailCardsHorizontally)
                        .frame(width: isWide ? TodayDashboardLayoutMetrics.railMinimumWidth : nil)
                    }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func mainContent(dashboard: TodayDashboardSnapshot, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
            TodayDashboardHeaderView(header: dashboard.header, weather: dashboard.weather)
            TodayDashboardRecommendationCards(
                recommendations: dashboard.recommendations,
                onAction: performRecommendationAction
            )
            TodayDashboardTaskListView(
                tasks: snapshot.plan.tasks,
                rows: dashboard.tasks,
                selectedTaskID: viewModel.selectedTaskID,
                toggleCompletion: viewModel.toggleTaskCompletion,
                selectTask: selectTodayTask
            )
            let lowerLayout: AnyLayout = isWide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: SuisuiSpacing.lg))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: SuisuiSpacing.lg))
            lowerLayout {
                TodayDashboardWeeklyScheduleCard(schedule: dashboard.weeklySchedule)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                TodayDashboardReviewCard {
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityFocused($isReviewFocused)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func performRecommendationAction(_ recommendation: TodayRecommendation) {
        guard let taskID = recommendation.taskID else { return }
        switch recommendation.action {
        case .startFocus:
            viewModel.startFocus(taskID: taskID)
        case .selectTask:
            viewModel.selectTask(id: taskID)
        case .openReview:
            viewModel.selectTask(id: taskID)
            DispatchQueue.main.async {
                isReviewFocused = true
            }
        case .prepareScheduleDraft:
            _ = viewModel.addUnscheduledTaskToScheduleDraft(taskID: taskID)
        }
    }

    private func rail(dashboard: TodayDashboardSnapshot, presentsCardsHorizontally: Bool) -> some View {
        TodayDashboardRailView(
            dashboard: dashboard,
            assistantContext: snapshot.assistantContext,
            viewModel: viewModel,
            commandTitle: $commandTitle,
            openInspector: openInspectorForTodayRailTask,
            presentsCardsHorizontally: presentsCardsHorizontally
        )
    }
}
