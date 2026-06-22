import Foundation

let environment = ProcessInfo.processInfo.environment
let bundleIdentifier = environment["SOLOPM_SETTINGS_SMOKE_BUNDLE_IDENTIFIER"] ?? "dev.solopm.app"
let timeoutSeconds = Double(environment["SOLOPM_SETTINGS_SMOKE_TIMEOUT_SECONDS"] ?? "20") ?? 20
let deadline = Date().addingTimeInterval(timeoutSeconds)

func fail(_ message: String) -> Never {
    fputs("BLOCKER: settings save smoke \(message)\n", stderr)
    exit(1)
}

func taskAutomationEnabled() -> Bool {
    guard let defaults = UserDefaults(suiteName: bundleIdentifier) else {
        return false
    }
    defaults.synchronize()
    guard let data = defaults.data(forKey: "app.settings") else {
        return false
    }
    guard
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let taskAutoExecution = root["taskAutoExecution"] as? [String: Any],
        let isEnabled = taskAutoExecution["isEnabled"] as? Bool
    else {
        return false
    }
    return isEnabled
}

while Date() < deadline {
    if taskAutomationEnabled() {
        print("OK: settings save smoke verified task automation is enabled in isolated UserDefaults")
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.5)
}

fail("did not find taskAutoExecution.isEnabled=true in isolated UserDefaults for \(bundleIdentifier)")
