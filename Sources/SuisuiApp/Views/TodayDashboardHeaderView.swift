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
                Text("\(localizedTaskCount(header.taskCount)) · \(scheduledTodayLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: SuisuiSpacing.sm)
            TodayDashboardWeatherView(weather: weather)
        }
        // Keep weather attribution/retry as separate VoiceOver controls. A
        // combined parent would swallow those actions into the header label.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-dashboard-header")
        .accessibilityLabel(
            String(
                format: String(localized: "Suisui Today: %@. %@. %@. %@. %@"),
                header.title,
                header.greeting,
                localizedTaskCount(header.taskCount),
                scheduledTodayLabel,
                weather.accessibilityLabel
            )
        )
    }

    private var scheduledTodayLabel: String {
        localizedCount(
            header.scheduledTaskCount,
            one: "%d task scheduled today",
            other: "%d tasks scheduled today"
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
            if let attribution = weather.attribution,
               let legalURL = URL(string: weather.attributionURL ?? "https://weatherkit.apple.com/legal-attribution.html") {
                Link(destination: legalURL) {
                    Text(attribution)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .accessibilityIdentifier("today-weather-attribution")
                .accessibilityHint(String(localized: "Opens Apple Weather attribution and legal information."))
            }
            if weather.isStale || weather.state == .failed {
                Button(String(localized: "Retry weather")) {
                    NotificationCenter.default.post(name: .suisuiWeatherLocationDidChange, object: nil)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("today-weather-retry")
                .accessibilityHint(String(localized: "Requests the latest weather for the selected location."))
            }
        }
        .multilineTextAlignment(.trailing)
        // Keep the weather summary as a labeled container while retaining the
        // attribution link and retry button as independently discoverable
        // controls for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(weather.accessibilityLabel)
        .accessibilityIdentifier("today-weather")
    }
}
