/// The selected model that can supply editable Inspector content.
public enum InspectorSelectionContext: Equatable, Sendable {
    case none
    case project
    case task
}

public struct InspectorPresentationIntent: Equatable, Sendable {
    public let userRequested: Bool
    public let allowsCompactPresentation: Bool

    public init(userRequested: Bool, allowsCompactPresentation: Bool) {
        self.userRequested = userRequested
        self.allowsCompactPresentation = allowsCompactPresentation
    }

    public static let closed = InspectorPresentationIntent(
        userRequested: false,
        allowsCompactPresentation: false
    )
}

/// Pure policy separating per-scene user intent from effective presentation.
/// Route or selection invalidation only affects visibility. Crossing from wide
/// into compact mode dismisses passive wide-window intent, while a fresh
/// explicit compact request survives delayed hosted-window geometry updates.
public enum InspectorPresentationPolicy {
    public static let wideMinimumWidth = 1_180.0

    public static func shouldPresent(
        windowWidth: Double,
        route: BoardRoute,
        selection: InspectorSelectionContext,
        userRequested: Bool,
        allowsCompactPresentation: Bool
    ) -> Bool {
        guard userRequested, selection != .none else {
            return false
        }

        switch route {
        case .project:
            guard selection == .project || selection == .task else {
                return false
            }
        case .primary(.today), .primary(.inbox):
            // These routes own persistent assistant rails. Only their explicit
            // Edit action may temporarily yield main-content space.
            guard selection == .task, allowsCompactPresentation else {
                return false
            }
        case .primary, .smartList, .review:
            return false
        }

        return windowWidth >= wideMinimumWidth || allowsCompactPresentation
    }

    public static func intentAfterResize(
        previousWindowWidth: Double,
        currentWindowWidth: Double,
        intent: InspectorPresentationIntent
    ) -> InspectorPresentationIntent {
        guard previousWindowWidth >= wideMinimumWidth,
              currentWindowWidth < wideMinimumWidth,
              !intent.allowsCompactPresentation else {
            return intent
        }

        // A passive wide-window preference closes when compacted. A fresh
        // explicit compact request is preserved above because SwiftUI can
        // report the clamped hosted-window width after the button action.
        return .closed
    }
}
