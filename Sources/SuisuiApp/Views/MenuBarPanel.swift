import SuisuiCore
import SwiftUI

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var controller: MenuBarSummaryController
    @ObservedObject var quickCaptureController: MenuBarQuickCaptureController
    @ObservedObject var sceneCoordinator: ProjectBoardSceneCoordinator
    @State private var quickCaptureTitle = ""

    private var viewModel: MenuBarSummaryViewModel {
        controller.viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.lg) {
            headerRow

            quickCaptureSection

            summarySection

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            windowShortcutsRow

            if viewModel.hasRecentProjects {
                recentProjectsSection
            }
        }
        .padding(SuisuiSpacing.lg)
        .frame(width: 320)
        .task {
            controller.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange)) { _ in
            controller.refresh()
        }
    }

    private var headerRow: some View {
        HStack(spacing: SuisuiSpacing.sm) {
            Text("Suisui")
                .font(.headline)

            Spacer()

            Button {
                openWindow(id: "project-board")
                sceneCoordinator.requestOpen(route: .settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Open Settings")
            .accessibilityIdentifier("menu-bar-settings-link")
        }
    }

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            HStack(spacing: SuisuiSpacing.sm) {
                TextField("Quick add to Inbox", text: $quickCaptureTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addQuickCapture)
                    .accessibilityIdentifier("menu-bar-quick-capture-title")
                    .accessibilityLabel("Quick add to Inbox")
                    .accessibilityHint("Creates a local Inbox task without opening the Project Board.")

                Button(action: addQuickCapture) {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Add to Inbox")
                .accessibilityIdentifier("menu-bar-quick-capture-button")
                .accessibilityHint("Adds the typed item to the local Inbox.")
            }

            if let errorMessage = quickCaptureController.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SuisuiTone.attention.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summarySection: some View {
        // The whole summary card is one tap target: "N tasks today" and
        // "N overdue" both resolve on the board's Today view, so tapping any
        // row opens the Project Board pre-selected on Today.
        Button(action: openBoardOnToday) {
            VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
                ForEach(viewModel.rows) { row in
                    SummaryRow(row: row)
                }

                if let emptyStateLabel = controller.emptyStateLabel {
                    Text(emptyStateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Open Today", systemImage: "chevron.right.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .soloCard()
        .help("Open the Project Board on Today")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menu-bar-open-today")
        .accessibilityLabel("Open Today")
        .accessibilityHint("Opens the Project Board with the Today view selected.")
    }

    private func openBoardOnToday() {
        // A broadcast is claimed atomically by one registered board. The
        // persisted value remains only the initial route for a new window.
        _ = sceneCoordinator.requestOpen(route: .primary(.today))
        openWindow(id: "project-board")
    }

    private var windowShortcutsRow: some View {
        HStack(spacing: SuisuiSpacing.sm) {
            Button {
                openWindow(id: "project-board")
            } label: {
                Label("Project Board", systemImage: "rectangle.3.group")
                    .frame(maxWidth: .infinity)
            }

            Button {
                openWindow(id: "voice-capture")
            } label: {
                Label("Voice Command", systemImage: "mic")
                    .frame(maxWidth: .infinity)
            }
            .help("Opens Voice Command from this menu. Global Option + Space status is shown in Settings.")
        }
        .controlSize(.large)
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            Text("Recent Projects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(viewModel.summary.recentProjectTitles, id: \.self) { title in
                Label(title, systemImage: "folder")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)
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
                .font(.callout)
            Spacer()
            SuisuiStatusChip(
                text: row.value,
                tone: row.tone == .attention ? .attention : .neutral
            )
        }
    }
}
