import SoloPMCore
import SwiftUI

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var controller: MenuBarSummaryController
    @ObservedObject var quickCaptureController: MenuBarQuickCaptureController
    @State private var quickCaptureTitle = ""

    private var viewModel: MenuBarSummaryViewModel {
        controller.viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SoloPM")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                openWindow(id: "project-board")
            } label: {
                Label("Project Board", systemImage: "rectangle.3.group")
            }

            Button {
                openWindow(id: "voice-capture")
            } label: {
                Label("Voice Command", systemImage: "mic")
            }
            .keyboardShortcut(.space, modifiers: [.option])

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings")
            .accessibilityIdentifier("menu-bar-settings-link")

            Divider()

            quickCaptureSection

            Divider()

            ForEach(viewModel.rows) { row in
                SummaryRow(row: row)
            }

            if let emptyStateLabel = controller.emptyStateLabel {
                Text(emptyStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if viewModel.hasRecentProjects {
                Divider()
                Text("Recent Projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.summary.recentProjectTitles, id: \.self) { title in
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(title)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            controller.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange)) { _ in
            controller.refresh()
        }
    }

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Add")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Quick add to Inbox", text: $quickCaptureTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addQuickCapture)
                    .accessibilityIdentifier("menu-bar-quick-capture-title")
                    .accessibilityLabel("Quick add to Inbox")
                    .accessibilityHint("Creates a local Inbox task without opening the Project Board.")

                Button(action: addQuickCapture) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Add to Inbox")
                .accessibilityIdentifier("menu-bar-quick-capture-button")
                .accessibilityHint("Adds the typed item to the local Inbox.")
            }

            if let errorMessage = quickCaptureController.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func addQuickCapture() {
        let title = quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        if quickCaptureController.createInboxTask(title: title) != nil {
            quickCaptureTitle = ""
            controller.refresh()
        }
    }
}

private struct SummaryRow: View {
    let row: MenuBarSummaryRow

    var body: some View {
        HStack {
            Label(row.title, systemImage: row.systemImage)
            Spacer()
            Text(row.value)
                .foregroundStyle(row.tone == .attention ? .orange : .secondary)
        }
    }
}
