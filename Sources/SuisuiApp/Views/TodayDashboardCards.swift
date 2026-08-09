import SuisuiCore
import SwiftUI

struct TodayDashboardRecommendationCards: View {
    let recommendations: [TodayRecommendation]
    let onAction: (TodayRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Recommendations", systemImage: "sparkles")
                .font(SuisuiTypography.sectionTitle)
            HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                ForEach(recommendations, id: \.taskID) { recommendation in
                    Button {
                        onAction(recommendation)
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
                    .accessibilityHint(recommendation.taskID == nil ? "No focus task is available." : "Selects this task without changing task status or Calendar.")
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
            Text(localizedCount(schedule.scheduledTaskCount, one: "%d task scheduled", other: "%d tasks scheduled"))
                .font(.headline.monospacedDigit())
            Text(localizedCount(schedule.unscheduledTaskCount, one: "%d task needs scheduling", other: "%d tasks need scheduling"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .soloCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-weekly-schedule-card")
        .accessibilityLabel(String(format: String(localized: "This Week: %@"), localizedCount(schedule.scheduledTaskCount, one: "%d task scheduled", other: "%d tasks scheduled")))
        .accessibilityValue(localizedCount(schedule.unscheduledTaskCount, one: "%d task needs scheduling", other: "%d tasks need scheduling"))
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
