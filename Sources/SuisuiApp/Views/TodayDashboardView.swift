import Foundation
import SuisuiCore
import SwiftUI

enum TodayDashboardLayoutMetrics {
    // Main needs room for task metadata and rail needs room for assistant actions.
    static let primaryMinimumWidth: CGFloat = 680
    static let railMinimumWidth: CGFloat = 320
    static let columnSpacing: CGFloat = 16
    static let horizontalInsets: CGFloat = 36
    static let twoColumnMinimumWidth = primaryMinimumWidth + railMinimumWidth + columnSpacing
}

struct TodayDashboardView<CatchUpContent: View>: View {
    let snapshot: TodayWorkflowSnapshot
    let schedule: ProjectBoardScheduleReadModel
    let projectTitlesByTaskID: [Int64: String]
    @ObservedObject var viewModel: TodayFeatureViewModel
    @Binding var commandTitle: String
    let displayName: String
    let dailyCapacityMinutes: Int
    let selectTodayTask: (ProjectBoardTask) -> Void
    let openInspectorForTodayRailTask: (Int64) -> Void
    let playDailyPlanningReadout: () -> Void
    @ViewBuilder let catchUpContent: () -> CatchUpContent
    private func makeDashboard(now: Date, calendar: Calendar, locale: Locale) -> TodayDashboardSnapshot {
        TodayDashboardSnapshotBuilder.make(
            today: snapshot,
            schedule: schedule,
            projectTitlesByTaskID: projectTitlesByTaskID,
            displayName: displayName,
            dailyCapacityMinutes: dailyCapacityMinutes,
            now: now,
            calendar: calendar,
            locale: locale
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
                let isWide = proxy.size.width - TodayDashboardLayoutMetrics.horizontalInsets >= TodayDashboardLayoutMetrics.twoColumnMinimumWidth
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
                    rail(dashboard: dashboard)
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
            TodayDashboardHeaderView(header: dashboard.header)
            TodayDashboardRecommendationCards(
                recommendations: dashboard.recommendations,
                selectTaskID: viewModel.selectTask
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func rail(dashboard: TodayDashboardSnapshot) -> some View {
        TodayDashboardRailView(
            dashboard: dashboard,
            assistantContext: snapshot.assistantContext,
            viewModel: viewModel,
            commandTitle: $commandTitle,
            openInspector: openInspectorForTodayRailTask
        )
    }
}
