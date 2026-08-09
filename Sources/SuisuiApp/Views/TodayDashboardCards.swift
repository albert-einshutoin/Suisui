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
                    .accessibilityHint(accessibilityHint(for: recommendation))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-recommendations")
    }

    private func accessibilityHint(for recommendation: TodayRecommendation) -> String {
        guard recommendation.taskID != nil else {
            return String(localized: "No focus task is available.")
        }

        switch recommendation.action {
        case .startFocus:
            return String(localized: "Starts local focus without changing task status or Calendar.")
        case .openReview:
            return String(localized: "Selects this task and moves to the Daily Planning Review without changing task status or Calendar.")
        case .prepareScheduleDraft:
            return String(localized: "Adds this task to the local schedule draft without writing Calendar.")
        case .selectTask:
            return String(localized: "Selects this task without changing task status or Calendar.")
        }
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
            if !schedule.rows.isEmpty {
                Divider()
                ForEach(schedule.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: SuisuiSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.dateLabel)
                                .font(.caption.weight(.semibold))
                            Text(row.timeLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 86, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            if let durationMinutes = row.durationMinutes {
                                Text(localizedDurationMinutes(durationMinutes))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        [row.dateLabel, row.timeLabel, row.title]
                            .compactMap { $0.isEmpty ? nil : $0 }
                            .joined(separator: ". ")
                    )
                    .accessibilityValue(
                        row.durationMinutes.map(localizedDurationMinutes) ?? ""
                    )
                    .accessibilityIdentifier("today-weekly-schedule-row-\(row.id)")
                }
            }
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
