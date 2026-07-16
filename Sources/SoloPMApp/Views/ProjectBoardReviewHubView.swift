import SoloPMCore
import SwiftUI

struct ProjectBoardReviewHubView<Content: View>: View {
    @Binding var route: BoardRoute
    let assistantQueueCount: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            switch ProjectBoardHubPresentationPolicy.presentation(
                for: Double(proxy.size.width)
            ) {
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

            Section("Automation") {
                reviewRow(
                    route: .automationActivity,
                    title: "Automation Activity",
                    subtitle: "Inspect AI usage, receipts, and execution history",
                    systemImage: "bolt.horizontal.circle",
                    accessibilityIdentifier: "review-destination-automation-activity"
                )
                reviewRow(
                    route: .assistantQueue,
                    title: "Assistant Queue",
                    subtitle: "Approve, defer, reject, or run reviewed work",
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
        HStack {
            Menu {
                compactDestination(.schedule, "Schedule")
                compactDestination(.completed, "Completed")
                compactDestination(.automationActivity, "Automation Activity")
                compactDestination(.assistantQueue, "Assistant Queue")
            } label: {
                Label("Choose Review View", systemImage: "sidebar.left")
            }
            .accessibilityIdentifier("review-hub-compact-navigation")
            Spacer()
        }
        .padding(10)
    }

    private func compactDestination(
        _ destination: ReviewRoute,
        _ title: LocalizedStringKey
    ) -> some View {
        Button {
            route = .review(destination)
        } label: {
            Text(title)
        }
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
                            String(format: String(localized: "%d items need attention"), count)
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
