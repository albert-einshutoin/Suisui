import SoloPMCore
import SwiftUI

/// Centered ⌘K palette overlay for the Project Board. Composition and
/// filtering live in `CommandPaletteComposer`; this view only renders items,
/// tracks keyboard selection, and forwards the chosen action to the board.
struct CommandPaletteView: View {
    let projects: [(id: Int64, title: String, isArchived: Bool)]
    var smartLists: [(id: String, name: String)] = []
    let onExecute: (CommandPaletteActionKind) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isInputFocused: Bool

    private var items: [CommandPaletteItem] {
        CommandPaletteComposer.items(query: query, projects: projects, smartLists: smartLists)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
                .accessibilityHidden(true)

            palettePanel
                .padding(.top, 120)
        }
        .onAppear {
            isInputFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private var palettePanel: some View {
        let visibleItems = items
        return VStack(spacing: 0) {
            TextField("Type a command or task…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isInputFocused)
                .onSubmit {
                    executeSelection(in: visibleItems)
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1, in: visibleItems)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1, in: visibleItems)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
                .padding(SoloPMSpacing.lg)
                .accessibilityIdentifier("command-palette-input")

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: SoloPMSpacing.xs) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            paletteRow(item, isSelected: index == selectedIndex) {
                                execute(item)
                            }
                            .id(item.id)
                        }
                    }
                    .padding(SoloPMSpacing.sm)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    guard visibleItems.indices.contains(newIndex) else {
                        return
                    }
                    proxy.scrollTo(visibleItems[newIndex].id)
                }
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SoloPMRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SoloPMRadius.card, style: .continuous)
                .strokeBorder(.quaternary)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
        .accessibilityIdentifier("command-palette")
    }

    private func paletteRow(
        _ item: CommandPaletteItem,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SoloPMSpacing.md) {
                Image(systemName: item.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))

                VStack(alignment: .leading, spacing: 1) {
                    rowTitle(for: item)
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(LocalizedStringKey(subtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SoloPMSpacing.md)
            .padding(.vertical, SoloPMSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: SoloPMRadius.control, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowAccessibilityLabel(for: item))
        .accessibilityHint(rowAccessibilityHint(for: item))
        .accessibilityIdentifier("command-palette-row-\(item.id)")
    }

    /// Static command titles route through localization; the create-task row
    /// and project rows carry user-provided text and must render verbatim.
    private func rowTitle(for item: CommandPaletteItem) -> Text {
        switch item.kind {
        // Smart list names arrive pre-localized (presets) or user-provided
        // (saved lists), so they render verbatim like project titles.
        case .createInboxTask, .openProject, .openSmartList:
            Text(item.title)
        case .openDestination, .openVoiceCommandWindow, .openSettingsWindow:
            Text(LocalizedStringKey(item.title))
        }
    }

    private func rowAccessibilityLabel(for item: CommandPaletteItem) -> Text {
        if let subtitle = item.subtitle {
            return rowTitle(for: item) + Text(verbatim: ", ") + Text(LocalizedStringKey(subtitle))
        }
        return rowTitle(for: item)
    }

    private func rowAccessibilityHint(for item: CommandPaletteItem) -> LocalizedStringKey {
        if case .createInboxTask = item.kind {
            return "Creates the task in your Inbox."
        }
        return ""
    }

    private func moveSelection(by offset: Int, in visibleItems: [CommandPaletteItem]) {
        guard !visibleItems.isEmpty else {
            return
        }
        let count = visibleItems.count
        selectedIndex = ((selectedIndex + offset) % count + count) % count
    }

    private func executeSelection(in visibleItems: [CommandPaletteItem]) {
        guard visibleItems.indices.contains(selectedIndex) else {
            return
        }
        execute(visibleItems[selectedIndex])
    }

    private func execute(_ item: CommandPaletteItem) {
        onExecute(item.kind)
        query = ""
        selectedIndex = 0
    }
}
