import CryptoKit
import Darwin
import Foundation

public enum DevelopmentRepositoryIndexError: Error, Equatable, Sendable {
    case invalidWorkspace
    case invalidQuery
    case invalidSelectedPath
    case tooManySelectedPaths
    case gitManifestUnavailable
    case manifestTooLarge
    case tooManyFiles
    case indexedContentTooLarge
}

public actor DevelopmentRepositoryIndex {
    public static let maximumFiles = 100_000
    public static let maximumManifestBytes = 32 * 1024 * 1024
    public static let maximumIndexedContentBytes = 512 * 1024 * 1024
    public static let maximumSelectedPaths = 64
    public static let maximumResults = 50

    private let database: SQLiteDatabaseWorker
    private let redactor: DeveloperSecretRedactor

    // Assignment-only redaction is deliberately broader for user-visible output.
    // For indexing, reject every such assignment unless its complete source line
    // is one of the narrow declarations below; unknown syntax stays fail-closed.
    private static let indexAssignments = try? NSRegularExpression(
        pattern: #"(?i)\b(?:api[_-]?key|token|password|secret)\s*[:=]"#
    )
    private static let safeSourceEqualsAssignment = try? NSRegularExpression(
        pattern: #"^\s*(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s+=\s+[A-Za-z_][A-Za-z0-9_.]*\s*$"#
    )
    private static let safeSourceTypedAssignment = try? NSRegularExpression(
        pattern: #"(?i:^(?:api[_-]?key|token|password|secret))\s*:\s*[A-Z][A-Za-z0-9_.<>?]*(?=\s*(?:[,){]|$))"#
    )

    public init(connection: SQLiteConnection, redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) {
        database = SQLiteDatabaseWorker(connection: connection)
        self.redactor = redactor
    }

    public init(path: String, redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) throws {
        database = try SQLiteDatabaseWorker(path: path)
        self.redactor = redactor
    }

    public func refresh(workspace: CodebaseMemoryWorkspace) async throws {
        let root = try Self.workspaceRoot(workspace.rootPath)
        let workspaceKey = Self.sha256(root.path)
        let records = try Self.records(root: root, redactor: redactor)

        try await database.transaction { connection in
            let generation = (try connection.queryRows(
                "SELECT COALESCE(MAX(generation), 0) + 1 AS generation FROM codebase_index_files WHERE workspace_key = ?;",
                parameters: [.text(workspaceKey)]
            ).first?.int64("generation")) ?? 1

            for record in records {
                try connection.execute(
                    """
                    INSERT INTO codebase_index_files (workspace_key, relative_path, byte_count, sha256, contents, generation)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(workspace_key, relative_path) DO UPDATE SET
                        byte_count = excluded.byte_count,
                        sha256 = excluded.sha256,
                        contents = excluded.contents,
                        generation = excluded.generation;
                    """,
                    parameters: [
                        .text(workspaceKey),
                        .text(record.relativePath),
                        .integer(Int64(record.byteCount)),
                        .text(record.sha256),
                        .text(record.contents),
                        .integer(generation),
                    ]
                )
            }
            try connection.execute(
                "DELETE FROM codebase_index_files WHERE workspace_key = ? AND generation < ?;",
                parameters: [.text(workspaceKey), .integer(generation)]
            )
        }
    }

    public func search(
        query rawQuery: String,
        workspace: CodebaseMemoryWorkspace,
        topK: Int = 10
    ) async throws -> [CodebaseMemorySnippet] {
        let root = try Self.workspaceRoot(workspace.rootPath)
        let query = try Self.validatedQuery(rawQuery)
        let terms = Self.searchTerms(query)
        guard !terms.isEmpty else {
            throw DevelopmentRepositoryIndexError.invalidQuery
        }
        let selectedPaths = try Self.validatedSelectedPaths(workspace.selectedRelativePaths, root: root)
        let limit = max(1, min(topK, Self.maximumResults))
        let workspaceKey = Self.sha256(root.path)

        return try await database.run { connection in
            let rows = try Self.ftsRows(
                connection: connection,
                terms: terms,
                joiner: " AND ",
                workspaceKey: workspaceKey,
                selectedPaths: selectedPaths,
                limit: limit
            )
            let ftsRows = rows.isEmpty
                ? try Self.ftsRows(
                    connection: connection,
                    terms: terms,
                    joiner: " OR ",
                    workspaceKey: workspaceKey,
                    selectedPaths: selectedPaths,
                    limit: limit
                )
                : rows
            let cjkTerms = terms.filter(Self.containsCJK)
            var finalRows = ftsRows
            if !cjkTerms.isEmpty, finalRows.count < limit {
                let exactFallback = try Self.fallbackRows(
                    connection: connection,
                    terms: cjkTerms,
                    joiner: " AND ",
                    workspaceKey: workspaceKey,
                    selectedPaths: selectedPaths,
                    excludedPaths: try finalRows.map { try $0.string("relative_path") },
                    limit: limit - finalRows.count
                )
                finalRows.append(contentsOf: exactFallback)
            }
            if !cjkTerms.isEmpty, finalRows.count < limit {
                let partialFallback = try Self.fallbackRows(
                    connection: connection,
                    terms: cjkTerms,
                    joiner: " OR ",
                    workspaceKey: workspaceKey,
                    selectedPaths: selectedPaths,
                    excludedPaths: try finalRows.map { try $0.string("relative_path") },
                    limit: limit - finalRows.count
                )
                finalRows.append(contentsOf: partialFallback)
            }
            return try finalRows.map { row in
                let path = try row.string("relative_path")
                let preview = try row.string("preview")
                return CodebaseMemorySnippet(
                    id: Self.sha256("\(workspaceKey):\(path)"),
                    title: path,
                    sourcePath: path,
                    bodyPreview: String(preview.prefix(400))
                )
            }
        }
    }

    private static func records(root: URL, redactor: DeveloperSecretRedactor) throws -> [IndexedFile] {
        let paths = try GitManifestReader.paths(at: root)
        var totalBytes = 0
        var records: [IndexedFile] = []
        for path in paths {
            guard let relativePath = try? DevelopmentRepositoryFilePathPolicy.validatedRelativePath(path),
                  // The policy trims user-facing paths, but git names are byte-level
                  // identities.  Never let a trimmed manifest name reopen another file.
                  relativePath == path else {
                continue
            }
            // The manifest name is untrusted filesystem input.  Descending from
            // the approved root with openat/O_NOFOLLOW rejects both an ancestor
            // swap and a final-component symlink before any bytes are indexed.
            guard let data = try? boundedFileData(root: root, relativePath: relativePath),
                  let contents = String(data: data, encoding: .utf8),
                  (try? DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)) != nil,
                  !containsIndexCredential(contents, relativePath: relativePath, redactor: redactor) else {
                continue
            }
            totalBytes += data.count
            guard totalBytes <= maximumIndexedContentBytes else {
                throw DevelopmentRepositoryIndexError.indexedContentTooLarge
            }
            records.append(IndexedFile(
                relativePath: relativePath,
                byteCount: data.count,
                sha256: sha256(data),
                contents: contents
            ))
        }
        return records
    }

    private static func workspaceRoot(_ rawPath: String) throws -> URL {
        guard rawPath.hasPrefix("/") else {
            throw DevelopmentRepositoryIndexError.invalidWorkspace
        }
        let root = URL(fileURLWithPath: rawPath).standardizedFileURL
        guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw DevelopmentRepositoryIndexError.invalidWorkspace
        }
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw DevelopmentRepositoryIndexError.invalidWorkspace
        }
        return root
    }

    private static func validatedQuery(_ rawQuery: String) throws -> String {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 512, !query.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw DevelopmentRepositoryIndexError.invalidQuery
        }
        return query
    }

    private static func validatedSelectedPaths(_ rawPaths: [String], root: URL) throws -> [RepositorySelection] {
        guard rawPaths.count <= maximumSelectedPaths else {
            throw DevelopmentRepositoryIndexError.tooManySelectedPaths
        }
        do {
            return try rawPaths.map { rawPath in
                let path = try DevelopmentRepositoryFilePathPolicy.validatedRelativeDirectoryPath(rawPath)
                guard let path else {
                    throw DevelopmentRepositoryIndexError.invalidSelectedPath
                }
                let isDirectory = (try? root.appendingPathComponent(path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return RepositorySelection(path: path, includesDescendants: isDirectory)
            }
        } catch {
            throw DevelopmentRepositoryIndexError.invalidSelectedPath
        }
    }

    private static func ftsRows(
        connection: SQLiteConnection,
        terms: [String],
        joiner: String,
        workspaceKey: String,
        selectedPaths: [RepositorySelection],
        limit: Int
    ) throws -> [SQLiteMaterializedRow] {
        let selection = selectedPaths.sqlClause(column: "i.relative_path")
        let sql = """
        SELECT i.relative_path,
               snippet(codebase_index_files_fts, 1, '', '', '…', 32) AS preview
        FROM codebase_index_files_fts
        INNER JOIN codebase_index_files i ON i.id = codebase_index_files_fts.rowid
        WHERE codebase_index_files_fts MATCH ? AND i.workspace_key = ?\(selection)
        ORDER BY bm25(codebase_index_files_fts), i.relative_path
        LIMIT ?;
        """
        return try connection.queryRows(
            sql,
            parameters: [.text(ftsMatch(terms, joiner: joiner)), .text(workspaceKey)] + selectedPaths.sqlParameters + [.integer(Int64(limit))]
        )
    }

    private static func fallbackRows(
        connection: SQLiteConnection,
        terms: [String],
        joiner: String,
        workspaceKey: String,
        selectedPaths: [RepositorySelection],
        excludedPaths: [String],
        limit: Int
    ) throws -> [SQLiteMaterializedRow] {
        let selection = selectedPaths.sqlClause(column: "relative_path")
        let predicate = terms.map { _ in "(instr(relative_path, ?) > 0 OR instr(contents, ?) > 0)" }.joined(separator: joiner)
        let exclusion = excludedPaths.isEmpty
            ? ""
            : " AND relative_path NOT IN (\(Array(repeating: "?", count: excludedPaths.count).joined(separator: ", ")))"
        return try connection.queryRows(
            "SELECT relative_path, contents FROM codebase_index_files WHERE workspace_key = ? AND (\(predicate))\(selection)\(exclusion) ORDER BY relative_path LIMIT ?;",
            parameters: [.text(workspaceKey)] + terms.flatMap { [.text($0), .text($0)] } + selectedPaths.sqlParameters + excludedPaths.map(SQLiteValue.text) + [.integer(Int64(limit))]
        )
        .map { row in
            let contents = try row.string("contents")
            return SQLiteMaterializedRow(cells: [
                "relative_path": try row.cell("relative_path"),
                "preview": .text(contextualPreview(contents: contents, terms: terms)),
            ])
        }
    }

    private static func searchTerms(_ query: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return SQLiteTaskStore.boundedSearchTokens(query.components(separatedBy: separators))
    }

    private static func ftsMatch(_ terms: [String], joiner: String) -> String {
        terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: joiner)
    }

    private static func contextualPreview(contents: String, terms: [String]) -> String {
        guard let match = terms.lazy.compactMap({
            contents.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])
        }).first else {
            return String(contents.prefix(400))
        }
        let start = contents.index(match.lowerBound, offsetBy: -160, limitedBy: contents.startIndex) ?? contents.startIndex
        let end = contents.index(match.upperBound, offsetBy: 238, limitedBy: contents.endIndex) ?? contents.endIndex
        return (start == contents.startIndex ? "" : "…") + String(contents[start..<end]) + (end == contents.endIndex ? "" : "…")
    }

    private static func containsIndexCredential(
        _ contents: String,
        relativePath: String,
        redactor: DeveloperSecretRedactor
    ) -> Bool {
        let report = redactor.redact(contents).report
        // Shared redaction intentionally treats every token assignment as risky for
        // user-visible output. Source indexing keeps that policy for specific
        // patterns, while allowing typed Swift names such as `token: Type`.
        if report.matchedPatternNames.contains(where: { $0 != "assignment" }) {
            return true
        }
        guard report.matchedPatternNames.contains("assignment") else {
            return false
        }
        // Only Swift syntax has the typed declaration forms accepted below.
        // Configuration and prose formats with the same tokens remain fail-closed.
        guard relativePath.lowercased().hasSuffix(".swift") else {
            return true
        }
        guard let assignments = indexAssignments,
              let safeEquals = safeSourceEqualsAssignment,
              let safeTyped = safeSourceTypedAssignment else {
            return true
        }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        let matches = assignments.matches(in: contents, range: range)
        guard !matches.isEmpty else {
            return true
        }
        return matches.contains { match in
            guard let swiftRange = Range(match.range, in: contents) else {
                return true
            }
            let lineRange = contents.lineRange(for: swiftRange)
            let line = String(contents[lineRange])
            let lineNSRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let assignmentSuffix = String(contents[swiftRange.lowerBound..<lineRange.upperBound])
            let suffixRange = NSRange(assignmentSuffix.startIndex..<assignmentSuffix.endIndex, in: assignmentSuffix)
            let typedMatch = safeTyped.firstMatch(in: assignmentSuffix, range: suffixRange) != nil
            let isTypedDeclaration = typedMatch && !line.contains("=") && !line.contains("\"") && !line.contains("'")
            let isEqualsDeclaration = safeEquals.firstMatch(in: line, range: lineNSRange) != nil
            return !(isTypedDeclaration || isEqualsDeclaration)
        }
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF:
                true
            default:
                false
            }
        }
    }

    private static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func boundedFileData(root: URL, relativePath: String) throws -> Data {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw DevelopmentRepositoryFileError.invalidRelativePath
        }
        var directoryDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directoryDescriptor >= 0 else {
            throw DevelopmentRepositoryFileError.symlinkNotAllowed
        }
        defer { Darwin.close(directoryDescriptor) }

        for component in components.dropLast() {
            let nextDescriptor = Darwin.openat(
                directoryDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard nextDescriptor >= 0 else {
                throw DevelopmentRepositoryFileError.symlinkNotAllowed
            }
            Darwin.close(directoryDescriptor)
            directoryDescriptor = nextDescriptor
        }

        let descriptor = Darwin.openat(
            directoryDescriptor,
            components[components.count - 1],
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw DevelopmentRepositoryFileError.symlinkNotAllowed
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var descriptorState = stat()
        guard Darwin.fstat(descriptor, &descriptorState) == 0,
              (descriptorState.st_mode & S_IFMT) == S_IFREG else {
            throw DevelopmentRepositoryFileError.targetIsDirectory
        }
        let data = try handle.read(upToCount: DevelopmentRepositoryFilePathPolicy.maximumContentBytes + 1) ?? Data()
        guard data.count <= DevelopmentRepositoryFilePathPolicy.maximumContentBytes else {
            throw DevelopmentRepositoryIndexError.indexedContentTooLarge
        }
        return data
    }
}

