import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 5 || CommandLine.arguments.count == 9 else {
    fputs("AX target frame audit requires app name, exact AX identifier, owned app PID, selected window title, and optional captured CG window x y width height.\n", stderr)
    exit(2)
}

let appName = CommandLine.arguments[1]
let targetIdentifier = CommandLine.arguments[2]
guard !targetIdentifier.isEmpty else {
    fputs("AX target frame audit identifier must not be empty.\n", stderr)
    exit(2)
}
guard let rawPID = Int32(CommandLine.arguments[3]), rawPID > 0 else {
    fputs("AX target frame audit app PID must be a positive integer.\n", stderr)
    exit(2)
}
let appPID = pid_t(rawPID)
let selectedWindowTitle = CommandLine.arguments[4]
let expectedWindowFrame: CGRect?
if CommandLine.arguments.count == 9 {
    guard let x = Double(CommandLine.arguments[5]),
          let y = Double(CommandLine.arguments[6]),
          let width = Double(CommandLine.arguments[7]),
          let height = Double(CommandLine.arguments[8]),
          width > 0,
          height > 0 else {
        fputs("Captured CG window frame must contain numeric x y width height values.\n", stderr)
        exit(2)
    }
    expectedWindowFrame = CGRect(x: x, y: y, width: width, height: height)
} else {
    expectedWindowFrame = nil
}
let environment = ProcessInfo.processInfo.environment
let maxNodes = Int(environment["SUISUI_UI_EVIDENCE_AX_MAX_NODES"] ?? "6000") ?? 6000
let identityFingerprintEnabled = environment["SUISUI_UI_EVIDENCE_AX_IDENTITY_FINGERPRINT"] == "1"

guard maxNodes > 0 else {
    fputs("SUISUI_UI_EVIDENCE_AX_MAX_NODES must be a positive integer.\n", stderr)
    exit(2)
}
guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to audit Suisui UI evidence targets.\n", stderr)
    exit(2)
}
guard NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier == appPID }) else {
    fputs("\(appName) PID \(appPID) is not visible to Accessibility.\n", stderr)
    exit(2)
}

let appElement = AXUIElementCreateApplication(appPID)
AXUIElementSetMessagingTimeout(appElement, 1.0)

func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 1.0)
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute, &value) == .success ? value : nil
}

func stringValue(_ value: CFTypeRef?) -> String? {
    guard let value else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
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
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
}

