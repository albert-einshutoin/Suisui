import SwiftUI

struct SettingsAppearanceSection: View {
    @Binding var appearancePreference: SoloPMAppearancePreference
    @Binding var languagePreference: AppLanguagePreference

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearancePreference) {
                ForEach(SoloPMAppearancePreference.allCases) { preference in
                    Label {
                        Text(LocalizedStringKey(preference.label))
                    } icon: {
                        Image(systemName: preference.systemImage)
                    }
                    .tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings-theme-picker")
            .accessibilityHint("Changes the appearance for all SoloPM windows.")
        }

        Section("Language") {
            Picker("Language", selection: $languagePreference) {
                ForEach(AppLanguagePreference.allCases) { preference in
                    Label {
                        Text(LocalizedStringKey(preference.label))
                    } icon: {
                        Image(systemName: preference.systemImage)
                    }
                    .tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings-language-picker")
            .accessibilityHint("Changes the language for all SoloPM windows.")
        }
    }
}
