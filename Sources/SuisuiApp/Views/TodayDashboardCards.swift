import SuisuiCore
import SwiftUI

struct TodayDashboardRecommendationCards: View {
    private typealias Card = (title: String, reason: String, taskID: Int64?, systemImage: String)

    let recommendation: TodayRecommendation
    let chips: [TodayRecommendationChip]
    let tasks: [TodayTaskRowSnapshot]
    let startFocus: (Int64) -> Void

    private var cards: [Card] {
        let primary: Card = (recommendation.title, recommendation.reason, recommendation.taskID, "sparkles")
        let alternatives: [Card] = chips.map { ($0.title, $0.reason, Optional($0.taskID), $0.systemImage) }
        let selectedTaskIDs = Set(([primary] + alternatives).compactMap { $0.taskID })
        let remainingTasks: [Card] = tasks
            .filter { !selectedTaskIDs.contains($0.taskID) }
            .map { task in
                (
                    task.title,
                    task.timeLabel ?? (task.projectTitle.isEmpty ? String(localized: "Today task") : task.projectTitle),
                    Optional(task.taskID),
                    "checklist"
                )
            }
        return Array(([primary] + alternatives + remainingTasks).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Recommendations", systemImage: "sparkles")
                .font(SuisuiTypography.sectionTitle)
            HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    Button {
                        if let taskID = card.taskID { startFocus(taskID) }
                    } label: {
                        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                            Image(systemName: card.systemImage)
                                .foregroundStyle(SuisuiBrand.soloBlue)
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(card.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .disabled(card.taskID == nil)
                    .soloCard()
                    .accessibilityLabel(card.title)
                    .accessibilityHint(card.taskID == nil ? "No focus task is available." : "Starts local focus without changing task status or Calendar.")
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
        .accessibilityLabel("This Week")
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
