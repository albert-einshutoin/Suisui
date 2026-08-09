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
        let layout: AnyLayout = presentsCardsHorizontally
            ? AnyLayout(HStackLayout(alignment: .top, spacing: SuisuiSpacing.lg))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: SuisuiSpacing.lg))
        layout {
            workloadCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
            focusCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
            assistantCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var workloadCard: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            Label("Workload", systemImage: "gauge.with.dots.needle.50percent")
                .font(SuisuiTypography.sectionTitle)
            Text(String(format: String(localized: "%d tasks planned"), dashboard.workload.plannedTaskCount))
                .font(.headline.monospacedDigit())
            Text(String(format: String(localized: "%d minutes available"), dashboard.workload.dailyCapacityMinutes))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .soloCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-workload-card")
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            Label("Focus", systemImage: "target")
                .font(SuisuiTypography.sectionTitle)
            if let recommendation = dashboard.recommendation {
                Text(recommendation.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No focus task")
                    .font(.subheadline.weight(.semibold))
                Text("Add a task to choose a focus for today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .soloCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-focus-card")
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
