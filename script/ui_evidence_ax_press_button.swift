import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("AX button press requires app pid/name and button identifier/text marker.\n", stderr)
    exit(2)
}

let appSelector = CommandLine.arguments[1]
let marker = CommandLine.arguments[2]
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SOLOPM_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to press SoloPM UI evidence buttons.\n", stderr)
    exit(2)
}

let runningApp: NSRunningApplication?
if let rawPID = Int32(appSelector) {
    let pid = pid_t(rawPID)
    runningApp = NSRunningApplication(processIdentifier: pid)
} else {
    runningApp = NSWorkspace.shared.runningApplications.first(where: { app in
        app.localizedName == appSelector || app.bundleIdentifier == "dev.solopm.app"
    })
}

guard let runningApp, !runningApp.isTerminated else {
    fputs("\(appSelector) process is not visible to Accessibility.\n", stderr)
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

func boolValue(_ value: CFTypeRef?) -> Bool? {
    guard let value else { return nil }
    if let number = value as? NSNumber {
        return number.boolValue
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

func signalParts(for element: AXUIElement) -> (role: String, enabled: Bool, signal: String) {
    let role = stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) ?? ""
    let enabled = boolValue(copyAttribute(element, kAXEnabledAttribute as CFString)) ?? true
    let attributes = [
        "AXIdentifier",
        "AXTitle",
        "AXDescription",
        "AXHelp",
        "AXValue",
        "AXLabel"
    ]
    let signal = attributes.compactMap { attribute in
        stringValue(copyAttribute(element, attribute as CFString))
    }.joined(separator: " ")
    return (role, enabled, signal)
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
    fputs("\(appSelector) has no visible AX windows.\n", stderr)
    exit(2)
}

let windows = elements(from: windowsValue)
guard !windows.isEmpty else {
    fputs("\(appSelector) has no visible AX windows.\n", stderr)
    exit(2)
}

var visitedCount = 0
var foundDisabledMatch = false
var queue = windows
var cursor = 0

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let signal = signalParts(for: element)
    if signal.role == (kAXButtonRole as String), signal.signal.contains(marker) {
        if !signal.enabled {
            foundDisabledMatch = true
        } else if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            print("pressed")
            exit(0)
        }
    }

    let children = childAttributes.flatMap { attribute in
        elements(from: copyAttribute(element, attribute as CFString))
    }
    if !children.isEmpty {
        queue.append(contentsOf: children)
    }
}

if visitedCount >= maxNodes {
    fputs("AX button scan reached SOLOPM_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
if foundDisabledMatch {
    fputs("button marker matched but was disabled: \(marker)\n", stderr)
} else {
    fputs("missing enabled AX button marker: \(marker)\n", stderr)
}
exit(1)
