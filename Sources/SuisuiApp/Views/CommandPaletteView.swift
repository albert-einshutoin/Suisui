import SuisuiCore
import SwiftUI

/// Centered ⌘K palette overlay for the Project Board. Composition and
/// filtering live in `CommandPaletteComposer`; this view only renders items,
/// tracks keyboard selection, and forwards the chosen action to the board.
struct CommandPaletteView: View {
    let projects: [(id: Int64, title: String, isArchived: Bool)]
    var smartLists: [(id: String, name: String)] = []
    let onExecute: (CommandPaletteActionKind) -> Void
    let onDismiss: () -> Void

    @StateObject private var searchModel: CommandPaletteSearchViewModel
    @State private var capture = QuickCaptureDraft()
    @State private var selectedIndex = 0
    @State private var retryRevision = 0
    @FocusState private var isInputFocused: Bool

    init(
        projects: [(id: Int64, title: String, isArchived: Bool)],
        smartLists: [(id: String, name: String)] = [],
        contentSearch: CommandPaletteContentSearch? = nil,
        onExecute: @escaping (CommandPaletteActionKind) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.projects = projects
        self.smartLists = smartLists
        self.onExecute = onExecute
        self.onDismiss = onDismiss
        _searchModel = StateObject(wrappedValue: CommandPaletteSearchViewModel(provider: contentSearch))
    }

    private var query: String { capture.input }
    private var contentItems: [CommandPaletteItem] {
        CommandPaletteComposer.contentItems(query: query, matches: searchModel.matches)
    }

    private struct SearchRequest: Hashable {
        let query: String
        let revision: Int
    }

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
            searchModel.reset()
        }
        .task(id: SearchRequest(query: query, revision: retryRevision)) {
            await searchModel.search(query: query)
        }
        .onDisappear {
            searchModel.reset()
        }
    }

    private var palettePanel: some View {
        let primaryItems = items
        let visibleItems = CommandPaletteComposer.visibleItems(primary: primaryItems, content: contentItems)
        return VStack(spacing: 0) {
            TextField("Type a command or task…", text: $capture.input)
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
                .padding(SuisuiSpacing.lg)
                .accessibilityIdentifier("command-palette-input")

            QuickCaptureDatePreview(capture: $capture, accessibilityPrefix: "command-palette")
                .padding(.horizontal, SuisuiSpacing.lg)
            searchStatus
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, SuisuiSpacing.lg)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: SuisuiSpacing.xs) {
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
                                .padding(.horizontal, SuisuiSpacing.md)
                                .padding(.top, SuisuiSpacing.sm)
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
                    .padding(SuisuiSpacing.sm)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous)
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
            HStack(spacing: SuisuiSpacing.md) {
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
            .padding(.horizontal, SuisuiSpacing.md)
            .padding(.vertical, SuisuiSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
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
            return "Opens a read-only preview of this local knowledge."
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

    @ViewBuilder
    private var searchStatus: some View {
        switch searchModel.state {
        case .idle:
            EmptyView()
        case .loading:
            Label("Searching local content…", systemImage: "magnifyingglass")
                .accessibilityIdentifier("command-palette-search-loading")
        case .loaded(let matches):
            if matches.isEmpty {
                Text("No matching local content.")
                    .accessibilityIdentifier("command-palette-search-empty")
            }
        case .failed(let message):
            HStack {
                Text(message).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("command-palette-search-error")
                Button("Retry search") { retryRevision += 1 }
                    .accessibilityIdentifier("command-palette-search-retry")
            }
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
        if case .createInboxTask = item.kind {
            onExecute(.createInboxTask(draft: capture.draft))
        } else {
            onExecute(item.kind)
        }
        capture = QuickCaptureDraft()
        selectedIndex = 0
    }
}
