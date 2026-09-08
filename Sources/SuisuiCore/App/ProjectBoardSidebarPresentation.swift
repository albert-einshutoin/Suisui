import Foundation

public enum ProjectBoardSidebarItemID: String, CaseIterable, Hashable, Sendable {
    case secretary
    case schedule
    case work
    case settings
}

public enum ProjectBoardSidebarItemBehavior: Equatable, Sendable {
    case route(BoardRoute)
}

public struct ProjectBoardSidebarItemPresentation: Equatable, Sendable {
    public let id: ProjectBoardSidebarItemID
    public let title: String
    public let systemImage: String
    public let behavior: ProjectBoardSidebarItemBehavior

    public init(
        id: ProjectBoardSidebarItemID,
        title: String,
        systemImage: String,
        behavior: ProjectBoardSidebarItemBehavior
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.behavior = behavior
    }
}

public enum ProjectBoardSidebarQuickAction: String, CaseIterable, Hashable, Sendable {
    case addTask
    case addByVoice
    case blockTime
    case importTasks

    public var title: String {
        switch self {
        case .addTask: "Add Task"
        case .addByVoice: "Add by Voice"
        case .blockTime: "Block Time"
        case .importTasks: "Import Tasks"
        }
    }

    public var systemImage: String {
        switch self {
        case .addTask: "plus.circle"
        case .addByVoice: "mic.circle"
        case .blockTime: "calendar.badge.clock"
        case .importTasks: "square.and.arrow.down"
        }
    }
}

public enum ProjectBoardSidebarPresentation {
    public static let items: [ProjectBoardSidebarItemPresentation] = [
        .init(id: .secretary, title: "Secretary", systemImage: "person.crop.circle", behavior: .route(.voiceCommand)),
        .init(id: .schedule, title: "Schedule", systemImage: "calendar", behavior: .route(.review(.schedule))),
        .init(id: .work, title: "Work", systemImage: "checklist", behavior: .route(.primary(.today))),
    ]

    /// Settings is a utility surface, not a work destination.
    public static let utilityItems: [ProjectBoardSidebarItemPresentation] = [
        .init(id: .settings, title: "Settings", systemImage: "gearshape", behavior: .route(.settings)),
    ]

    public static func selectedItemID(for route: BoardRoute) -> ProjectBoardSidebarItemID? {
        switch route {
        case .voiceCommand:
            .secretary
        case .review(.schedule): .schedule
        case .settings: .settings
        case .primary, .project, .smartList, .review:
            .work
        }
    }
}
