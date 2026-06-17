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
