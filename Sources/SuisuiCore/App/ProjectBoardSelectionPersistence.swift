import Foundation

public enum ProjectBoardSidebarDestination: Hashable, Sendable {
    case inbox
    case assistantQueue
    case today
    case catchUp
    case schedule
    case done
    case projects
    case project(Int64)

    public var title: String {
        switch self {
        case .inbox:
            "Inbox"
        case .assistantQueue:
            "Assistant Queue"
        case .today:
            "Today"
        case .catchUp:
            "Catch Up"
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
        case .assistantQueue:
            "tray.full"
        case .today:
            "sun.max"
        case .catchUp:
            "clock.badge.exclamationmark"
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
        case .assistantQueue:
            "assistant-queue"
        case .today:
            "today"
        case .catchUp:
            "catch-up"
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
    public static let storageKey = "suisui.projectBoard.selectedDestination"
    public static let environmentOverrideKey = "SUISUI_PROJECT_BOARD_SELECTED_DESTINATION"
    public static let defaultRawValue = "today"

    public static var environmentOverrideRawValue: String? {
        let rawValue = ProcessInfo.processInfo.environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawValue?.isEmpty == false ? rawValue : nil
    }

    /// Temporary encoder for command and payload adapters that still speak the
    /// former destination type. It cannot delegate to the typed codec because
    /// `.catchUp` remains a distinct compatibility signal while `BoardRoute`
    /// renders it contextually inside Today. Remove this with
    /// `ProjectBoardSidebarDestination` after every adapter uses `BoardRoute`.
    public static func rawValue(for destination: ProjectBoardSidebarDestination) -> String {
        switch destination {
        case .inbox:
            return "inbox"
        case .assistantQueue:
            return "assistant-queue"
        case .today:
            return "today"
        case .catchUp:
            return "catch-up"
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

    /// Persists typed routes using the new stable codec while the explicitly
    /// named adapter avoids ambiguity with legacy `.project(42)` shorthand.
    public static func rawValue(forTypedRoute route: BoardRoute) -> String {
        ProjectBoardRouteCodec.rawValue(for: route)
    }

    /// Adapts the existing project model input to the typed route codec without
    /// changing the legacy destination API still used by the current UI.
    public static func route(
        from rawValue: String,
        availableProjects: [ProjectBoardProject]
    ) -> BoardRoute {
        ProjectBoardRouteCodec.route(
            from: rawValue,
            availableProjectIDs: Set(availableProjects.map(\.id))
        )
    }

    /// Temporary compatibility decoder paired with the legacy encoder above.
    /// It intentionally preserves `.catchUp`; consolidating it into Today now
    /// would change production UI behavior before the typed sidebar migration.
    public static func destination(
        from rawValue: String,
        availableProjects: [ProjectBoardProject]
    ) -> ProjectBoardSidebarDestination {
        switch rawValue {
        case "inbox":
            return .inbox
        case "assistant-queue":
            return .assistantQueue
        case "today":
            return .today
        case "catch-up":
            return .catchUp
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
    public static let environmentOverrideKey = "SUISUI_PROJECT_BOARD_SELECTED_TASK_ID"

    public static var environmentOverrideTaskID: Int64? {
        let rawValue = ProcessInfo.processInfo.environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty, let taskID = Int64(rawValue), taskID > 0 else {
            return nil
        }
        return taskID
    }

    public static var environmentSuppressesInboxAutoSelection: Bool {
        ProcessInfo.processInfo.environment["SUISUI_INBOX_EVIDENCE_CLEAR_SELECTION"] == "1"
    }
}
