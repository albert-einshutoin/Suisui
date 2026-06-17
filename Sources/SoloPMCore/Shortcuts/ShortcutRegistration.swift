import Combine
import Foundation

public struct KeyboardShortcut: Equatable, Sendable {
    public var key: String
    public var modifiers: [String]

    public init(key: String, modifiers: [String]) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let defaultVoiceCapture = KeyboardShortcut(key: "space", modifiers: ["option"])
}

public struct ShortcutRegistrationState: Equatable, Sendable {
    public var voiceCaptureShortcut: KeyboardShortcut
    public var isRegistered: Bool
    public var conflictDescription: String?

    public init(
        voiceCaptureShortcut: KeyboardShortcut = .defaultVoiceCapture,
        isRegistered: Bool = false,
        conflictDescription: String? = nil
    ) {
        self.voiceCaptureShortcut = voiceCaptureShortcut
        self.isRegistered = isRegistered
        self.conflictDescription = conflictDescription
    }
}

public protocol ShortcutClient: Sendable {
    func state() -> ShortcutRegistrationState
    func registerVoiceCaptureShortcut(_ shortcut: KeyboardShortcut) throws -> ShortcutRegistrationState
    func unregisterVoiceCaptureShortcut() throws -> ShortcutRegistrationState
}

public final class InMemoryShortcutClient: ShortcutClient, @unchecked Sendable {
    private let lock = NSLock()
    private var registrationState: ShortcutRegistrationState

    public init(state: ShortcutRegistrationState = ShortcutRegistrationState()) {
        self.registrationState = state
    }

    public func state() -> ShortcutRegistrationState {
        lock.lock()
        defer { lock.unlock() }
        return registrationState
    }

    public func registerVoiceCaptureShortcut(_ shortcut: KeyboardShortcut) throws -> ShortcutRegistrationState {
        lock.lock()
        defer { lock.unlock() }

        registrationState = ShortcutRegistrationState(
            voiceCaptureShortcut: shortcut,
            isRegistered: true,
            conflictDescription: nil
        )
        return registrationState
    }

    public func unregisterVoiceCaptureShortcut() throws -> ShortcutRegistrationState {
        lock.lock()
        defer { lock.unlock() }

        registrationState.isRegistered = false
        return registrationState
    }
}

@MainActor
public final class ShortcutSettingsViewModel: ObservableObject {
    @Published public private(set) var state: ShortcutRegistrationState
    @Published public private(set) var errorMessage: String?

    private let client: any ShortcutClient

    public init(client: any ShortcutClient) {
        self.client = client
        self.state = client.state()
        self.errorMessage = nil
    }

    public var displayShortcut: String {
        let modifiers = state.voiceCaptureShortcut.modifiers
            .map { $0.capitalized }
            .joined(separator: " + ")
        return modifiers.isEmpty ? state.voiceCaptureShortcut.key.capitalized : "\(modifiers) + \(state.voiceCaptureShortcut.key.capitalized)"
    }

    public var canRegister: Bool {
        state.conflictDescription == nil
    }

    public func registerDefaultVoiceCaptureShortcut() {
        do {
            state = try client.registerVoiceCaptureShortcut(.defaultVoiceCapture)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func unregisterVoiceCaptureShortcut() {
        do {
            state = try client.unregisterVoiceCaptureShortcut()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
