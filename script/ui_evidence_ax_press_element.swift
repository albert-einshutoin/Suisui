import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let rawPID = Int32(CommandLine.arguments[1]),
      rawPID > 0 else {
    fputs("AX element press requires an app pid and AX identifier marker.\n", stderr)
    exit(2)
}

let appPID = pid_t(rawPID)
let marker = CommandLine.arguments[2]
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SOLOPM_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to press SoloPM UI elements.\n", stderr)
    exit(2)
}

guard let runningApp = NSRunningApplication(processIdentifier: appPID), !runningApp.isTerminated else {
    fputs("Target app pid \(appPID) is not running.\n", stderr)
    exit(2)
}

let appElement = AXUIElementCreateApplication(appPID)
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

func actionNames(for element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let names else {
        return []
    }
    return names as? [String] ?? []
}

func activateTarget() -> Bool {
    _ = runningApp.activate(options: [.activateAllWindows])
    for _ in 0..<20 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == appPID {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}

func press(_ element: AXUIElement, windows: [AXUIElement]) -> Bool {
    guard actionNames(for: element).contains(kAXPressAction as String),
          activateTarget() else {
        return false
    }
    for window in windows {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
}

func select(_ element: AXUIElement, windows: [AXUIElement]) -> Bool {
    var isSettable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(
        element,
        kAXSelectedAttribute as CFString,
        &isSettable
    ) == .success,
    isSettable.boolValue,
    activateTarget() else {
        return false
    }
    for window in windows {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    return AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success
}

func pressElementOrAncestor(_ element: AXUIElement, windows: [AXUIElement]) -> Bool {
    var candidate: AXUIElement? = element
    for _ in 0..<8 {
        guard let current = candidate else { return false }
        if press(current, windows: windows) || select(current, windows: windows) {
            return true
        }
        candidate = elements(from: copyAttribute(current, kAXParentAttribute as CFString)).first
    }
    return false
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = copyAttribute(element, kAXPositionAttribute as CFString),
          let sizeValue = copyAttribute(element, kAXSizeAttribute as CFString),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        return nil
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
          AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size),
          size.width > 1, size.height > 1 else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

// Some locally built SwiftUI rows expose neither AXPress nor a settable
// AXSelected even though the same source presses fine on the hosted runner.
// Fall back to a synthetic click at the matched element's own frame center;
// the coordinates come from the PID-scoped AX element, so the click stays
// bound to the launched evidence app, matching the AppleScript
// "click at {center}" pattern already used by the header-layout gate.
func clickElementCenter(_ element: AXUIElement, windows: [AXUIElement]) -> Bool {
    guard let frame = frame(of: element), activateTarget() else {
        return false
    }
    for window in windows {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    guard let mouseDown = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseDown,
        mouseCursorPosition: center,
        mouseButton: .left
    ), let mouseUp = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseUp,
        mouseCursorPosition: center,
        mouseButton: .left
    ) else {
        return false
    }
    mouseDown.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    mouseUp.post(tap: .cghidEventTap)
    return true
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
    fputs("Target app pid \(appPID) has no visible AX windows.\n", stderr)
    exit(2)
}

let windows = elements(from: windowsValue)
guard !windows.isEmpty else {
    fputs("Target app pid \(appPID) has no visible AX windows.\n", stderr)
    exit(2)
}

var queue = windows
var cursor = 0
var visitedCount = 0
var foundUnpressableMatch = false

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)) ?? ""
    if identifier.contains(marker) {
        if pressElementOrAncestor(element, windows: windows) {
            print("pressed AX element \(identifier)")
            exit(0)
        }
        if clickElementCenter(element, windows: windows) {
            print("clicked AX element center \(identifier)")
            exit(0)
        }
        foundUnpressableMatch = true
    }

    for attribute in childAttributes {
        queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)))
    }
}

if visitedCount >= maxNodes {
    fputs("AX element press reached SOLOPM_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
if foundUnpressableMatch {
    fputs("AX identifier matched but did not expose a successful AXPress action: \(marker).\n", stderr)
} else {
    fputs("Missing AX identifier marker: \(marker).\n", stderr)
}
exit(1)
