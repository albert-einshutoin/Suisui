import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

struct CatchUpWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var summary: MissedTaskReviewSummary {
        viewModel.missedTaskReview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                WorkflowHeader(
                    title: "Catch Up",
                    subtitle: String(format: String(localized: "%d missed tasks need review"), summary.newlyMissedCount),
                    systemImage: "clock.badge.exclamationmark"
                )
                Spacer(minLength: 12)
                CatchUpCountStrip(summary: summary)
            }

            CatchUpMissedTaskReviewPanel(summary: summary, viewModel: viewModel)

            if let stateErrorMessage = summary.stateErrorMessage {
                Label(stateErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("catch-up-state-error")
            }

            if let feedback = viewModel.todayCommandFeedback {
                Label(feedback, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("catch-up-feedback")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-workflow")
        .accessibilityLabel("Catch Up")
        .accessibilityHint("Reviews overdue, blocked, stale, and unscheduled local tasks.")
    }
}

private struct CatchUpMissedTaskReviewPanel: View {
    let summary: MissedTaskReviewSummary
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Missed Review", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(String(format: String(localized: "%d new"), summary.newlyMissedCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if summary.immediateQueue.isEmpty {
                ContentUnavailableView(
                    "No missed work",
                    systemImage: "checkmark.circle",
                    description: Text("Overdue, blocked, stale, and unscheduled tasks will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.immediateQueue) { item in
                            CatchUpMissedTaskRow(item: item, viewModel: viewModel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-missed-review-panel")
        .accessibilityLabel("Missed task review")
        .accessibilityHint("Shows newly missed local tasks and recovery actions.")
    }
}

private struct CatchUpCountStrip: View {
    let summary: MissedTaskReviewSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                badgeRow
            }
            VStack(alignment: .leading, spacing: 8) {
                badgeRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-count-strip")
        .accessibilityLabel("Catch Up counts")
    }

    private var badgeRow: some View {
        Group {
            CatchUpCountBadge(label: "Missed", value: summary.newlyMissedCount, tint: .red)
            CatchUpCountBadge(label: "Due Today", value: summary.dueTodayCount, tint: .green)
            CatchUpCountBadge(label: "Overdue", value: summary.overdueCount, tint: .orange)
            CatchUpCountBadge(label: "Blocked", value: summary.blockedCount, tint: .purple)
            CatchUpCountBadge(label: "Unscheduled", value: summary.unscheduledCount, tint: .blue)
            CatchUpCountBadge(label: "Stale", value: summary.staleCount, tint: .gray)
        }
    }
}

private struct CatchUpCountBadge: View {
    let label: String
    let value: Int
    let tint: Color

    private var identifierSuffix: String {
        label.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private var localizedLabel: String {
        switch label {
        case "Missed":
            String(localized: "Missed")
        case "Due Today":
            String(localized: "Due Today")
        case "Overdue":
            String(localized: "Overdue")
        case "Blocked":
            String(localized: "Blocked")
        case "Unscheduled":
            String(localized: "Unscheduled")
        case "Stale":
            String(localized: "Stale")
        default:
            label
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 72, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("catch-up-missed-count-badge-\(identifierSuffix)")
        .accessibilityLabel(String(format: String(localized: "%@ tasks"), localizedLabel))
        .accessibilityValue("\(value)")
    }
}

private struct CatchUpMissedTaskRow: View {
    let item: MissedTaskReviewItem
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.task.status.systemImage)
                    .foregroundStyle(item.task.status.tint)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.task.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.task.title)
                    HStack(spacing: 8) {
                        Label(item.projectTitle, systemImage: "folder")
                        Label(LocalizedStringKey(item.task.priority.label), systemImage: "flag")
                        if let dueAt = item.task.dueAt {
                            Label(dueAt, systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                CatchUpReasonPills(reasons: item.reasons)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.completeMissedTask(id: item.task.id)
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
                .controlSize(.small)
                .accessibilityIdentifier("catch-up-missed-complete-\(item.task.id)")
                .accessibilityHint("Completes this local task and removes it from the missed queue.")

                Button {
                    viewModel.rescheduleMissedTaskForToday(id: item.task.id)
                } label: {
                    Label("Today", systemImage: "calendar.badge.clock")
                }
                .controlSize(.small)
                .accessibilityIdentifier("catch-up-missed-reschedule-\(item.task.id)")
                .accessibilityHint("Reschedules this local task for today without writing external Calendar.")

                Button {
                    viewModel.deferMissedTaskForLater(id: item.task.id)
                } label: {
                    Label("Later", systemImage: "clock")
                }
                .controlSize(.small)
                .accessibilityIdentifier("catch-up-missed-defer-\(item.task.id)")
                .accessibilityHint("Marks this local task reviewed for today without changing its task fields.")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catch-up-missed-review-row-\(item.task.id)")
    }
}

private struct CatchUpReasonPills: View {
    let reasons: [MissedTaskReviewReason]

    private var localizedReasonTitles: [String] {
        reasons.map { reason in
            switch reason {
            case .overdue:
                String(localized: "Overdue")
            case .dueToday:
                String(localized: "Due Today")
            case .blocked:
                String(localized: "Blocked")
            case .unscheduled:
                String(localized: "Unscheduled")
            case .stale:
                String(localized: "Stale")
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reasons, id: \.rawValue) { reason in
                Text(LocalizedStringKey(reason.title))
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reasons")
        .accessibilityValue(localizedReasonTitles.joined(separator: ", "))
    }
}
