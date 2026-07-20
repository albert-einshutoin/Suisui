import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let rawPID = Int32(CommandLine.arguments[1]),
      rawPID > 0 else {
    fputs("AX identifier count requires an app PID and identifier marker.\n", stderr)
    exit(2)
}

let appPID = pid_t(rawPID)
let identifierMarker = CommandLine.arguments[2]
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to count Suisui UI evidence markers.\n", stderr)
    exit(2)
}
guard let runningApp = NSRunningApplication(processIdentifier: appPID), !runningApp.isTerminated else {
    fputs("Target app PID \(appPID) is not running.\n", stderr)
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
    return (value as? NSNumber)?.stringValue
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

func isEnabled(_ element: AXUIElement) -> Bool {
    guard let value = copyAttribute(element, kAXEnabledAttribute as CFString) else {
        return true
    }
    return (value as? NSNumber)?.boolValue ?? true
}

func isActionable(_ element: AXUIElement) -> Bool {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let names,
          let actionNames = names as? [String] else {
        return false
    }
    return actionNames.contains(kAXPressAction as String)
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
          size.width > 1,
          size.height > 1 else {
        return nil
    }
    return CGRect(origin: position, size: size)
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
    fputs("Target app PID \(appPID) has no visible AX windows.\n", stderr)
    exit(2)
}

var queue = elements(from: windowsValue)
var cursor = 0
var visitedCount = 0
var totalCount = 0
var enabledCount = 0
var enabledActionableFrames: [CGRect] = []

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)) ?? ""
    if identifier.contains(identifierMarker) {
        totalCount += 1
        if isEnabled(element) {
            enabledCount += 1
            if isActionable(element), let elementFrame = frame(of: element) {
                // SwiftUI can expose the same visible Button as more than one
                // actionable AX node. Overlapping frames represent one CTA;
                // spatially separate frames remain separate visible actions.
                if !enabledActionableFrames.contains(where: { $0.intersects(elementFrame) }) {
                    enabledActionableFrames.append(elementFrame)
                }
            }
        }
    }
    for attribute in childAttributes {
        queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)))
    }
}

if visitedCount >= maxNodes {
    fputs("AX identifier count reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
    exit(2)
}

print("total=\(totalCount) enabled=\(enabledCount) actionable_enabled=\(enabledActionableFrames.count)")
