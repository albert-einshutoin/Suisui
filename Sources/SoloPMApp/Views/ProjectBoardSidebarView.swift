import SoloPMCore
import SwiftUI

struct ProjectBoardSidebarCounts: Equatable {
    let today: Int
    let inbox: Int
    let projects: Int
    let review: Int
}

/// The primary source list intentionally owns only the four stable product
/// areas. Feature-level navigation belongs to the Projects and Review hubs so
/// adding a workflow cannot silently grow the app's top-level information
/// architecture again.
struct ProjectBoardSidebarView: View {
    @Binding var route: BoardRoute
    let counts: ProjectBoardSidebarCounts

    var body: some View {
        List(selection: primarySelection) {
            primaryRow(
                destination: .today,
                title: "Today",
                systemImage: "sun.max",
                count: counts.today,
                accessibilityIdentifier: "sidebar-destination-today"
            )
            primaryRow(
                destination: .inbox,
                title: "Inbox",
                systemImage: "tray",
                count: counts.inbox,
                accessibilityIdentifier: "sidebar-destination-inbox"
            )
            primaryRow(
                destination: .projects,
                title: "Projects",
                systemImage: "folder.circle",
                count: counts.projects,
                accessibilityIdentifier: "sidebar-destination-projects"
            )
            primaryRow(
                destination: .review,
                title: "Review",
                systemImage: "checklist",
                count: counts.review,
                accessibilityIdentifier: "sidebar-destination-review"
            )
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("project-board-sidebar")
        .accessibilityLabel("Project navigation")
        .accessibilityHint("Select Today, Inbox, Projects, or Review.")
    }

    private var primarySelection: Binding<BoardPrimaryDestination?> {
        Binding(
            get: { route.primaryDestination },
            set: { destination in
                guard let destination else {
                    return
                }
                route = .primary(destination)
            }
        )
    }

    private func primaryRow(
        destination: BoardPrimaryDestination,
        title: LocalizedStringKey,
        systemImage: String,
        count: Int,
        accessibilityIdentifier: String
    ) -> some View {
        Label {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityLabel(
                            String(
                                format: String(localized: "%d items"),
                                count
                            )
                        )
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
        .tag(destination)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(
            count > 0
                ? String(format: String(localized: "%d items"), count)
                : String(localized: "No pending items")
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension BoardRoute {
    var primaryDestination: BoardPrimaryDestination? {
        switch self {
        case .primary(let destination):
            return destination
        case .project, .smartList:
            return .projects
        case .review:
            return .review
        }
    }
}
