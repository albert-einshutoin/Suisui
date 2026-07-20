import CoreGraphics
import Foundation

let environment = ProcessInfo.processInfo.environment
let ownerName = environment["SUISUI_WINDOW_OWNER"] ?? "Suisui"
let ownerPID = environment["SUISUI_WINDOW_OWNER_PID"].flatMap(Int.init)
let requiredWindowName = environment["SUISUI_WINDOW_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
let requireSingleWindow = environment["SUISUI_REQUIRE_SINGLE_WINDOW"] == "1"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fputs("Could not read window list.\n", stderr)
    exit(2)
}

struct Candidate {
    let id: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let area: Double
}

let candidates = windowInfo.compactMap { window -> Candidate? in
    guard window[kCGWindowOwnerName as String] as? String == ownerName else { return nil }
    if let ownerPID {
        guard window[kCGWindowOwnerPID as String] as? Int == ownerPID else { return nil }
    }
    guard (window[kCGWindowLayer as String] as? Int) == 0 else { return nil }
    guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
    let windowName = window[kCGWindowName as String] as? String ?? ""
    if let requiredWindowName, !requiredWindowName.isEmpty, windowName != requiredWindowName {
        return nil
    }
    guard let id = window[kCGWindowNumber as String] as? Int else { return nil }
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
    let width = bounds["Width"] as? Double ?? 0
    let height = bounds["Height"] as? Double ?? 0
    guard width >= 640, height >= 420 else { return nil }
    let x = bounds["X"] as? Double ?? 0
    let y = bounds["Y"] as? Double ?? 0
    return Candidate(
        id: id,
        x: Int(x.rounded(.down)),
        y: Int(y.rounded(.down)),
        width: Int(width.rounded(.down)),
        height: Int(height.rounded(.down)),
        area: width * height
    )
}.sorted { $0.area > $1.area }

if requireSingleWindow {
    guard candidates.count == 1 else {
        fputs("Expected exactly one visible PID-owned named window, found \(candidates.count).\n", stderr)
        exit(1)
    }
}

guard let candidate = candidates.first else {
    let windowDescription = requiredWindowName?.isEmpty == false ? " named \(requiredWindowName!)" : ""
    fputs("No visible \(ownerName) window\(windowDescription) was found.\n", stderr)
    exit(1)
}

print("\(candidate.id) \(candidate.x) \(candidate.y) \(candidate.width) \(candidate.height)")
