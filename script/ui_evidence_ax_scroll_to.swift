import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("AX scroll requires app name, an exact AX identifier, and the owned app PID.\n", stderr)
    exit(2)
}

let appName = CommandLine.arguments[1]
let targetIdentifier = CommandLine.arguments[2]
guard !targetIdentifier.isEmpty else {
    fputs("AX scroll target identifier must not be empty.\n", stderr)
    exit(2)
}
guard let rawPID = Int32(CommandLine.arguments[3]), rawPID > 0 else {
    fputs("AX scroll app PID must be a positive integer.\n", stderr)
    exit(2)
}
let appPID = pid_t(rawPID)
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000

guard maxNodes > 0 else {
    fputs("SUISUI_UI_EVIDENCE_AX_MAX_NODES must be a positive integer.\n", stderr)
    exit(2)
}
guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to scroll Suisui UI evidence targets.\n", stderr)
    exit(2)
}
guard NSWorkspace.shared.runningApplications.contains(where: { app in
    app.processIdentifier == appPID
}) else {
    fputs("\(appName) PID \(appPID) is not visible to Accessibility.\n", stderr)
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

func numberValue(_ value: CFTypeRef?) -> Double? {
    guard let value else { return nil }
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let string = value as? String {
        return Double(string)
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

func pointValue(_ value: CFTypeRef?) -> CGPoint? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
}

func sizeValue(_ value: CFTypeRef?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let position = pointValue(copyAttribute(element, kAXPositionAttribute as CFString)),
          let size = sizeValue(copyAttribute(element, kAXSizeAttribute as CFString)),
          size.width > 0,
          size.height > 0 else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

func isOwnedByEvidenceApp(_ element: AXUIElement) -> Bool {
    var pid: pid_t = 0
    return AXUIElementGetPid(element, &pid) == .success && pid == appPID
}

func appendUnique(_ element: AXUIElement, to elements: inout [AXUIElement]) {
    guard !elements.contains(where: { CFEqual($0, element) }) else { return }
    elements.append(element)
}

func describeFrame(_ frame: CGRect?) -> String {
    guard let frame else { return "unavailable" }
    return String(
        format: "%.1fx%.1f+%.1f+%.1f",
        frame.width,
        frame.height,
        frame.minX,
        frame.minY
    )
}

let childAttributes = [
    kAXChildrenAttribute as String,
    "AXVisibleChildren",
    "AXContents",
    "AXRows",
    "AXColumns",
    "AXDisclosedRows"
]

func parentChain(startingAt element: AXUIElement) -> [AXUIElement] {
    var chain = [AXUIElement]()
    var current = element

    for _ in 0..<128 {
        guard let parent = elements(from: copyAttribute(current, kAXParentAttribute as CFString)).first,
              isOwnedByEvidenceApp(parent),
              !chain.contains(where: { CFEqual($0, parent) }) else {
            break
        }
        chain.append(parent)
        current = parent
    }
    return chain
}

func verticalScrollBars(from element: AXUIElement) -> [AXUIElement] {
    var scrollBars = [AXUIElement]()
    let role = stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) ?? ""
    let orientation = stringValue(copyAttribute(element, kAXOrientationAttribute as CFString)) ?? ""
    if role == (kAXScrollBarRole as String), orientation == (kAXVerticalOrientationValue as String) {
        appendUnique(element, to: &scrollBars)
    }

    for scrollBar in elements(from: copyAttribute(element, kAXVerticalScrollBarAttribute as CFString)) {
        guard isOwnedByEvidenceApp(scrollBar) else { continue }
        appendUnique(scrollBar, to: &scrollBars)
    }

    for child in childAttributes.flatMap({ attribute in
        elements(from: copyAttribute(element, attribute as CFString))
    }) {
        let childRole = stringValue(copyAttribute(child, kAXRoleAttribute as CFString)) ?? ""
        let childOrientation = stringValue(copyAttribute(child, kAXOrientationAttribute as CFString)) ?? ""
        if childRole == (kAXScrollBarRole as String),
           childOrientation == (kAXVerticalOrientationValue as String),
           isOwnedByEvidenceApp(child) {
            appendUnique(child, to: &scrollBars)
        }
    }
    return scrollBars
}

func hasUsefulIntersection(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else { return false }
    // A one-pixel overlap is not useful screenshot evidence. Keep enough of
    // the landmark visible to make the specialized raster materially distinct.
    let requiredHeight = min(64.0, lhs.height)
    return intersection.width > 1 && intersection.height >= requiredHeight
}

func targetIsVisible(
    _ target: AXUIElement,
    in windowFrames: [CGRect],
    clippedBy scrollAreaFrames: [CGRect]
) -> Bool {
    guard let targetFrame = frame(of: target),
          windowFrames.contains(where: { hasUsefulIntersection(targetFrame, $0) }) else {
        return false
    }
    return scrollAreaFrames.allSatisfy { hasUsefulIntersection(targetFrame, $0) }
}

struct ScrollSweepResult {
    let didSetValue: Bool
    let lastError: AXError?
}

func sweepVerticalScrollBar(
    _ scrollBar: AXUIElement,
    target: AXUIElement,
    windowFrames: [CGRect],
    scrollAreaFrames: [CGRect]
) -> ScrollSweepResult {
    var settable = DarwinBoolean(false)
    let settableResult = AXUIElementIsAttributeSettable(
        scrollBar,
        kAXValueAttribute as CFString,
        &settable
    )
    guard settableResult == .success, settable.boolValue else {
        return ScrollSweepResult(didSetValue: false, lastError: settableResult)
    }

    let minimum = numberValue(copyAttribute(scrollBar, kAXMinValueAttribute as CFString)) ?? 0
    let maximum = numberValue(copyAttribute(scrollBar, kAXMaxValueAttribute as CFString)) ?? 1
    let current = numberValue(copyAttribute(scrollBar, kAXValueAttribute as CFString)) ?? minimum
    guard minimum.isFinite, maximum.isFinite, current.isFinite, maximum > minimum else {
        return ScrollSweepResult(didSetValue: false, lastError: .illegalArgument)
    }

    let stepCount = 40
    let allValues = (0...stepCount).map { step in
        minimum + ((maximum - minimum) * Double(step) / Double(stepCount))
    }
    let targetFrame = frame(of: target)
    let clipFrame = scrollAreaFrames.last
    let targetIsBelow = targetFrame.map { targetFrame in
        clipFrame.map { targetFrame.midY >= $0.midY } ?? true
    } ?? true
    let forward = allValues.filter { $0 >= current }
    let backward = allValues.filter { $0 < current }.reversed()
    let orderedValues = targetIsBelow
        ? forward + backward
        : Array(backward) + forward

    var didSetValue = false
    var lastError: AXError?
    for value in orderedValues {
        let result = AXUIElementSetAttributeValue(
            scrollBar,
            kAXValueAttribute as CFString,
            NSNumber(value: value)
        )
        if result != .success {
            lastError = result
            continue
        }
        didSetValue = true
        Thread.sleep(forTimeInterval: 0.05)
        if targetIsVisible(target, in: windowFrames, clippedBy: scrollAreaFrames) {
            return ScrollSweepResult(didSetValue: true, lastError: nil)
        }
    }
    return ScrollSweepResult(didSetValue: didSetValue, lastError: lastError)
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
let windowFrames = windows.compactMap(frame)

var visitedCount = 0
var queue = windows
var cursor = 0
var target: AXUIElement?
var discoveredScrollAreas = [AXUIElement]()

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    let role = stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) ?? ""
    if role == (kAXScrollAreaRole as String) {
        appendUnique(element, to: &discoveredScrollAreas)
    }
    let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)) ?? ""
    if identifier == targetIdentifier {
        target = element
        break
    }

    let children = childAttributes.flatMap { attribute in
        elements(from: copyAttribute(element, attribute as CFString))
    }
    if !children.isEmpty {
        queue.append(contentsOf: children)
    }
}

