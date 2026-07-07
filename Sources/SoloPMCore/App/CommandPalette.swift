import Foundation

/// Actions the Project Board command palette (⌘K) can execute.
public enum CommandPaletteActionKind: Equatable, Sendable {
    /// Creates a task in the Inbox from the palette query text. Natural-language
    /// due-date parsing happens downstream in `createInboxTask`, not here.
    case createInboxTask(title: String)
    case openDestination(ProjectBoardSidebarDestination)
    case openProject(id: Int64, title: String)
    case openSmartList(id: String, name: String)
    case openVoiceCommandWindow
    case openSettingsWindow
}

public struct CommandPaletteItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let kind: CommandPaletteActionKind

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        kind: CommandPaletteActionKind
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.kind = kind
    }
}

/// Pure composition logic for the command palette so ordering, filtering, and
/// capping stay deterministic and unit-testable without SwiftUI.
public enum CommandPaletteComposer {
    public static let maxItemCount = 12
    public static let maxEmptyQueryProjectCount = 5

    /// Sidebar destinations offered by the palette, in default display order.
    public static let defaultDestinations: [ProjectBoardSidebarDestination] = [
        .today,
        .inbox,
        .assistantQueue,
        .schedule,
        .done,
        .catchUp
    ]

    public static func items(
        query: String,
        projects: [(id: Int64, title: String, isArchived: Bool)],
        destinations: [ProjectBoardSidebarDestination] = defaultDestinations,
        smartLists: [(id: String, name: String)] = []
    ) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeProjects = projects.filter { !$0.isArchived }

        guard !trimmedQuery.isEmpty else {
            var items = destinations.map(destinationItem)
            items.append(voiceCommandWindowItem)
            items.append(settingsWindowItem)
            items.append(contentsOf: smartLists.map(smartListItem))
            items.append(contentsOf: activeProjects.prefix(maxEmptyQueryProjectCount).map(projectItem))
            return Array(items.prefix(maxItemCount))
        }

        var candidates = destinations.map(destinationItem)
        candidates.append(voiceCommandWindowItem)
        candidates.append(settingsWindowItem)
        candidates.append(contentsOf: smartLists.map(smartListItem))
        candidates.append(contentsOf: activeProjects.map(projectItem))

        let matches = candidates
            .compactMap { item -> (item: CommandPaletteItem, score: Int)? in
                guard let score = fuzzyScore(query: trimmedQuery, candidate: item.title) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.item.title != rhs.item.title {
                    return lhs.item.title < rhs.item.title
                }
                return lhs.item.id < rhs.item.id
            }

        var items = [createInboxTaskItem(title: trimmedQuery)]
        items.append(contentsOf: matches.map(\.item))
        return Array(items.prefix(maxItemCount))
    }

    /// Case-insensitive subsequence match. Returns nil when `query` is not a
    /// subsequence of `candidate`; otherwise a deterministic score that rewards
    /// contiguous prefixes, word boundaries, and contiguous runs.
    public static func fuzzyScore(query: String, candidate: String) -> Int? {
        let queryCharacters = Array(query.lowercased())
        let candidateCharacters = Array(candidate.lowercased())
        guard !queryCharacters.isEmpty else {
            return 0
        }
        guard queryCharacters.count <= candidateCharacters.count else {
            return nil
        }

        var score = 0
        var queryIndex = 0
        var previousMatchIndex = -2
        for candidateIndex in candidateCharacters.indices {
            guard queryIndex < queryCharacters.count else {
                break
            }
            guard candidateCharacters[candidateIndex] == queryCharacters[queryIndex] else {
                continue
            }
            score += 1
            if candidateIndex == previousMatchIndex + 1 {
                score += 2
            }
            if candidateIndex == 0 {
                score += 4
            } else {
                let previousCharacter = candidateCharacters[candidateIndex - 1]
                if !previousCharacter.isLetter && !previousCharacter.isNumber {
                    score += 3
                }
            }
            previousMatchIndex = candidateIndex
            queryIndex += 1
        }
        guard queryIndex == queryCharacters.count else {
            return nil
        }
        if candidateCharacters.starts(with: queryCharacters) {
            score += 5
        }
        return score
    }

    private static func destinationItem(_ destination: ProjectBoardSidebarDestination) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "destination-\(destination.accessibilityIdentifierSuffix)",
            title: destination.title,
            systemImage: destination.systemImage,
            kind: .openDestination(destination)
        )
    }

    private static func projectItem(_ project: (id: Int64, title: String, isArchived: Bool)) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "project-\(project.id)",
            title: project.title,
            systemImage: "folder",
            kind: .openProject(id: project.id, title: project.title)
        )
    }

    private static func smartListItem(_ smartList: (id: String, name: String)) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "smart-list-\(smartList.id)",
            title: smartList.name,
            subtitle: "Smart List",
            systemImage: "line.3.horizontal.decrease.circle",
            kind: .openSmartList(id: smartList.id, name: smartList.name)
        )
    }

    private static var voiceCommandWindowItem: CommandPaletteItem {
        CommandPaletteItem(
            id: "window-voice-command",
            title: "Voice Command",
            systemImage: "mic",
            kind: .openVoiceCommandWindow
        )
    }

    private static var settingsWindowItem: CommandPaletteItem {
        CommandPaletteItem(
            id: "window-settings",
            title: "Settings",
            systemImage: "gearshape",
            kind: .openSettingsWindow
        )
    }

    private static func createInboxTaskItem(title: String) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "create-inbox-task",
            title: title,
            subtitle: "Add to Inbox",
            systemImage: "plus.circle",
            kind: .createInboxTask(title: title)
        )
    }
}
