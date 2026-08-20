import Foundation

public enum ProjectBoardSidebarItemID: String, CaseIterable, Hashable, Sendable {
    case inbox
    case today
    case projects
    case schedule
    case completed
    case voiceCommand
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

    public var title: String {
        switch self {
        case .addTask: "Add Task"
        case .addByVoice: "Add by Voice"
        case .blockTime: "Block Time"
        }
    }

    public var systemImage: String {
        switch self {
        case .addTask: "plus.circle"
        case .addByVoice: "mic.circle"
        case .blockTime: "calendar.badge.clock"
        }
    }
}

public enum ProjectBoardSidebarPresentation {
    public static let items: [ProjectBoardSidebarItemPresentation] = [
        .init(id: .inbox, title: "Inbox", systemImage: "tray", behavior: .route(.primary(.inbox))),
        .init(id: .today, title: "Today", systemImage: "sun.max", behavior: .route(.primary(.today))),
        .init(id: .projects, title: "Projects", systemImage: "folder", behavior: .route(.primary(.projects))),
        .init(id: .schedule, title: "Schedule", systemImage: "calendar", behavior: .route(.review(.schedule))),
        .init(id: .completed, title: "Completed", systemImage: "checkmark.circle", behavior: .route(.review(.completed))),
        .init(id: .voiceCommand, title: "Voice Command", systemImage: "mic", behavior: .route(.voiceCommand)),
        .init(id: .settings, title: "Settings", systemImage: "gearshape", behavior: .route(.settings)),
    ]

    public static func selectedItemID(for route: BoardRoute) -> ProjectBoardSidebarItemID? {
        switch route {
        case .primary(.inbox): .inbox
        case .primary(.today): .today
        case .primary(.projects), .project, .smartList: .projects
        case .review(.schedule): .schedule
        case .review(.completed): .completed
        case .settings: .settings
        case .voiceCommand: .voiceCommand
        // These routes have no dedicated sidebar row; selecting a nearby row
        // would falsely imply the user is viewing that destination.
        case .primary(.review), .review(.automationActivity), .review(.assistantQueue): nil
        }
    }
}
