import SoloPMCore
import XCTest

final class SettingsReadinessPresentationTests: XCTestCase {
    func testOptionalUnconfiguredCapabilityIsNeutralUntilRequested() {
        let row = SettingsReadinessPresentation.optionalCapability(
            id: "mcp",
            title: "MCP",
            hasLoaded: false,
            failure: nil
        )

        XCTAssertEqual(row.state, .setupWhenNeeded)
        XCTAssertEqual(row.group, .setUpWhenUsed)
        XCTAssertEqual(row.action, .openMCP)
    }

    func testActualFailureNeedsAttention() {
        let row = SettingsReadinessPresentation.failedCapability(
            id: "calendar",
            title: "Calendar",
            redactedReason: "Authorization expired"
        )

        XCTAssertEqual(row.state, .needsAction)
        XCTAssertEqual(row.group, .needsAttention)
        XCTAssertEqual(row.detail, "Authorization expired")
        XCTAssertEqual(row.action, .retry(featureID: "calendar"))
    }

    func testReadyCapabilityIsSeparatedFromOptionalSetup() {
        let row = SettingsReadinessPresentation.readyCapability(
            id: "privacy",
            title: "Privacy",
            detail: "Secrets stay in Keychain.",
            action: .openPrivacy
        )

        XCTAssertEqual(row.state, .ready)
        XCTAssertEqual(row.group, .readyNow)
    }

    func testGroupsPreserveProgressiveDisclosureOrderAndHideAdvanced() {
        let rows = [
            SettingsReadinessPresentation.failedCapability(
                id: "calendar",
                title: "Calendar",
                redactedReason: "Authorization expired"
            ),
            SettingsReadinessPresentation.optionalCapability(
                id: "mcp",
                title: "MCP",
                hasLoaded: false,
                failure: nil
            ),
            SettingsReadinessPresentation.readyCapability(
                id: "privacy",
                title: "Privacy",
                detail: "Local by default.",
                action: .openPrivacy
            ),
            SettingsReadinessRow(
                id: "sync",
                title: "Sync",
                detail: "Available when Advanced is enabled.",
                state: .setupWhenNeeded,
                group: .advanced,
                action: .openSync
            )
        ]

        XCTAssertEqual(
            SettingsReadinessPresentation.grouped(rows: rows, showsAdvanced: false).map(\.group),
            [.readyNow, .setUpWhenUsed, .needsAttention]
        )
        XCTAssertEqual(
            SettingsReadinessPresentation.grouped(rows: rows, showsAdvanced: true).map(\.group),
            [.readyNow, .setUpWhenUsed, .needsAttention, .advanced]
        )
    }

    func testOperationalStatesRemainDistinctWhileUsingStableGroups() {
        let checking = SettingsReadinessPresentation.capability(
            id: "google-calendar",
            title: "Google Calendar",
            detail: "Readiness has not been checked.",
            state: .checking,
            action: .retry(featureID: "google-calendar")
        )
        let blocked = SettingsReadinessPresentation.capability(
            id: "calendar",
            title: "Calendar",
            detail: "Permission is denied.",
            state: .blocked,
            action: .openSync
        )
        let unsupported = SettingsReadinessPresentation.capability(
            id: "reminders",
            title: "Reminder",
            detail: "Permission is restricted on this Mac.",
            state: .unsupported,
            action: .openSync
        )

        XCTAssertEqual(checking.state, .checking)
        XCTAssertEqual(checking.group, .setUpWhenUsed)
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertEqual(blocked.group, .needsAttention)
        XCTAssertEqual(unsupported.state, .unsupported)
        XCTAssertEqual(unsupported.group, .needsAttention)
    }
}
