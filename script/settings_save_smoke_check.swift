import Foundation

let environment = ProcessInfo.processInfo.environment
let bundleIdentifier = environment["SOLOPM_SETTINGS_SMOKE_BUNDLE_IDENTIFIER"] ?? "dev.solopm.app"
let timeoutSeconds = Double(environment["SOLOPM_SETTINGS_SMOKE_TIMEOUT_SECONDS"] ?? "20") ?? 20
let expectedGoogleCalendarID = environment["SOLOPM_SETTINGS_SMOKE_GOOGLE_CALENDAR_ID"]
let deadline = Date().addingTimeInterval(timeoutSeconds)

func fail(_ message: String) -> Never {
    fputs("BLOCKER: settings save smoke \(message)\n", stderr)
    exit(1)
}

func decodedSettingsRoot() -> [String: Any]? {
    guard let defaults = UserDefaults(suiteName: bundleIdentifier) else {
        return nil
    }
    defaults.synchronize()
    guard let data = defaults.data(forKey: "app.settings") else {
        return nil
    }

    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

func settingsMatchExpectedRuntimeState() -> Bool {
    guard let root = decodedSettingsRoot(),
          let taskAutoExecution = root["taskAutoExecution"] as? [String: Any],
          let isEnabled = taskAutoExecution["isEnabled"] as? Bool,
          isEnabled
    else {
        return false
    }

    guard let expectedGoogleCalendarID else {
        return true
    }
    let googleCalendarID = root["googleCalendarID"] as? String
    return googleCalendarID == expectedGoogleCalendarID
}

while Date() < deadline {
    if settingsMatchExpectedRuntimeState() {
        if expectedGoogleCalendarID != nil {
            print("OK: settings save smoke verified task automation and the expected Google Calendar ID in isolated UserDefaults")
        } else {
            print("OK: settings save smoke verified task automation is enabled in isolated UserDefaults")
        }
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.5)
}

if expectedGoogleCalendarID != nil {
    fail("did not find taskAutoExecution.isEnabled=true and the expected googleCalendarID in isolated UserDefaults for \(bundleIdentifier)")
} else {
    fail("did not find taskAutoExecution.isEnabled=true in isolated UserDefaults for \(bundleIdentifier)")
}
