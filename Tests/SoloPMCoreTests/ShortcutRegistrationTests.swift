import XCTest
@testable import SoloPMCore

@MainActor
final class ShortcutRegistrationTests: XCTestCase {
    func testShortcutSettingsViewModelRegistersAndUnregistersDefaultShortcut() {
        let client = InMemoryShortcutClient()
        let viewModel = ShortcutSettingsViewModel(client: client)

        XCTAssertEqual(viewModel.displayShortcut, "Option + Space")
        XCTAssertFalse(viewModel.state.isRegistered)

        viewModel.registerDefaultVoiceCaptureShortcut()

        XCTAssertTrue(viewModel.state.isRegistered)
        XCTAssertEqual(viewModel.state.voiceCaptureShortcut, .defaultVoiceCapture)

        viewModel.unregisterVoiceCaptureShortcut()

        XCTAssertFalse(viewModel.state.isRegistered)
    }

    func testShortcutConflictDisablesRegistrationState() {
        let viewModel = ShortcutSettingsViewModel(
            client: InMemoryShortcutClient(
                state: ShortcutRegistrationState(conflictDescription: "Option + Space is already used.")
            )
        )

        XCTAssertFalse(viewModel.canRegister)
    }

    func testShortcutRegistrationErrorsAreRedactedBeforeUserDisplay() {
        let viewModel = ShortcutSettingsViewModel(client: ThrowingShortcutClient())

        viewModel.registerDefaultVoiceCaptureShortcut()

        XCTAssertEqual(viewModel.errorMessage, "Shortcut registration failed with [REDACTED_SECRET]")
        XCTAssertFalse(viewModel.errorMessage?.contains("sk-shortcut-secret") ?? true)
    }
}

private struct ThrowingShortcutClient: ShortcutClient {
    func state() -> ShortcutRegistrationState {
        ShortcutRegistrationState()
    }

    func registerVoiceCaptureShortcut(_ shortcut: KeyboardShortcut) throws -> ShortcutRegistrationState {
        throw ShortcutSecretError()
    }

    func unregisterVoiceCaptureShortcut() throws -> ShortcutRegistrationState {
        throw ShortcutSecretError()
    }
}

private struct ShortcutSecretError: Error, CustomStringConvertible {
    var description: String {
        "Shortcut registration failed with sk-shortcut-secret"
    }
}
