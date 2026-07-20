import XCTest
@testable import SuisuiCore

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
                state: ShortcutRegistrationState(
                    status: .conflict,
                    detail: "Option + Space is already used."
                )
            )
        )

        XCTAssertFalse(viewModel.canRegister)
        XCTAssertEqual(viewModel.statusLabel, "Conflict")
        XCTAssertTrue(viewModel.showsInAppFallback)
    }

    func testRegisterIsIdempotentAndHandlerOpensOnce() {
        let client = RecordingShortcutClient()
        let viewModel = ShortcutSettingsViewModel(client: client)

        viewModel.registerDefaultVoiceCaptureShortcut()
        viewModel.registerDefaultVoiceCaptureShortcut()
        client.trigger()

        XCTAssertEqual(client.registerCallCount, 1)
        XCTAssertEqual(client.handlerCallCount, 1)
        XCTAssertEqual(viewModel.state.status, .registered)
    }

    func testUnregisterStopsHandlerAndReturnsToNotRegistered() {
        let client = RecordingShortcutClient()
        let viewModel = ShortcutSettingsViewModel(client: client)

        viewModel.registerDefaultVoiceCaptureShortcut()
        viewModel.unregisterVoiceCaptureShortcut()
        client.trigger()

        XCTAssertEqual(client.unregisterCallCount, 1)
        XCTAssertEqual(client.handlerCallCount, 0)
        XCTAssertEqual(viewModel.state.status, .notRegistered)
    }

    func testTypedStatusLabelsCoverUnavailableWithoutPretendingRegistrationSucceeded() {
        let viewModel = ShortcutSettingsViewModel(
            client: InMemoryShortcutClient(
                state: ShortcutRegistrationState(
                    status: .unavailable,
                    detail: "Global shortcuts are unavailable."
                )
            )
        )

        XCTAssertEqual(viewModel.statusLabel, "Unavailable")
        XCTAssertFalse(viewModel.state.isRegistered)
        XCTAssertTrue(viewModel.showsInAppFallback)
        XCTAssertEqual(viewModel.fallbackShortcutLabel, "Shift + Command + V")
    }

    func testVoiceOpenRequestGateSuppressesDuplicateRequestsUntilWindowAppears() {
        let gate = VoiceShortcutOpenRequestGate()
        var openRequestCount = 0

        gate.handle(
            isWindowVisible: false,
            activateExisting: { XCTFail("No window is visible.") },
            requestOpen: {
                openRequestCount += 1
                return true
            }
        )
        gate.handle(
            isWindowVisible: false,
            activateExisting: { XCTFail("No window is visible.") },
            requestOpen: {
                openRequestCount += 1
                return true
            }
        )

        XCTAssertEqual(openRequestCount, 1)

        gate.markWindowVisible()
        var activationCount = 0
        gate.handle(
            isWindowVisible: true,
            activateExisting: { activationCount += 1 },
            requestOpen: { XCTFail("Visible windows must be activated, not reopened."); return false }
        )
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(openRequestCount, 1)
    }

    func testVoiceOpenRequestGateAllowsRetryWhenOpeningIsUnavailable() {
        let gate = VoiceShortcutOpenRequestGate()
        var openRequestCount = 0

        for _ in 0..<2 {
            gate.handle(
                isWindowVisible: false,
                activateExisting: { XCTFail("No window is visible.") },
                requestOpen: {
                    openRequestCount += 1
                    return false
                }
            )
        }

        XCTAssertEqual(openRequestCount, 2)
    }

    func testVoiceOpenRequestGateAllowsRetryAfterPendingRequestTimesOut() async {
        let gate = VoiceShortcutOpenRequestGate(
            pendingTimeoutNanoseconds: 1,
            sleep: { _ in }
        )
        var openRequestCount = 0

        gate.handle(
            isWindowVisible: false,
            activateExisting: { XCTFail("No window is visible.") },
            requestOpen: {
                openRequestCount += 1
                return true
            }
        )
        await Task.yield()
        await Task.yield()
        gate.handle(
            isWindowVisible: false,
            activateExisting: { XCTFail("No window is visible.") },
            requestOpen: {
                openRequestCount += 1
                return true
            }
        )

        XCTAssertEqual(openRequestCount, 2)
    }

    func testVoiceOpenRequestGateCancelsPendingTimeoutWhenWindowAppears() async {
        let gate = VoiceShortcutOpenRequestGate(
            pendingTimeoutNanoseconds: 1,
            sleep: { _ in }
        )
        var openRequestCount = 0
        var activationCount = 0

        gate.handle(
            isWindowVisible: false,
            activateExisting: { XCTFail("No window is visible.") },
            requestOpen: {
                openRequestCount += 1
                return true
            }
        )
        gate.markWindowVisible()
        await Task.yield()
        await Task.yield()
        gate.handle(
            isWindowVisible: true,
            activateExisting: { activationCount += 1 },
            requestOpen: { XCTFail("The existing window must be activated."); return false }
        )

        XCTAssertEqual(openRequestCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testVoiceWindowIdentityMatchesJapaneseTitleByStructuralIdentifier() {
        XCTAssertTrue(
            VoiceWindowIdentity.matches(
                identifierRawValue: "voice-capture",
                title: "音声コマンド"
            )
        )
        XCTAssertFalse(
            VoiceWindowIdentity.matches(
                identifierRawValue: nil,
                title: "Voice Command"
            )
        )
    }

    func testShortcutRegistrationErrorsAreRedactedBeforeUserDisplay() {
        let viewModel = ShortcutSettingsViewModel(client: ThrowingShortcutClient())

        viewModel.registerDefaultVoiceCaptureShortcut()

        XCTAssertEqual(viewModel.errorMessage, "Shortcut registration failed with [REDACTED_SECRET]")
        XCTAssertFalse(viewModel.errorMessage?.contains("sk-shortcut-secret") ?? true)
    }
}

private final class RecordingShortcutClient: ShortcutClient, @unchecked Sendable {
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var handlerCallCount = 0
    private var isHandlerEnabled = false

    func state() -> ShortcutRegistrationState {
        ShortcutRegistrationState(status: isHandlerEnabled ? .registered : .notRegistered)
    }

    func registerVoiceCaptureShortcut(_ shortcut: KeyboardShortcut) throws -> ShortcutRegistrationState {
        registerCallCount += 1
        isHandlerEnabled = true
        return ShortcutRegistrationState(voiceCaptureShortcut: shortcut, status: .registered)
    }

    func unregisterVoiceCaptureShortcut() throws -> ShortcutRegistrationState {
        unregisterCallCount += 1
        isHandlerEnabled = false
        return ShortcutRegistrationState(status: .notRegistered)
    }

    func trigger() {
        guard isHandlerEnabled else {
            return
        }
        handlerCallCount += 1
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
