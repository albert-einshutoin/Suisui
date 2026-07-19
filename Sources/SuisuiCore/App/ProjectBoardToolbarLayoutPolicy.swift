import Foundation

public struct ProjectBoardToolbarContext: Equatable, Sendable {
    public enum RouteKind: Equatable, Sendable {
        case today
        case inbox
        case projects
        case project
        case review
        case smartList
    }

    public let routeKind: RouteKind
    public let isDeveloperModeEnabled: Bool
    public let hasInspectorSelection: Bool

    public init(
        routeKind: RouteKind,
        isDeveloperModeEnabled: Bool,
        hasInspectorSelection: Bool
    ) {
        self.routeKind = routeKind
        self.isDeveloperModeEnabled = isDeveloperModeEnabled
        self.hasInspectorSelection = hasInspectorSelection
    }

    public var hasPrimaryVoiceAction: Bool {
        true
    }

    public var showsIntegrations: Bool {
        true
    }

    public var showsAutomation: Bool {
        true
    }

    public var showsSettings: Bool {
        true
    }

    public var showsDeveloperTerminal: Bool {
        isDeveloperModeEnabled && routeKind == .project
    }

    public var showsInspectorToggle: Bool {
        hasInspectorSelection
    }

    public static let today = ProjectBoardToolbarContext(
        routeKind: .today,
        isDeveloperModeEnabled: false,
        hasInspectorSelection: false
    )

    public static let project = ProjectBoardToolbarContext(
        routeKind: .project,
        isDeveloperModeEnabled: false,
        hasInspectorSelection: false
    )

    public static let developerProject = ProjectBoardToolbarContext(
        routeKind: .project,
        isDeveloperModeEnabled: true,
        hasInspectorSelection: false
    )
}

public enum ProjectBoardToolbarLayoutPolicy {
    public struct Item: Equatable {
        public let identifierRawValue: String
        public let label: String
        public let paletteLabel: String
        public let toolTip: String?
        public let accessibilityIdentifier: String?
        public let isNativeToggleAction: Bool

        public init(
            identifierRawValue: String,
            label: String,
            paletteLabel: String,
            toolTip: String?,
            accessibilityIdentifier: String?,
            isNativeToggleAction: Bool
        ) {
            self.identifierRawValue = identifierRawValue
            self.label = label
            self.paletteLabel = paletteLabel
            self.toolTip = toolTip
            self.accessibilityIdentifier = accessibilityIdentifier
            self.isNativeToggleAction = isNativeToggleAction
        }
    }

    public static func nativeSidebarRemovalIndexes(in items: [Item]) -> [Int] {
        items.enumerated().compactMap { index, item in
            isNativeSidebarToggle(item) || isNativeSidebarTrackingSeparator(item) ? index : nil
        }
    }

    private static func isNativeSidebarToggle(_ item: Item) -> Bool {
        if item.identifierRawValue == "NSToolbarToggleSidebarItemIdentifier" {
            return true
        }

        if item.identifierRawValue.localizedCaseInsensitiveContains("toggleSidebar")
            || item.identifierRawValue.localizedCaseInsensitiveContains("toggle-sidebar") {
            return true
        }

        if item.isNativeToggleAction {
            return true
        }

        return nativeSidebarToggleLabels.contains(item.label)
            || nativeSidebarToggleLabels.contains(item.paletteLabel)
            || nativeSidebarToggleLabels.contains(item.toolTip ?? "")
    }

    private static func isNativeSidebarTrackingSeparator(_ item: Item) -> Bool {
        item.identifierRawValue == "NSToolbarSidebarTrackingSeparatorItemIdentifier"
            || item.identifierRawValue.localizedCaseInsensitiveContains("SidebarTrackingSeparator")
            || item.identifierRawValue.localizedCaseInsensitiveContains("TrackingSeparator")
    }

    private static let nativeSidebarToggleLabels: Set<String> = [
        "Hide Sidebar",
        "Show Sidebar",
        "サイドバーを非表示",
        "サイドバーを表示"
    ]
}
