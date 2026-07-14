import Foundation

/// The four stable top-level areas of the Project Board.
public enum BoardPrimaryDestination: String, CaseIterable, Hashable, Sendable {
    case today
    case inbox
    case projects
    case review
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
}

/// Deterministic conversion between persisted route strings and typed routes.
public enum ProjectBoardRouteCodec {
    /// Decodes both current stable values and legacy fixture values.
    public static func route(
        from rawValue: String,
        availableProjectIDs: Set<Int64>
    ) -> BoardRoute {
        switch rawValue {
        case "today", "catch-up", "primary:today":
            return .primary(.today)
        case "inbox", "primary:inbox":
            return .primary(.inbox)
        case "projects", "primary:projects":
            return .primary(.projects)
        case "primary:review":
            return .primary(.review)
        case "schedule", "review:schedule":
            return .review(.schedule)
        case "done", "review:completed":
            return .review(.completed)
        case "review:automation":
            return .review(.automationActivity)
        case "assistant-queue", "review:assistant-queue":
            return .review(.assistantQueue)
        default:
            return dynamicRoute(from: rawValue, availableProjectIDs: availableProjectIDs)
        }
    }

    /// Encodes only valid routes in the new stable representation, returning
    /// `nil` when an associated identifier cannot be decoded symmetrically.
    public static func rawValue(for route: BoardRoute) -> String? {
        switch route {
        case .primary(let destination):
            return "primary:\(destination.rawValue)"
        case .project(let projectID):
            guard Validation.accepts(projectID: projectID) else {
                return nil
            }
            return "project:\(projectID)"
        case .smartList(let smartListID):
            guard Validation.accepts(smartListID: smartListID) else {
                return nil
            }
            return "smart-list:\(smartListID)"
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
                  Validation.accepts(projectID: projectID),
                  availableProjectIDs.contains(projectID) else {
                return .primary(.today)
            }
            return .project(projectID)
        case "smart-list":
            guard Validation.accepts(smartListID: identifier) else {
                return .primary(.today)
            }
            return .smartList(identifier)
        default:
            return .primary(.today)
        }
    }

    /// Route payload validity belongs to the codec rather than callers so
    /// decoding and encoding cannot silently drift into asymmetric behavior.
    private enum Validation {
        static func accepts(projectID: Int64) -> Bool {
            projectID > 0
        }

        static func accepts(smartListID: String) -> Bool {
            guard let firstCharacter = smartListID.first,
                  let lastCharacter = smartListID.last,
                  !firstCharacter.isWhitespace,
                  !lastCharacter.isWhitespace else {
                return false
            }

            return !smartListID.unicodeScalars.contains { scalar in
                CharacterSet.controlCharacters.contains(scalar)
            }
        }
    }
}
