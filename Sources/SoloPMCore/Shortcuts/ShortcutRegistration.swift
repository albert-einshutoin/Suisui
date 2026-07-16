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

public enum VoiceWindowIdentity {
    public static let identifierRawValue = "voice-capture"

    public static func matches(identifierRawValue: String?, title _: String) -> Bool {
        identifierRawValue == self.identifierRawValue
    }
}

@MainActor
public final class VoiceShortcutOpenRequestGate {
    public typealias Sleep = @Sendable (UInt64) async -> Void

    private var isOpenRequestPending = false
    private var pendingResetTask: Task<Void, Never>?
    private var pendingGeneration: UInt64 = 0
    private let pendingTimeoutNanoseconds: UInt64
    private let sleep: Sleep

    public init(
        pendingTimeoutNanoseconds: UInt64 = 2_000_000_000,
        sleep: @escaping Sleep = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.pendingTimeoutNanoseconds = pendingTimeoutNanoseconds
        self.sleep = sleep
    }

    deinit {
        pendingResetTask?.cancel()
    }

    public func handle(
        isWindowVisible: Bool,
        activateExisting: () -> Void,
        requestOpen: () -> Bool
    ) {
        if isWindowVisible {
            clearPendingRequest()
            activateExisting()
            return
        }
        guard !isOpenRequestPending else {
            return
        }
        isOpenRequestPending = true
        if !requestOpen() {
            clearPendingRequest()
        } else {
            schedulePendingReset()
        }
    }

    public func markWindowVisible() {
        clearPendingRequest()
    }

    public func markWindowClosed() {
        clearPendingRequest()
    }

    private func schedulePendingReset() {
        pendingResetTask?.cancel()
        pendingGeneration &+= 1
        let generation = pendingGeneration
        let timeout = pendingTimeoutNanoseconds
        let sleep = sleep

        // The request can be accepted by SwiftUI without ever creating a
        // window. A bounded reset keeps the global shortcut recoverable while
        // the generation check prevents an older timeout from clearing a newer
        // request.
        pendingResetTask = Task { @MainActor [weak self] in
            await sleep(timeout)
            guard !Task.isCancelled, self?.pendingGeneration == generation else {
                return
            }
            self?.isOpenRequestPending = false
            self?.pendingResetTask = nil
        }
    }

    private func clearPendingRequest() {
        pendingGeneration &+= 1
        pendingResetTask?.cancel()
        pendingResetTask = nil
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
