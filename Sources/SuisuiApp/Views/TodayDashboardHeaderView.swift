import SuisuiCore
import SwiftUI

struct TodayDashboardHeaderView: View {
    let header: TodayDashboardHeaderSnapshot
    let weather: TodayWeatherSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: SuisuiSpacing.lg) {
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
            Spacer(minLength: SuisuiSpacing.sm)
            TodayDashboardWeatherView(weather: weather)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-dashboard-header")
        .accessibilityLabel(
            String(
                format: String(localized: "Suisui Today: %@. %@. %@ today, %@ scheduled. %@"),
                header.title,
                header.greeting,
                localizedTaskCount(header.taskCount),
                localizedTaskCount(header.scheduledTaskCount),
                weather.accessibilityLabel
            )
        )
    }
}

private struct TodayDashboardWeatherView: View {
    let weather: TodayWeatherSnapshot

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label(weather.title, systemImage: "cloud.sun")
                .font(.subheadline.weight(.medium))
            Text(weather.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weather.accessibilityLabel)
        .accessibilityIdentifier("today-weather")
    }
}
