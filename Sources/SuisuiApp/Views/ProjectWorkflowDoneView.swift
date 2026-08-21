import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

private enum DoneHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case thisWeek
    case thisMonth

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        }
    }
}

struct DoneWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    let appSettings: AppSettings
    @State private var historyFilter: DoneHistoryFilter = .all

    init(viewModel: ProjectBoardViewModel, appSettings: AppSettings = .default) {
        self.viewModel = viewModel
        self.appSettings = appSettings
    }

    private var analytics: DoneAnalyticsSummary {
        viewModel.derivedReadModels.doneAnalytics
    }

    private var filteredRecentTasks: [ProjectBoardTask] {
        let calendar = VisualEvidenceRuntimeContext.runtimeCalendar()
        let now = VisualEvidenceRuntimeContext.referenceDate()
        return analytics.recentTasks.filter { task in
            matchesHistoryFilter(task, now: now, calendar: calendar)
        }
    }

    private var historyGroups: [DoneHistoryGroup] {
        DoneHistoryGrouping.grouped(
            tasks: filteredRecentTasks,
            now: VisualEvidenceRuntimeContext.referenceDate(),
            calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
        )
    }

    private var doneReceiptRows: [ExecutionReceiptHistoryRow] {
        Array(viewModel.executionReceiptHistorySnapshot.rows.prefix(4))
    }

    private func historySectionTitle(_ section: DoneHistorySection) -> LocalizedStringKey {
        switch section {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .lastSevenDays: "Last 7 days"
        case .older: "Older"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = CockpitLayoutPolicy.presentsSplitRail(contentWidth: Double(proxy.size.width))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label("Completed", systemImage: "checkmark.circle")
                        .font(.title2.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(
                        String(
                            format: String(localized: "%d completed"),
                            analytics.completedTaskCount
                        )
                    )
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                if isWide {
                    HStack(alignment: .top, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                        donePrimaryColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        doneSummaryRail
                            .frame(width: CGFloat(CockpitLayoutPolicy.railWidth), alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            donePrimaryColumn
                            doneSummaryRail
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-workflow")
        .accessibilityLabel("Completed")
        .accessibilityHint("Reviews completed tasks, completed projects, and local recap.")
    }

    private var donePrimaryColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                historyFilterBar
                historyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var doneSummaryRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    DoneStatTile(
                        title: "Completed Tasks",
                        value: "\(analytics.completedTaskCount)",
                        systemImage: "checkmark.square"
                    )
                    DoneStatTile(
                        title: "Completed Projects",
                        value: "\(analytics.completedProjectCount)",
                        systemImage: "folder.badge.checkmark"
                    )
                    DoneStatValueTile(
                        title: "On-Time Rate",
                        value: analytics.onTimeRate.map { "\(Int($0 * 100))%" } ?? "—",
                        systemImage: "clock.badge.checkmark"
                    )
                    DoneStatTile(
                        title: "Streak",
                        value: localizedCount(analytics.streakDays, one: "%d day", other: "%d days"),
                        systemImage: "flame"
                    )
                }
                DoneWeeklyTrendChartView(buckets: analytics.weeklyTrendBuckets)
                DoneCompletionHeatmapView(buckets: analytics.completionHeatmapBuckets)
                DoneProductivityInsightView(
                    bestWeekdaySummary: analytics.bestWeekdaySummary,
                    bestHourSummary: analytics.bestHourSummary
                )
                doneExecutionReceiptsPanel
                localRuleInsight
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var historyFilterBar: some View {
        HStack(spacing: 6) {
            ForEach(DoneHistoryFilter.allCases) { filter in
                Button {
                    historyFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            historyFilter == filter
                                ? AnyShapeStyle(SuisuiBrand.soloBlue.opacity(0.16))
                                : AnyShapeStyle(SuisuiSurface.groupedContent),
                            in: Capsule()
                        )
                        .foregroundStyle(historyFilter == filter ? SuisuiBrand.soloBlue : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("done-history-filter-\(filter.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-history-filters")
    }

    private var localRuleInsight: some View {
        Label {
            Text(LocalizedStringKey(analytics.localRuleInsight))
        } icon: {
            Image(systemName: "lock.doc")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("done-local-rule-insight")
    }

    private var doneExecutionReceiptsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Execution Receipts", systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
            if let unavailableMessage = viewModel.executionReceiptHistorySnapshot.unavailableMessage {
                Text(unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if doneReceiptRows.isEmpty {
                Text("No local execution receipts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(doneReceiptRows) { row in
                    ExecutionReceiptHistoryRowView(row: row)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-execution-receipts")
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Completed", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if filteredRecentTasks.isEmpty {
                ContentUnavailableView(
                    "No completed tasks yet",
                    systemImage: "checkmark.circle",
                    description: Text("Tasks appear here after they are completed.")
                )
            } else {
                ForEach(historyGroups, id: \.section) { group in
                    Text(historySectionTitle(group.section))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.tasks) { task in
                        DoneTaskHistoryRow(task: task, viewModel: viewModel)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func matchesHistoryFilter(
        _ task: ProjectBoardTask,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard historyFilter != .all else {
            return true
        }
        guard let completedAt = task.completedAt.flatMap({
            SuisuiTimestampDisplay.parse($0, calendar: calendar)?.date
        }) else {
            return historyFilter == .thisMonth
        }
        switch historyFilter {
        case .all:
            return true
        case .today:
            return calendar.isDate(completedAt, inSameDayAs: now)
        case .thisWeek:
            let startOfToday = calendar.startOfDay(for: now)
            let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return completedAt >= startOfWeek
        case .thisMonth:
            return calendar.isDate(completedAt, equalTo: now, toGranularity: .month)
        }
    }
}

struct ExecutionUsageMeterSummaryView: View {
    let snapshot: ExecutionUsageMeterSnapshot
    let managedAIBilling: ManagedAIBillingSettings

    private var usageThresholdRows: [ManagedAIUsageThresholdRow] {
        managedAIBilling.usageThresholdRows(for: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let unavailableMessage = snapshot.unavailableMessage {
                ContentUnavailableView(
                    "Execution usage meter is unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(unavailableMessage)
                )
            } else {
                Text(snapshot.scopeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ai-usage-meter-scope")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                    usageMetric("Total Tokens", snapshot.summary.totalTokenLabel, "number")
                    usageMetric("Tracked Runs", snapshot.summary.receiptCountLabel, "checklist")
                    usageMetric("Cost", snapshot.summary.costLabel, "creditcard")
                }

                if let latestDay = snapshot.dailyRows.first {
                    ExecutionUsageMeterBucketRowView(title: "Latest Day", row: latestDay)
                }
                if let latestMonth = snapshot.monthlyRows.first {
                    ExecutionUsageMeterBucketRowView(title: "Latest Month", row: latestMonth)
                }
                if let topProject = snapshot.projectRows.first {
                    ExecutionUsageMeterBucketRowView(title: "Top Project", row: topProject)
                }
                if !usageThresholdRows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Usage Threshold Status")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(usageThresholdRows) { row in
                            ManagedAIUsageThresholdRowView(row: row)
                        }
                    }
                    .accessibilityIdentifier("ai-usage-threshold-status")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI Usage Meter")
        .accessibilityValue(snapshot.accessibilityValue)
        .accessibilityHint("Shows receipt-derived token and cost usage without raw prompts, receipt identifiers, or provider secrets.")
    }

    private func usageMetric(_ title: LocalizedStringKey, _ value: String, _ systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct ManagedAIUsageThresholdRowView: View {
    let row: ManagedAIUsageThresholdRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(row.usedLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(row.capLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Label(row.statusLabel, systemImage: statusSystemImage)
                .font(SuisuiTypography.compactLabel.monospacedDigit())
                .foregroundStyle(row.status == .exceeded ? SuisuiTone.danger.color : SuisuiTone.positive.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.accessibilityValue)
        .accessibilityIdentifier("ai-usage-threshold-row-\(row.scope.rawValue)")
    }

    private var statusSystemImage: String {
        row.status == .exceeded ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }
}

private struct ExecutionUsageMeterBucketRowView: View {
    let title: LocalizedStringKey
    let row: ExecutionUsageMeterBucketRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(row.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(row.summary.totalTokenLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(row.summary.costLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(row.accessibilityValue)
    }
}

struct ExecutionReceiptHistoryFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct DoneStatTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .leading)
        .padding(10)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
    }
}

private struct DoneStatValueTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .leading)
        .padding(10)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
    }
}

private struct DoneWeeklyTrendChartView: View {
    let buckets: [DoneAnalyticsWeekBucket]

    private var maxCount: Int {
        max(buckets.map(\.completedCount).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Monthly Trend", systemImage: "chart.bar")
                .font(.headline)

            if buckets.isEmpty {
                Text("Not enough data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(buckets, id: \.weekLabel) { bucket in
                        VStack(spacing: 6) {
                            Text("\(bucket.completedCount)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: SuisuiRadius.control)
                                .fill(SuisuiBrand.soloBlue)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 8,
                                    maxHeight: max(8, CGFloat(bucket.completedCount) / CGFloat(maxCount) * 80)
                                )
                            Text(bucket.weekLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(bucket.weekLabel)
                        .accessibilityValue("\(bucket.completedCount) tasks")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottom)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-weekly-trend")
    }
}

private struct DoneCompletionHeatmapView: View {
    let buckets: [DoneAnalyticsDayBucket]
    private let columns = [
        GridItem(.adaptive(minimum: 18, maximum: 18), spacing: 4)
    ]

    private var maxCompletedCount: Int {
        max(buckets.map(\.completedCount).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Completion Heatmap", systemImage: "square.grid.3x3")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("Last 28 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(buckets, id: \.dayKey) { bucket in
                    RoundedRectangle(cornerRadius: SuisuiRadius.control)
                        .fill(heatmapColor(for: bucket.completedCount))
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: SuisuiRadius.control)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                        )
                        .overlay {
                            if bucket.completedCount > 0 {
                                Circle()
                                    .fill(SuisuiTone.neutral.color.opacity(0.72))
                                    .frame(
                                        width: heatmapMarkerDiameter(for: bucket.completedCount),
                                        height: heatmapMarkerDiameter(for: bucket.completedCount)
                                    )
                            }
                        }
                        .accessibilityIdentifier("done-heatmap-day-\(bucket.dayKey)")
                        .accessibilityLabel(String(format: String(localized: "Completed tasks on %@"), bucket.dayKey))
                        .accessibilityValue(String(format: String(localized: "%d tasks"), bucket.completedCount))
                }
            }

            HStack(spacing: 6) {
                Text("Fewer completions")
                heatmapLegendCell(count: 0)
                heatmapLegendCell(count: max(maxCompletedCount / 2, 1))
                heatmapLegendCell(count: maxCompletedCount)
                Text("More completions")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("done-heatmap-legend")

            Text("Heatmap intensity is based on local completion history only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-completion-heatmap")
    }

    private func heatmapColor(for count: Int) -> Color {
        guard count > 0 else {
            return Color.secondary.opacity(0.10)
        }
        let normalized = min(Double(count) / Double(maxCompletedCount), 1.0)
        return SuisuiTone.positive.color.opacity(0.25 + normalized * 0.55)
    }

    private func heatmapMarkerDiameter(for count: Int) -> CGFloat {
        guard count > 0 else {
            return 0
        }
        let normalized = min(Double(count) / Double(maxCompletedCount), 1.0)
        return 3 + CGFloat(normalized * 6)
    }

    private func heatmapLegendCell(count: Int) -> some View {
        RoundedRectangle(cornerRadius: SuisuiRadius.control)
            .fill(heatmapColor(for: count))
            .frame(width: 18, height: 18)
            .overlay {
                if count > 0 {
                    Circle()
                        .fill(SuisuiTone.neutral.color.opacity(0.72))
                        .frame(
                            width: heatmapMarkerDiameter(for: count),
                            height: heatmapMarkerDiameter(for: count)
                        )
                }
            }
            .accessibilityHidden(true)
    }
}

private struct DoneProductivityInsightView: View {
    let bestWeekdaySummary: DoneAnalyticsBestWeekdaySummary
    let bestHourSummary: DoneAnalyticsBestHourSummary
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            DoneInsightTile(
                title: "Best Day",
                value: bestWeekdayValue,
                detail: bestWeekdayDetail,
                systemImage: "calendar.badge.clock"
            )
            .accessibilityIdentifier("done-best-weekday-summary")

            DoneInsightTile(
                title: "Peak Time",
                value: bestHourValue,
                detail: bestHourDetail,
                systemImage: "clock.badge.checkmark"
            )
            .accessibilityIdentifier("done-best-hour-summary")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-productivity-insight")
    }

    private var bestWeekdayValue: String {
        guard let weekday = bestWeekdaySummary.weekday else {
            return String(localized: "No completion history yet")
        }
        return Self.weekdayLabel(for: weekday, calendar: calendar, locale: locale, timeZone: timeZone)
    }

    private var bestWeekdayDetail: String {
        guard !bestWeekdaySummary.isEmpty else {
            return String(localized: "Complete tasks to build weekday trends.")
        }
        return localizedCount(
            bestWeekdaySummary.completedCount,
            one: "%d task completed on this weekday.",
            other: "%d tasks completed on this weekday."
        )
    }

    private var bestHourValue: String {
        guard let hour = bestHourSummary.hour else {
            return String(localized: "No peak time yet")
        }
        return Self.hourLabel(for: hour)
    }

    private var bestHourDetail: String {
        guard !bestHourSummary.isEmpty else {
            return String(localized: "Completed tasks with timestamps will show hourly trends.")
        }
        return localizedDisplay(
            "%@ around %@, usually %@.",
            localizedCount(
                bestHourSummary.completedCount,
                one: "%d task",
                other: "%d tasks"
            ),
            bestHourValue,
            localizedTimeOfDayLabel
        )
    }

    private var localizedTimeOfDayLabel: String {
        switch bestHourSummary.timeOfDay {
        case .morning:
            return String(localized: "Morning")
        case .afternoon:
            return String(localized: "Afternoon")
        case .evening:
            return String(localized: "Evening")
        case .night:
            return String(localized: "Night")
        case nil:
            return String(localized: "No peak time yet")
        }
    }

    private static func weekdayLabel(
        for weekday: Int,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        let labels = formatter.weekdaySymbols ?? []
        let labelIndex = weekday - 1
        return labels.indices.contains(labelIndex) ? labels[labelIndex] : String(localized: "Weekday")
    }

    private static func hourLabel(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

private struct DoneInsightTile: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(10)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
    }
}

private struct DoneTaskHistoryRow: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                .foregroundStyle(task.status == .done ? SuisuiTone.positive.color : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(doneMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                DoneTaskHistoryActions(task: task, viewModel: viewModel)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var doneMetadata: String {
        let projectTitle = viewModel.projectTitle(for: task)
        if let completedAt = task.completedAt {
            // `completedAt` is a stored ISO8601 instant. Printing it verbatim
            // showed the user "2026-07-09T12:00:00Z" — a UTC machine string on
            // the one screen that exists to celebrate finished work.
            return localizedDisplay(
                "%@ completed at %@",
                projectTitle,
                SuisuiTimestampDisplay.absolute(
                    completedAt,
                    calendar: VisualEvidenceRuntimeContext.runtimeCalendar(),
                    locale: localizedDisplayLocale()
                )
            )
        }
        return localizedDisplay("%@ completed", projectTitle)
    }
}

private struct DoneTaskHistoryActions: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.enqueueDoneFollowUpDraft(for: task.id)
            } label: {
                Label("Follow Up", systemImage: "plus.bubble")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("done-follow-up-task-\(task.id)")
            .accessibilityHint("Creates an Assistant Queue approval item; no tasks are created until approval.")

            if task.status == .done {
                Button {
                    viewModel.reopenCompletedTask(id: task.id)
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("done-reopen-task-\(task.id)")
            }
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-history-row-actions-\(task.id)")
    }
}

struct ExecutionReceiptHistoryRowView: View {
    let row: ExecutionReceiptHistoryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(row.statusLabel, systemImage: statusSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(row.toolLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.occurredAtLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(row.outcomeSummary)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(row.usageLabel)
                Text(row.referenceSummary)
                Text(row.sourceSummary)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)

            Text(row.receiptIDLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("execution-receipt-row-\(row.id)")
        .accessibilityLabel("Execution receipt")
        .accessibilityValue(row.accessibilityValue)
        .accessibilityHint("Shows the redacted outcome, usage state, references, sources, and receipt identifier for approved AI work.")
    }

    private var statusSystemImage: String {
        switch row.status {
        case .notStarted:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .skipped:
            return "forward.end.circle"
        case .canceled:
            return "stop.circle"
        }
    }

    private var statusTint: Color {
        switch row.status {
        case .notStarted, .skipped, .canceled:
            return .secondary
        case .running:
            return SuisuiBrand.soloBlue
        case .succeeded:
            return SuisuiTone.positive.color
        case .failed:
            return SuisuiTone.danger.color
        }
    }
}
