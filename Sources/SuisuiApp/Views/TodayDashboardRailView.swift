import SuisuiCore
import SwiftUI

struct TodayDashboardRailView: View {
    let dashboard: TodayDashboardSnapshot
    let assistantContext: TodayAssistantRailContext
    @ObservedObject var viewModel: TodayFeatureViewModel
    @Binding var commandTitle: String
    let openInspector: (Int64) -> Void
    let presentsCardsHorizontally: Bool

    var body: some View {
        let primaryLayout: AnyLayout = presentsCardsHorizontally
            ? AnyLayout(HStackLayout(alignment: .top, spacing: SuisuiSpacing.lg))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: SuisuiSpacing.lg))
        let integrationLayout: AnyLayout = presentsCardsHorizontally
            ? AnyLayout(HStackLayout(alignment: .top, spacing: SuisuiSpacing.lg))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: SuisuiSpacing.lg))
        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
            primaryLayout {
                workloadCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                focusCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            integrationLayout {
                TodayIntegrationCard(integration: dashboard.integrations.calendar)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                TodayIntegrationCard(integration: dashboard.integrations.slack)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            assistantCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var workloadCard: some View {
        TodayWorkloadCard(workload: dashboard.workload)
    }

    private var focusCard: some View {
        TodayFocusCard(
            session: viewModel.focusSession,
            tasks: dashboard.tasks,
            suggestedTaskID: dashboard.recommendation?.taskID,
            startFocusSession: viewModel.startFocusSession,
            openInspector: openInspector
        )
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Suisui Assistant", systemImage: "sparkles")
                .font(SuisuiTypography.sectionTitle)
            TodayAssistantRail(
                commandTitle: $commandTitle,
                context: assistantContext,
                viewModel: viewModel,
                openInspector: openInspector
            )
        }
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-assistant-card")
    }
}

private struct TodayIntegrationCard: View {
    let integration: TodayIntegrationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label(integration.title, systemImage: systemImage)
                .font(SuisuiTypography.sectionTitle)
            Text(integration.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .accessibilityHint("Opens Settings to manage this connection. It does not start sync or send messages.")
        }
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(integration.accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var accessibilityIdentifier: String {
        integration.service == .calendar ? "today-calendar-card" : "today-slack-card"
    }

    private var systemImage: String {
        switch integration.state {
        case .notConnected:
            integration.service == .calendar ? "calendar.badge.exclamationmark" : "bubble.left.and.bubble.right"
        case .permissionPending:
            "lock.badge.clock"
        case .connected:
            "checkmark.circle"
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .synced:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}

private struct TodayWorkloadCard: View {
    let workload: TodayWorkloadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Workload", systemImage: "gauge.with.dots.needle.50percent")
                .font(SuisuiTypography.sectionTitle)
            HStack(spacing: SuisuiSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(workload.ratio, 1))
                        .stroke(workload.isOverCapacity ? .orange : SuisuiBrand.soloBlue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(workload.ratio * 100))%")
                        .font(.caption.monospacedDigit())
                }
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                    Text("\(hours(workload.plannedMinutes)) / \(hours(workload.capacityMinutes))")
                        .font(.headline.monospacedDigit())
                    Text(localizedCount(workload.plannedTaskCount, one: "%d task planned", other: "%d tasks planned"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Label(String(format: String(localized: "Scheduled: %@"), hours(workload.scheduledMinutes)), systemImage: "calendar")
                .font(.caption)
            Label(String(format: String(localized: "Focus blocks: %@"), hours(workload.focusTaskBlockMinutes)), systemImage: "target")
                .font(.caption)
            if workload.isOverCapacity {
                Label(
                    String(format: String(localized: "Over capacity by %@."), hours(workload.plannedMinutes - workload.capacityMinutes)),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .soloCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-workload-card")
        .accessibilityLabel(String(format: String(localized: "Workload: %@ of %@ planned."), hours(workload.plannedMinutes), hours(workload.capacityMinutes)))
        .accessibilityValue(workload.isOverCapacity
            ? String(format: String(localized: "Over capacity by %@."), hours(workload.plannedMinutes - workload.capacityMinutes))
            : String(format: String(localized: "Scheduled: %@. Focus blocks: %@."), hours(workload.scheduledMinutes), hours(workload.focusTaskBlockMinutes)))
    }

    private func hours(_ minutes: Int) -> String {
        if minutes.isMultiple(of: 60) {
            return String(format: String(localized: "%d h"), minutes / 60)
        }
        return String(format: String(localized: "%.1f h"), Double(minutes) / 60)
    }
}
