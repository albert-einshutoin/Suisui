import Foundation
import SuisuiCore

/// Wires the SQLite-backed palette content search into the Project Board.
/// The connection is opened lazily on the first debounced search (off the
/// main actor) so constructing the board never blocks on migrations.
enum CommandPaletteContentSearchFactory {
    static func make() -> CommandPaletteContentSearch {
        let holder = LazyCommandPaletteContentSearchHolder()
        return { query in
            try holder.search(query)
        }
    }
}

private final class LazyCommandPaletteContentSearchHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var service: CommandPaletteContentSearchService?
    func search(_ query: String) throws -> [CommandPaletteContentMatch] {
        lock.lock()
        defer { lock.unlock() }
        if let service { return try service.search(query: query) }
        let connection = try AppRuntimeFactory.migratedConnection()
        let searchService = CommandPaletteContentSearchService(
            taskStore: SQLiteTaskStore(connection: connection),
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
        service = searchService
        return try searchService.search(query: query)
    }
}