public struct SQLiteCodebaseMemoryConnector: CodebaseMemoryConnector {
    private let index: DevelopmentRepositoryIndex

    public init(index: DevelopmentRepositoryIndex) {
        self.index = index
    }

    public func search(_ request: CodebaseMemorySearchRequest) async throws -> [CodebaseMemorySnippet] {
        try await index.search(query: request.query, workspace: request.workspace)
    }
}

private struct IndexedFile: Sendable {
    let relativePath: String
    let byteCount: Int
    let sha256: String
    let contents: String
}

private struct RepositorySelection: Sendable {
    let path: String
    let includesDescendants: Bool
}

private extension Array where Element == RepositorySelection {
    func sqlClause(column: String) -> String {
        guard !isEmpty else {
            return ""
        }
        let clauses = map { selection in
            selection.includesDescendants
                ? "(\(column) = ? OR substr(\(column), 1, length(?)) = ?)"
                : "\(column) = ?"
        }
        return " AND (\(clauses.joined(separator: " OR ")))"
    }

    var sqlParameters: [SQLiteValue] {
        flatMap { selection in
            guard selection.includesDescendants else {
                return [SQLiteValue.text(selection.path)]
            }
            let prefix = selection.path + "/"
            return [SQLiteValue.text(selection.path), .text(prefix), .text(prefix)]
        }
    }
}

