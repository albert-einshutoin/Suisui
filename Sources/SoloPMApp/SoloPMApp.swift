import SoloPMCore
import SwiftUI

@main
struct SoloPMApplication: App {
    private let menuBarViewModel = MenuBarSummaryViewModel()
    private let settings = AppSettings.default

    var body: some Scene {
        MenuBarExtra("SoloPM", systemImage: "checklist") {
            MenuBarPanel(viewModel: menuBarViewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
    }
}

private struct MenuBarPanel: View {
    let viewModel: MenuBarSummaryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SoloPM")
                    .font(.headline)
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
            }

            Button {
            } label: {
                Label("Voice Command", systemImage: "mic")
            }
            .disabled(true)

            Divider()

            SummaryRow(title: "Today", value: viewModel.todayLabel, systemImage: "calendar")
            SummaryRow(title: "Overdue", value: viewModel.overdueLabel, systemImage: "exclamationmark.triangle")
            SummaryRow(title: "This Week", value: viewModel.thisWeekLabel, systemImage: "clock")

            if viewModel.hasRecentProjects {
                Divider()
                Text("Recent Projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.summary.recentProjectTitles, id: \.self) { title in
                    Text(title)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section("AI") {
                LabeledContent("Provider", value: settings.aiProvider.displayName)
                SecureField("API Key", text: .constant(""))
                    .disabled(true)
            }

            Section("Voice") {
                LabeledContent("Speech to Text", value: settings.sttProvider.displayName)
                LabeledContent("Shortcut", value: "Option + Space")
            }

            Section("Privacy") {
                Toggle("Notifications", isOn: .constant(settings.notificationsEnabled))
                    .disabled(true)
                LabeledContent("Workspace", value: settings.defaultWorkspacePath ?? "Not selected")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 360)
    }
}

