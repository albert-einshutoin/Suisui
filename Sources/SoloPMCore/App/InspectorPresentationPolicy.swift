/// The selected model that can supply editable Inspector content.
public enum InspectorSelectionContext: Equatable, Sendable {
    case none
    case project
    case task
}

/// Pure policy separating durable per-scene user intent from the Inspector's
/// effective presentation. This boundary lets resize, route invalidation, and
/// deletion hide the Inspector without silently rewriting the user's choice.
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
}
