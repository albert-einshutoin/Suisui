public struct ProjectBoardCompactNavigationPresentation: Equatable, Sendable {
    public enum Label: Equatable, Sendable {
        case localized(String)
        case verbatim(String)
    }

    public let label: Label
    public let badgeCount: Int?

    public init(label: Label, badgeCount: Int? = nil) {
        self.label = label
        self.badgeCount = badgeCount
    }

    public static func review(
        route: BoardRoute,
        assistantQueueCount: Int
    ) -> ProjectBoardCompactNavigationPresentation {
        switch route {
        case .primary(.review):
            return ProjectBoardCompactNavigationPresentation(label: .localized("Review"))
        case .review(.schedule):
            return ProjectBoardCompactNavigationPresentation(label: .localized("Schedule"))
        case .review(.completed):
            return ProjectBoardCompactNavigationPresentation(label: .localized("Completed"))
        case .review(.automationActivity):
            return ProjectBoardCompactNavigationPresentation(label: .localized("Automation Activity"))
        case .review(.assistantQueue):
            return ProjectBoardCompactNavigationPresentation(
                label: .localized("Assistant Queue"),
                badgeCount: assistantQueueCount > 0 ? assistantQueueCount : nil
            )
        default:
            return ProjectBoardCompactNavigationPresentation(label: .localized("Review"))
        }
    }

    public static func projects(
        route: BoardRoute,
        projects: [ProjectBoardProject],
        smartLists: [SmartList]
    ) -> ProjectBoardCompactNavigationPresentation {
        switch route {
        case .primary(.projects):
            return ProjectBoardCompactNavigationPresentation(label: .localized("Portfolio"))
        case .project(let projectID):
            guard let project = projects.first(where: { $0.id == projectID }) else {
                return ProjectBoardCompactNavigationPresentation(label: .localized("Project Not Found"))
            }
            // User-authored titles are display content, not localization keys;
            // verbatim handling preserves the exact text and avoids accidental lookup collisions.
            return ProjectBoardCompactNavigationPresentation(label: .verbatim(project.title))
        case .smartList(let smartListID):
            guard let smartList = smartLists.first(where: { $0.id == smartListID }) else {
                return ProjectBoardCompactNavigationPresentation(label: .localized("Smart List Not Found"))
            }
            if smartList.isPreset {
                return ProjectBoardCompactNavigationPresentation(label: .localized(smartList.name))
            }
            // Custom smart-list names are user-authored for the same reason as project titles.
            return ProjectBoardCompactNavigationPresentation(label: .verbatim(smartList.name))
        default:
            return ProjectBoardCompactNavigationPresentation(label: .localized("Project Not Found"))
        }
    }
}
