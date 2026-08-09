import SuisuiCore
import SwiftUI

struct TodayDashboardHeaderView: View {
    let header: TodayDashboardHeaderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            Label("Today", systemImage: "sun.max.fill")
                .font(SuisuiTypography.pageTitle)
            Text(header.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(header.greeting)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-dashboard-header")
        .accessibilityLabel(
            String(
                format: String(localized: "Suisui Today: %@. %@. %d tasks today, %d scheduled"),
                header.title,
                header.greeting,
                header.taskCount,
                header.scheduledTaskCount
            )
        )
    }
}
