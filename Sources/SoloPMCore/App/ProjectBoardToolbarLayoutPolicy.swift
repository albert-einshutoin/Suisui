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