func sizeValue(_ value: CFTypeRef?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let position = pointValue(copyAttribute(element, kAXPositionAttribute as CFString)),
          let size = sizeValue(copyAttribute(element, kAXSizeAttribute as CFString)),
          size.width.isFinite,
          size.height.isFinite,
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

guard let windowsValue = copyAttribute(appElement, kAXWindowsAttribute as CFString) else {
    fputs("\(appName) has no AX windows.\n", stderr)
    exit(2)
}
let ownedWindows = elements(from: windowsValue).filter(isOwnedByEvidenceApp)
guard !ownedWindows.isEmpty else {
    fputs("\(appName) has no AX windows owned by PID \(appPID).\n", stderr)
    exit(2)
}

let titleMatchedWindows: [AXUIElement]
if selectedWindowTitle.isEmpty {
    titleMatchedWindows = ownedWindows
} else {
    titleMatchedWindows = ownedWindows.filter {
        stringValue(copyAttribute($0, kAXTitleAttribute as CFString)) == selectedWindowTitle
    }
}

let selectedWindow: AXUIElement
if let expectedWindowFrame {
    // The screenshot is bound to a concrete CGWindow immediately before this
    // audit. Match that geometry instead of focus, because a SwiftUI inspector
    // sheet can legitimately own focus while the underlying board is captured.
    let frameTolerance = 1.0
    let matchingWindows = titleMatchedWindows.filter { window in
        guard let candidate = frame(of: window) else { return false }
        return abs(candidate.minX - expectedWindowFrame.minX) <= frameTolerance
            && abs(candidate.minY - expectedWindowFrame.minY) <= frameTolerance
            && abs(candidate.width - expectedWindowFrame.width) <= frameTolerance
            && abs(candidate.height - expectedWindowFrame.height) <= frameTolerance
    }
    guard matchingWindows.count == 1, let window = matchingWindows.first else {
        fputs("Expected exactly one owned AX window matching the captured CG frame; found \(matchingWindows.count).\n", stderr)
        exit(2)
    }
    selectedWindow = window
} else if !selectedWindowTitle.isEmpty {
    guard titleMatchedWindows.count == 1, let window = titleMatchedWindows.first else {
        fputs("Expected exactly one owned AX window titled \(selectedWindowTitle); found \(titleMatchedWindows.count).\n", stderr)
        exit(2)
    }
    selectedWindow = window
} else {
    guard let focusedWindow = elements(from: copyAttribute(appElement, kAXFocusedWindowAttribute as CFString)).first,
          isOwnedByEvidenceApp(focusedWindow),
          ownedWindows.contains(where: { CFEqual($0, focusedWindow) }) else {
        fputs("Could not resolve the focused owned AX window for \(appName) PID \(appPID).\n", stderr)
        exit(2)
    }
    selectedWindow = focusedWindow
}

guard let windowFrame = frame(of: selectedWindow) else {
    fputs("Selected AX window has no positive frame.\n", stderr)
    exit(2)
}

let childAttributes = [
    kAXChildrenAttribute as String,
    "AXVisibleChildren",
    "AXContents",
    "AXRows",
    "AXColumns",
    "AXDisclosedRows"
]
var queue = [selectedWindow]
var cursor = 0
var visitedCount = 0
var matches = [AXUIElement]()

while cursor < queue.count && visitedCount < maxNodes {
    let element = queue[cursor]
    cursor += 1
    visitedCount += 1

    guard isOwnedByEvidenceApp(element) else { continue }
    let identifier = stringValue(copyAttribute(element, "AXIdentifier" as CFString)) ?? ""
    if identifier == targetIdentifier,
       !matches.contains(where: { CFEqual($0, element) }) {
        matches.append(element)
    }
    for child in childAttributes.flatMap({ elements(from: copyAttribute(element, $0 as CFString)) }) {
        if isOwnedByEvidenceApp(child),
           !queue.contains(where: { CFEqual($0, child) }) {
            queue.append(child)
        }
    }
}

if visitedCount >= maxNodes {
    fputs("AX target frame audit reached SUISUI_UI_EVIDENCE_AX_MAX_NODES=\(maxNodes).\n", stderr)
}
guard !matches.isEmpty else {
    fputs("No exact AX identifier \(targetIdentifier) was found in the selected window.\n", stderr)
    exit(1)
}
struct VisibleCandidate {
    let element: AXUIElement
    let targetFrame: CGRect
    let visibleFrame: CGRect
}

// Length-prefixed UTF-8 hex keeps every identity field on one TSV line without
// collapsing tabs, newlines, carriage returns, or absent values into the same
// fingerprint. This must be injective because duplicate AX publications are
// accepted only when their complete identities are exactly equal.
func identityFingerprintField(_ value: String?) -> String {
    guard let value else { return "n" }
    let bytes = Array(value.utf8)
    let encoded = bytes.map { String(format: "%02x", $0) }.joined()
    return "s\(bytes.count):\(encoded)"
}

let identityAttributes: [CFString] = [
    kAXRoleAttribute as CFString,
    kAXSubroleAttribute as CFString,
    kAXTitleAttribute as CFString,
    kAXDescriptionAttribute as CFString,
    kAXHelpAttribute as CFString,
    kAXValueAttribute as CFString,
    "AXLabel" as CFString
]

func candidateIdentityFingerprint(_ candidate: VisibleCandidate) -> String {
    let geometryFields = String(
        format: "%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f",
        candidate.targetFrame.minX,
        candidate.targetFrame.minY,
        candidate.targetFrame.width,
        candidate.targetFrame.height,
        candidate.visibleFrame.minX,
        candidate.visibleFrame.minY,
        candidate.visibleFrame.width,
        candidate.visibleFrame.height
    )
    let identityFields = identityAttributes.map { attribute in
        identityFingerprintField(stringValue(copyAttribute(candidate.element, attribute)))
    }
    return ([geometryFields] + identityFields).joined(separator: "\t")
}

func visibleCandidate(for target: AXUIElement) -> VisibleCandidate? {
    guard let targetFrame = frame(of: target) else { return nil }

    var ancestorScrollAreaFrames = [CGRect]()
    var parentCursor = target
    var seenParents = [AXUIElement]()
    for _ in 0..<128 {
        guard let parent = elements(from: copyAttribute(parentCursor, kAXParentAttribute as CFString)).first,
              isOwnedByEvidenceApp(parent),
              !seenParents.contains(where: { CFEqual($0, parent) }) else {
            break
        }
        seenParents.append(parent)
        if stringValue(copyAttribute(parent, kAXRoleAttribute as CFString)) == (kAXScrollAreaRole as String) {
            guard let scrollAreaFrame = frame(of: parent) else { return nil }
            ancestorScrollAreaFrames.append(scrollAreaFrame)
        }
        if CFEqual(parent, selectedWindow) { break }
        parentCursor = parent
    }

    var visibleFrame = targetFrame.intersection(windowFrame)
    for scrollAreaFrame in ancestorScrollAreaFrames {
        visibleFrame = visibleFrame.intersection(scrollAreaFrame)
    }
    guard !visibleFrame.isNull,
          visibleFrame.width.isFinite,
          visibleFrame.height.isFinite,
          visibleFrame.width >= min(44, targetFrame.width),
          visibleFrame.height >= min(44, targetFrame.height) else {
        return nil
    }
    return VisibleCandidate(element: target, targetFrame: targetFrame, visibleFrame: visibleFrame)
}

let candidates = matches.compactMap(visibleCandidate)
if identityFingerprintEnabled {
    guard !candidates.isEmpty else {
        fputs("Identity fingerprint requires a visible AX target for identifier \(targetIdentifier); found none from \(matches.count) exact match(es).\n", stderr)
        exit(1)
    }
    let candidateFingerprints = Set(candidates.map(candidateIdentityFingerprint))
    // Identical visible AX duplicates are a SwiftUI publication detail, not a
    // second product target. Distinct identities remain ambiguous and fail.
    if candidateFingerprints.count != 1 {
        fputs("Identity fingerprint found \(candidateFingerprints.count) distinct visible candidate fingerprint(s) for identifier \(targetIdentifier) across \(candidates.count) visible candidate(s).\n", stderr)
        exit(1)
    }
}
guard let selectedCandidate = candidates.sorted(by: { lhs, rhs in
    let lhsVisibleArea = lhs.visibleFrame.width * lhs.visibleFrame.height
    let rhsVisibleArea = rhs.visibleFrame.width * rhs.visibleFrame.height
    if lhsVisibleArea != rhsVisibleArea { return lhsVisibleArea > rhsVisibleArea }

    let lhsFrameArea = lhs.targetFrame.width * lhs.targetFrame.height
    let rhsFrameArea = rhs.targetFrame.width * rhs.targetFrame.height
    if lhsFrameArea != rhsFrameArea { return lhsFrameArea > rhsFrameArea }
    if lhs.targetFrame.minY != rhs.targetFrame.minY { return lhs.targetFrame.minY < rhs.targetFrame.minY }
    if lhs.targetFrame.minX != rhs.targetFrame.minX { return lhs.targetFrame.minX < rhs.targetFrame.minX }
    if lhs.visibleFrame.minY != rhs.visibleFrame.minY { return lhs.visibleFrame.minY < rhs.visibleFrame.minY }
    if lhs.visibleFrame.minX != rhs.visibleFrame.minX { return lhs.visibleFrame.minX < rhs.visibleFrame.minX }
    if lhs.visibleFrame.height != rhs.visibleFrame.height { return lhs.visibleFrame.height > rhs.visibleFrame.height }
    if lhs.visibleFrame.width != rhs.visibleFrame.width { return lhs.visibleFrame.width > rhs.visibleFrame.width }
    if lhs.targetFrame.height != rhs.targetFrame.height { return lhs.targetFrame.height > rhs.targetFrame.height }
    return lhs.targetFrame.width > rhs.targetFrame.width
}).first else {
    fputs("No exact AX identifier \(targetIdentifier) has a positive, meaningfully visible frame in the selected window (\(matches.count) match(es) inspected).\n", stderr)
    exit(1)
}
let targetFrame = selectedCandidate.targetFrame
let visibleFrame = selectedCandidate.visibleFrame

// TSV keeps the shell transport deterministic while retaining sub-point AX
// geometry. The receipt writer validates these values again before signing the
// complete capture set.
let receiptFields = String(
    format: "%@\t%.3f\t%.3f\t%.3f\t%.3f",
    targetIdentifier,
    targetFrame.width,
    targetFrame.height,
    visibleFrame.width,
    visibleFrame.height
)
if !identityFingerprintEnabled {
    print(receiptFields)
    exit(0)
}
print([receiptFields, candidateIdentityFingerprint(selectedCandidate)].joined(separator: "\t"))
