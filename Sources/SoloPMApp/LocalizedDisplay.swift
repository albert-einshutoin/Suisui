import Foundation
import SwiftUI

func localizedDisplay(_ key: String) -> String {
    if let preference = AppLanguagePreference.environmentOverride
        ?? AppLanguagePreference(rawValue: UserDefaults.standard.string(forKey: AppLanguagePreference.storageKey) ?? ""),
       preference != .system,
       let localizationPath = Bundle.main.path(forResource: preference.localeIdentifier, ofType: "lproj"),
       let localizationBundle = Bundle(path: localizationPath) {
        // Dynamic status strings do not inherit SwiftUI's environment locale.
        // Resolve them from the same explicit app preference so visible text,
        // help, and accessibility values cannot drift to the system language.
        return localizationBundle.localizedString(forKey: key, value: key, table: nil)
    }
    return String(localized: String.LocalizationValue(key))
}

func localizedDisplay(_ formatKey: String, _ arguments: CVarArg...) -> String {
    String(format: localizedDisplay(formatKey), arguments: arguments)
}

func localizedTaskCount(_ count: Int) -> String {
    localizedDisplay(count == 1 ? "%d task" : "%d tasks", count)
}

func localizedSettingsDisplay(_ value: String) -> String {
    let smokePrefix = "Smoke: "
    if value.hasPrefix(smokePrefix) {
        let status = String(value.dropFirst(smokePrefix.count))
        return localizedDisplay("Smoke: %@", localizedSettingsDisplay(status))
    }
    return localizedDisplay(value)
}
