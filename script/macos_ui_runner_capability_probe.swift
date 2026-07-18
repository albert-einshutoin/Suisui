import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

var displayCount: UInt32 = 0
let displayQuery = CGGetActiveDisplayList(0, nil, &displayCount)
let hasActiveDisplay = displayQuery == .success && displayCount > 0

let mainDisplayID = CGMainDisplayID()
let mainScreen = NSScreen.screens.first { screen in
    guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return false
    }
    return CGDirectDisplayID(screenNumber.uint32Value) == mainDisplayID
} ?? NSScreen.main
let displayFrame = mainScreen?.frame ?? .zero
let displayVisibleFrame = mainScreen?.visibleFrame ?? .zero

func roundedInteger(_ value: CGFloat) -> Int {
    Int(value.rounded())
}

let hasAccessibilityPermission = AXIsProcessTrusted()
let hasScreenRecordingPermission: Bool
if #available(macOS 10.15, *) {
    hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
} else {
    hasScreenRecordingPermission = false
}

// Keep this probe deliberately side-effect free. CI must report missing TCC
// grants instead of opening permission prompts that cannot be answered on an
// unattended runner.
print("active_display=\(hasActiveDisplay ? 1 : 0)")
print("accessibility=\(hasAccessibilityPermission ? 1 : 0)")
print("screen_recording=\(hasScreenRecordingPermission ? 1 : 0)")
// Geometry is intentionally numeric-only so hosted diagnostics can prove
// runner capacity without exposing host, user, or display identity details.
print("display_frame_x=\(roundedInteger(displayFrame.origin.x))")
print("display_frame_y=\(roundedInteger(displayFrame.origin.y))")
print("display_frame_width=\(roundedInteger(displayFrame.width))")
print("display_frame_height=\(roundedInteger(displayFrame.height))")
print("display_visible_frame_x=\(roundedInteger(displayVisibleFrame.origin.x))")
print("display_visible_frame_y=\(roundedInteger(displayVisibleFrame.origin.y))")
print("display_visible_frame_width=\(roundedInteger(displayVisibleFrame.width))")
print("display_visible_frame_height=\(roundedInteger(displayVisibleFrame.height))")
