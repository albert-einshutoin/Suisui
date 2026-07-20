import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 5 else {
    fputs("AX marker check requires app name, AX identifier marker, text marker, and an optional app PID.\n", stderr)
    exit(2)
}

let appName = CommandLine.arguments[1]
let identifierNeedle = CommandLine.arguments[2]
let textNeedle = CommandLine.arguments[3]
let requestedPID: pid_t?
if CommandLine.arguments.count == 5 {
    guard let rawPID = Int32(CommandLine.arguments[4]), rawPID > 0 else {
        fputs("AX marker check app PID must be a positive integer.\n", stderr)
        exit(2)
    }
    requestedPID = pid_t(rawPID)
} else {
    requestedPID = nil
}
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000
let requireIdentifierSubtree = environment["SUISUI_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE"] == "1"
let requireExactIdentifier = environment["SUISUI_UI_EVIDENCE_AX_REQUIRE_EXACT_IDENTIFIER"] == "1"

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to inspect Suisui UI evidence markers.\n", stderr)
    exit(2)
}

let appPID: pid_t
if let requestedPID {
    // A smoke owns this exact PID. Resolving by display name here could inspect
    // a developer's separately running Suisui and turn a failed launch green.
    guard NSWorkspace.shared.runningApplications.contains(where: { app in
        app.processIdentifier == requestedPID
    }) else {
        fputs("\(appName) PID \(requestedPID) is not visible to Accessibility.\n", stderr)
        exit(2)
    }
    appPID = requestedPID
} else {
    guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { app in
        app.localizedName == appName || app.bundleIdentifier == "dev.suisui.app"
    }) else {
        fputs("\(appName) process is not visible to Accessibility.\n", stderr)
        exit(2)
    }
    appPID = runningApp.processIdentifier
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

func subtreeContainsText(startingAt root: AXUIElement, textNeedle: String) -> Bool {
    var visitedCount = 0
    var queue = [root]
    var cursor = 0

    while cursor < queue.count && visitedCount < maxNodes {
        let element = queue[cursor]
        cursor += 1
        visitedCount += 1

        if textNeedle.isEmpty || signalParts(for: element).signal.contains(textNeedle) {
            return true
        }

        let children = childAttributes.flatMap { attribute in
            elements(from: copyAttribute(element, attribute as CFString))
        }
        if !children.isEmpty {
            queue.append(contentsOf: children)
        }
    }

    if visitedCount >= maxNodes {
        fputs("AX marker subtree scan reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
    }
    return false
}

guard let windowsValue = copyAttribute(appElement, kAXWindowsAttribute as CFString) else {
    fputs("\(appName) has no visible AX windows.\n", stderr)
    exit(2)
}

let windows = elements(from: windowsValue)
guard !windows.isEmpty else {
    fputs("\(appName) has no visible AX windows.\n", stderr)
    exit(2)
}

// Performance smoke needs a localization- and brand-independent first-window
// timestamp. Keep that intent explicit instead of treating an empty AX
// identifier as a wildcard, which conflicts with exact-identifier audits.
if identifierNeedle == "__AX_ANY_WINDOW__" {
    print("present")
    exit(0)
}

var foundIdentifier = false
// An empty text marker intentionally means identifier-only verification. This
// keeps stable AX identifiers usable across locales without accepting a missing
// identifier as product evidence.
var foundText = textNeedle.isEmpty
var visitedCount = 0
var queue = windows
var cursor = 0

func identifierMatches(_ identifier: String) -> Bool {
    requireExactIdentifier
        ? identifier == identifierNeedle
        : identifier.contains(identifierNeedle)
}

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let signal = signalParts(for: element)
    if requireIdentifierSubtree {
        if identifierMatches(signal.identifier) {
            foundIdentifier = true
            if subtreeContainsText(startingAt: element, textNeedle: textNeedle) {
                print("present")
                exit(0)
            }
        }
    } else {
        if identifierMatches(signal.identifier) {
            foundIdentifier = true
        }
        if signal.signal.contains(textNeedle) {
            foundText = true
        }
        if foundIdentifier && foundText {
            print("present")
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
    fputs("AX marker scan reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
if !foundIdentifier {
    fputs("missing AX identifier marker: \(identifierNeedle)\n", stderr)
}
if !textNeedle.isEmpty && !foundText {
    fputs("missing AX text marker: \(textNeedle)\n", stderr)
}
exit(1)
