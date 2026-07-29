import ApplicationServices
import AppKit
import Foundation

guard (CommandLine.arguments.count == 2 || CommandLine.arguments.count == 6),
      let rawPID = Int32(CommandLine.arguments[1]),
      rawPID > 0 else {
    fputs("AX frame dump requires an app pid and optional expected window x y width height.\n", stderr)
    exit(2)
}

let appPID = pid_t(rawPID)
let expectedWindowFrame: CGRect?
if CommandLine.arguments.count == 6 {
    guard let x = Double(CommandLine.arguments[2]),
          let y = Double(CommandLine.arguments[3]),
          let width = Double(CommandLine.arguments[4]),
          let height = Double(CommandLine.arguments[5]),
          width > 0,
          height > 0 else {
        fputs("Expected AX window frame must contain numeric x y width height values.\n", stderr)
        exit(2)
    }
    expectedWindowFrame = CGRect(x: x, y: y, width: width, height: height)
} else {
    expectedWindowFrame = nil
}
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to inspect Suisui layout frames.\n", stderr)
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

func matchesExpectedWindowFrame(_ element: AXUIElement) -> Bool {
    guard let expectedWindowFrame else { return true }
    guard let position = point(from: copyAttribute(element, kAXPositionAttribute as CFString)),
          let dimensions = size(from: copyAttribute(element, kAXSizeAttribute as CFString)) else {
        return false
    }
    let tolerance = 1.0
    return abs(position.x - expectedWindowFrame.origin.x) <= tolerance
        && abs(position.y - expectedWindowFrame.origin.y) <= tolerance
        && abs(dimensions.width - expectedWindowFrame.width) <= tolerance
        && abs(dimensions.height - expectedWindowFrame.height) <= tolerance
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

let allWindows = elements(from: windowsValue)
let primaryWindows = allWindows.filter(matchesExpectedWindowFrame)
guard !primaryWindows.isEmpty else {
    fputs("Target app pid \(appPID) has no AX window matching the visible CoreGraphics frame.\n", stderr)
    exit(2)
}

var visitedCount = 0
let overlayIdentifiers = Set(["project-inspector", "task-inspector"])

func isContainedInExpectedWindow(position: CGPoint, dimensions: CGSize) -> Bool {
    guard let expectedWindowFrame else { return true }
    let tolerance = 1.0
    return position.x >= expectedWindowFrame.minX - tolerance
        && position.y >= expectedWindowFrame.minY - tolerance
        && position.x + dimensions.width <= expectedWindowFrame.maxX + tolerance
        && position.y + dimensions.height <= expectedWindowFrame.maxY + tolerance
}

func traverse(_ roots: [AXUIElement], overlayOnly: Bool) {
    var queue = roots
    var cursor = 0
    while cursor < queue.count && visitedCount < maxNodes {
        let element = queue[cursor]
        cursor += 1
        visitedCount += 1

        if let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)),
           !identifier.isEmpty,
           (!overlayOnly || overlayIdentifiers.contains(identifier)),
           let position = point(from: copyAttribute(element, kAXPositionAttribute as CFString)),
           let dimensions = size(from: copyAttribute(element, kAXSizeAttribute as CFString)) {
            var fields = [
                tsvSafe(identifier),
                String(Int(position.x.rounded())),
                String(Int(position.y.rounded())),
                String(Int(dimensions.width.rounded())),
                String(Int(dimensions.height.rounded()))
            ]
            if overlayOnly || (
                overlayIdentifiers.contains(identifier)
                    && !isContainedInExpectedWindow(position: position, dimensions: dimensions)
            ) {
                fields.append("overlay")
            }
            print(fields.joined(separator: "\t"))
        }

        for attribute in childAttributes {
            queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)))
        }
    }
}

traverse(primaryWindows, overlayOnly: false)
if expectedWindowFrame != nil {
    traverse(allWindows.filter { !matchesExpectedWindowFrame($0) }, overlayOnly: true)
}

if visitedCount >= maxNodes {
    fputs("AX frame dump reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
    exit(1)
}
