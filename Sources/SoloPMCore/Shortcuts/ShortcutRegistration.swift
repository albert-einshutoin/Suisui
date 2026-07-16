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

public enum ShortcutRegistrationStatus: String, Equatable, Sendable {
    case registered
    case notRegistered
    case conflict
    case unavailable
}

public struct ShortcutRegistrationState: Equatable, Sendable {
    public var voiceCaptureShortcut: KeyboardShortcut
    public var status: ShortcutRegistrationStatus
    public var detail: String?

    public init(
        voiceCaptureShortcut: KeyboardShortcut = .defaultVoiceCapture,
        status: ShortcutRegistrationStatus = .notRegistered,
        detail: String? = nil
    ) {
        self.voiceCaptureShortcut = voiceCaptureShortcut
        self.status = status
        self.detail = detail
    }

    public var isRegistered: Bool {
        status == .registered
    }

    public var conflictDescription: String? {
        status == .conflict ? detail : nil
    }
}

public protocol ShortcutClient: Sendable {
    func state() -> ShortcutRegistrationState
    func registerVoiceCaptureShortcut(_ shortcut: KeyboardShortcut) throws -> ShortcutRegistrationState
    func unregisterVoiceCaptureShortcut() throws -> ShortcutRegistrationState
}

@MainActor
public final class VoiceShortcutOpenRequestGate {
    private var isOpenRequestPending = false

    public init() {}

    public func handle(
        isWindowVisible: Bool,
        activateExisting: () -> Void,
        requestOpen: () -> Bool
    ) {
        if isWindowVisible {
            isOpenRequestPending = false
            activateExisting()
            return
        }
        guard !isOpenRequestPending else {
            return
        }
        isOpenRequestPending = true
        if !requestOpen() {
            isOpenRequestPending = false
        }
    }

    public func markWindowVisible() {
        isOpenRequestPending = false
    }

    public func markWindowClosed() {
        isOpenRequestPending = false
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
        state.status == .notRegistered
    }

    public var canUnregister: Bool {
        state.status == .registered
    }

    public var statusLabel: String {
        switch state.status {
        case .registered:
            "Registered"
        case .notRegistered:
            "Not registered"
        case .conflict:
            "Conflict"
        case .unavailable:
            "Unavailable"
        }
    }

    public var fallbackShortcutLabel: String {
        "Shift + Command + V"
    }

    public var showsInAppFallback: Bool {
        state.status != .registered
    }

    public func registerDefaultVoiceCaptureShortcut() {
        guard canRegister else {
            return
        }
        do {
            state = try client.registerVoiceCaptureShortcut(.defaultVoiceCapture)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingErrorMessageSanitizer.message(from: error)
        }
    }

    public func unregisterVoiceCaptureShortcut() {
        guard canUnregister else {
            return
        }
        do {
            state = try client.unregisterVoiceCaptureShortcut()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingErrorMessageSanitizer.message(from: error)
        }
    }
}
