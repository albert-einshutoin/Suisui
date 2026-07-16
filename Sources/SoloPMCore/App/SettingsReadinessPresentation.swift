import Foundation

public enum SettingsReadinessState: Equatable, Sendable {
    case ready
    case setupWhenNeeded
    case checking
    case needsAction
    case blocked
    case unsupported
}

public enum SettingsReadinessGroup: Int, CaseIterable, Hashable, Sendable {
    case readyNow
    case setUpWhenUsed
    case needsAttention
    case advanced
}

public enum SettingsReadinessAction: Equatable, Sendable {
    case openAI
    case openPrivacy
    case showAdvanced
    case openMCP
    case openSync
    case retry(featureID: String)
}

public struct SettingsReadinessRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let state: SettingsReadinessState
    public let group: SettingsReadinessGroup
    public let action: SettingsReadinessAction?

    public init(
        id: String,
        title: String,
        detail: String,
        state: SettingsReadinessState,
        group: SettingsReadinessGroup,
        action: SettingsReadinessAction?
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.group = group
        self.action = action
    }
}

public struct SettingsReadinessRowGroup: Identifiable, Equatable, Sendable {
    public var id: SettingsReadinessGroup { group }
    public let group: SettingsReadinessGroup
    public let rows: [SettingsReadinessRow]

    public init(group: SettingsReadinessGroup, rows: [SettingsReadinessRow]) {
        self.group = group
        self.rows = rows
    }
}

public enum SettingsReadinessPresentation {
    public static func capability(
        id: String,
        title: String,
        detail: String,
        state: SettingsReadinessState,
        action: SettingsReadinessAction?
    ) -> SettingsReadinessRow {
        SettingsReadinessRow(
            id: id,
            title: title,
            detail: detail,
            state: state,
            group: group(for: state),
            action: action
        )
    }

    public static func optionalCapability(
        id: String,
        title: String,
        hasLoaded: Bool,
        failure: String?,
        action: SettingsReadinessAction? = nil
    ) -> SettingsReadinessRow {
        if let failure, !failure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return failedCapability(id: id, title: title, redactedReason: failure)
        }
        return SettingsReadinessRow(
            id: id,
            title: title,
            detail: hasLoaded ? "Set up only when you choose to use this feature." : "Not loaded until you open its settings.",
            state: .setupWhenNeeded,
            group: .setUpWhenUsed,
            action: action ?? defaultAction(for: id)
        )
    }

    public static func failedCapability(
        id: String,
        title: String,
        redactedReason: String
    ) -> SettingsReadinessRow {
        capability(
            id: id,
            title: title,
            detail: redactedReason,
            state: .needsAction,
            action: .retry(featureID: id)
        )
    }

    public static func readyCapability(
        id: String,
        title: String,
        detail: String,
        action: SettingsReadinessAction? = nil
    ) -> SettingsReadinessRow {
        capability(
            id: id,
            title: title,
            detail: detail,
            state: .ready,
            action: action
        )
    }

    public static func grouped(
        rows: [SettingsReadinessRow],
        showsAdvanced: Bool
    ) -> [SettingsReadinessRowGroup] {
        SettingsReadinessGroup.allCases.compactMap { group in
            guard showsAdvanced || group != .advanced else { return nil }
            let groupRows = rows.filter { $0.group == group }
            guard !groupRows.isEmpty else { return nil }
            return SettingsReadinessRowGroup(group: group, rows: groupRows)
        }
    }

    private static func defaultAction(for id: String) -> SettingsReadinessAction? {
        switch id {
        case "ai": .openAI
        case "privacy": .openPrivacy
        case "mcp": .openMCP
        case "sync": .openSync
        default: nil
        }
    }

    private static func group(for state: SettingsReadinessState) -> SettingsReadinessGroup {
        switch state {
        case .ready:
            .readyNow
        case .setupWhenNeeded, .checking:
            .setUpWhenUsed
        case .needsAction, .blocked, .unsupported:
            .needsAttention
        }
    }
}
