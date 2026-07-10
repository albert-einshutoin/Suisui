import Foundation
import SoloPMCore
import SwiftUI

/// Sidebar section listing built-in smart list presets, user-saved smart
/// lists, and the creation affordance. Selection intentionally bypasses the
/// sidebar `List(selection:)` binding: `ProjectBoardSidebarDestination` is a
/// contract-pinned enum, so smart lists overlay the detail through their own
/// `selectedSmartListID` state instead of extending the destination enum.
struct SmartListSidebarSection: View {
    let smartLists: [SmartList]
    let selectedSmartListID: String?
    let onSelect: (SmartList) -> Void
    let onCreate: () -> Void
    let onDelete: (SmartList) -> Void

    var body: some View {
        Section("Smart Lists") {
            ForEach(smartLists) { smartList in
                SmartListSidebarRow(
                    smartList: smartList,
                    isSelected: selectedSmartListID == smartList.id,
                    onSelect: { onSelect(smartList) },
                    onDelete: smartList.isPreset ? nil : { onDelete(smartList) }
                )
            }

            Button(action: onCreate) {
                Label("New Smart List…", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Create a saved smart list filter")
            .accessibilityIdentifier("project-board-smart-list-new")
            .accessibilityLabel("New Smart List")
            .accessibilityHint("Opens a sheet that saves a reusable task filter to local app storage.")
        }
    }
}

private struct SmartListSidebarRow: View {
    let smartList: SmartList
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            Label {
                Text(LocalizedStringKey(smartList.name))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        .help(LocalizedStringKey(smartList.name))
        .accessibilityIdentifier("project-board-smart-list-row-\(smartList.id)")
        .accessibilityLabel(localizedDisplay("Smart list %@", localizedDisplay(smartList.name)))
        .accessibilityHint("Shows tasks matching this saved filter in the board detail.")
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Smart List", systemImage: "trash")
                }
                .accessibilityIdentifier("project-board-smart-list-delete-\(smartList.id)")
            }
        }
    }
}

/// Flat filtered task list for the selected smart list. Reuses the same
/// `WorkflowTaskSurface` rows that the Today and Inbox flat lists render, so
/// completion toggles and selection behave identically.
struct SmartListWorkflowView: View {
    let smartList: SmartList
    @ObservedObject var viewModel: ProjectBoardViewModel
    let timeZoneIdentifier: String

    var body: some View {
        let tasks = smartList.matchingTasks(
            in: viewModel.snapshot,
            now: VisualEvidenceRuntimeContext.referenceDate(),
            timeZoneIdentifier: timeZoneIdentifier
        )
        WorkflowTaskSurface(
            title: smartList.name,
            subtitle: localizedDisplay("%d matching tasks", tasks.count),
            systemImage: "line.3.horizontal.decrease.circle",
            tasks: tasks,
            emptyTitle: "No matching tasks",
            emptyDescription: "Tasks matching this smart list appear here as projects change.",
            viewModel: viewModel,
            footer: { EmptyView() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart-list-workflow")
        .accessibilityLabel(localizedDisplay("Smart list %@", localizedDisplay(smartList.name)))
        .accessibilityHint("Lists local tasks matching the selected smart list filter.")
    }
}

/// Small creation sheet for a saved smart list. Empty status/priority
/// selections mean "no constraint" so a name plus any single criterion is
/// enough to save a useful list.
struct SmartListEditorSheet: View {
    let onSave: (SmartList) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var selectedStatuses: Set<ProjectTaskStatus> = []
    @State private var selectedPriorities: Set<ProjectTaskPriority> = []
    @State private var isDueWithinEnabled = false
    @State private var dueWithinDays = 7
    @State private var isOverdueOnly = false
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Label("New Smart List", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.headline)
                }

                Section("Smart List") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("smart-list-name")
                }

                Section("Statuses") {
                    ForEach(ProjectTaskStatus.allCases) { status in
                        Toggle(isOn: statusBinding(status)) {
                            Text(LocalizedStringKey(status.title))
                        }
                        .accessibilityIdentifier("smart-list-status-\(status.rawValue)")
                    }
                }

                Section("Priorities") {
                    ForEach(ProjectTaskPriority.allCases) { priority in
                        Toggle(isOn: priorityBinding(priority)) {
                            Text(LocalizedStringKey(priority.label))
                        }
                        .accessibilityIdentifier("smart-list-priority-\(priority.rawValue)")
                    }
                }

                Section("Due") {
                    Toggle(isOn: $isDueWithinEnabled) {
                        Text("Due within days")
                    }
                    .accessibilityIdentifier("smart-list-due-within-toggle")

                    Stepper(value: $dueWithinDays, in: 1...365) {
                        Text(localizedDisplay("Due within %d days", dueWithinDays))
                    }
                    .disabled(!isDueWithinEnabled)
                    .accessibilityIdentifier("smart-list-due-within-stepper")

                    Toggle(isOn: $isOverdueOnly) {
                        Text("Overdue only")
                    }
                    .accessibilityIdentifier("smart-list-overdue-toggle")
                }

                Section("Search") {
                    TextField("Search text", text: $searchText)
                        .accessibilityIdentifier("smart-list-search")
                }

                Section {
                    HStack(spacing: 8) {
                        Button(action: save) {
                            Label("Save Smart List", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .help("Saves this smart list to local app storage")
                        .accessibilityIdentifier("smart-list-save")
                        .accessibilityHint("Saves this smart list to local app storage.")

                        Button(action: onCancel) {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                        .accessibilityIdentifier("smart-list-cancel")
                        .accessibilityHint("Closes the sheet without saving a smart list.")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 420, minHeight: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart-list-editor")
        .accessibilityLabel("New Smart List")
    }

    private func statusBinding(_ status: ProjectTaskStatus) -> Binding<Bool> {
        Binding(
            get: { selectedStatuses.contains(status) },
            set: { isOn in
                if isOn {
                    selectedStatuses.insert(status)
                } else {
                    selectedStatuses.remove(status)
                }
            }
        )
    }

    private func priorityBinding(_ priority: ProjectTaskPriority) -> Binding<Bool> {
        Binding(
            get: { selectedPriorities.contains(priority) },
            set: { isOn in
                if isOn {
                    selectedPriorities.insert(priority)
                } else {
                    selectedPriorities.remove(priority)
                }
            }
        )
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let criteria = SmartListCriteria(
            statuses: selectedStatuses.isEmpty ? nil : selectedStatuses,
            priorities: selectedPriorities.isEmpty ? nil : selectedPriorities,
            dueWithinDays: isDueWithinEnabled ? dueWithinDays : nil,
            overdueOnly: isOverdueOnly,
            searchText: trimmedSearchText.isEmpty ? nil : trimmedSearchText
        )
        onSave(SmartList(id: UUID().uuidString, name: trimmedName, criteria: criteria))
    }
}
