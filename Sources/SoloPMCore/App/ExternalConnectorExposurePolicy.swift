import Foundation

public enum ExternalConnectorProductID: String, CaseIterable, Equatable, Sendable {
    case googleCalendar = "google-calendar"
    case slack
    case gmail
    case googleDrive = "google-drive"
    case notion
    case todoist
    case linear
    case githubIssues = "github-issues"
}

public enum ExternalConnectorExposureState: String, Equatable, Sendable {
    case visible
    case assistantQueueDraftOnly = "assistant-queue-draft-only"
    case internalOnly = "internal"
    case notSupported = "not-supported"
}

public struct ExternalConnectorExposure: Equatable, Sendable {
    public var id: ExternalConnectorProductID
    public var displayName: String
    public var state: ExternalConnectorExposureState
    public var detail: String
    public var systemImage: String

    public init(
        id: ExternalConnectorProductID,
        displayName: String,
        state: ExternalConnectorExposureState,
        detail: String,
        systemImage: String
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.detail = detail
        self.systemImage = systemImage
    }
}

public enum ExternalConnectorExposurePolicy {
    public static let all: [ExternalConnectorExposure] = [
        ExternalConnectorExposure(
            id: .googleCalendar,
            displayName: "Google Calendar",
            state: .visible,
            detail: "Settings owns OAuth, readiness, writable calendar selection, and disconnect controls.",
            systemImage: "calendar.badge.plus"
        ),
        ExternalConnectorExposure(
            id: .slack,
            displayName: "Slack",
            state: .assistantQueueDraftOnly,
            detail: "External message requests stay reviewable in Assistant Queue; SoloPM does not send directly.",
            systemImage: "bubble.left.and.bubble.right"
        ),
        ExternalConnectorExposure(
            id: .gmail,
            displayName: "Gmail",
            state: .assistantQueueDraftOnly,
            detail: "Mail requests create reviewed drafts only until account, revoke, and audit UI exists.",
            systemImage: "envelope"
        ),
        ExternalConnectorExposure(
            id: .googleDrive,
            displayName: "Google Drive",
            state: .internalOnly,
            detail: "Document connector code remains internal until permission and file-selection UI is complete.",
            systemImage: "externaldrive"
        ),
        ExternalConnectorExposure(
            id: .notion,
            displayName: "Notion",
            state: .internalOnly,
            detail: "Database mapping infrastructure is not product-visible without connect and revoke UI.",
            systemImage: "doc.richtext"
        ),
        ExternalConnectorExposure(
            id: .todoist,
            displayName: "Todoist",
            state: .notSupported,
            detail: "Task import/export remains local until product-visible authorization is designed.",
            systemImage: "checklist"
        ),
        ExternalConnectorExposure(
            id: .linear,
            displayName: "Linear",
            state: .notSupported,
            detail: "Issue sync is not exposed until team-scoped authorization and audit UI exists.",
            systemImage: "line.3.horizontal.decrease.circle"
        ),
        ExternalConnectorExposure(
            id: .githubIssues,
            displayName: "GitHub Issues",
            state: .notSupported,
            detail: "Issue writes stay out of Settings until repository-scoped connect and revoke UI exists.",
            systemImage: "number"
        )
    ]

    public static var settingsVisible: [ExternalConnectorExposure] {
        all.filter { $0.state == .visible }
    }

    public static var assistantQueueDraftOnly: [ExternalConnectorExposure] {
        all.filter { $0.state == .assistantQueueDraftOnly }
    }

    public static func exposure(for id: ExternalConnectorProductID) -> ExternalConnectorExposure {
        all.first { $0.id == id }!
    }
}
