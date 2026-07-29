import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 8,
      let rawPID = Int32(CommandLine.arguments[1]),
      rawPID > 0,
      let expectedX = Double(CommandLine.arguments[2]),
      let expectedY = Double(CommandLine.arguments[3]),
      let expectedWidth = Double(CommandLine.arguments[4]),
      let expectedHeight = Double(CommandLine.arguments[5]),
      let targetWidth = Double(CommandLine.arguments[6]),
      let targetHeight = Double(CommandLine.arguments[7]),
      expectedWidth > 0,
      expectedHeight > 0,
      targetWidth > 0,
      targetHeight > 0 else {
    fputs("AX window resize requires pid expected-x expected-y expected-width expected-height target-width target-height.\n", stderr)
    exit(2)
}

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is required to resize the Project Board window.\n", stderr)
    exit(2)
}

let appPID = pid_t(rawPID)
guard let runningApp = NSRunningApplication(processIdentifier: appPID), !runningApp.isTerminated else {
    fputs("Target app pid \(appPID) is not running.\n", stderr)
    exit(2)
}

let appElement = AXUIElementCreateApplication(appPID)
AXUIElementSetMessagingTimeout(appElement, 1)

func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 1)
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute, &value) == .success ? value : nil
}

func elements(from value: CFTypeRef?) -> [AXUIElement] {
    guard let value else { return [] }
    guard let array = value as? [AnyObject] else { return [] }
    return array.compactMap { item in
        let value = item as CFTypeRef
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

func point(from value: CFTypeRef?) -> CGPoint? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point) ? point : nil
}

func size(from value: CFTypeRef?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size) ? size : nil
}

let expectedFrame = CGRect(
    x: expectedX,
    y: expectedY,
    width: expectedWidth,
    height: expectedHeight
)
let tolerance = 1.0
let candidates = elements(from: copyAttribute(appElement, kAXWindowsAttribute as CFString)).filter { window in
    guard let position = point(from: copyAttribute(window, kAXPositionAttribute as CFString)),
          let dimensions = size(from: copyAttribute(window, kAXSizeAttribute as CFString)) else {
        return false
    }
    return abs(position.x - expectedFrame.origin.x) <= tolerance
        && abs(position.y - expectedFrame.origin.y) <= tolerance
        && abs(dimensions.width - expectedFrame.width) <= tolerance
        && abs(dimensions.height - expectedFrame.height) <= tolerance
}

guard candidates.count == 1, let targetWindow = candidates.first else {
    fputs("Expected one PID-owned AX window matching the visible CoreGraphics frame, found \(candidates.count).\n", stderr)
    exit(1)
}

_ = runningApp.activate(options: [.activateAllWindows])
_ = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)

// Growing from the left edge makes the full runner width available and avoids
// mistaking desktop placement clamping for a product minimum.
var normalizedPosition = CGPoint(x: 0, y: expectedFrame.origin.y)
guard let positionValue = AXValueCreate(.cgPoint, &normalizedPosition) else {
    fputs("Could not construct the target AX window position.\n", stderr)
    exit(2)
}
let positionStatus = AXUIElementSetAttributeValue(
    targetWindow,
    kAXPositionAttribute as CFString,
    positionValue
)

var targetSize = CGSize(width: targetWidth, height: targetHeight)
guard let sizeValue = AXValueCreate(.cgSize, &targetSize) else {
    fputs("Could not construct the target AX window size.\n", stderr)
    exit(2)
}
let sizeStatus = AXUIElementSetAttributeValue(
    targetWindow,
    kAXSizeAttribute as CFString,
    sizeValue
)

guard positionStatus == .success, sizeStatus == .success else {
    fputs("AX resize failed (position=\(positionStatus.rawValue), size=\(sizeStatus.rawValue)).\n", stderr)
    exit(1)
}
