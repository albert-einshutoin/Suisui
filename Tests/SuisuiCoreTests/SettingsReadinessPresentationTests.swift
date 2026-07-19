import SuisuiCore
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
            redactedReason: "Authorization expired",
            action: .retry(featureID: "calendar")
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
                redactedReason: "Authorization expired",
                action: .retry(featureID: "calendar")
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
        XCTAssertEqual(unsupported.group, .setUpWhenUsed)
    }

    func testAIInvalidAndUnavailableRemainDistinctAndOpenAISettings() {
        let invalid = SettingsReadinessPresentation.aiProviderCapability(
            id: "ai",
            title: "AI Provider",
            detail: "OpenAI: Invalid",
            statusLabel: "Invalid",
            readiness: .needsAction(reason: "Re-enter the provider API key in Keychain.")
        )
        let unavailable = SettingsReadinessPresentation.aiProviderCapability(
            id: "ai",
            title: "AI Provider",
            detail: "OpenAI: Unavailable",
            statusLabel: "Unavailable",
            readiness: .unavailable(reason: "Keychain access is unavailable.")
        )

        XCTAssertEqual(invalid.state, .blocked)
        XCTAssertEqual(invalid.group, .needsAttention)
        XCTAssertEqual(invalid.action, .openAI)
        XCTAssertEqual(unavailable.state, .unsupported)
        XCTAssertEqual(unavailable.group, .setUpWhenUsed)
        XCTAssertEqual(unavailable.action, .openAI)
    }

    func testAICheckingAndOptionalSetupDoNotBecomeFailures() {
        let checking = SettingsReadinessPresentation.aiProviderCapability(
            id: "ai",
            title: "AI Provider",
            detail: "Checking the local server.",
            statusLabel: "Checking server",
            readiness: .checking
        )
        let setup = SettingsReadinessPresentation.aiProviderCapability(
            id: "ai",
            title: "AI Provider",
            detail: "Save the provider API key in Keychain.",
            statusLabel: "Not configured",
            readiness: .needsAction(reason: "Save the provider API key in Keychain.")
        )

        XCTAssertEqual(checking.state, .checking)
        XCTAssertEqual(checking.group, .setUpWhenUsed)
        XCTAssertEqual(setup.state, .setupWhenNeeded)
        XCTAssertEqual(setup.group, .setUpWhenUsed)
    }

    func testAIEndpointFailureNeedsAttentionButStillOpensSettings() {
        let row = SettingsReadinessPresentation.aiProviderCapability(
            id: "ai",
            title: "AI Provider",
            detail: "The local endpoint refused the connection.",
            statusLabel: "The local endpoint refused the connection.",
            readiness: .needsAction(reason: "The local endpoint refused the connection.")
        )

        XCTAssertEqual(row.state, .needsAction)
        XCTAssertEqual(row.group, .needsAttention)
        XCTAssertEqual(row.action, .openAI)
    }

    func testVoiceReadinessDistinguishesInstallUnsupportedCheckingAndFailure() {
        let notInstalled = SettingsReadinessPresentation.voiceProviderCapability(
            id: "stt",
            title: "STT",
            detail: "Model not installed",
            statusLabel: "Model not installed"
        )
        let unsupported = SettingsReadinessPresentation.voiceProviderCapability(
            id: "tts",
            title: "TTS",
            detail: "Provider is unavailable in this build.",
            statusLabel: "Unsupported"
        )
        let checking = SettingsReadinessPresentation.voiceProviderCapability(
            id: "stt",
            title: "STT",
            detail: "Downloading model",
            statusLabel: "Downloading"
        )
        let failure = SettingsReadinessPresentation.voiceProviderCapability(
            id: "tts",
            title: "TTS",
            detail: "Download failed",
            statusLabel: "Download failed"
        )

        XCTAssertEqual(notInstalled.state, .setupWhenNeeded)
        XCTAssertEqual(notInstalled.group, .setUpWhenUsed)
        XCTAssertEqual(unsupported.state, .unsupported)
        XCTAssertEqual(unsupported.group, .setUpWhenUsed)
        XCTAssertEqual(checking.state, .checking)
        XCTAssertEqual(checking.group, .setUpWhenUsed)
        XCTAssertEqual(failure.state, .needsAction)
        XCTAssertEqual(failure.group, .needsAttention)
        XCTAssertEqual(failure.action, .openAI)
    }

    func testFailureActionMatchesAvailableBehavior() {
        let settingsFailure = SettingsReadinessPresentation.failedCapability(
            id: "sync",
            title: "Sync",
            redactedReason: "Backend check failed.",
            action: .openSync
        )
        let retryableFailure = SettingsReadinessPresentation.failedCapability(
            id: "google-calendar",
            title: "Google Calendar",
            redactedReason: "Status check failed.",
            action: .retry(featureID: "google-calendar")
        )

        XCTAssertEqual(settingsFailure.action, .openSync)
        XCTAssertEqual(retryableFailure.action, .retry(featureID: "google-calendar"))
    }
}
