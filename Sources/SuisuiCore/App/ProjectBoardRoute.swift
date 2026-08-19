import Foundation

/// The four stable top-level areas of the Project Board.
public enum BoardPrimaryDestination: String, CaseIterable, Hashable, Sendable {
    case today
    case inbox
    case projects
    case review

    /// ⌘1–⌘4 must land on the same rows the sidebar renders, in the same
    /// order, or the shortcut and the list disagree about what "2" means.
    /// `ProjectBoardSidebarView` renders this order.
    public static let orderedForKeyboardSelection: [BoardPrimaryDestination] = [
        .today, .inbox, .projects, .review
    ]
}

/// A workflow presented within the consolidated Review area.
public enum ReviewRoute: String, CaseIterable, Hashable, Sendable {
    case schedule
    case completed
    case automationActivity
    case assistantQueue
}

/// A typed destination that can be shared by persistence and scene navigation.
public enum BoardRoute: Hashable, Sendable {
    case primary(BoardPrimaryDestination)
    case project(Int64)
    case smartList(String)
    case review(ReviewRoute)
    case settings
}

/// A contextual focus preserved while an older route is migrated into the
/// stable four-area information architecture.
public enum BoardRouteFocus: Hashable, Sendable {
    case catchUp
}

/// Pure decoding result. `route` remains safe to persist while `focus` is a
/// one-shot presentation intent owned by the window that decoded it.
public struct ProjectBoardRouteResolution: Equatable, Sendable {
    public let route: BoardRoute
    public let focus: BoardRouteFocus?

    public init(route: BoardRoute, focus: BoardRouteFocus?) {
        self.route = route
        self.focus = focus
    }
}

public enum ProjectBoardHubPresentation: Equatable, Sendable {
    case compact
    case wide
}

/// Nested hub navigation yields its column before the primary content becomes
/// cramped. Keeping the threshold pure makes the 960-point product contract
/// testable without coupling Core to SwiftUI geometry.
public enum ProjectBoardHubPresentationPolicy {
    public static let wideMinimumWidth = 1_100.0

    public static func presentation(for availableWidth: Double) -> ProjectBoardHubPresentation {
        availableWidth >= wideMinimumWidth ? .wide : .compact
    }
}

/// Deterministic conversion between persisted route strings and typed routes.
public enum ProjectBoardRouteCodec {
    /// Decodes both current stable values and historical persisted values.
    public static func route(
        from rawValue: String,
        availableProjectIDs: Set<Int64>
    ) -> BoardRoute {
        resolution(
            from: rawValue,
            availableProjectIDs: availableProjectIDs
        ).route
    }

    /// Preserves contextual migration intent without expanding the stable
    /// `BoardRoute` model with presentation-only destinations.
    public static func resolution(
        from rawValue: String,
        availableProjectIDs: Set<Int64>
    ) -> ProjectBoardRouteResolution {
        let route: BoardRoute
        let focus: BoardRouteFocus?
        switch rawValue {
        case "catch-up":
            route = .primary(.today)
            focus = .catchUp
        case "today", "primary:today":
            route = .primary(.today)
            focus = nil
        case "inbox", "primary:inbox":
            route = .primary(.inbox)
            focus = nil
        case "projects", "primary:projects":
            route = .primary(.projects)
            focus = nil
        case "primary:review":
            route = .primary(.review)
            focus = nil
        case "schedule", "review:schedule":
            route = .review(.schedule)
            focus = nil
        case "done", "review:completed":
            route = .review(.completed)
            focus = nil
        case "review:automation":
            route = .review(.automationActivity)
            focus = nil
        case "assistant-queue", "review:assistant-queue":
            route = .review(.assistantQueue)
            focus = nil
        case "settings":
            route = .settings
            focus = nil
        default:
            route = dynamicRoute(from: rawValue, availableProjectIDs: availableProjectIDs)
            focus = nil
        }
        return ProjectBoardRouteResolution(route: route, focus: focus)
    }

    /// Encodes every route in the new stable representation.
    public static func rawValue(for route: BoardRoute) -> String {
        switch route {
        case .primary(let destination):
            return "primary:\(destination.rawValue)"
        case .project(let projectID):
            return "project:\(projectID)"
        case .smartList(let smartListID):
            // Smart List IDs are public opaque Strings. A versioned UTF-8
            // encoding preserves every value without delimiter or whitespace loss.
            let payload = Data(smartListID.utf8).base64EncodedString()
            return "smart-list-v1:\(payload)"
        case .review(let reviewRoute):
            switch reviewRoute {
            case .schedule:
                return "review:schedule"
            case .completed:
                return "review:completed"
            case .automationActivity:
                return "review:automation"
            case .assistantQueue:
                return "review:assistant-queue"
            }
        case .settings:
            return "settings"
        }
    }

    private static func dynamicRoute(
        from rawValue: String,
        availableProjectIDs: Set<Int64>
    ) -> BoardRoute {
        let components = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else {
            return .primary(.today)
        }

        let kind = components[0]
        let identifier = String(components[1])
        switch kind {
        case "project":
            // Persisted selections can outlive their database rows. Falling
            // back avoids restoring a route whose project can no longer load.
            guard let projectID = Int64(identifier),
                  availableProjectIDs.contains(projectID) else {
                return .primary(.today)
            }
            return .project(projectID)
        case "smart-list-v1":
            return canonicalSmartListRoute(from: identifier)
        case "smart-list":
            guard LegacySmartListValidation.accepts(identifier) else {
                return .primary(.today)
            }
            return .smartList(identifier)
        default:
            return .primary(.today)
        }
    }

    private static func canonicalSmartListRoute(from payload: String) -> BoardRoute {
        guard let data = Data(base64Encoded: payload),
              data.base64EncodedString() == payload,
              let identifier = String(data: data, encoding: .utf8) else {
            return .primary(.today)
        }
        return .smartList(identifier)
    }

    /// Legacy values predate the total v1 encoding and remain intentionally
    /// narrower. A separate canonical kind keeps every opaque legacy ID valid.
    private enum LegacySmartListValidation {
        static func accepts(_ identifier: String) -> Bool {
            guard let firstCharacter = identifier.first,
                  let lastCharacter = identifier.last,
                  !firstCharacter.isWhitespace,
                  !lastCharacter.isWhitespace else {
                return false
            }

            return !identifier.unicodeScalars.contains { scalar in
                CharacterSet.controlCharacters.contains(scalar)
            }
        }
    }
}
