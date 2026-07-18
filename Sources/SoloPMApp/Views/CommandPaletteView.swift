import SoloPMCore
import SwiftUI

/// Centered ⌘K palette overlay for the Project Board. Composition and
/// filtering live in `CommandPaletteComposer`; this view only renders items,
/// tracks keyboard selection, and forwards the chosen action to the board.
struct CommandPaletteView: View {
    let projects: [(id: Int64, title: String, isArchived: Bool)]
    var smartLists: [(id: String, name: String)] = []
    var contentSearch: CommandPaletteContentSearch?
    let onExecute: (CommandPaletteActionKind) -> Void
    let onDismiss: () -> Void

    /// Fuzzy filtering stays instant; the SQLite-backed content search only
    /// fires this long after the last keystroke so fast typing never queries.
    private static let contentSearchDebounceNanoseconds: UInt64 = 150_000_000

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var contentItems: [CommandPaletteItem] = []
    @State private var contentSearchTask: Task<Void, Never>?
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
        .onChange(of: query) { _, newQuery in
            selectedIndex = 0
            scheduleContentSearch(for: newQuery)
        }
        .onDisappear {
            contentSearchTask?.cancel()
        }
    }

    private var palettePanel: some View {
        let primaryItems = items
        let visibleItems = CommandPaletteComposer.visibleItems(primary: primaryItems, content: contentItems)
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
                        ForEach(Array(primaryItems.enumerated()), id: \.element.id) { index, item in
                            paletteRow(item, isSelected: index == selectedIndex) {
                                execute(item)
                            }
                            .id(item.id)
                        }

                        if !contentItems.isEmpty {
                            Text("Content matches")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, SoloPMSpacing.md)
                                .padding(.top, SoloPMSpacing.sm)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("command-palette-content-section")

                            ForEach(Array(contentItems.enumerated()), id: \.element.id) { index, item in
                                paletteRow(item, isSelected: primaryItems.count + index == selectedIndex) {
                                    execute(item)
                                }
                                .id(item.id)
                            }
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
                        rowSubtitle(for: item, subtitle: subtitle)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(rowAccessibilityLabel(for: item))
        .accessibilityHint(rowAccessibilityHint(for: item))
        .accessibilityIdentifier(rowAccessibilityIdentifier(for: item))
    }

    private func rowTitle(for item: CommandPaletteItem) -> Text {
        switch item.kind {
        // Smart list names arrive pre-localized (presets) or user-provided
        // (saved lists), so they render verbatim like project titles. Content
        // hits carry user task titles and knowledge frame names.
        case .createInboxTask, .openProject, .openSmartList, .revealTask, .openKnowledgeFrame:
            Text(verbatim: item.title)
        case .openDestination, .openVoiceCommandWindow, .openSettingsWindow:
            Text(LocalizedStringKey(item.title))
        }
    }

    private func rowSubtitle(for item: CommandPaletteItem, subtitle: String) -> Text {
        switch item.kind {
        // Content-match snippets are user content and must never hit the
        // localization table.
        case .revealTask, .openKnowledgeFrame:
            Text(verbatim: subtitle)
        default:
            Text(LocalizedStringKey(subtitle))
        }
    }

    private func rowAccessibilityLabel(for item: CommandPaletteItem) -> Text {
        if let subtitle = item.subtitle {
            return rowTitle(for: item) + Text(verbatim: ", ") + rowSubtitle(for: item, subtitle: subtitle)
        }
        return rowTitle(for: item)
    }

    private func rowAccessibilityHint(for item: CommandPaletteItem) -> LocalizedStringKey {
        switch item.kind {
        case .createInboxTask:
            return "Creates the task in your Inbox."
        case .revealTask:
            return "Opens this task on the Project Board."
        case .openKnowledgeFrame:
            return "Closes the palette. Knowledge frames do not have a dedicated view yet."
        default:
            return ""
        }
    }

    /// Content-match rows use the documented `command-palette-fts-…` pattern
    /// (stable record IDs, never user text); every other row keeps the
    /// existing `command-palette-row-…` pattern.
    private func rowAccessibilityIdentifier(for item: CommandPaletteItem) -> String {
        switch item.kind {
        case .revealTask, .openKnowledgeFrame:
            return "command-palette-\(item.id)"
        default:
            return "command-palette-row-\(item.id)"
        }
    }

    /// Debounced content search: cancels the in-flight lookup on every
    /// keystroke and reruns the injected provider off the main actor once the
    /// query has been stable for 150ms. Queries under the minimum length clear
    /// the section immediately.
    private func scheduleContentSearch(for newQuery: String) {
        contentSearchTask?.cancel()
        let trimmedQuery = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Content rows belong to the previous query. Clear them before the
        // debounce so keyboard and pointer actions can never execute stale
        // results while the next SQLite lookup is pending.
        contentItems = []
        guard let contentSearch,
              trimmedQuery.count >= CommandPaletteComposer.minimumContentSearchQueryLength else {
            return
        }

        contentSearchTask = Task {
            try? await Task.sleep(nanoseconds: Self.contentSearchDebounceNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            let matches = await Task.detached {
                contentSearch(trimmedQuery)
            }.value
            guard !Task.isCancelled else {
                return
            }
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else {
                return
            }
            contentItems = CommandPaletteComposer.contentItems(query: trimmedQuery, matches: matches)
        }
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
