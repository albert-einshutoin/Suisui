import Foundation

public enum ProjectBoardSidebarDestination: Hashable, Sendable {
    case inbox
    case today
    case schedule
    case done
    case projects
    case project(Int64)

    public var title: String {
        switch self {
        case .inbox:
            "Inbox"
        case .today:
            "Today"
        case .schedule:
            "Schedule"
        case .done:
            "Done"
        case .projects:
            "Projects"
        case .project:
            "Project"
        }
    }

    public var systemImage: String {
        switch self {
        case .inbox:
            "tray"
        case .today:
            "sun.max"
        case .schedule:
            "calendar"
        case .done:
            "checkmark.circle"
        case .projects:
            "folder.circle"
        case .project:
            "folder"
        }
    }

    public var accessibilityIdentifierSuffix: String {
        switch self {
        case .inbox:
            "inbox"
        case .today:
            "today"
        case .schedule:
            "schedule"
        case .done:
            "done"
        case .projects:
            "projects"
        case .project(let projectID):
            "project-\(projectID)"
        }
    }

    public func accessibilityLabel(count: Int) -> String {
        "\(title), \(count) item\(count == 1 ? "" : "s")"
    }
}

public enum ProjectBoardSelectionPersistence {
    public static let storageKey = "solopm.projectBoard.selectedDestination"
    public static let environmentOverrideKey = "SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION"
    public static let defaultRawValue = "today"

    public static var environmentOverrideRawValue: String? {
        let rawValue = ProcessInfo.processInfo.environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawValue?.isEmpty == false ? rawValue : nil
    }

    public static func rawValue(for destination: ProjectBoardSidebarDestination) -> String {
        switch destination {
        case .inbox:
            return "inbox"
        case .today:
            return "today"
        case .schedule:
            return "schedule"
        case .done:
            return "done"
        case .projects:
            return "projects"
        case .project(let projectID):
            return "project:\(projectID)"
        }
    }

    public static func destination(
        from rawValue: String,
        availableProjects: [ProjectBoardProject]
    ) -> ProjectBoardSidebarDestination {
        switch rawValue {
        case "inbox":
            return .inbox
        case "today":
            return .today
        case "schedule":
            return .schedule
        case "done":
            return .done
        case "projects":
            return .projects
        default:
            let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return .today
            }
            switch parts[0] {
            case "project":
                // Saved app state can outlive a project row. Falling back to
                // Today keeps launch deterministic for empty or reseeded DBs.
                guard let projectID = Int64(parts[1]),
                      availableProjects.contains(where: { $0.id == projectID }) else {
                    return .today
                }
                return .project(projectID)
            default:
                return .today
            }
        }
    }
}

public enum ProjectBoardTaskSelectionPersistence {
    public static let environmentOverrideKey = "SOLOPM_PROJECT_BOARD_SELECTED_TASK_ID"

    public static var environmentOverrideTaskID: Int64? {
        let rawValue = ProcessInfo.processInfo.environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty, let taskID = Int64(rawValue), taskID > 0 else {
            return nil
        }
        return taskID
    }
}
