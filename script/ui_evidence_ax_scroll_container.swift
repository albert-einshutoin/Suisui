import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let rawPID = Int32(CommandLine.arguments[1]) else {
    fputs("AX scroll requires app pid and a scroll-container identifier/text marker.\n", stderr)
    exit(2)
}

let pid = pid_t(rawPID)
let marker = CommandLine.arguments[2]
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000
let scrollEventCount = Int(environment["SUISUI_UI_EVIDENCE_AX_SCROLL_EVENTS"] ?? "10") ?? 10

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to scroll Suisui UI evidence.\n", stderr)
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

func activateTarget() -> Bool {
    // Directly launched smoke binaries are not registered through
    // LaunchServices, so NSRunningApplication activation alone can be ignored.
    // Set the process AX state first, then retain AppKit activation as a second
    // signal before sending any input event.
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

struct TraversalNode {
    let element: AXUIElement
    let owningWindow: AXUIElement
}

let windows = elements(from: windowsValue)
var queue = windows.map { TraversalNode(element: $0, owningWindow: $0) }
var cursor = 0
var visitedCount = 0

while cursor < queue.count && visitedCount < maxNodes {
    let node = queue[cursor]
    let element = node.element
    cursor += 1
    visitedCount += 1

    let role = stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) ?? ""
    if role == (kAXScrollAreaRole as String), signal(for: element).contains(marker) {
        guard activateTarget() else {
            fputs("Refusing AX scroll because app pid \(pid) is not frontmost.\n", stderr)
            exit(1)
        }
        // Raising every app window leaves the last sibling above the modal we
        // are about to scroll. Raise only the window that owns the matched
        // container so its sheet remains visible and receives the wheel event.
        _ = AXUIElementPerformAction(node.owningWindow, kAXRaiseAction as CFString)
        guard let position = point(from: copyAttribute(element, kAXPositionAttribute as CFString)),
              let dimensions = size(from: copyAttribute(element, kAXSizeAttribute as CFString)),
              dimensions.width > 0,
              dimensions.height > 0,
              let source = CGEventSource(stateID: .hidSystemState) else {
            fputs("AX scroll container marker \(marker) has no usable screen bounds.\n", stderr)
            exit(1)
        }
        let center = CGPoint(
            x: position.x + dimensions.width / 2,
            y: position.y + dimensions.height / 2
        )
        for _ in 0..<max(1, scrollEventCount) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let event = CGEvent(
                    scrollWheelEvent2Source: source,
                    units: .line,
                    wheelCount: 1,
                    wheel1: -8,
                    wheel2: 0,
                    wheel3: 0
                  ) else {
                fputs("Refusing AX scroll because target focus changed.\n", stderr)
                exit(1)
            }
            event.location = center
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.15)
        }
        print("scrolled AX container \(marker)")
        exit(0)
    }

    for attribute in childAttributes {
        queue.append(contentsOf: elements(from: copyAttribute(element, attribute as CFString)).map {
            TraversalNode(element: $0, owningWindow: node.owningWindow)
        })
    }
}

if visitedCount >= maxNodes {
    fputs("AX scroll scan reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
fputs("Missing AX scroll container marker: \(marker).\n", stderr)
exit(1)
