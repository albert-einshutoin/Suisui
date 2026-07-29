import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let rawPID = Int32(CommandLine.arguments[1]) else {
    fputs("AX text input requires app pid, field identifier/text marker, and replacement text.\n", stderr)
    exit(2)
}

let pid = pid_t(rawPID)
let marker = CommandLine.arguments[2]
let replacement = CommandLine.arguments[3]
let maxNodes = Int(ProcessInfo.processInfo.environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to type into Suisui fields.\n", stderr)
    exit(2)
}

guard let runningApp = NSRunningApplication(processIdentifier: pid), !runningApp.isTerminated else {
    fputs("Target app pid \(pid) is not running.\n", stderr)
    exit(2)
}

let appElement = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(appElement, 1.0)

func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 1.0)
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    return result == .success ? value : nil
}

func stringValue(_ value: CFTypeRef?) -> String? {
    guard let value else { return nil }
    if let string = value as? String {
        return string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

func elements(from value: CFTypeRef?) -> [AXUIElement] {
    guard let value else { return [] }
    if CFGetTypeID(value) == AXUIElementGetTypeID() {
        return [unsafeBitCast(value, to: AXUIElement.self)]
    }
    guard let array = value as? [AnyObject] else { return [] }
    return array.compactMap { item in
        let value = item as CFTypeRef
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

func signal(for element: AXUIElement) -> String {
    [
        "AXIdentifier",
        "AXTitle",
        "AXDescription",
        "AXHelp",
        "AXValue",
        "AXLabel"
    ].compactMap { attribute in
        stringValue(copyAttribute(element, attribute as CFString))
    }.joined(separator: " ")
}

func postKey(
    _ source: CGEventSource,
    keyCode: CGKeyCode,
    keyDown: Bool,
    flags: CGEventFlags = []
) -> Bool {
    guard let event = CGEvent(
        keyboardEventSource: source,
        virtualKey: keyCode,
        keyDown: keyDown
    ) else {
        return false
    }
    event.flags = flags
    event.post(tap: .cghidEventTap)
    return true
}

func activateTarget() -> Bool {
    // Directly launched smoke binaries are not registered through
    // LaunchServices, so NSRunningApplication activation alone can be ignored.
    // AX frontmost state keeps typed input pinned to the owned PID.
    _ = AXUIElementSetAttributeValue(
        appElement,
        kAXFrontmostAttribute as CFString,
        kCFBooleanTrue
    )
    _ = runningApp.activate(options: [.activateAllWindows])
    for _ in 0..<20 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}

func targetFieldIsFocused(_ element: AXUIElement) -> Bool {
    guard let focused = copyAttribute(element, kAXFocusedAttribute as CFString) as? NSNumber else {
        return false
    }
    return focused.boolValue
}

func copyPasteboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
    (pasteboard.pasteboardItems ?? []).map { item in
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) {
                copy.setData(data, forType: type)
            }
        }
        return copy
    }
}

func restorePasteboard(_ savedPasteboardItems: [NSPasteboardItem], on pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    if !savedPasteboardItems.isEmpty {
        pasteboard.writeObjects(savedPasteboardItems)
    }
}

func typeReplacement() -> Bool {
    let pasteboard = NSPasteboard.general
    let savedPasteboardItems = copyPasteboardItems(pasteboard)
    defer { restorePasteboard(savedPasteboardItems, on: pasteboard) }

    pasteboard.clearContents()
    guard pasteboard.setString(replacement, forType: .string),
          let source = CGEventSource(stateID: .hidSystemState),
          postKey(source, keyCode: 0, keyDown: true, flags: .maskCommand),
          postKey(source, keyCode: 0, keyDown: false, flags: .maskCommand) else {
        return false
    }
    Thread.sleep(forTimeInterval: 0.1)

    if replacement.isEmpty {
        let posted = postKey(source, keyCode: 51, keyDown: true)
            && postKey(source, keyCode: 51, keyDown: false)
        Thread.sleep(forTimeInterval: 0.5)
        return posted
    }

    let posted = postKey(source, keyCode: 9, keyDown: true, flags: .maskCommand)
        && postKey(source, keyCode: 9, keyDown: false, flags: .maskCommand)
    Thread.sleep(forTimeInterval: 0.5)
    return posted
}

let childAttributes = [
    kAXChildrenAttribute as String,
    "AXVisibleChildren",
    "AXContents",
    "AXRows",
    "AXColumns",
    "AXDisclosedRows"
]

guard let windowsValue = copyAttribute(appElement, kAXWindowsAttribute as CFString) else {
    fputs("Target app pid \(pid) has no visible AX windows.\n", stderr)
    exit(2)
}

var queue = elements(from: windowsValue)
var cursor = 0
var visitedCount = 0

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let role = stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) ?? ""
    if (role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String)),
       signal(for: element).contains(marker) {
        guard activateTarget() else {
            fputs("Refusing AX text input because app pid \(pid) is not frontmost.\n", stderr)
            exit(1)
        }
        let focusResult = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard focusResult == .success else {
            fputs("Failed to focus AX text field marker \(marker): \(focusResult.rawValue).\n", stderr)
            exit(1)
        }
        Thread.sleep(forTimeInterval: 0.3)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              targetFieldIsFocused(element) else {
            fputs("Refusing AX text input because the target field is not focused in app pid \(pid).\n", stderr)
            exit(1)
        }
        guard typeReplacement() else {
            fputs("Failed to post keyboard input to app pid \(pid).\n", stderr)
            exit(1)
        }

        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.1)
            let actual = stringValue(copyAttribute(element, kAXValueAttribute as CFString)) ?? ""
            if actual == replacement {
                print("set text field \(marker)")
                exit(0)
            }
        }
        fputs("AX text field marker \(marker) did not retain the replacement value.\n", stderr)
        exit(1)
    }

    for attribute in childAttributes {
        queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)))
    }
}

if visitedCount >= maxNodes {
    fputs("AX text field scan reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
fputs("Missing AX text field marker: \(marker).\n", stderr)
exit(1)
