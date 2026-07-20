import Foundation
import SuisuiCore

/// Wires the SQLite-backed palette content search into the Project Board.
/// The connection is opened lazily on the first debounced search (off the
/// main actor) so constructing the board never blocks on migrations.
enum CommandPaletteContentSearchFactory {
    static func makeIfAvailable() -> CommandPaletteContentSearch? {
        let holder = LazyCommandPaletteContentSearchHolder()
        return { query in
            holder.search(query)
        }
    }
}

private final class LazyCommandPaletteContentSearchHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var service: CommandPaletteContentSearchService?
    private var didFailToOpen = false

    func search(_ query: String) -> [CommandPaletteContentMatch] {
        lock.lock()
        if service == nil && !didFailToOpen {
            if let connection = try? AppRuntimeFactory.migratedConnection() {
                service = CommandPaletteContentSearchService(
                    taskStore: SQLiteTaskStore(connection: connection),
                    knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
                )
            } else {
                // Content matches degrade gracefully, like smart lists: the
                // fuzzy palette still works if the database cannot be opened.
                didFailToOpen = true
            }
        }
        let resolvedService = service
        lock.unlock()
        return resolvedService?.search(query: query) ?? []
    }
}
