public struct AssistantQueueRowActionPresentation: Equatable, Sendable {
    public enum Action: Hashable, Sendable {
        case approve
        case run
        case reopen
        case edit
        case `defer`
        case reject
    }

    public let primaryAction: Action?
    public let secondaryActions: [Action]

    private init(primaryAction: Action?, secondaryActions: [Action]) {
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }

    public static func make(for row: AssistantQueueReadModelRow) -> Self {
        let capabilities = actionsEnabled(on: row)

        if row.state == .running {
            // Reject does not cancel the in-flight execution coordinator. Hiding it
            // avoids presenting a false cancellation control while work is running.
            return Self(primaryAction: nil, secondaryActions: [])
        }

        guard capabilities.isSubset(of: allowedActions(for: row.state)) else {
            return Self(primaryAction: nil, secondaryActions: [])
        }

        let primaryCandidates = [Action.approve, .run, .reopen].filter(capabilities.contains)
        guard primaryCandidates.count <= 1 else {
            return Self(primaryAction: nil, secondaryActions: [])
        }

        let secondaryActions = [Action.edit, .defer, .reject].filter(capabilities.contains)
        return Self(
            primaryAction: primaryCandidates.first,
            secondaryActions: secondaryActions
        )
    }

    private static func actionsEnabled(on row: AssistantQueueReadModelRow) -> Set<Action> {
        var actions: Set<Action> = []
        if row.canApprove { actions.insert(.approve) }
        if row.canRun { actions.insert(.run) }
        if row.canRetry { actions.insert(.reopen) }
        if row.canEdit { actions.insert(.edit) }
        if row.canDefer { actions.insert(.defer) }
        if row.canReject { actions.insert(.reject) }
        return actions
    }

    private static func allowedActions(for state: AssistantQueueState) -> Set<Action> {
        switch state {
        case .captured, .interpreted, .drafted, .waitingReview:
            return [.approve, .edit, .defer, .reject]
        case .approved:
            return [.run, .edit, .defer, .reject]
        case .running, .blocked:
            return [.reject]
        case .failed:
            return [.reopen]
        case .deferred:
            return [.approve, .edit, .reject]
        case .done, .rejected:
            return []
        }
    }
}
