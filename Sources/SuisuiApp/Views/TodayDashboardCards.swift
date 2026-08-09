import SuisuiCore
import SwiftUI

struct TodayDashboardRecommendationCards: View {
    let recommendations: [TodayRecommendation]
    let startFocus: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Recommendations", systemImage: "sparkles")
                .font(SuisuiTypography.sectionTitle)
            HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                ForEach(recommendations, id: \.taskID) { recommendation in
                    Button {
                        if let taskID = recommendation.taskID { startFocus(taskID) }
                    } label: {
                        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(SuisuiBrand.soloBlue)
                            Text(recommendation.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(recommendation.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .disabled(recommendation.taskID == nil)
                    .soloCard()
                    .accessibilityLabel(String(format: String(localized: "Recommendation: %@. %@"), recommendation.title, recommendation.reason))
                    .accessibilityHint(recommendation.taskID == nil ? "No focus task is available." : "Starts local focus without changing task status or Calendar.")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-recommendations")
    }
}

struct TodayDashboardWeeklyScheduleCard: View {
    let schedule: TodayWeeklyScheduleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("This Week", systemImage: "calendar")
                .font(SuisuiTypography.sectionTitle)
            Text(String(format: String(localized: "%d tasks scheduled"), schedule.scheduledTaskCount))
                .font(.headline.monospacedDigit())
            Text(String(format: String(localized: "%d tasks need scheduling"), schedule.unscheduledTaskCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .soloCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-weekly-schedule-card")
        .accessibilityLabel(String(format: String(localized: "This Week: %d scheduled"), schedule.scheduledTaskCount))
        .accessibilityValue(String(format: String(localized: "%d tasks need scheduling"), schedule.unscheduledTaskCount))
    }
}

struct TodayDashboardReviewCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            Label("Review", systemImage: "checklist")
                .font(SuisuiTypography.sectionTitle)
            content()
        }
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-review-card")
    }
}
