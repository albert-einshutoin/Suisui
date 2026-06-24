import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("AX marker check requires app name, AX identifier marker, and text marker.\n", stderr)
    exit(2)
}

let appName = CommandLine.arguments[1]
let identifierNeedle = CommandLine.arguments[2]
let textNeedle = CommandLine.arguments[3]
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SOLOPM_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to inspect SoloPM UI evidence markers.\n", stderr)
    exit(2)
}

guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { app in
    app.localizedName == appName || app.bundleIdentifier == "dev.solopm.app"
}) else {
    fputs("\(appName) process is not visible to Accessibility.\n", stderr)
    exit(2)
}

let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
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

func signalParts(for element: AXUIElement) -> (identifier: String, signal: String) {
    let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)) ?? ""
    let attributes = [
        "AXTitle",
        "AXDescription",
        "AXHelp",
        "AXValue",
        "AXRole",
        "AXSubrole",
        "AXLabel"
    ]
    let signal = ([identifier] + attributes.compactMap { attribute in
        stringValue(copyAttribute(element, attribute as CFString))
    }).joined(separator: " ")
    return (identifier, signal)
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
    fputs("\(appName) has no visible AX windows.\n", stderr)
    exit(2)
}

let windows = elements(from: windowsValue)
guard !windows.isEmpty else {
    fputs("\(appName) has no visible AX windows.\n", stderr)
    exit(2)
}

var foundIdentifier = false
var foundText = false
var visitedCount = 0
var queue = windows
var cursor = 0

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let signal = signalParts(for: element)
    if signal.identifier.contains(identifierNeedle) {
        foundIdentifier = true
    }
    if signal.signal.contains(textNeedle) {
        foundText = true
    }
    if foundIdentifier && foundText {
        print("present")
        exit(0)
    }

    let children = childAttributes.flatMap { attribute in
        elements(from: copyAttribute(element, attribute as CFString))
    }
    if !children.isEmpty {
        queue.append(contentsOf: children)
    }
}

if visitedCount >= maxNodes {
    fputs("AX marker scan reached SOLOPM_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
if !foundIdentifier {
    fputs("missing AX identifier marker: \(identifierNeedle)\n", stderr)
}
if !foundText {
    fputs("missing AX text marker: \(textNeedle)\n", stderr)
}
exit(1)
