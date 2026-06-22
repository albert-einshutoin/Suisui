import SoloPMCore
import XCTest

final class ProjectBoardToolbarLayoutPolicyTests: XCTestCase {
    func testRemovesNativeSidebarToggleAndTrackingSeparatorTogether() {
        let items = [
            toolbarItem(identifier: "com.apple.SwiftUI.toggleSidebar", label: "Hide Sidebar", isNativeToggleAction: true),
            toolbarItem(identifier: "NSToolbarSidebarTrackingSeparatorItemIdentifier"),
            toolbarItem(identifier: "project.integrations", label: "Integrations", accessibilityIdentifier: "project-board-integrations-menu"),
            toolbarItem(identifier: "project.voice", label: "Voice Command", accessibilityIdentifier: "project-board-voice-command"),
            toolbarItem(identifier: "project.settings", label: "Settings", accessibilityIdentifier: "project-board-settings-link"),
            toolbarItem(identifier: "project.terminal", label: "Terminal", accessibilityIdentifier: "project-board-terminal-toggle")
        ]

        XCTAssertEqual(ProjectBoardToolbarLayoutPolicy.nativeSidebarRemovalIndexes(in: items), [0, 1])
    }

    func testTrailingActionStartUsesProjectActionIdentifiersAfterSidebarItemsAreRemoved() {
        let items = [
            toolbarItem(identifier: "project.sidebar", label: "Sidebar", accessibilityIdentifier: "project-board-sidebar-toggle"),
            toolbarItem(identifier: "project.integrations", label: "Integrations", accessibilityIdentifier: "project-board-integrations-menu"),
            toolbarItem(identifier: "project.voice", label: "Voice Command", accessibilityIdentifier: "project-board-voice-command"),
            toolbarItem(identifier: "project.settings", label: "Settings", accessibilityIdentifier: "project-board-settings-link"),
            toolbarItem(identifier: "project.terminal", label: "Terminal", accessibilityIdentifier: "project-board-terminal-toggle")
        ]

        XCTAssertEqual(ProjectBoardToolbarLayoutPolicy.trailingActionStartIndex(in: items), 1)
        XCTAssertEqual(ProjectBoardToolbarLayoutPolicy.flexibleSpaceInsertionIndex(in: items), 1)
    }

    func testFlexibleSpaceIsNotDuplicatedWhenToolbarAlreadySeparatesSidebarAndActions() {
        let items = [
            toolbarItem(identifier: "project.sidebar", label: "Sidebar", accessibilityIdentifier: "project-board-sidebar-toggle"),
            toolbarItem(identifier: "NSToolbarFlexibleSpaceItem"),
            toolbarItem(identifier: "project.integrations", label: "Integrations", accessibilityIdentifier: "project-board-integrations-menu"),
            toolbarItem(identifier: "project.voice", label: "Voice Command", accessibilityIdentifier: "project-board-voice-command")
        ]

        XCTAssertNil(ProjectBoardToolbarLayoutPolicy.flexibleSpaceInsertionIndex(in: items))
    }

    func testLocalizedToolbarLabelsStillIdentifySidebarAndTrailingActions() {
        let items = [
            toolbarItem(identifier: "project.sidebar", label: "サイドバー", accessibilityIdentifier: "project-board-sidebar-toggle"),
            toolbarItem(identifier: "swiftui-toggle-sidebar", label: "サイドバーを表示"),
            toolbarItem(identifier: "SidebarTrackingSeparator"),
            toolbarItem(identifier: "localized.integrations", label: "連携"),
            toolbarItem(identifier: "localized.settings", label: "設定")
        ]

        XCTAssertEqual(ProjectBoardToolbarLayoutPolicy.nativeSidebarRemovalIndexes(in: items), [1, 2])
        XCTAssertEqual(ProjectBoardToolbarLayoutPolicy.trailingActionStartIndex(in: items), 3)
    }

    private func toolbarItem(
        identifier: String,
        label: String = "",
        paletteLabel: String = "",
        toolTip: String? = nil,
        accessibilityIdentifier: String? = nil,
        isNativeToggleAction: Bool = false
    ) -> ProjectBoardToolbarLayoutPolicy.Item {
        ProjectBoardToolbarLayoutPolicy.Item(
            identifierRawValue: identifier,
            label: label,
            paletteLabel: paletteLabel,
            toolTip: toolTip,
            accessibilityIdentifier: accessibilityIdentifier,
            isNativeToggleAction: isNativeToggleAction
        )
    }
}
