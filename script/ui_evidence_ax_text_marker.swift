import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let rawPID = Int32(CommandLine.arguments[1]), rawPID > 0 else {
    fputs("AX text marker requires app PID and text marker.\n", stderr)
    exit(2)
}
guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to inspect Suisui text.\n", stderr)
    exit(2)
}

let appPID = pid_t(rawPID)
let marker = CommandLine.arguments[2]
guard NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier == appPID }) else {
    fputs("Suisui PID is not visible to Accessibility.\n", stderr)
    exit(2)
}

let appElement = AXUIElementCreateApplication(appPID)
AXUIElementSetMessagingTimeout(appElement, 1.0)

func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 1.0)
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute, &value) == .success ? value : nil
}

func stringValue(_ value: CFTypeRef?) -> String {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return ""
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

let childAttributes = [
    kAXChildrenAttribute as String,
    "AXVisibleChildren",
    "AXContents",
    "AXRows",
    "AXColumns",
    "AXDisclosedRows"
]

guard let windowValue = copyAttribute(appElement, kAXWindowsAttribute as CFString) else {
    fputs("Suisui has no visible AX windows.\n", stderr)
    exit(1)
}

var queue = elements(from: windowValue)
var cursor = 0
let maxNodes = Int(ProcessInfo.processInfo.environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000
while cursor < queue.count && cursor < maxNodes {
    let element = queue[cursor]
    cursor += 1
    let signal = [
        stringValue(copyAttribute(element, "AXIdentifier" as CFString)),
        stringValue(copyAttribute(element, kAXTitleAttribute as CFString)),
        stringValue(copyAttribute(element, kAXDescriptionAttribute as CFString)),
        stringValue(copyAttribute(element, kAXHelpAttribute as CFString)),
        stringValue(copyAttribute(element, kAXValueAttribute as CFString)),
        stringValue(copyAttribute(element, "AXLabel" as CFString))
    ].joined(separator: " ")
    if signal.contains(marker) {
        print("present")
        exit(0)
    }
    for attribute in childAttributes {
        queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)))
    }
}

if cursor >= maxNodes {
    fputs("AX text marker scan reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
fputs("missing AX text marker: \(marker)\n", stderr)
exit(1)