guard let target else {
    if visitedCount >= maxNodes {
        fputs("AX scroll scan reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
    }
    fputs("missing exact AX scroll target: \(targetIdentifier)\n", stderr)
    exit(1)
}

let ancestors = parentChain(startingAt: target)
let ancestorScrollAreas = ancestors.filter { element in
    (stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) ?? "") == (kAXScrollAreaRole as String)
}
let scrollAreaFrames = ancestorScrollAreas.compactMap(frame)

if targetIsVisible(target, in: windowFrames, clippedBy: scrollAreaFrames) {
    print("already-visible")
    exit(0)
}

// Prefer the platform action when the app exposes it, but verify the resulting
// geometry. SwiftUI ScrollView children can report AXError.actionUnsupported,
// so an action result alone is not sufficient evidence.
let directActionResult = AXUIElementPerformAction(target, "AXScrollToVisible" as CFString)
if directActionResult == .success {
    Thread.sleep(forTimeInterval: 0.1)
    if targetIsVisible(target, in: windowFrames, clippedBy: scrollAreaFrames) {
        print("scrolled-action")
        exit(0)
    }
}

var scrollAreaCandidates = [AXUIElement]()
for scrollArea in ancestorScrollAreas.reversed() {
    appendUnique(scrollArea, to: &scrollAreaCandidates)
}
for scrollArea in discoveredScrollAreas.reversed() {
    appendUnique(scrollArea, to: &scrollAreaCandidates)
}

var scrollBars = [AXUIElement]()
for scrollArea in scrollAreaCandidates {
    for scrollBar in verticalScrollBars(from: scrollArea) {
        appendUnique(scrollBar, to: &scrollBars)
    }
}

var didSetAnyValue = false
var lastSweepError: AXError?
for scrollBar in scrollBars {
    let result = sweepVerticalScrollBar(
        scrollBar,
        target: target,
        windowFrames: windowFrames,
        scrollAreaFrames: scrollAreaFrames
    )
    didSetAnyValue = didSetAnyValue || result.didSetValue
    lastSweepError = result.lastError ?? lastSweepError
    if targetIsVisible(target, in: windowFrames, clippedBy: scrollAreaFrames) {
        print("scrolled-scrollbar")
        exit(0)
    }
}

if visitedCount >= maxNodes {
    fputs("AX scroll scan reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
let ancestorRoles = ancestors.map { element in
    stringValue(copyAttribute(element, kAXRoleAttribute as CFString)) ?? "unknown"
}.joined(separator: " -> ")
let windowFrameDescription = windowFrames.map { describeFrame($0) }.joined(separator: ", ")
fputs("AX scroll could not reveal exact target: \(targetIdentifier)\n", stderr)
fputs("target frame: \(describeFrame(frame(of: target)))\n", stderr)
fputs("owned window frames: \(windowFrameDescription.isEmpty ? "unavailable" : windowFrameDescription)\n", stderr)
fputs("ancestor roles: \(ancestorRoles.isEmpty ? "unavailable" : ancestorRoles)\n", stderr)
fputs("direct AXScrollToVisible result: AXError \(directActionResult.rawValue)\n", stderr)
fputs("vertical scroll areas/bars: \(scrollAreaCandidates.count)/\(scrollBars.count); set value: \(didSetAnyValue)\n", stderr)
if let lastSweepError {
    fputs("last vertical scrollbar AXError: \(lastSweepError.rawValue)\n", stderr)
}
exit(1)
