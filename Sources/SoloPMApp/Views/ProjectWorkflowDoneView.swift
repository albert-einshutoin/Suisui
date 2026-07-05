import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

struct DoneWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    let appSettings: AppSettings
    @State private var isExportingExecutionReceipts = false
    @State private var executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: Data())

    init(viewModel: ProjectBoardViewModel, appSettings: AppSettings = .default) {
        self.viewModel = viewModel
        self.appSettings = appSettings
    }

    private var analytics: DoneAnalyticsSummary {
        viewModel.derivedReadModels.doneAnalytics
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label("Done", systemImage: "checkmark.circle")
                        .font(.title2.weight(.semibold))
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    DoneStatTile(title: "Completed Tasks", value: analytics.completedTaskCount, systemImage: "checkmark.square")
                    DoneStatTile(title: "Completed Projects", value: analytics.completedProjectCount, systemImage: "folder.badge.checkmark")
                    DoneStatTile(title: "Today", value: analytics.completedTodayCount, systemImage: "sun.max")
                    DoneStatTile(title: "7 Days", value: analytics.completedThisWeekCount, systemImage: "calendar")
                    DoneStatTile(title: "Streak", value: analytics.streakDays, systemImage: "flame")
                }

                DoneCompletionHeatmapView(buckets: analytics.completionHeatmapBuckets)
                DoneProductivityInsightView(
                    bestWeekdaySummary: analytics.bestWeekdaySummary,
                    bestHourSummary: analytics.bestHourSummary
                )

                Label {
                    Text(LocalizedStringKey(analytics.localRuleInsight))
                } icon: {
                    Image(systemName: "lock.doc")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("done-local-rule-insight")

                VStack(alignment: .leading, spacing: 10) {
                    Label("Recent Completed", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    if analytics.recentTasks.isEmpty {
                        ContentUnavailableView(
                            "No completed tasks yet",
                            systemImage: "checkmark.circle",
                            description: Text("Tasks appear here after they are completed.")
                        )
                    } else {
                        ForEach(analytics.recentTasks) { task in
                            DoneTaskHistoryRow(task: task, viewModel: viewModel)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("AI Usage Meter", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                    ExecutionUsageMeterSummaryView(
                        snapshot: viewModel.executionUsageMeterSnapshot,
                        managedAIBilling: appSettings.managedAIBilling
                    )
                }
                .accessibilityIdentifier("ai-usage-meter-summary")

                VStack(alignment: .leading, spacing: 10) {
                    Label("Recent AI Receipts", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    HStack(spacing: 8) {
                        TextField(
                            "Search receipts",
                            text: Binding(
                                get: { viewModel.executionReceiptHistorySearchText },
                                set: { viewModel.setExecutionReceiptHistorySearchText($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("execution-receipt-search-field")

                        Menu {
                            Button("All Statuses") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(nil)
                            }
                            Divider()
                            Button("Succeeded") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.succeeded)
                            }
                            Button("Failed") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.failed)
                            }
                            Button("Canceled") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.canceled)
                            }
                            Button("Running") {
                                viewModel.setExecutionReceiptHistoryStatusFilter(.running)
                            }
                        } label: {
                            Label(receiptStatusFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityIdentifier("execution-receipt-status-filter")

                        Menu {
                            Button("All References") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(nil)
                            }
                            Divider()
                            Button("Task") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.task)
                            }
                            Button("Project") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.project)
                            }
                            Button("Document") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.document)
                            }
                            Button("Reminder") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.reminder)
                            }
                            Button("Calendar Event") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.calendarEvent)
                            }
                            Button("Development Branch") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.developmentBranch)
                            }
                            Button("Pull Request") {
                                viewModel.setExecutionReceiptHistoryReferenceKindFilter(.pullRequest)
                            }
                        } label: {
                            Label(receiptReferenceFilterLabel, systemImage: "tag")
                        }
                        .accessibilityIdentifier("execution-receipt-reference-filter")

                        Button {
                            viewModel.prepareExecutionReceiptHistoryExport()
                            guard let data = viewModel.executionReceiptHistoryExportData else {
                                return
                            }
                            executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: data)
                            isExportingExecutionReceipts = true
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.executionReceiptHistorySnapshot.rows.isEmpty)
                        .accessibilityIdentifier("execution-receipt-export-button")
                    }
                    .font(.caption)

                    if let exportMessage = viewModel.executionReceiptHistoryExportMessage {
                        Label(exportMessage, systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("execution-receipt-export-message")
                    }
                    if let unavailableMessage = viewModel.executionReceiptHistorySnapshot.unavailableMessage {
                        ContentUnavailableView(
                            "Execution receipts are unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(unavailableMessage)
                        )
                    } else if viewModel.executionReceiptHistorySnapshot.rows.isEmpty {
                        ContentUnavailableView(
                            "No AI receipts yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Receipts appear here after approved AI work runs.")
                        )
                    } else {
                        ForEach(viewModel.executionReceiptHistorySnapshot.rows) { row in
                            ExecutionReceiptHistoryRowView(row: row)
                        }
                    }
                }
                .accessibilityIdentifier("recent-ai-receipts")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-workflow")
        .onAppear {
            viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()
        }
        .fileExporter(
            isPresented: $isExportingExecutionReceipts,
            document: executionReceiptExportDocument,
            contentType: .json,
            defaultFilename: executionReceiptDefaultExportFilename
        ) { result in
            switch result {
            case .success:
                viewModel.recordExecutionReceiptHistoryExportCompleted()
                executionReceiptExportDocument = ExecutionReceiptHistoryFileDocument(data: Data())
            case .failure(let error):
                viewModel.recordExecutionReceiptHistoryFileFailure(error)
            }
        }
    }

    private var receiptStatusFilterLabel: LocalizedStringKey {
        guard let status = viewModel.executionReceiptHistoryStatusFilter else {
            return "All Statuses"
        }
        switch status {
        case .notStarted:
            return "Not Started"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        case .canceled:
            return "Canceled"
        }
    }

    private var receiptReferenceFilterLabel: LocalizedStringKey {
        guard let referenceKind = viewModel.executionReceiptHistoryReferenceKindFilter else {
            return "All References"
        }
        switch referenceKind {
        case .unknown:
            return "Unknown"
        case .assistantQueue:
            return "Assistant Queue"
        case .actionPlan:
            return "Action Plan"
        case .reviewSession:
            return "Review Session"
        case .task:
            return "Task"
        case .project:
            return "Project"
        case .document:
            return "Document"
        case .calendarEvent:
            return "Calendar Event"
        case .notification:
            return "Notification"
        case .reminder:
            return "Reminder"
        case .developmentBranch:
            return "Development Branch"
        case .developmentBaseBranch:
            return "Development Base Branch"
        case .developmentCommit:
            return "Development Commit"
        case .file:
            return "File"
        case .pullRequest:
            return "Pull Request"
        case .externalMCP:
            return "External MCP"
        }
    }

    private var executionReceiptDefaultExportFilename: String {
        "solopm-receipts-\(Self.exportDateFormatter.string(from: Date())).json"
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct ExecutionUsageMeterSummaryView: View {
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
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
            Text(row.statusLabel)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(row.status == .exceeded ? .red : .green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.accessibilityValue)
        .accessibilityIdentifier("ai-usage-threshold-row-\(row.scope.rawValue)")
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

private struct ExecutionReceiptHistoryFileDocument: FileDocument {
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
    let value: Int
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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
                    RoundedRectangle(cornerRadius: 4)
                        .fill(heatmapColor(for: bucket.completedCount))
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                        )
                        .accessibilityIdentifier("done-heatmap-day-\(bucket.dayKey)")
                        .accessibilityLabel(String(format: String(localized: "Completed tasks on %@"), bucket.dayKey))
                        .accessibilityValue(String(format: String(localized: "%d tasks"), bucket.completedCount))
                }
            }

            Text("Heatmap intensity is based on local completion history only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-completion-heatmap")
    }

    private func heatmapColor(for count: Int) -> Color {
        guard count > 0 else {
            return Color.secondary.opacity(0.10)
        }
        let normalized = min(Double(count) / Double(maxCompletedCount), 1.0)
        return Color.green.opacity(0.25 + normalized * 0.55)
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
        return String(
            format: String(localized: "%d tasks completed on this weekday."),
            bestWeekdaySummary.completedCount
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
        return String(
            format: String(localized: "%d tasks around %@, usually %@."),
            bestHourSummary.completedCount,
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DoneTaskHistoryRow: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                .foregroundStyle(task.status == .done ? .green : .secondary)
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
            return String(format: String(localized: "%@ completed at %@"), projectTitle, completedAt)
        }
        return String(format: String(localized: "%@ completed"), projectTitle)
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
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}
