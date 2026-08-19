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
    private let onOpenSearch: () -> Void
    private let onOpenVoiceCommand: () -> Void
    private let onAddTask: () -> Void
    private let onAddByVoice: () -> Void
    private let onBlockTime: () -> Void

    init(
        route: Binding<BoardRoute>,
        counts: ProjectBoardSidebarCounts,
        onOpenSearch: @escaping () -> Void,
        onOpenVoiceCommand: @escaping () -> Void,
        onAddTask: @escaping () -> Void,
        onAddByVoice: @escaping () -> Void,
        onBlockTime: @escaping () -> Void
    ) {
        _route = route
        self.counts = counts
        self.onOpenSearch = onOpenSearch
        self.onOpenVoiceCommand = onOpenVoiceCommand
        self.onAddTask = onAddTask
        self.onAddByVoice = onAddByVoice
        self.onBlockTime = onBlockTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(LocalizedStringKey("Suisui"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LocalizedStringKey("Suisui")))

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
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey("Search")))
            .accessibilityIdentifier("sidebar-open-search")
            .accessibilityHint(Text(LocalizedStringKey("Opens the command palette.")))
            .help(LocalizedStringKey("Opens the command palette."))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(ProjectBoardSidebarPresentation.items, id: \.id) { item in
                        sidebarRow(item)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("Quick Actions"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                quickAction(.addTask, handler: onAddTask)
                quickAction(.addByVoice, handler: onAddByVoice)
                quickAction(.blockTime, handler: onBlockTime)
            }
            .padding(SuisuiSpacing.md)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .padding(SuisuiSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-sidebar")
        .accessibilityLabel(Text(LocalizedStringKey("Project navigation")))
        .accessibilityHint(Text(LocalizedStringKey("Navigate work or open a quick action.")))
    }

    @ViewBuilder
    private func sidebarRow(
        _ item: ProjectBoardSidebarItemPresentation
    ) -> some View {
        switch item.behavior {
        case .route:
            destinationSidebarRow(item)
        case .openVoiceCommand:
            utilitySidebarRow(item)
        }
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

    @ViewBuilder
    private func utilitySidebarRow(
        _ item: ProjectBoardSidebarItemPresentation
    ) -> some View {
        // An optional mapping prevents invalid presentation data from gaining a misleading hint or crashing release builds.
        if let hintKey = utilityAccessibilityHintKey(for: item.behavior) {
            sidebarRowButton(
                item,
                isSelected: false,
                hintKey: hintKey
            )
        }
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
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
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
        case .openVoiceCommand:
            onOpenVoiceCommand()
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

    private func utilityAccessibilityHintKey(
        for behavior: ProjectBoardSidebarItemBehavior
    ) -> String? {
        switch behavior {
        case .route:
            nil
        case .openVoiceCommand:
            "Opens Voice Command."
        }
    }

    private func accessibilityHintKey(
        for action: ProjectBoardSidebarQuickAction
    ) -> String {
        switch action {
        case .addTask:
            "Opens the inline composer for a new local task."
        case .addByVoice:
            "Opens Voice Command."
        case .blockTime:
            "Creates a local schedule draft without writing Calendar."
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
        }
    }
}