enum GitManifestReader {
    static func paths(
        at root: URL,
        timeout: TimeInterval = 15,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) throws -> [String] {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = executableURL
        // This read-only manifest must not inherit repository or user hooks.
        // In particular, core.fsmonitor can execute a repo-configured command.
        process.arguments = [
            "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=/dev/null",
            "ls-files", "--cached", "--others", "--exclude-standard", "-z",
        ]
        process.currentDirectoryURL = root
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": "/nonexistent",
            "XDG_CONFIG_HOME": "/nonexistent",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
        ]
        let result = ProcessResult()
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        // Drain before waiting: git can block forever when its manifest fills the pipe.
        group.enter()
        DispatchQueue.global().async {
            result.output = boundedManifestData(
                from: standardOutput.fileHandleForReading,
                limit: DevelopmentRepositoryIndex.maximumManifestBytes
            )
            if result.output.exceeded {
                process.terminate()
            }
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            // A stuck git process must not pin the refresh actor indefinitely.
            // Close the read side after a bounded TERM grace period so the drain
            // task also gets a deterministic upper bound before SIGKILL.
            if process.isRunning {
                process.terminate()
            }
            if group.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
            try? standardOutput.fileHandleForReading.close()
            _ = group.wait(timeout: .now() + 1)
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        guard !result.output.exceeded else {
            throw DevelopmentRepositoryIndexError.manifestTooLarge
        }
        guard process.terminationStatus == 0 else {
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        let paths = result.output.data.split(separator: 0, omittingEmptySubsequences: true).compactMap { String(data: $0, encoding: .utf8) }
        guard paths.count <= DevelopmentRepositoryIndex.maximumFiles else {
            throw DevelopmentRepositoryIndexError.tooManyFiles
        }
        return paths
    }
}

private final class ProcessResult: @unchecked Sendable {
    var output = ManifestData(data: Data(), exceeded: false)
}

private struct ManifestData: Sendable {
    let data: Data
    let exceeded: Bool
}

private func boundedManifestData(from handle: FileHandle, limit: Int) -> ManifestData {
    var data = Data()
    while data.count <= limit {
        guard let chunk = try? handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)),
              !chunk.isEmpty else {
            return ManifestData(data: data, exceeded: false)
        }
        data.append(chunk)
    }
    return ManifestData(data: data, exceeded: true)
}
