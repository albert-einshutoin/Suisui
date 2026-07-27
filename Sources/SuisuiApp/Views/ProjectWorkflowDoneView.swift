import Foundation
import SuisuiCore
import SwiftUI
import UniformTypeIdentifiers

struct DoneWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    let appSettings: AppSettings

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
                    Label("Completed", systemImage: "checkmark.circle")
                        .font(.title2.weight(.semibold))
                    Spacer()
                }

                // Streak, completion heatmap, best weekday, and peak hour were
                // habit metrics: they measure how much the user moved, not
                // whether a promise was kept. That is the opposite of what this
                // product claims to own — completing a task is not the same as
                // delivering a commitment, and a week spent shipping one
                // release rendered as "Streak 0". Counts of finished work stay;
                // the productivity scoring is gone until there is an outcome to
                // score against.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    DoneStatTile(title: "Completed Tasks", value: analytics.completedTaskCount, systemImage: "checkmark.square")
                    DoneStatTile(title: "Completed Projects", value: analytics.completedProjectCount, systemImage: "folder.badge.checkmark")
                    DoneStatTile(title: "Today", value: analytics.completedTodayCount, systemImage: "sun.max")
                    DoneStatTile(title: "7 Days", value: analytics.completedThisWeekCount, systemImage: "calendar")
                }

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

            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("done-workflow")
        .accessibilityLabel("Completed")
        .accessibilityHint("Reviews completed tasks, completed projects, and local recap.")
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
            return String(
                format: String(localized: "%@ completed at %@"),
                projectTitle,
                SuisuiTimestampDisplay.absolute(
                    completedAt,
                    calendar: VisualEvidenceRuntimeContext.runtimeCalendar()
                )
            )
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
            return SuisuiBrand.soloBlue
        case .succeeded:
            return SuisuiTone.positive.color
        case .failed:
            return SuisuiTone.danger.color
        }
    }
}
