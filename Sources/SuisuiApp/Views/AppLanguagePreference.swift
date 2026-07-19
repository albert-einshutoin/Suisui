import SwiftUI

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english
    case japanese

    static let storageKey = "suisui.languagePreference"
    static let environmentOverrideKey = "SUISUI_LANGUAGE_PREFERENCE"

    static var environmentOverride: AppLanguagePreference? {
        guard let rawValue = ProcessInfo.processInfo.environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty else {
            return nil
        }
        return AppLanguagePreference(rawValue: rawValue)
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "System"
        case .english:
            "English"
        case .japanese:
            "Japanese"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "globe"
        case .english:
            "textformat.abc"
        case .japanese:
            "character.book.closed"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            Locale.autoupdatingCurrent.identifier
        case .english:
            "en"
        case .japanese:
            "ja"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
}
