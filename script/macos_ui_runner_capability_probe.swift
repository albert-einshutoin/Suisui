import ApplicationServices
import CoreGraphics
import Foundation

var displayCount: UInt32 = 0
let displayQuery = CGGetActiveDisplayList(0, nil, &displayCount)
let hasActiveDisplay = displayQuery == .success && displayCount > 0

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
