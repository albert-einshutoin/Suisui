import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let rawPID = Int32(CommandLine.arguments[1]), rawPID > 0,
      let keyCode = UInt16(CommandLine.arguments[2]),
      [9, 18, 19, 20, 21, 40, 43].contains(keyCode),
      ["command", "command-shift"].contains(CommandLine.arguments[3]) else {
    fputs("Keyboard shortcut requires an owned PID, supported key code, and command or command-shift.\n", stderr)
    exit(2)
}
let pid = pid_t(rawPID)
guard AXIsProcessTrusted(),
      let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
    fputs("Keyboard shortcut requires Accessibility permission and a running owned PID.\n", stderr)
    exit(2)
}

// Smoke binaries are launched directly. AX activation addresses this PID even
// when another checkout has the same LaunchServices bundle identifier.
let application = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(application, 1)
_ = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
for _ in 0..<20 {
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
    Thread.sleep(forTimeInterval: 0.05)
}
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
    fputs("Refusing shortcut because the owned PID is not frontmost.\n", stderr)
    exit(1)
}
guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
    fputs("Could not create keyboard shortcut events.\n", stderr)
    exit(1)
}
let flags: CGEventFlags = CommandLine.arguments[3] == "command-shift" ? [.maskCommand, .maskShift] : [.maskCommand]
// Use the same foreground-checked HID path as native AX text input. Posting
// directly to a process does not exercise AppKit menu key equivalents here.
for event in [down, up] {
    event.flags = flags
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        fputs("Refusing shortcut because the owned PID lost foreground focus.\n", stderr)
        exit(1)
    }
    event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
}
// Delivery alone is not proof of success; callers check the destination UI.
print("posted shortcut to owned PID \(pid)")
