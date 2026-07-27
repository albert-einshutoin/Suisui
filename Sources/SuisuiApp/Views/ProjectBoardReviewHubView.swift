import SuisuiCore
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
            // Assistant Queue is where an approved plan actually runs — the
            // last step of the product's headline flow. It used to sit last,
            // under "Automation", so the happiest voice path ended with a
            // window switch plus a hunt through two sections. It leads now.
            Section("Approve and Run") {
                reviewRow(
                    route: .assistantQueue,
                    title: "Assistant Queue",
                    subtitle: "Approve, defer, reject, or run reviewed work",
                    systemImage: "tray.full",
                    count: assistantQueueCount,
                    accessibilityIdentifier: "review-destination-assistant-queue"
                )
            }

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
                // Renamed from "Automation Activity" / "Inspect AI usage".
                // These are the receipts proving what actually ran — the
                // product's evidence trail, not an admin usage report.
                reviewRow(
                    route: .automationActivity,
                    title: "Execution Record",
                    subtitle: "See what actually ran, with receipts and evidence",
                    systemImage: "doc.text.magnifyingglass",
                    accessibilityIdentifier: "review-destination-automation-activity"
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
                compactDestination(
                    .assistantQueue,
                    "Assistant Queue",
                    accessibilityIdentifier: "review-hub-compact-destination-assistant-queue"
                )
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
                    .automationActivity,
                    "Execution Record",
                    accessibilityIdentifier: "review-hub-compact-destination-automation-activity"
                )
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
