import AppKit
import SuisuiCore
import SwiftUI

struct ProjectBoardSidebarCounts: Equatable {
    let today: Int
    let inbox: Int
    let projects: Int
    let schedule: Int
    let completed: Int

    init(
        today: Int,
        inbox: Int,
        projects: Int,
        schedule: Int,
        completed: Int
    ) {
        self.today = today
        self.inbox = inbox
        self.projects = projects
        self.schedule = schedule
        self.completed = completed
    }

    func count(for itemID: ProjectBoardSidebarItemID) -> Int? {
        switch itemID {
        case .today: today
        case .inbox: inbox
        case .projects: projects
        case .schedule: schedule
        case .completed: completed
        case .voiceCommand, .settings: nil
        }
    }
}

struct ProjectBoardSidebarView: View {
    @Binding private var route: BoardRoute
    private let counts: ProjectBoardSidebarCounts
    private let profileDisplayName: String
    private let planLabel: String?
    private let onOpenSearch: () -> Void
    private let onAddTask: () -> Void
    private let onAddByVoice: () -> Void
    private let onBlockTime: () -> Void
    private let onImportTasks: () -> Void

    init(
        route: Binding<BoardRoute>,
        counts: ProjectBoardSidebarCounts,
        profileDisplayName: String = "",
        planLabel: String? = nil,
        onOpenSearch: @escaping () -> Void,
        onAddTask: @escaping () -> Void,
        onAddByVoice: @escaping () -> Void,
        onBlockTime: @escaping () -> Void,
        onImportTasks: @escaping () -> Void
    ) {
        _route = route
        self.counts = counts
        self.profileDisplayName = profileDisplayName
        self.planLabel = planLabel
        self.onOpenSearch = onOpenSearch
        self.onAddTask = onAddTask
        self.onAddByVoice = onAddByVoice
        self.onBlockTime = onBlockTime
        self.onImportTasks = onImportTasks
    }

    private var resolvedProfileDisplayName: String {
        let trimmed = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localizedDisplay("Local profile") : trimmed
    }

    private var profileInitial: String {
        let trimmed = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "L"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
                Text(LocalizedStringKey("Suisui"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LocalizedStringKey("Suisui")))

            // Search, destinations, and Quick Actions share one Liquid Glass
            // sampling region. Destinations stay outside a ScrollView so all
            // seven sample items remain visible at the 1024×676 contract.
            VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
                Button(action: onOpenSearch) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .accessibilityHidden(true)
                        Text(LocalizedStringKey("Search"))
                        Spacer()
                        Text(LocalizedStringKey("⌘K"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
                    .suisuiLiquidGlassControlSurface(cornerRadius: 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey("Search")))
                .accessibilityIdentifier("sidebar-open-search")
                .accessibilityHint(Text(LocalizedStringKey("Opens the command palette.")))
                .help(LocalizedStringKey("Opens the command palette."))

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(ProjectBoardSidebarPresentation.items, id: \.id) { item in
                        sidebarRow(item)
                    }
                }
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("Quick Actions"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    quickAction(.addTask, handler: onAddTask)
                    quickAction(.addByVoice, handler: onAddByVoice)
                    quickAction(.blockTime, handler: onBlockTime)
                    quickAction(.importTasks, handler: onImportTasks)
                }
                .padding(SuisuiSpacing.sm)
                .suisuiLiquidGlassControlSurface(cornerRadius: 12)
            }
            .suisuiLiquidGlassControlGroup(spacing: SuisuiSpacing.sm)

            Spacer(minLength: 0)

