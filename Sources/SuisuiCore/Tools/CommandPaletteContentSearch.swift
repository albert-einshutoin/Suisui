import Foundation

/// SQLite-backed implementation of the palette's injected
/// `CommandPaletteContentSearch` closure. Task hits lead because the board can
/// reveal them directly; knowledge FTS hits fill the remaining slots.
///
/// Store errors — including FTS syntax edge cases — degrade to an empty
/// section instead of failing the palette, mirroring
/// `WorkspaceQuestionRetriever`'s "never fail the question" policy.
public final class CommandPaletteContentSearchService: @unchecked Sendable {
    private let taskStore: SQLiteTaskStore
    private let knowledgeFrameStore: SQLiteKnowledgeFrameStore

    public init(taskStore: SQLiteTaskStore, knowledgeFrameStore: SQLiteKnowledgeFrameStore) {
        self.taskStore = taskStore
        self.knowledgeFrameStore = knowledgeFrameStore
    }

    public func search(
        query: String,
        limit: Int = CommandPaletteComposer.maxContentItemCount
    ) -> [CommandPaletteContentMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= CommandPaletteComposer.minimumContentSearchQueryLength, limit > 0 else {
            return []
        }

        var matches: [CommandPaletteContentMatch] = []

        // Tasks: FTS exact hits first, then bounded SQLite substring completion.
        let tasks = (try? taskStore.searchOpenTasksByContent(text: trimmed, limit: limit)) ?? []
        for task in tasks {
            // Snippet from the detail when the hit is there; a title-only hit
            // falls back to the title so the fragment always shows the match.
            let content: String
            if let detail = task.detail, detail.range(of: trimmed, options: .caseInsensitive) != nil {
                content = detail
            } else {
                content = task.title
            }
            matches.append(
                CommandPaletteContentMatch(
                    source: .task(id: task.id, projectID: task.projectID),
                    title: task.title,
                    content: content
                )
            )
        }

        // Knowledge: reuses the FTS sanitizer inside
        // `SQLiteKnowledgeFrameStore.search` (`SQL.escapeFTS` + quoted phrase),
        // so quotes and asterisks in the query cannot break the MATCH clause.
        if matches.count < limit {
            let frames = (try? knowledgeFrameStore.search(
                query: trimmed,
                limit: limit - matches.count
            )) ?? []
            for frame in frames {
                matches.append(
                    CommandPaletteContentMatch(
                        source: .knowledge(id: frame.id),
                        title: frame.name,
                        content: frame.body
                    )
                )
            }
        }

        return matches
    }
}
