import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let rawPID = Int32(CommandLine.arguments[1]),
      rawPID > 0 else {
    fputs("AX frame dump requires an app pid.\n", stderr)
    exit(2)
}

let appPID = pid_t(rawPID)
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SOLOPM_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to inspect SoloPM layout frames.\n", stderr)
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

func point(from value: CFTypeRef?) -> CGPoint? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
}

func size(from value: CFTypeRef?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
}

func tsvSafe(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
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

var queue = elements(from: windowsValue)
guard !queue.isEmpty else {
    fputs("Target app pid \(appPID) has no visible AX windows.\n", stderr)
    exit(2)
}

var cursor = 0
var visitedCount = 0
while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    if let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)),
       !identifier.isEmpty,
       let position = point(from: copyAttribute(element, kAXPositionAttribute as CFString)),
       let dimensions = size(from: copyAttribute(element, kAXSizeAttribute as CFString)) {
        print([
            tsvSafe(identifier),
            String(Int(position.x.rounded())),
            String(Int(position.y.rounded())),
            String(Int(dimensions.width.rounded())),
            String(Int(dimensions.height.rounded()))
        ].joined(separator: "\t"))
    }

    for attribute in childAttributes {
        queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)))
    }
}

if visitedCount >= maxNodes {
    fputs("AX frame dump reached SOLOPM_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
    exit(1)
}
