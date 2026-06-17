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
}
