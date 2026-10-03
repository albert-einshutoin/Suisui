import ApplicationServices
import AppKit
import Foundation

let countsToolbar = CommandLine.arguments.count >= 3 && CommandLine.arguments[2] == "--toolbar-count"
let readsMenuState = CommandLine.arguments.count >= 3 && CommandLine.arguments[2] == "--menu-item-state"
let pressesMenu = CommandLine.arguments.count >= 3 && CommandLine.arguments[2] == "--menu-press"
guard (countsToolbar ? CommandLine.arguments.count == 3 :
       readsMenuState ? CommandLine.arguments.count == 5 :
       pressesMenu ? CommandLine.arguments.count == 4 :
       CommandLine.arguments.count == 3 || (
        CommandLine.arguments.count == 4 && ["--exact", "--center"].contains(CommandLine.arguments[3])
      )),
      let rawPID = Int32(CommandLine.arguments[1]),
      rawPID > 0 else {
    fputs("AX element press requires a pid and identifier [--exact|--center], --toolbar-count, --menu-item-state title localized-title, or --menu-press identifier.\n", stderr)
    exit(2)
}

let appPID = pid_t(rawPID)
let marker = pressesMenu ? CommandLine.arguments[3] : CommandLine.arguments[2]
let exactMatch = pressesMenu || CommandLine.arguments.count == 4
let centersElement = !pressesMenu && CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--center"
guard !marker.isEmpty,
      !readsMenuState || (!CommandLine.arguments[3].isEmpty && !CommandLine.arguments[4].isEmpty) else {
    fputs("AX identifiers and menu titles must not be empty.\n", stderr)
    exit(2)
}
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000
guard maxNodes > 0 else {
    fputs("SUISUI_UI_EVIDENCE_AX_MAX_NODES must be positive.\n", stderr)
    exit(2)
}

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to press Suisui UI elements.\n", stderr)
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
    guard actionNames(for: element).contains(kAXPressAction as String) else {
        return false
    }
    // AXPress is PID-scoped and does not require the application to be
    // frontmost. Trying it first avoids treating a denied foreground
    // activation as if the product control were missing.
    let performPressWithoutActivation =
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    if performPressWithoutActivation {
        return true
    }
    guard activateTarget() else { return false }
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
    isSettable.boolValue else {
        return false
    }
    // Selection is also bound to this exact AX element. Keep foreground
    // activation as a retry for OS variants that require it, not a prerequisite
    // that can mask a valid selectable SwiftUI row.
    let selectWithoutActivation =
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    if selectWithoutActivation {
        return true
    }
    guard activateTarget() else { return false }
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
    guard let frame = frame(of: element) else {
        fputs("Owned AX element has no positive visible frame.\n", stderr)
        return false
    }
    guard activateTarget() else {
        fputs("Could not activate owned PID \(appPID); frontmost PID is \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1).\n", stderr)
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

// System Events can omit SwiftUI toolbar descendants. Use the same native AX
// tree for toolbar discovery and actions, scoped to the owned Project Board.
func descendants(of roots: [AXUIElement]) -> [AXUIElement] {
    var queue = roots
    var visited = [AXUIElement]()
    var cursor = 0
    while cursor < queue.count {
        let element = queue[cursor]
        cursor += 1
        if visited.contains(where: { CFEqual($0, element) }) { continue }
        guard visited.count < maxNodes else {
            fputs("AX toolbar traversal reached SUISUI_UI_EVIDENCE_AX_MAX_NODES.\n", stderr)
            exit(1)
        }
        visited.append(element)
        for attribute in childAttributes {
            queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)))
        }
    }
    return visited
}

if countsToolbar {
    let projectBoardIdentifiers = Set(["project-board-sidebar-toggle", "project-board-integrations-menu"])
    let projectBoardWindows = windows.filter { window in
        let identifiers = Set(descendants(of: [window]).compactMap {
            stringValue(copyAttribute($0, "AXIdentifier" as CFString))
        })
        return projectBoardIdentifiers.isSubset(of: identifiers)
    }
    guard projectBoardWindows.count == 1 else {
        fputs("Expected one PID-owned Project Board AX window, found \(projectBoardWindows.count).\n", stderr)
        exit(1)
    }
    let toolbars = descendants(of: projectBoardWindows).filter {
        stringValue(copyAttribute($0, kAXRoleAttribute as CFString)) == (kAXToolbarRole as String)
    }
    guard toolbars.count == 1 else {
        fputs("Expected one native Project Board toolbar, found \(toolbars.count).\n", stderr)
        exit(1)
    }
    print(toolbars.count)
    exit(0)
}

if readsMenuState {
    let menuTitles = Set([CommandLine.arguments[3], CommandLine.arguments[4]])
    for _ in 0..<20 {
        let matches = descendants(of: [appElement]).filter {
            stringValue(copyAttribute($0, kAXRoleAttribute as CFString)) == (kAXMenuItemRole as String)
                && menuTitles.contains(stringValue(copyAttribute($0, kAXTitleAttribute as CFString)) ?? "")
                && frame(of: $0) != nil
        }
        guard matches.count <= 1 else {
            fputs("Expected one visible owned menu item, found \(matches.count).\n", stderr)
            exit(1)
        }
        if let item = matches.first {
            guard let enabled = copyAttribute(item, kAXEnabledAttribute as CFString) as? NSNumber else {
                fputs("Owned menu item enabled state is unknown.\n", stderr)
                exit(1)
            }
            print(enabled.boolValue ? "enabled" : "disabled")
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    fputs("Owned visible menu item was not available.\n", stderr)
    exit(1)
}

var queue = pressesMenu ? [appElement] : windows
var cursor = 0
var visitedCount = 0
var foundUnpressableMatch = false

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)) ?? ""
    if exactMatch ? identifier == marker : identifier.contains(marker) {
        if centersElement {
            guard clickElementCenter(element, windows: windows) else {
                fputs("Could not click the owned exact AX element center.\n", stderr)
                exit(1)
            }
            print("clicked owned AX element center \(identifier)")
            exit(0)
        }
        if pressesMenu {
            guard stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) == (kAXMenuItemRole as String),
                  frame(of: element) != nil,
                  let enabled = copyAttribute(element, kAXEnabledAttribute as CFString) as? NSNumber,
                  enabled.boolValue,
                  AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
                fputs("Owned menu item was not visibly enabled and pressable.\n", stderr)
                exit(1)
            }
            print("pressed owned menu item \(identifier)")
            exit(0)
        }
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
    fputs("AX element press reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
if foundUnpressableMatch {
    fputs("AX identifier matched but did not expose a successful AXPress action: \(marker).\n", stderr)
} else {
    fputs("Missing AX identifier marker: \(marker).\n", stderr)
}
exit(1)
