import SuisuiCore
import SwiftUI

struct TodayDashboardRecommendationCards: View {
    let recommendations: [TodayRecommendation]
    let onAction: (TodayRecommendation) -> Void
    var stacksVertically: Bool = false

    private var cardMinHeight: CGFloat {
        stacksVertically
            ? TodayDashboardLayoutMetrics.recommendationCardStackedMinHeight
            : TodayDashboardLayoutMetrics.recommendationCardMinHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Recommendations", systemImage: "sparkles")
                .font(SuisuiTypography.sectionTitle)
            Group {
                if stacksVertically {
                    VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
                        ForEach(recommendations, id: \.id) { recommendation in
                            recommendationButton(recommendation)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                        ForEach(recommendations, id: \.id) { recommendation in
                            recommendationButton(recommendation)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-recommendations")
    }

    private func recommendationButton(_ recommendation: TodayRecommendation) -> some View {
        Button {
            onAction(recommendation)
        } label: {
            VStack(alignment: .leading, spacing: stacksVertically ? SuisuiSpacing.sm : SuisuiSpacing.md) {
                HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                    Image(systemName: recommendationIcon(for: recommendation))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(actionColor(for: recommendation), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                        Text(recommendation.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(recommendation.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(stacksVertically ? 2 : nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if stacksVertically {
                        Spacer(minLength: 0)
                        Text(actionTitle(for: recommendation))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                actionColor(for: recommendation),
                                in: RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
                            )
                    }
                }
                if !stacksVertically {
                    Spacer(minLength: 0)
                    Text(actionTitle(for: recommendation))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            actionColor(for: recommendation),
                            in: RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
                        )
                }
            }
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: cardMinHeight,
                maxHeight: stacksVertically ? cardMinHeight : .infinity,
                alignment: .topLeading
            )
        }
        .buttonStyle(.plain)
        .todayDashboardCard()
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel(String(format: String(localized: "Recommendation: %@. %@"), recommendation.title, recommendation.reason))
        .accessibilityHint(accessibilityHint(for: recommendation))
    }

    private func recommendationIcon(for recommendation: TodayRecommendation) -> String {
        switch recommendation.action {
        case .startFocus: "timer"
        case .openReview: "flag.fill"
        case .prepareScheduleDraft: "clock.fill"
        case .selectTask: "arrow.right.circle.fill"
        case .addTask: "plus"
        case .openCatchUp: "arrow.triangle.2.circlepath"
        case .suggestBreak: "cup.and.saucer.fill"
        }
    }

    private func actionColor(for recommendation: TodayRecommendation) -> Color {
        switch recommendation.action {
        case .startFocus, .selectTask: SuisuiBrand.soloBlue
        case .openReview, .openCatchUp: Color(nsColor: .systemGreen)
        case .prepareScheduleDraft, .suggestBreak: Color(nsColor: .systemOrange)
        case .addTask: Color(nsColor: .systemPurple)
        }
    }

    private func actionTitle(for recommendation: TodayRecommendation) -> String {
        switch recommendation.action {
        case .startFocus: String(localized: "Start Focus")
        case .openReview: String(localized: "Review")
        case .prepareScheduleDraft, .suggestBreak: String(localized: "Schedule")
        case .selectTask: String(localized: "Open Task")
        case .addTask: String(localized: "Add Task")
        case .openCatchUp: String(localized: "Catch Up")
        }
    }

    private func accessibilityHint(for recommendation: TodayRecommendation) -> String {
        switch recommendation.action {
        case .startFocus:
            return String(localized: "Starts local focus without changing task status or Calendar.")
        case .openReview:
            return String(localized: "Selects this task and moves to the Daily Planning Review without changing task status or Calendar.")
        case .prepareScheduleDraft:
            return String(localized: "Adds this task to the local schedule draft without writing Calendar.")
        case .selectTask:
            return String(localized: "Selects this task without changing task status or Calendar.")
        case .addTask:
            return String(localized: "Prefills the Today command field so you can add a local task.")
        case .openCatchUp:
            return String(localized: "Moves VoiceOver focus to the Catch Up review.")
        case .suggestBreak:
            return String(localized: "Moves VoiceOver focus to the review area for a short break.")
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
        .todayDashboardCard()
        // Weekly rows are independently addressable schedule items; do not
        // flatten them into the card's summary element.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-weekly-schedule-card")
        .accessibilityLabel(String(format: String(localized: "This Week: %@"), localizedCount(schedule.scheduledTaskCount, one: "%d task scheduled", other: "%d tasks scheduled")))
        .accessibilityValue(localizedCount(schedule.unscheduledTaskCount, one: "%d task needs scheduling", other: "%d tasks need scheduling"))
    }
}

struct TodayDashboardReviewCard: View {
    let review: TodayReviewSnapshot
    let externalActivity: TodayExternalActivityModel
    let openReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Needs Review")
                .font(SuisuiTypography.sectionTitle)
                .padding(.bottom, SuisuiSpacing.md)

            if review.items.isEmpty {
                Text("No items need review right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, SuisuiSpacing.md)
            } else {
                ForEach(review.items) { item in
                    reviewItemRow(item)
                    if item.id != review.items.last?.id {
                        Divider().padding(.leading, 42)
                    }
                }

            }

            externalChangesDivider
            if externalActivity.rows.isEmpty {
                Text("No external changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, SuisuiSpacing.sm)
            } else {
                ForEach(externalActivity.rows, id: \.id) { row in
                    externalActivityRow(row)
                    if row.id != externalActivity.rows.last?.id {
                        Divider().padding(.leading, 42)
                    }
                }
            }

            Divider()
                .padding(.top, SuisuiSpacing.md)
            Button(action: openReview) {
                HStack(spacing: SuisuiSpacing.xs) {
                    Text("View all review items")
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.top, SuisuiSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityHint("Opens the Review area without changing tasks or external services.")
            .accessibilityIdentifier("today-review-view-all")
        }
        .todayDashboardCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-review-card")
    }

    private func reviewItemRow(_ item: TodayReviewItemSnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            reviewIcon(systemName: item.kind == .dailyPlanning ? "doc.text" : "clock.arrow.circlepath")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: SuisuiSpacing.sm)
            Text(item.kind == .dailyPlanning ? "Daily Planning" : "Catch Up")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("today-review-item-\(item.id)")
        .accessibilityLabel("\(item.title). \(item.detail)")
    }

    private var externalChangesDivider: some View {
        HStack(spacing: SuisuiSpacing.sm) {
            Rectangle()
                .fill(SuisuiBorder.subtle)
                .frame(height: 1)
            Text("External changes")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(SuisuiBorder.subtle)
                .frame(height: 1)
        }
        .padding(.vertical, SuisuiSpacing.md)
        .accessibilityAddTraits(.isHeader)
    }

    private func externalActivityRow(_ row: TodayExternalActivitySummaryRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            reviewIcon(systemName: systemImage(for: row.service))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(row.id)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private func reviewIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 30, height: 30)
            .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }

    private func systemImage(for service: TodayIntegrationService) -> String {
        switch service {
        case .calendar:
            "calendar"
        case .slack:
            "bubble.left.and.bubble.right"
        }
    }
}
