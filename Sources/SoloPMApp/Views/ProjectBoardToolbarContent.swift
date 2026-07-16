import SoloPMCore
import SwiftUI

struct ProjectBoardToolbarContent: ToolbarContent {
    let context: ProjectBoardToolbarContext
    let sidebarToggleHelp: String
    let undoFeedback: String?
    let isInspectorPresented: Bool
    let canSyncGoogleCalendar: Bool
    let googleCalendarSyncHelp: String
    let onToggleSidebar: () -> Void
    let onOpenSearch: () -> Void
    let onOpenVoiceCommand: () -> Void
    let onToggleInspector: () -> Void
    let onExportTasks: () -> Void
    let onImportTasks: () -> Void
    let onRequestGoogleCalendarSync: () -> Void
    let onReviewTaskAutomation: () -> Void
    let onToggleTerminal: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onToggleSidebar) {
                Label("Sidebar", systemImage: "sidebar.left")
            }
            .help(sidebarToggleHelp)
            .accessibilityIdentifier("project-board-sidebar-toggle")
            .accessibilityLabel(sidebarToggleHelp)
        }

        if let undoFeedback {
            ToolbarItem(placement: .navigation) {
                Label {
                    Text(verbatim: undoFeedback)
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("project-board-undo-feedback")
            }
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onOpenSearch) {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search and commands")
            .accessibilityIdentifier("project-board-command-palette")

            if context.hasPrimaryVoiceAction {
                Button(action: onOpenVoiceCommand) {
                    Label("Voice Command", systemImage: "mic")
                }
                .help("Voice Command")
                .accessibilityIdentifier("project-board-voice-command")
            }
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        if context.showsInspectorToggle {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onToggleInspector) {
                    Label("Details", systemImage: "sidebar.trailing")
                }
                .help(isInspectorPresented ? "Hide Details" : "Show Details")
                .accessibilityIdentifier("project-board-inspector-toggle")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                if context.showsIntegrations {
                    Menu {
                        Button(action: onExportTasks) {
                            Label("Export Tasks", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("project-board-export-tasks")

                        Button(action: onImportTasks) {
                            Label("Import Tasks", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("project-board-import-tasks")

                        Divider()

                        Button(action: onRequestGoogleCalendarSync) {
                            Label("Google Calendar Sync", systemImage: "calendar.badge.plus")
                        }
                        .disabled(!canSyncGoogleCalendar)
                        .help(googleCalendarSyncHelp)
                        .accessibilityIdentifier("project-board-google-calendar-sync")
                    } label: {
                        Label("Integrations", systemImage: "arrow.left.arrow.right")
                    }
                }

                if context.showsAutomation {
                    Button(action: onReviewTaskAutomation) {
                        Label("Review Task Automation", systemImage: "sparkles")
                    }
                    .help("Review Task Automation: prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings")
                    .accessibilityHint("Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings.")
                    .accessibilityIdentifier("project-board-task-auto-execution-review")
                }

                if context.showsDeveloperTerminal {
                    Button(action: onToggleTerminal) {
                        Label("Terminal", systemImage: "terminal")
                    }
                    .keyboardShortcut("`", modifiers: [.control])
                    .accessibilityIdentifier("project-board-terminal-toggle")
                }

                if context.showsSettings {
                    Divider()
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open Settings")
                    .accessibilityIdentifier("project-board-settings-link")
                }
            } label: {
                Label("Utilities", systemImage: "ellipsis.circle")
            }
            .help("Integrations, automation, settings, and developer tools")
            .accessibilityIdentifier("project-board-integrations-menu")
        }
    }
}
