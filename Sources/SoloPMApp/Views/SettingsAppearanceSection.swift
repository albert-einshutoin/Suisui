import SwiftUI

struct SettingsAppearanceSection: View {
    @Binding var appearancePreference: SoloPMAppearancePreference

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearancePreference) {
                ForEach(SoloPMAppearancePreference.allCases) { preference in
                    Label(preference.label, systemImage: preference.systemImage)
                        .tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings-theme-picker")
            .accessibilityHint("Changes the appearance for all SoloPM windows.")
        }
    }
}
