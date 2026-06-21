import Foundation
import SwiftUI

func localizedDisplay(_ key: String) -> String {
    String(localized: String.LocalizationValue(key))
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
