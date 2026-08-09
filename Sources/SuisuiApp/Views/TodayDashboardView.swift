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

    private var dashboard: TodayDashboardSnapshot {
        TodayDashboardSnapshotBuilder.make(
            today: snapshot,
            schedule: schedule,
            projectTitlesByTaskID: projectTitlesByTaskID,
            displayName: displayName,
            dailyCapacityMinutes: dailyCapacityMinutes,
            now: Date(),
            calendar: calendar,
            locale: locale
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                Group {
                    if proxy.size.width - TodayDashboardLayoutMetrics.horizontalInsets >= TodayDashboardLayoutMetrics.twoColumnMinimumWidth {
                        HStack(alignment: .top, spacing: TodayDashboardLayoutMetrics.columnSpacing) {
                            mainContent
                                .frame(minWidth: TodayDashboardLayoutMetrics.primaryMinimumWidth, maxWidth: .infinity, alignment: .topLeading)
                            rail
                                .frame(width: TodayDashboardLayoutMetrics.railMinimumWidth)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
                            mainContent
                            rail
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
            TodayDashboardHeaderView(header: dashboard.header)
            TodayDashboardRecommendationCards(
                recommendation: dashboard.recommendation,
                chips: snapshot.recommendationChips,
                tasks: dashboard.tasks,
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

    private var rail: some View {
        TodayDashboardRailView(
            dashboard: dashboard,
            assistantContext: snapshot.assistantContext,
            viewModel: viewModel,
            commandTitle: $commandTitle,
            openInspector: openInspectorForTodayRailTask
        )
    }
}
