import SwiftUI

struct SettingsAppearanceSection: View {
    @Binding var appearancePreference: SuisuiAppearancePreference
    @Binding var languagePreference: AppLanguagePreference

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearancePreference) {
                ForEach(SuisuiAppearancePreference.allCases) { preference in
                    Label {
                        Text(LocalizedStringKey(preference.label))
                    } icon: {
                        Image(systemName: preference.systemImage)
                    }
                    .tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            .suisuiLiquidGlassControlSurface(cornerRadius: 12, interactive: true)
            .accessibilityIdentifier("settings-theme-picker")
            .accessibilityHint("Changes the appearance for all Suisui windows.")
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
            .padding(8)
            .suisuiLiquidGlassControlSurface(cornerRadius: 12, interactive: true)
            .accessibilityIdentifier("settings-language-picker")
            .accessibilityHint("Changes the language for all Suisui windows.")
        }
    }
}
