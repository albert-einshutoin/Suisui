import SuisuiCore
import SwiftUI

/// The single work surface for task-oriented routes. Existing workflow views
/// remain the owners of their mutations; this hub only removes their separate
/// top-level navigation entries.
struct ProjectBoardWorkHubView<Content: View>: View {
    @Binding var route: BoardRoute
    let smartLists: [SmartList]
    let assistantQueueCount: Int
    let onCreateSmartList: () -> Void
    let onDeleteSmartList: (SmartList) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            switch ProjectBoardHubPresentationPolicy.presentation(for: Double(proxy.size.width)) {
            case .wide:
                HSplitView {
                    workNavigation
                        .frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
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
        .accessibilityIdentifier("work-hub")
        .accessibilityLabel("Work")
    }

    private var workNavigation: some View {
        VStack(spacing: 0) {
            List(selection: workSelection) {
                Section("Work") {
                    workRow(.primary(.today), title: "Today", systemImage: "sun.max")
                    workRow(.primary(.inbox), title: "Inbox", systemImage: "tray")
                    workRow(.primary(.projects), title: "Projects", systemImage: "folder")
                    workRow(.review(.completed), title: "Completed", systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier("work-hub-work")

                Section("Smart Lists") {
                    ForEach(smartLists) { smartList in
                        smartListRow(smartList)
                    }

                    Button(action: onCreateSmartList) {
                        Label("New Smart List…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("work-hub-smart-list-new")
                }
                .accessibilityIdentifier("work-hub-smart-lists")

                Section("Review") {
                    workRow(.review(.automationActivity), title: "Automation Activity", systemImage: "doc.text.magnifyingglass")
                    workRow(
                        .review(.assistantQueue),
                        title: "Pending Actions",
                        systemImage: "tray.full",
                        count: assistantQueueCount
                    )
                }
                .accessibilityIdentifier("work-hub-review")
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("work-hub-navigation")
            .accessibilityLabel("Work navigation")
        }
    }

    private var compactNavigation: some View {
        let label = workLabel

        return HStack(spacing: 10) {
            Menu {
                Section("Work") {
                    compactDestination(.primary(.today), title: "Today")
                    compactDestination(.primary(.inbox), title: "Inbox")
                    compactDestination(.primary(.projects), title: "Projects")
                    compactDestination(.review(.completed), title: "Completed")
                }
                Section("Smart Lists") {
                    ForEach(smartLists) { smartList in
                        Button {
                            route = .smartList(smartList.id)
                        } label: {
                            Text(smartList.isPreset ? localizedDisplay(smartList.name) : smartList.name)
                        }
                    }
                    Button(action: onCreateSmartList) {
                        Label("New Smart List…", systemImage: "plus.circle")
                    }
                }
                Section("Review") {
                    compactDestination(.review(.automationActivity), title: "Automation Activity")
                    compactDestination(.review(.assistantQueue), title: "Pending Actions")
                }
                if let selectedCustomSmartList {
                    Button(role: .destructive) {
                        onDeleteSmartList(selectedCustomSmartList)
                    } label: {
                        Label("Delete Selected Smart List", systemImage: "trash")
                    }
                    .accessibilityIdentifier("work-hub-compact-delete-smart-list")
                    .accessibilityHint("Deletes only the currently selected custom smart list.")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.left")
                        .accessibilityHidden(true)
                    Text(label)
                    if assistantQueueCount > 0 {
                        Text(verbatim: "\(assistantQueueCount)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .help("Choose Work destination.")
            .accessibilityIdentifier("work-hub-compact-navigation")

            Spacer()
        }
        .padding(10)
    }

    private func workRow(
        _ destination: BoardRoute,
        title: LocalizedStringKey,
        systemImage: String,
        count: Int = 0
    ) -> some View {
        Label {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .tag(destination)
        .accessibilityIdentifier(workAccessibilityIdentifier(for: destination))
    }

    private func smartListRow(_ smartList: SmartList) -> some View {
        let isSelected = route == .smartList(smartList.id)
        return Label {
            if smartList.isPreset {
                Text(LocalizedStringKey(smartList.name))
            } else {
                Text(verbatim: smartList.name)
            }
        } icon: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .tag(BoardRoute.smartList(smartList.id))
        .contextMenu {
            if !smartList.isPreset {
                Button(role: .destructive) {
                    onDeleteSmartList(smartList)
                } label: {
                    Label("Delete Smart List", systemImage: "trash")
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("work-hub-smart-list-row-\(smartList.id)")
    }

    private func compactDestination(
        _ destination: BoardRoute,
        title: LocalizedStringKey
    ) -> some View {
        Button(title) {
            route = destination
        }
        .accessibilityIdentifier(workAccessibilityIdentifier(for: destination))
    }

    private var selectedCustomSmartList: SmartList? {
        guard case .smartList(let id) = route else { return nil }
        return smartLists.first(where: { $0.id == id && !$0.isPreset })
    }

    private var workSelection: Binding<BoardRoute?> {
        Binding(
            get: { selectedWorkRoute },
            set: { route = $0 ?? route }
        )
    }

    private var selectedWorkRoute: BoardRoute? {
        switch route {
        case .primary(.today): .primary(.today)
        case .primary(.inbox): .primary(.inbox)
        case .primary(.projects), .project: .primary(.projects)
        case .smartList: route
        case .review(.completed): .review(.completed)
        case .review(.automationActivity): route
        case .review(.assistantQueue), .primary(.review):
            .review(.assistantQueue)
        case .review(.schedule), .settings, .voiceCommand:
            nil
        }
    }

    private var workLabel: LocalizedStringKey {
        switch selectedWorkRoute {
        case .primary(.today): "Today"
        case .primary(.inbox): "Inbox"
        case .primary(.projects), .project: "Projects"
        case .smartList: "Smart Lists"
        case .review(.completed): "Completed"
        case .review(.automationActivity): "Automation Activity"
        case .review(.assistantQueue), .primary(.review): "Pending Actions"
        default: "Work"
        }
    }

    private func workAccessibilityIdentifier(for route: BoardRoute) -> String {
        switch route {
        case .primary(.today): "work-destination-today"
        case .primary(.inbox): "work-destination-inbox"
        case .primary(.projects): "work-destination-projects"
        case .review(.completed): "work-destination-completed"
        case .review(.automationActivity): "work-destination-activity"
        case .review(.assistantQueue), .primary(.review):
            "work-destination-pending-actions"
        case .smartList: "work-destination-smart-list"
        case .project, .review(.schedule), .settings, .voiceCommand:
            "work-destination"
        }
    }
}
