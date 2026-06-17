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

