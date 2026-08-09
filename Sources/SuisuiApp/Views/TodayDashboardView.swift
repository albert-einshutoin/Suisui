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
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private func makeDashboard(now: Date) -> TodayDashboardSnapshot {
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
        let dashboard = makeDashboard(now: Date())
        GeometryReader { proxy in
            ScrollView(.vertical) {
                Group {
                    if proxy.size.width - TodayDashboardLayoutMetrics.horizontalInsets >= TodayDashboardLayoutMetrics.twoColumnMinimumWidth {
                        HStack(alignment: .top, spacing: TodayDashboardLayoutMetrics.columnSpacing) {
                            mainContent(dashboard: dashboard)
                                .frame(minWidth: TodayDashboardLayoutMetrics.primaryMinimumWidth, maxWidth: .infinity, alignment: .topLeading)
                            rail(dashboard: dashboard)
                                .frame(width: TodayDashboardLayoutMetrics.railMinimumWidth)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
                            mainContent(dashboard: dashboard)
                            rail(dashboard: dashboard)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func mainContent(dashboard: TodayDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
            TodayDashboardHeaderView(header: dashboard.header)
            TodayDashboardRecommendationCards(
                recommendations: dashboard.recommendations,
                startFocus: viewModel.startFocus
            )
            TodayDashboardTaskListView(
                tasks: snapshot.plan.tasks,
                rows: dashboard.tasks,
                selectedTaskID: viewModel.selectedTaskID,
                toggleCompletion: viewModel.toggleTaskCompletion,
                selectTask: selectTodayTask
            )
            TodayDashboardWeeklyScheduleCard(schedule: dashboard.weeklySchedule)
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