            profileFooter
        }
        .padding(.horizontal, SuisuiSpacing.md)
        .padding(.vertical, SuisuiSpacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-sidebar")
        .accessibilityLabel(Text(LocalizedStringKey("Project navigation")))
        .accessibilityHint(Text(LocalizedStringKey("Navigate work or open a quick action.")))
    }

    private var profileFooter: some View {
        HStack(spacing: 10) {
            Text(profileInitial)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedProfileDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let planLabel, !planLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(planLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("sidebar-profile")
        .accessibilityLabel(Text(resolvedProfileDisplayName))
        .accessibilityValue(
            planLabel.flatMap { label in
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? ""
        )
    }

    @ViewBuilder
    private func sidebarRow(
        _ item: ProjectBoardSidebarItemPresentation
    ) -> some View {
        destinationSidebarRow(item)
    }

    private func destinationSidebarRow(
        _ item: ProjectBoardSidebarItemPresentation
    ) -> some View {
        let isSelected = ProjectBoardSidebarPresentation.selectedItemID(for: route) == item.id

        return sidebarRowButton(
            item,
            isSelected: isSelected,
            hintKey: "Opens this section."
        )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sidebarRowButton(
        _ item: ProjectBoardSidebarItemPresentation,
        isSelected: Bool,
        hintKey: String
    ) -> some View {
        let count = counts.count(for: item.id)

        return Button {
            perform(item.behavior)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(item.title))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.accentColor)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.12),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(item.title)))
        .accessibilityValue(countAccessibilityValue(for: item.id))
        .accessibilityIdentifier(accessibilityIdentifier(for: item.id))
        .accessibilityHint(Text(LocalizedStringKey(hintKey)))
        .help(LocalizedStringKey(hintKey))
    }

    private func quickAction(
        _ action: ProjectBoardSidebarQuickAction,
        handler: @escaping () -> Void
    ) -> some View {
        Button(action: handler) {
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(action.title))
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .suisuiLiquidGlassControlSurface(
                    cornerRadius: 10,
                    interactive: true
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(action.title)))
        .accessibilityIdentifier(quickActionAccessibilityIdentifier(for: action))
        .accessibilityHint(Text(LocalizedStringKey(accessibilityHintKey(for: action))))
        .help(LocalizedStringKey(accessibilityHintKey(for: action)))
    }

    private func perform(_ behavior: ProjectBoardSidebarItemBehavior) {
        switch behavior {
        case .route(let destination):
            route = destination
        }
    }

    private func countAccessibilityValue(for itemID: ProjectBoardSidebarItemID) -> String {
        guard let count = counts.count(for: itemID) else {
            return ""
        }
        guard count > 0 else {
            return switch itemID {
            case .inbox: localizedDisplay("No pending items")
            case .today: localizedDisplay("No items today")
            case .projects: localizedDisplay("No projects")
            case .schedule: localizedDisplay("No scheduled items")
            case .completed: localizedDisplay("No completed items")
            case .voiceCommand, .settings: ""
            }
        }
        return localizedCount(count, one: "%d item", other: "%d items")
    }

    private func accessibilityHintKey(
        for action: ProjectBoardSidebarQuickAction
    ) -> String {
        switch action {
        case .addTask:
            "Opens the inline composer for a new local task."
        case .addByVoice:
            "Opens Voice Quick Capture."
        case .blockTime:
            "Creates a local schedule draft without writing Calendar."
        case .importTasks:
            "Imports tasks from a local JSON file."
        }
    }

    private func accessibilityIdentifier(for itemID: ProjectBoardSidebarItemID) -> String {
        switch itemID {
        case .inbox: "sidebar-destination-inbox"
        case .today: "sidebar-destination-today"
        case .projects: "sidebar-destination-projects"
        case .schedule: "sidebar-destination-schedule"
        case .completed: "sidebar-destination-completed"
        case .voiceCommand: "sidebar-action-voice-command"
        case .settings: "sidebar-action-settings"
        }
    }

    private func quickActionAccessibilityIdentifier(
        for action: ProjectBoardSidebarQuickAction
    ) -> String {
        switch action {
        case .addTask: "sidebar-quick-add-task"
        case .addByVoice: "sidebar-quick-add-by-voice"
        case .blockTime: "sidebar-quick-block-time"
        case .importTasks: "sidebar-quick-import-tasks"
        }
    }
}
