import SuisuiCore
import SwiftUI

struct ProjectBoardReviewHubView<Content: View>: View {
    @Binding var route: BoardRoute
    let assistantQueueCount: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            switch presentation(for: proxy.size.width) {
            case .wide:
                HSplitView {
                    reviewNavigation
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .compact:
                VStack(spacing: 0) {
                    compactNavigation
                    Divider()
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-hub")
    }

    private func presentation(for availableWidth: CGFloat) -> ProjectBoardHubPresentation {
        if case .review(.schedule) = route {
            return .compact
        }
        return ProjectBoardHubPresentationPolicy.presentation(for: Double(availableWidth))
    }

    private var reviewNavigation: some View {
        List(selection: reviewSelection) {
            Section("Plan") {
                reviewRow(
                    route: .schedule,
                    title: "Schedule",
                    subtitle: "Review workload and approval-ready drafts",
                    systemImage: "calendar",
                    accessibilityIdentifier: "review-destination-schedule"
                )
            }

            Section("Work") {
                reviewRow(
                    route: .completed,
                    title: "Completed",
                    subtitle: "See completed work and local recap",
                    systemImage: "checkmark.circle",
                    accessibilityIdentifier: "review-destination-completed"
                )
            }

            Section("Review") {
                reviewRow(
                    route: .assistantQueue,
                    title: "Pending Actions",
                    subtitle: "Review proposed changes before execution.",
                    systemImage: "tray.full",
                    count: assistantQueueCount,
                    accessibilityIdentifier: "review-destination-assistant-queue"
                )
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("review-hub-navigation")
        .accessibilityLabel("Review navigation")
    }

    private var compactNavigation: some View {
        let presentation = ProjectBoardCompactNavigationPresentation.review(
            route: route,
            assistantQueueCount: assistantQueueCount
        )

        return HStack {
            Menu {
                compactDestination(
                    .schedule,
                    "Schedule",
                    accessibilityIdentifier: "review-hub-compact-destination-schedule"
                )
                compactDestination(
                    .completed,
                    "Completed",
                    accessibilityIdentifier: "review-hub-compact-destination-completed"
                )
                compactDestination(
                    .assistantQueue,
                    "Pending Actions",
                    accessibilityIdentifier: "review-hub-compact-destination-assistant-queue"
                )
            } label: {
                compactLabel(presentation)
            }
            .help("Choose Review destination.")
            .accessibilityIdentifier("review-hub-compact-navigation")
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder
    private func compactLabel(
        _ presentation: ProjectBoardCompactNavigationPresentation
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sidebar.left")
                .accessibilityHidden(true)
            // The policy keeps fixed labels localizable while preserving
            // user-authored text verbatim.
            switch presentation.label {
            case .localized(let key):
                Text(LocalizedStringKey(key))
            case .verbatim(let value):
                Text(verbatim: value)
            }
            if let count = presentation.badgeCount {
                Text(verbatim: "\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel(
                        localizedCount(
                            count,
                            one: "%d item needs attention",
                            other: "%d items need attention"
                        )
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func compactDestination(
        _ destination: ReviewRoute,
        _ title: LocalizedStringKey,
        accessibilityIdentifier: String
    ) -> some View {
        Button {
            route = .review(destination)
        } label: {
            Text(title)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var reviewSelection: Binding<ReviewRoute?> {
        Binding(
            get: {
                guard case .review(let reviewRoute) = route else {
                    return nil
                }
                return reviewRoute
            },
            set: { reviewRoute in
                guard let reviewRoute else {
                    return
                }
                route = .review(reviewRoute)
            }
        )
    }

    private func reviewRow(
        route: ReviewRoute,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        count: Int = 0,
        accessibilityIdentifier: String
    ) -> some View {
        Label {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(subtitle)
                }
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel(
                            localizedCount(
                                count,
                                one: "%d item needs attention",
                                other: "%d items need attention"
                            )
                        )
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
        .tag(route)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
