import AppKit
import Carbon.HIToolbox
import SuisuiCore
import SwiftUI

struct VoiceWindowIdentifierInstaller: NSViewRepresentable {
    private static let identifier = NSUserInterfaceItemIdentifier(VoiceWindowIdentity.identifierRawValue)

    func makeNSView(context: Context) -> NSView {
        WindowIdentifierView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.identifier = Self.identifier
    }

    private final class WindowIdentifierView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = VoiceWindowIdentifierInstaller.identifier
        }
    }
}

final class SystemShortcutClient: ShortcutClient, @unchecked Sendable {
    private static let voiceHotKeyID = EventHotKeyID(
        signature: OSType(0x5350_4D56), // "SPMV"
        id: 1
    )

    private let lock = NSLock()
    private let handler: @MainActor @Sendable () -> Void
    private var registrationState = ShortcutRegistrationState()
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    deinit {
        unregisterCarbonResources()
    }

    func state() -> ShortcutRegistrationState {
        lock.withLock {
            registrationState
        }
    }

    func registerVoiceCaptureShortcut(_ shortcut: SuisuiCore.KeyboardShortcut) throws -> ShortcutRegistrationState {
        lock.withLock {
            guard hotKeyRef == nil else {
                return registrationState
            }
            guard shortcut == .defaultVoiceCapture else {
                registrationState = ShortcutRegistrationState(
                    voiceCaptureShortcut: shortcut,
                    status: .unavailable,
                    detail: "Suisui currently supports only Option + Space."
                )
                return registrationState
            }

            let handlerStatus = installEventHandlerIfNeeded()
            guard handlerStatus == noErr else {
                registrationState = unavailableState(
                    shortcut: shortcut,
                    detail: "The global shortcut event handler is unavailable."
                )
                return registrationState
            }

            var newHotKeyRef: EventHotKeyRef?
            let registrationStatus = RegisterEventHotKey(
                UInt32(kVK_Space),
                UInt32(optionKey),
                Self.voiceHotKeyID,
                GetApplicationEventTarget(),
                0,
                &newHotKeyRef
            )

            guard registrationStatus == noErr, let newHotKeyRef else {
                registrationState = ShortcutRegistrationState(
                    voiceCaptureShortcut: shortcut,
                    status: registrationStatus == eventHotKeyExistsErr ? .conflict : .unavailable,
                    detail: registrationStatus == eventHotKeyExistsErr
                        ? "Option + Space is already used by another app."
                        : "Option + Space could not be registered on this Mac."
                )
                return registrationState
            }

            hotKeyRef = newHotKeyRef
            registrationState = ShortcutRegistrationState(
                voiceCaptureShortcut: shortcut,
                status: .registered
            )
            return registrationState
        }
    }

    func unregisterVoiceCaptureShortcut() throws -> ShortcutRegistrationState {
        lock.withLock {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
                self.hotKeyRef = nil
            }
            registrationState = ShortcutRegistrationState(status: .notRegistered)
            return registrationState
        }
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        return InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func unregisterCarbonResources() {
        lock.withLock {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
                self.hotKeyRef = nil
            }
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
        }
    }

    private func dispatchHandler() {
        let shouldHandle = lock.withLock {
            registrationState.status == .registered && hotKeyRef != nil
        }
        guard shouldHandle else {
            return
        }
        Task { @MainActor [handler] in
            handler()
        }
    }

    private func unavailableState(shortcut: SuisuiCore.KeyboardShortcut, detail: String) -> ShortcutRegistrationState {
        ShortcutRegistrationState(
            voiceCaptureShortcut: shortcut,
            status: .unavailable,
            detail: detail
        )
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == voiceHotKeyID.signature, hotKeyID.id == voiceHotKeyID.id else {
            return OSStatus(eventNotHandledErr)
        }

        let client = Unmanaged<SystemShortcutClient>.fromOpaque(userData).takeUnretainedValue()
        client.dispatchHandler()
        return noErr
    }
}

@MainActor
final class VoiceWindowActivationCoordinator {
    static let shared = VoiceWindowActivationCoordinator()

    private let openRequestGate = VoiceShortcutOpenRequestGate()
    private var openVoiceWindow: (() -> Void)?

    func installOpenRequest(_ openVoiceWindow: @escaping () -> Void) {
        self.openVoiceWindow = openVoiceWindow
    }

    func activateExistingWindowOrRequestOpen() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        SuisuiInAppVoiceNavigation.requestOpen()
        if let openVoiceWindow {
            openVoiceWindow()
        }
    }

    func markVoiceWindowVisible() {
        openRequestGate.markWindowVisible()
    }

    func markVoiceWindowClosed() {
        openRequestGate.markWindowClosed()
    }

    private var visibleVoiceWindow: NSWindow? {
        NSApplication.shared.windows.first { window in
            VoiceWindowIdentity.matches(
                identifierRawValue: window.identifier?.rawValue,
                title: window.title
            )
                && (window.isVisible || window.isMiniaturized)
        }
    }

    private func performVoiceCommandShortcutMenuItem() -> Bool {
        guard let mainMenu = NSApp.mainMenu else {
            return false
        }
        return performVoiceCommandShortcutMenuItem(in: mainMenu)
    }

    private func performVoiceCommandShortcutMenuItem(in menu: NSMenu) -> Bool {
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        if let index = menu.items.firstIndex(where: { item in
            let modifiers = item.keyEquivalentModifierMask.intersection(relevantModifiers)
            // AppKit can encode Shift either in the modifier mask or as an
            // uppercase key equivalent. Accept both representations while
            // still excluding the standard Command+V Paste item.
            let isVoiceKeyEquivalent = item.keyEquivalent == "V"
                || (item.keyEquivalent == "v" && modifiers.contains(.shift))
            return item.isEnabled
                && isVoiceKeyEquivalent
                && modifiers.contains(.command)
        }) {
            menu.performActionForItem(at: index)
            return true
        }
        for item in menu.items {
            if let submenu = item.submenu, performVoiceCommandShortcutMenuItem(in: submenu) {
                return true
            }
        }
        return false
    }

}

@MainActor
final class GlobalShortcutRuntime {
    static let shared = GlobalShortcutRuntime()

    let settingsViewModel: ShortcutSettingsViewModel

    private init() {
        let client = SystemShortcutClient {
            VoiceWindowActivationCoordinator.shared.activateExistingWindowOrRequestOpen()
        }
        let settingsViewModel = ShortcutSettingsViewModel(client: client)
        settingsViewModel.registerDefaultVoiceCaptureShortcut()
        self.settingsViewModel = settingsViewModel
    }
}
