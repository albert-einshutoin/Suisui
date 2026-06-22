import Foundation

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

    public static func trailingActionStartIndex(in items: [Item]) -> Int? {
        if let actionIndex = items.firstIndex(where: isProjectBoardTrailingAction) {
            return actionIndex
        }

        if let settingsIndex = items.firstIndex(where: { $0.accessibilityIdentifier == "project-board-settings-link" }) {
            return max(0, settingsIndex - 2)
        }

        if let terminalIndex = items.firstIndex(where: { $0.accessibilityIdentifier == "project-board-terminal-toggle" }) {
            return max(0, terminalIndex - 3)
        }

        return items.count > 1 ? 1 : nil
    }

    public static func flexibleSpaceInsertionIndex(in items: [Item]) -> Int? {
        guard let actionIndex = trailingActionStartIndex(in: items),
              actionIndex > 0,
              !isFlexibleSpace(items[actionIndex - 1]) else {
            return nil
        }

        return actionIndex
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

    private static func isProjectBoardTrailingAction(_ item: Item) -> Bool {
        if let accessibilityIdentifier = item.accessibilityIdentifier,
           projectBoardTrailingActionAccessibilityIdentifiers.contains(accessibilityIdentifier) {
            return true
        }

        return projectBoardTrailingActionLabels.contains(item.label)
            || projectBoardTrailingActionLabels.contains(item.paletteLabel)
            || projectBoardTrailingActionLabels.contains(item.toolTip ?? "")
    }

    private static func isFlexibleSpace(_ item: Item) -> Bool {
        item.identifierRawValue == "NSToolbarFlexibleSpaceItem"
            || item.identifierRawValue.localizedCaseInsensitiveContains("FlexibleSpace")
    }

    private static let projectBoardTrailingActionAccessibilityIdentifiers: Set<String> = [
        "project-board-integrations-menu",
        "project-board-voice-command",
        "project-board-settings-link",
        "project-board-terminal-toggle"
    ]

    private static let projectBoardTrailingActionLabels: Set<String> = [
        "Integrations",
        "連携",
        "Voice Command",
        "音声コマンド",
        "Settings",
        "設定",
        "Terminal",
        "ターミナル"
    ]

    private static let nativeSidebarToggleLabels: Set<String> = [
        "Hide Sidebar",
        "Show Sidebar",
        "サイドバーを非表示",
        "サイドバーを表示"
    ]
}
