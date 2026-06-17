import Foundation
@testable import SoloPMCore

final class InMemoryShortcutClient: ShortcutClient, @unchecked Sendable {
    private let lock = NSLock()
    private var registrationState: ShortcutRegistrationState

    init(state: ShortcutRegistrationState = ShortcutRegistrationState()) {
        self.registrationState = state
    }

    func state() -> ShortcutRegistrationState {
        lock.lock()
        defer { lock.unlock() }
        return registrationState
    }

    func registerVoiceCaptureShortcut(_ shortcut: KeyboardShortcut) throws -> ShortcutRegistrationState {
        lock.lock()
        defer { lock.unlock() }

        registrationState = ShortcutRegistrationState(
            voiceCaptureShortcut: shortcut,
            isRegistered: true,
            conflictDescription: nil
        )
        return registrationState
    }

    func unregisterVoiceCaptureShortcut() throws -> ShortcutRegistrationState {
        lock.lock()
        defer { lock.unlock() }

        registrationState.isRegistered = false
        return registrationState
    }
}
