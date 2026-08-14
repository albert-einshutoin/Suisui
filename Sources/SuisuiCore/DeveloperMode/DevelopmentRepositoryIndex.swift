import CryptoKit
import Darwin
import Foundation

public enum DevelopmentRepositoryIndexError: Error, Equatable, Sendable {
    case invalidWorkspace
    case invalidQuery
    case invalidSelectedPath
    case tooManySelectedPaths
    case gitManifestUnsupported
    case gitManifestUnavailable
    case manifestTooLarge
    case tooManyFiles
    case indexedContentTooLarge
    case fileReadUnavailable
}

public actor DevelopmentRepositoryIndex {
    public static let maximumFiles = 100_000
    public static let maximumManifestBytes = 32 * 1024 * 1024
    public static let maximumIndexedContentBytes = 512 * 1024 * 1024
    public static let maximumSelectedPaths = 64
    public static let maximumResults = 50
    private static let maximumQueryUTF8Bytes = 4 * 1024

    private let database: SQLiteDatabaseWorker
    private let redactor: DeveloperSecretRedactor
    private let maximumRefreshReadBytes: Int
    private let manifestExecutableURL: URL

    // Assignment-only redaction is deliberately broader for user-visible output.
    // For indexing, reject every such assignment unless it matches one of the
    // narrow Swift grammars below; unknown syntax stays fail-closed.
    private static let credentialKeyAssignments = try? NSRegularExpression(
        pattern: #"\b(?i:(?:[A-Za-z_][A-Za-z0-9_]*)?(?:api[_-]?key|access[_-]?key|private[_-]?key|token|password|secret|credentials?)[A-Za-z0-9_]*)\b"#
    )
    private static let authorizationIdentifier = try? NSRegularExpression(
        pattern: #"\b(?i:authorization)\b"#
    )
    private static let standaloneProviderCredential = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])(?:xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{20,})(?![A-Za-z0-9_-])"#
    )
    private static let safeSwiftAssignment = try? NSRegularExpression(
        pattern: #"^\s*(?:(?:let|var)\s+)?(?:self\.)?[A-Za-z_][A-Za-z0-9_]*\s+=\s*(.+?)\s*$"#
    )
    private static let safeSwiftOptionalBinding = try? NSRegularExpression(
        pattern: #"^\s*(?:guard|if)\s+let\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_]*)\s+=\s*(.+?)(?:\s+else)?\s*\{"#
    )
    private static let safeSwiftCallLabel = try? NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*\s*:\s*(.+?)\s*,?\s*\)*\s*$"#
    )
    private static let safeSwiftExpressionAtom = try? NSRegularExpression(
        pattern: #"^(?:try\s+)?(?:nil|true|false|\.?[A-Za-z_][A-Za-z0-9_]*(?:(?:\?\.|\.)[A-Za-z_][A-Za-z0-9_]*)*(?:\(\s*(?:(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?\.?[A-Za-z_][A-Za-z0-9_]*(?:(?:\?\.|\.)[A-Za-z_][A-Za-z0-9_]*)*(?:\s*,\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?\.?[A-Za-z_][A-Za-z0-9_]*(?:(?:\?\.|\.)[A-Za-z_][A-Za-z0-9_]*)*)*)?\s*\))?)$"#
    )
    private static let safeSourceTypedDeclaration = try? NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*\s*:\s*[A-Z\[(][A-Za-z0-9_.<>\[\]():?,\s]*$"#
    )
    private static let safeSourceTypedFunctionParameter = try? NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*\s*:\s*[A-Z\[(][A-Za-z0-9_.<>\[\]():?,\s]*(?:\s*=\s*nil)?(?=\s*(?:,|\)))"#
    )
    private static let safeSwiftNominalTypeDeclaration = try? NSRegularExpression(
        pattern: #"^\s*(?:(?:private|public|internal|fileprivate|final)\s+)*(?:struct|class|enum|protocol|actor|extension)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*(?:[A-Z][A-Za-z0-9_.<>?]*|@unchecked\s+Sendable)(?:\s*,\s*(?:[A-Z][A-Za-z0-9_.<>?]*|@unchecked\s+Sendable))*\s*(?:[{][}]?)?\s*$"#
    )
    private static let safeSwiftCaseDeclaration = try? NSRegularExpression(
        pattern: #"^\s*case\s+\.[A-Za-z_][A-Za-z0-9_]*\s*:\s*$"#
    )
    private static let serializedCredential = try? NSRegularExpression(
        pattern: #"(?im)^\s*[\"']?client[-_]key[-_]data[\"']?\s*:\s*\S+|^\s*-----BEGIN (?:[A-Z0-9 ]*PRIVATE KEY)-----"#
    )
    private static let yamlClientKeyData = try? NSRegularExpression(
        pattern: #"(?i)client[-_]key[-_]data"#
    )
    private static let swiftTypedDeclarationPrefix = try? NSRegularExpression(
        pattern: #"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*\s+)*(?:(?:(?:private|public|internal|fileprivate)(?:\(set\))?|static|final|lazy)\s+)*(?:let|var)\s+$"#
    )
    private static let swiftFunctionParameterPrefix = try? NSRegularExpression(
        pattern: #"\b(?:func\s+[A-Za-z_][A-Za-z0-9_]*\s*|init\s*)$"#
    )
    private static let swiftCallOpener = try? NSRegularExpression(
        pattern: #"^\s*(?:try\s+)?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\s*$"#
    )

    private struct SwiftLexicalPosition {
        var isInNormalCode: Bool
        var openParenthesis: String.Index?
    }

    private enum SwiftLiteralKind: Equatable {
        case string
        case regex
    }

    private struct SwiftLiteralDelimiter {
        var kind: SwiftLiteralKind
        var hashCount: Int
        var isMultiline: Bool
    }

    private struct WorkspaceRootDescriptor {
        let descriptor: Int32
        let device: dev_t
        let inode: ino_t
    }

    public init(connection: SQLiteConnection, redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) {
        self.init(
            connection: connection,
            redactor: redactor,
            maximumRefreshReadBytes: DevelopmentRepositoryIndex.maximumIndexedContentBytes,
            manifestExecutableURL: GitManifestReader.defaultExecutableURL
        )
    }

    init(
        connection: SQLiteConnection,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        maximumRefreshReadBytes: Int = DevelopmentRepositoryIndex.maximumIndexedContentBytes,
        manifestExecutableURL: URL = GitManifestReader.defaultExecutableURL
    ) {
        database = SQLiteDatabaseWorker(connection: connection)
        self.redactor = redactor
        self.maximumRefreshReadBytes = maximumRefreshReadBytes
        self.manifestExecutableURL = manifestExecutableURL
    }

    public init(path: String, redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) throws {
        database = try SQLiteDatabaseWorker(path: path)
        self.redactor = redactor
        maximumRefreshReadBytes = DevelopmentRepositoryIndex.maximumIndexedContentBytes
        manifestExecutableURL = GitManifestReader.defaultExecutableURL
    }

    public func refresh(workspace: CodebaseMemoryWorkspace) async throws {
        let root = try Self.workspaceRoot(workspace.rootPath)
        let rootDescriptor = try Self.openWorkspaceRoot(root)
        defer { Darwin.close(rootDescriptor.descriptor) }
        let workspaceKey = Self.workspaceKey(root: root, descriptor: rootDescriptor)
        let records = try Self.records(
            root: root,
            rootDescriptor: rootDescriptor,
            redactor: redactor,
            maximumRefreshReadBytes: maximumRefreshReadBytes,
            manifestExecutableURL: manifestExecutableURL
        )

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
            // A successful refresh is the only point at which a same-path
            // replacement may retire its former inode's snapshot. Keeping this
            // inside the transaction preserves it if the new snapshot fails.
            try connection.execute(
                "DELETE FROM codebase_index_files WHERE workspace_key = ? OR (workspace_key LIKE ? AND workspace_key <> ?);",
                parameters: [
                    .text(Self.legacyWorkspaceKey(root: root)),
                    .text("\(Self.workspaceKeyPrefix(root: root))%"),
                    .text(workspaceKey),
                ]
            )
        }
    }

    public func search(
        query rawQuery: String,
        workspace: CodebaseMemoryWorkspace,
        topK: Int = 10
    ) async throws -> [CodebaseMemorySnippet] {
        let root = try Self.workspaceRoot(workspace.rootPath)
        let rootDescriptor = try Self.openWorkspaceRoot(root)
        defer { Darwin.close(rootDescriptor.descriptor) }
        let query = try Self.validatedQuery(rawQuery)
        let terms = Self.searchTerms(query)
        guard !terms.isEmpty else {
            throw DevelopmentRepositoryIndexError.invalidQuery
        }
        let selectedPaths = try Self.validatedSelectedPaths(workspace.selectedRelativePaths, root: root)
        let limit = max(1, min(topK, Self.maximumResults))
        try Self.verifyWorkspaceRoot(root, matches: rootDescriptor)
        let workspaceKey = Self.workspaceKey(root: root, descriptor: rootDescriptor)

        let snippets = try await database.run { connection in
            let rows = try Self.ftsRows(
                connection: connection,
                terms: terms,
                joiner: " AND ",
                workspaceKey: workspaceKey,
                selectedPaths: selectedPaths,
                limit: limit
            )
            let cjkTerms = terms.filter(Self.containsCJK)
            var finalRows = rows
            if !cjkTerms.isEmpty, finalRows.count < limit {
                let exactFallback = try Self.fallbackRows(
                    connection: connection,
                    terms: terms,
                    joiner: " AND ",
                    workspaceKey: workspaceKey,
                    selectedPaths: selectedPaths,
                    excludedPaths: try finalRows.map { try $0.string("relative_path") },
                    limit: limit - finalRows.count
                )
                finalRows.append(contentsOf: exactFallback)
            }
            if finalRows.count < limit {
                // Prefer full-term FTS and CJK substring matches before partial
                // matches, then fill only the remaining slots without duplicates.
                let partialRows = try Self.ftsRows(
                    connection: connection,
                    terms: terms,
                    joiner: " OR ",
                    workspaceKey: workspaceKey,
                    selectedPaths: selectedPaths,
                    excludedPaths: try finalRows.map { try $0.string("relative_path") },
                    limit: limit - finalRows.count
                )
                finalRows.append(contentsOf: partialRows)
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
        try Self.verifyWorkspaceRoot(root, matches: rootDescriptor)
        return snippets
    }

    private static func records(
        root: URL,
        rootDescriptor: WorkspaceRootDescriptor,
        redactor: DeveloperSecretRedactor,
        maximumRefreshReadBytes: Int,
        manifestExecutableURL: URL
    ) throws -> [IndexedFile] {
        try verifyWorkspaceRoot(root, matches: rootDescriptor)
        let entries = try GitManifestReader.entries(
            at: root,
            executableURL: manifestExecutableURL,
            expectedRootIdentity: .init(device: rootDescriptor.device, inode: rootDescriptor.inode)
        )
        try verifyWorkspaceRoot(root, matches: rootDescriptor)
        var totalBytes = 0
        var records: [IndexedFile] = []
        for entry in entries {
            // Git itself marks these entries as absent from this checkout. They
            // are intentional manifest exclusions, unlike a post-manifest
            // file-to-directory replacement which must abort the refresh.
            guard !entry.isUnavailable else {
                continue
            }
            let path = entry.path
            try verifyWorkspaceRoot(root, matches: rootDescriptor)
            guard let relativePath = try? DevelopmentRepositoryFilePathPolicy.validatedRelativePath(path),
                  // The policy trims user-facing paths, but git names are byte-level
                  // identities.  Never let a trimmed manifest name reopen another file.
                  relativePath == path else {
                continue
            }
            // The manifest name is untrusted filesystem input.  Descending from
            // the approved root with openat/O_NOFOLLOW rejects both an ancestor
            // swap and a final-component symlink before any bytes are indexed.
            let read: BoundedFileRead
            do {
                read = try boundedFileRead(rootDescriptor: rootDescriptor.descriptor, relativePath: relativePath)
            } catch DevelopmentRepositoryFileError.symlinkNotAllowed {
                continue
            } catch {
                // A partial snapshot is worse than a failed refresh: preserve the
                // prior generation until all manifest files can be read again.
                throw DevelopmentRepositoryIndexError.fileReadUnavailable
            }
            // Every opened byte consumes the refresh budget, even when later
            // rejected as binary or secret. Otherwise a manifest full of
            // excluded files could bypass the aggregate work limit.
            totalBytes += read.data.count
            guard totalBytes <= maximumRefreshReadBytes else {
                throw DevelopmentRepositoryIndexError.indexedContentTooLarge
            }
            guard !read.isOversized else {
                continue
            }
            let data = read.data
            guard let contents = String(data: data, encoding: .utf8),
                  (try? DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)) != nil,
                  !containsIndexCredential(contents, relativePath: relativePath, redactor: redactor) else {
                continue
            }
            records.append(IndexedFile(
                relativePath: relativePath,
                byteCount: data.count,
                sha256: sha256(data),
                contents: contents
            ))
        }
        try verifyWorkspaceRoot(root, matches: rootDescriptor)
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

    private static func openWorkspaceRoot(_ root: URL) throws -> WorkspaceRootDescriptor {
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw DevelopmentRepositoryIndexError.invalidWorkspace
        }
        var state = stat()
        guard Darwin.fstat(descriptor, &state) == 0, (state.st_mode & S_IFMT) == S_IFDIR else {
            Darwin.close(descriptor)
            throw DevelopmentRepositoryIndexError.invalidWorkspace
        }
        return WorkspaceRootDescriptor(descriptor: descriptor, device: state.st_dev, inode: state.st_ino)
    }

    private static func verifyWorkspaceRoot(_ root: URL, matches descriptor: WorkspaceRootDescriptor) throws {
        try verifyWorkspaceRootIdentity(root, device: descriptor.device, inode: descriptor.inode)
    }

    private static func workspaceKey(root: URL, descriptor: WorkspaceRootDescriptor) -> String {
        "\(workspaceKeyPrefix(root: root))\(descriptor.device):\(descriptor.inode)"
    }

    private static func workspaceKeyPrefix(root: URL) -> String {
        "repository-index:\(sha256(root.path)):"
    }

    private static func legacyWorkspaceKey(root: URL) -> String {
        sha256(root.path)
    }

    static func verifyWorkspaceRootIdentity(_ root: URL, device: dev_t, inode: ino_t) throws {
        var state = stat()
        guard Darwin.lstat(root.path, &state) == 0,
              (state.st_mode & S_IFMT) == S_IFDIR,
              state.st_dev == device,
              state.st_ino == inode else {
            throw DevelopmentRepositoryIndexError.fileReadUnavailable
        }
    }

    private static func validatedQuery(_ rawQuery: String) throws -> String {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // One Character may contain unbounded combining scalars.  Bound UTF-8
        // first so tokenization cannot retain a multi-megabyte grapheme.
        guard !query.isEmpty,
              query.utf8.count <= maximumQueryUTF8Bytes,
              query.count <= 512,
              !query.unicodeScalars.contains(where: { $0.value == 0 }) else {
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
        excludedPaths: [String] = [],
        limit: Int
    ) throws -> [SQLiteMaterializedRow] {
        let selection = selectedPaths.sqlClause(column: "i.relative_path")
        let exclusion = excludedPaths.isEmpty
            ? ""
            : " AND i.relative_path NOT IN (\(Array(repeating: "?", count: excludedPaths.count).joined(separator: ", ")))"
        let sql = """
        SELECT i.relative_path,
               snippet(codebase_index_files_fts, 1, '', '', '…', 32) AS preview
        FROM codebase_index_files_fts
        INNER JOIN codebase_index_files i ON i.id = codebase_index_files_fts.rowid
        WHERE codebase_index_files_fts MATCH ? AND i.workspace_key = ?\(selection)\(exclusion)
        ORDER BY bm25(codebase_index_files_fts), i.relative_path
        LIMIT ?;
        """
        return try connection.queryRows(
            sql,
            parameters: [.text(ftsMatch(terms, joiner: joiner)), .text(workspaceKey)] + selectedPaths.sqlParameters + excludedPaths.map(SQLiteValue.text) + [.integer(Int64(limit))]
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
        // SQLite lower() gives the fallback its intended ASCII-insensitive
        // behavior while preserving bound terms and CJK substring matching.
        let predicate = terms.map { _ in "(instr(lower(relative_path), lower(?)) > 0 OR instr(lower(contents), lower(?)) > 0)" }.joined(separator: joiner)
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
        let words = query.components(separatedBy: separators)
        let terms = words.flatMap(cjkBigramsOrWord)
        return SQLiteTaskStore.boundedSearchTokens(terms)
    }

    private static func cjkBigramsOrWord(_ word: String) -> [String] {
        let characters = Array(word)
        guard characters.count > 1,
              characters.allSatisfy(isCJKCharacter) else {
            return [word]
        }
        // CJK natural-language queries have no word boundaries.  Use bounded
        // 2-grams so the existing AND-first, OR-completion search can retrieve
        // relevant fragments without requiring the whole sentence in one file.
        return (0..<(characters.count - 1)).map { index in
            String(characters[index...(index + 1)])
        }
    }

    private static func isCJKCharacter(_ character: Character) -> Bool {
        !character.unicodeScalars.isEmpty && character.unicodeScalars.allSatisfy(isCJK)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF, 0xFF66...0xFF9F:
            true
        default:
            false
        }
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
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        // JSON object keys may spell credential names with Unicode escapes.  The
        // parser decodes those escapes before this boundary decides persistence.
        if relativePath.lowercased().hasSuffix(".json"), containsJSONCredentialKey(contents) {
            return true
        }
        if containsAmbiguousNonSwiftEscape(contents, relativePath: relativePath) {
            return true
        }
        guard let standaloneProviderCredential,
              let serializedCredential,
              let yamlClientKeyData else {
            return true
        }
        // These opaque provider prefixes are secrets even in prose, without an
        // assignment key; reject them before any repository text is persisted.
        if standaloneProviderCredential.firstMatch(in: contents, range: range) != nil {
            return true
        }
        // A client-key-data token is secret material regardless of delimiter or
        // format; YAML anchors can separate its key from the eventual mapping.
        if yamlClientKeyData.firstMatch(in: contents, range: range) != nil {
            return true
        }
        if serializedCredential.firstMatch(in: contents, range: range) != nil {
            return true
        }
        let report = redactor.redact(contents).report
        // Shared redaction intentionally treats every token assignment as risky for
        // user-visible output. Source indexing keeps that policy for specific
        // patterns, while allowing typed Swift names such as `token: Type`.
        // Drafts redact every Authorization value. Indexing can reopen only its
        // typed Swift forms below, after correlating the actual identifier range.
        if report.matchedPatternNames.contains(where: { $0 != "assignment" && $0 != "authorization_header" }) {
            return true
        }
        guard let assignments = credentialKeyAssignments,
              let authorizationIdentifiers = authorizationIdentifier,
              let safeAssignment = safeSwiftAssignment,
              let safeOptionalBinding = safeSwiftOptionalBinding,
              let safeCallLabel = safeSwiftCallLabel,
              let safeExpressionAtom = safeSwiftExpressionAtom,
              let safeTypedDeclaration = safeSourceTypedDeclaration,
              let safeTypedFunctionParameter = safeSourceTypedFunctionParameter,
              let safeNominalTypeDeclaration = safeSwiftNominalTypeDeclaration,
              let safeCaseDeclaration = safeSwiftCaseDeclaration,
              let typedDeclarationPrefix = swiftTypedDeclarationPrefix,
              let functionParameterPrefix = swiftFunctionParameterPrefix,
              let callOpener = swiftCallOpener else {
            return true
        }
        let candidateMatches = assignments.matches(in: contents, range: range) +
            authorizationIdentifiers.matches(in: contents, range: range)
        // Only Swift has a narrow safe grammar. Non-prose formats are
        // fail-closed on credential-shaped identifiers; prose keeps the
        // delimiter check so ordinary documentation remains searchable.
        if isNonSwiftNonProseFile(relativePath), !candidateMatches.isEmpty {
            return true
        }
        let candidateEnds = Set(candidateMatches.compactMap { Range($0.range, in: contents)?.upperBound })
        let assignmentEnds = credentialAssignmentDelimiterEnds(in: contents, candidateEnds: candidateEnds)
        let matches = candidateMatches.filter {
            Range($0.range, in: contents).map { assignmentEnds.contains($0.upperBound) } == true
        }
        guard !matches.isEmpty else {
            return report.matchedPatternNames.contains("assignment") ||
                report.matchedPatternNames.contains("authorization_header")
        }
        // The source-shape exceptions below are meaningful only for Swift files.
        // A config or prose file using the same text remains fail-closed.
        guard relativePath.lowercased().hasSuffix(".swift") else {
            return true
        }
        let matchPositions = Set(matches.compactMap { Range($0.range, in: contents)?.lowerBound })
        let lexicalPositions = swiftLexicalPositions(in: contents, at: matchPositions)
        return matches.contains { match in
            guard let swiftRange = Range(match.range, in: contents) else {
                return true
            }
            let lineRange = contents.lineRange(for: swiftRange)
            let line = String(contents[lineRange])
            // A source-shaped exception must end on this line.  Swift permits
            // operators and assignments to continue onto the next one, where a
            // literal credential could otherwise be appended after a safe name.
            let continuesOnNextLine = hasSwiftContinuation(after: lineRange.upperBound, in: contents)
            guard let lexicalPosition = lexicalPositions[swiftRange.lowerBound], lexicalPosition.isInNormalCode else {
                return true
            }
            let assignmentPrefix = String(contents[lineRange.lowerBound..<swiftRange.lowerBound])
            let prefixRange = NSRange(assignmentPrefix.startIndex..<assignmentPrefix.endIndex, in: assignmentPrefix)
            let assignmentSuffix = String(contents[swiftRange.lowerBound..<lineRange.upperBound])
            let suffixRange = NSRange(assignmentSuffix.startIndex..<assignmentSuffix.endIndex, in: assignmentSuffix)
            let openerPrefix = lexicalPosition.openParenthesis.map { openParenthesis in
                let openerLineRange = contents.lineRange(for: openParenthesis..<contents.index(after: openParenthesis))
                return String(contents[openerLineRange.lowerBound..<openParenthesis])
            }
            let hasSafeTypedDeclaration = typedDeclarationPrefix.firstMatch(in: assignmentPrefix, range: prefixRange) != nil &&
                safeTypedDeclaration.firstMatch(in: assignmentSuffix, range: suffixRange) != nil
            let isTypedFunctionParameter = openerPrefix.map { prefix in
                let range = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
                return functionParameterPrefix.firstMatch(in: prefix, range: range) != nil
            } == true &&
                safeTypedFunctionParameter.firstMatch(in: assignmentSuffix, range: suffixRange) != nil
            let isTypedDeclaration = (hasSafeTypedDeclaration &&
                !line.contains("=") && !line.contains("\"") && !line.contains("'")) ||
                (isTypedFunctionParameter && !line.contains("\"") && !line.contains("'"))
            let fullLineRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let isNominalType = safeNominalTypeDeclaration.firstMatch(in: line, range: fullLineRange) != nil
            let isCaseDeclaration = safeCaseDeclaration.firstMatch(in: line, range: fullLineRange) != nil
            let isSafeAssignment = containsSafeSwiftExpression(in: line, grammar: safeAssignment, atom: safeExpressionAtom) ||
                // The binding's name must be this candidate. Otherwise a later
                // assignment in the same body could inherit the binding's safety.
                containsSafeSwiftOptionalBinding(
                    in: line,
                    source: contents,
                    lineStart: lineRange.lowerBound,
                    candidateRange: swiftRange,
                    grammar: safeOptionalBinding,
                    atom: safeExpressionAtom
                )
            // These forms contain only source identifiers/member references, never
            // a literal credential. The surrounding argument list prevents config
            // syntax from becoming an indexing exception.
            let hasCurrentLineCommentOrQuote = assignmentPrefix.contains("//") ||
                assignmentPrefix.contains("/*") ||
                assignmentPrefix.contains("\"") ||
                assignmentPrefix.contains("'")
            let isAuthorization = String(contents[swiftRange]).caseInsensitiveCompare("authorization") == .orderedSame
            let isCallLabel = !hasCurrentLineCommentOrQuote &&
                hasOpenSwiftArgumentList(in: contents, openParenthesis: lexicalPosition.openParenthesis, callOpener: callOpener) &&
                (containsSafeSwiftExpression(in: assignmentSuffix, grammar: safeCallLabel, atom: safeExpressionAtom) ||
                    (isAuthorization && containsSafeSwiftAuthorizationCallLabel(in: assignmentSuffix, grammar: safeCallLabel, atom: safeExpressionAtom)))
            let isSafeSourceShape = isNominalType || isCaseDeclaration ||
                (!continuesOnNextLine && (isTypedDeclaration || isSafeAssignment || isCallLabel))
            return !isSafeSourceShape
        }
    }

    private static func hasSwiftContinuation(after lineEnd: String.Index, in source: String) -> Bool {
        var index = lineEnd
        while true {
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            guard index < source.endIndex else {
                return false
            }
            let nextIndex = source.index(after: index)
            let nextCharacter = nextIndex < source.endIndex ? source[nextIndex] : nil
            if source[index] == "/", nextCharacter == "/" {
                while index < source.endIndex, source[index] != "\n", source[index] != "\r" {
                    index = source.index(after: index)
                }
                continue
            }
            if source[index] == "@" {
                // Attributes begin a new declaration context; they cannot
                // continue an expression.
                return false
            }
            if source[index] == "#" {
                // A conditional-compilation line may surround a postfix chain.
                // Skip the directive and classify the next normal code token.
                while index < source.endIndex, source[index] != "\n", source[index] != "\r" {
                    index = source.index(after: index)
                }
                continue
            }
            break
        }
        guard index < source.endIndex else {
            return false
        }
        let character = source[index]
        if !character.isLetter && !character.isNumber && character != "_" &&
            !["}", ")", "]"].contains(character) {
            // Operators include user-defined Unicode forms, so a fixed operator
            // list would reopen the multiline literal bypass.
            return true
        }
        var tokenEnd = index
        while tokenEnd < source.endIndex,
              (source[tokenEnd].isLetter || source[tokenEnd].isNumber || source[tokenEnd] == "_") {
            tokenEnd = source.index(after: tokenEnd)
        }
        // `as` and `is` may place their type on a following line or after a
        // tab. Treat the complete identifier token as a continuation keyword.
        let token = String(source[index..<tokenEnd])
        return token == "as" || token == "is"
    }

    private static func isNonSwiftNonProseFile(_ relativePath: String) -> Bool {
        let filename = URL(fileURLWithPath: relativePath).lastPathComponent.lowercased()
        if ["readme", "license"].contains(filename) {
            return false
        }
        let extensionName = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        return extensionName != "swift" && extensionName != "json" &&
            !["md", "markdown", "txt", "rst", "adoc"].contains(extensionName)
    }

    private static func containsJSONCredentialKey(_ contents: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(contents.utf8), options: [.fragmentsAllowed]) else {
            // Escaped keys are undecidable without a valid parse. A malformed
            // JSON config therefore cannot receive the raw-regex fallback.
            return true
        }
        return containsJSONCredentialKey(in: object)
    }

    private static func containsAmbiguousNonSwiftEscape(
        _ contents: String,
        relativePath: String
    ) -> Bool {
        let extensionName = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        guard extensionName != "json", extensionName != "swift" else {
            return false
        }
        // Escape expansion differs across non-Swift languages and can turn a
        // harmless raw token into a credential key. Reject it at this boundary
        // rather than attempting to maintain parsers for every indexed format.
        return contents.contains("\\u") || contents.contains("\\U") || contents.contains("\\x")
    }

    private static func containsJSONCredentialKey(in object: Any) -> Bool {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if isJSONCredentialKey(key) || containsJSONCredentialKey(in: value) {
                    return true
                }
            }
            return false
        }
        if let array = object as? [Any] {
            return array.contains { containsJSONCredentialKey(in: $0) }
        }
        return false
    }

    private static func isJSONCredentialKey(_ key: String) -> Bool {
        let normalized = String(key.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }).lowercased()
        if ["auth", "auths", "authorization", "identitytoken"].contains(normalized) {
            return true
        }
        return ["apikey", "accesskey", "privatekey", "clientkeydata", "token", "password", "secret", "credential", "credentials"].contains {
            normalized.hasSuffix($0)
        }
    }

    private static func containsSafeSwiftExpression(
        in value: String,
        grammar: NSRegularExpression,
        atom: NSRegularExpression
    ) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = grammar.firstMatch(in: value, range: range),
              let expressionRange = Range(match.range(at: 1), in: value) else {
            return false
        }
        return isSafeSwiftExpression(String(value[expressionRange]), atom: atom)
    }

    private static func containsSafeSwiftOptionalBinding(
        in value: String,
        source: String,
        lineStart: String.Index,
        candidateRange: Range<String.Index>,
        grammar: NSRegularExpression,
        atom: NSRegularExpression
    ) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = grammar.firstMatch(in: value, range: range),
              let nameRange = Range(match.range(at: 1), in: value),
              let expressionRange = Range(match.range(at: 2), in: value) else {
            return false
        }
        let nameStart = source.index(lineStart, offsetBy: value.distance(from: value.startIndex, to: nameRange.lowerBound))
        let nameEnd = source.index(lineStart, offsetBy: value.distance(from: value.startIndex, to: nameRange.upperBound))
        guard (nameStart..<nameEnd) == candidateRange else {
            return false
        }
        return isSafeSwiftExpression(String(value[expressionRange]), atom: atom)
    }

    private static func containsSafeSwiftAuthorizationCallLabel(
        in value: String,
        grammar: NSRegularExpression,
        atom: NSRegularExpression
    ) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = grammar.firstMatch(in: value, range: range),
              let expressionRange = Range(match.range(at: 1), in: value),
              value.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("))") else {
            return false
        }
        // The legacy label grammar consumes every trailing `)`. Restore one only
        // for Authorization's nested source call; an unterminated call stays closed.
        return isSafeSwiftExpression(String(value[expressionRange]) + ")", atom: atom)
    }

    // Resolve every candidate's next meaningful token during one walk. A
    // per-candidate lookahead turns a long comment packed with token-like text
    // into quadratic work, so pending candidates share the same delimiter.
    private static func credentialAssignmentDelimiterEnds(
        in source: String,
        candidateEnds: Set<String.Index>
    ) -> Set<String.Index> {
        var lineComment = false
        var blockCommentDepth = 0
        var pendingEnds: [String.Index] = []
        var quoteCanClose = true
        var assignmentEnds: Set<String.Index> = []
        var index = source.startIndex

        func resolvePending(with character: Character) {
            if character == ":" || character == "=" {
                assignmentEnds.formUnion(pendingEnds)
            }
            pendingEnds.removeAll(keepingCapacity: true)
            quoteCanClose = true
        }

        while index < source.endIndex {
            if candidateEnds.contains(index) {
                pendingEnds.append(index)
            }
            let character = source[index]
            let nextIndex = source.index(after: index)
            let nextCharacter = nextIndex < source.endIndex ? source[nextIndex] : nil

            if lineComment {
                if character == "\n" || character == "\r" {
                    lineComment = false
                }
            } else if blockCommentDepth > 0 {
                if character == "/", nextCharacter == "*" {
                    blockCommentDepth += 1
                    index = source.index(after: nextIndex)
                    continue
                }
                if character == "*", nextCharacter == "/" {
                    blockCommentDepth -= 1
                    index = source.index(after: nextIndex)
                    continue
                }
            } else if !pendingEnds.isEmpty {
                let beginsLineComment =
                    (character == "/" && nextCharacter == "/") ||
                    (character == "-" && nextCharacter == "-") ||
                    character == "#"
                let isExplicitLineContinuation = character == "\\" &&
                    (nextCharacter == "\n" || nextCharacter == "\r")
                if character.isWhitespace {
                    // Keep looking.
                } else if quoteCanClose, character == "\"" || character == "'" || character == "`" {
                    quoteCanClose = false
                } else if isExplicitLineContinuation {
                    // Python-style explicit continuations make the following
                    // line part of this assignment expression.
                    index = source.index(after: nextIndex)
                    continue
                } else if beginsLineComment {
                    // C-family, SQL, and Python line comments are all legal in
                    // supported source types, so wait for the next line token.
                    lineComment = true
                    index = character == "#" ? nextIndex : source.index(after: nextIndex)
                    continue
                } else if character == "/", nextCharacter == "*" {
                    blockCommentDepth = 1
                    index = source.index(after: nextIndex)
                    continue
                } else {
                    resolvePending(with: character)
                }
            }
            index = nextIndex
        }
        return assignmentEnds
    }

    // Scan once and snapshot only credential-like positions: rescanning each
    // prefix would make a dense, 256 KiB source file quadratic.
    // The snapshots also keep comment/string text from creating a safe exception
    // or contributing a misleading unmatched parenthesis.
    // ponytail: this intentionally recognizes only the lexical states needed by
    // the credential exceptions; use SwiftSyntax if those exceptions grow.
    private static func swiftLexicalPositions(
        in source: String,
        at positions: Set<String.Index>
    ) -> [String.Index: SwiftLexicalPosition] {
        var lineComment = false
        var blockCommentDepth = 0
        var literalDelimiter: SwiftLiteralDelimiter?
        var unmatchedOpenParentheses: [String.Index] = []
        var snapshots: [String.Index: SwiftLexicalPosition] = [:]
        var index = source.startIndex

        while index < source.endIndex {
            if positions.contains(index) {
                snapshots[index] = SwiftLexicalPosition(
                    isInNormalCode: !lineComment && blockCommentDepth == 0 && literalDelimiter == nil,
                    openParenthesis: unmatchedOpenParentheses.last
                )
            }
            let character = source[index]
            let nextIndex = source.index(after: index)
            let nextCharacter = nextIndex < source.endIndex ? source[nextIndex] : nil

            if lineComment {
                lineComment = character != "\n" && character != "\r"
                index = nextIndex
                continue
            }
            if blockCommentDepth > 0 {
                if character == "/", nextCharacter == "*" {
                    blockCommentDepth += 1
                    index = source.index(after: nextIndex)
                } else if character == "*", nextCharacter == "/" {
                    blockCommentDepth -= 1
                    index = source.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
                continue
            }
            if let delimiter = literalDelimiter {
                if let escapedDelimiterEnd = escapedLiteralDelimiterEnd(at: index, in: source, delimiter: delimiter) {
                    index = escapedDelimiterEnd
                } else if let closingDelimiterEnd = literalDelimiterEnd(at: index, in: source, delimiter: delimiter) {
                    literalDelimiter = nil
                    index = closingDelimiterEnd
                } else {
                    index = nextIndex
                }
                continue
            }

            if character == "/", nextCharacter == "/" {
                lineComment = true
                index = source.index(after: nextIndex)
            } else if character == "/", nextCharacter == "*" {
                blockCommentDepth = 1
                index = source.index(after: nextIndex)
            } else if let delimiter = literalDelimiterStarting(at: index, in: source) {
                literalDelimiter = delimiter
                let delimiterLength = delimiter.kind == .regex
                    ? 1 + delimiter.hashCount
                    : (delimiter.isMultiline ? 3 : 1) + delimiter.hashCount
                index = source.index(index, offsetBy: delimiterLength)
            } else if character == "(" {
                unmatchedOpenParentheses.append(index)
                index = nextIndex
            } else if character == ")" {
                _ = unmatchedOpenParentheses.popLast()
                index = nextIndex
            } else {
                index = nextIndex
            }
        }

        return snapshots
    }

    private static func literalDelimiterStarting(at index: String.Index, in source: String) -> SwiftLiteralDelimiter? {
        if source[index] == "\"" {
            return SwiftLiteralDelimiter(kind: .string, hashCount: 0, isMultiline: source[index...].hasPrefix("\"\"\""))
        }
        guard source[index] == "#" else {
            return nil
        }
        var hashCount = 0
        var cursor = index
        while cursor < source.endIndex, source[cursor] == "#" {
            hashCount += 1
            cursor = source.index(after: cursor)
        }
        guard cursor < source.endIndex else {
            return nil
        }
        if source[cursor] == "\"" {
            return SwiftLiteralDelimiter(kind: .string, hashCount: hashCount, isMultiline: source[cursor...].hasPrefix("\"\"\""))
        }
        if source[cursor] == "/" {
            return SwiftLiteralDelimiter(kind: .regex, hashCount: hashCount, isMultiline: true)
        }
        return nil
    }

    private static func escapedLiteralDelimiterEnd(
        at index: String.Index,
        in source: String,
        delimiter: SwiftLiteralDelimiter
    ) -> String.Index? {
        guard source[index] == "\\" else {
            return nil
        }
        var cursor = source.index(after: index)
        if delimiter.kind == .regex {
            // Swift regex literals escape a potential `/<hashes>` terminator as
            // `\/<hashes>`; raw strings instead put the hashes before the quote.
            return literalDelimiterEnd(at: cursor, in: source, delimiter: delimiter)
        }
        for _ in 0..<delimiter.hashCount {
            guard cursor < source.endIndex, source[cursor] == "#" else {
                return nil
            }
            cursor = source.index(after: cursor)
        }
        return literalDelimiterEnd(at: cursor, in: source, delimiter: delimiter)
    }

    private static func literalDelimiterEnd(
        at index: String.Index,
        in source: String,
        delimiter: SwiftLiteralDelimiter
    ) -> String.Index? {
        var cursor = index
        let closingCharacter: Character = delimiter.kind == .regex ? "/" : "\""
        for _ in 0..<(delimiter.kind == .regex ? 1 : (delimiter.isMultiline ? 3 : 1)) {
            guard cursor < source.endIndex, source[cursor] == closingCharacter else {
                return nil
            }
            cursor = source.index(after: cursor)
        }
        for _ in 0..<delimiter.hashCount {
            guard cursor < source.endIndex, source[cursor] == "#" else {
                return nil
            }
            cursor = source.index(after: cursor)
        }
        return cursor < source.endIndex && source[cursor] == "#" ? nil : cursor
    }

    private static func hasOpenSwiftArgumentList(
        in source: String,
        openParenthesis: String.Index?,
        callOpener: NSRegularExpression
    ) -> Bool {
        guard let openParenthesis else {
            return false
        }
        let lineRange = source.lineRange(for: openParenthesis..<source.index(after: openParenthesis))
        let openerPrefix = String(source[lineRange.lowerBound..<openParenthesis])
        let range = NSRange(openerPrefix.startIndex..<openerPrefix.endIndex, in: openerPrefix)
        return callOpener.firstMatch(in: openerPrefix, range: range) != nil
    }

    private static func isSafeSwiftExpression(_ expression: String, atom: NSRegularExpression) -> Bool {
        let comparisonParts = expression.components(separatedBy: "==")
        guard comparisonParts.count <= 2 else {
            return false
        }
        if comparisonParts.count == 2,
           !["true", "false", "nil"].contains(comparisonParts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
            return false
        }
        // Each operand is intentionally limited to source names, member access,
        // and calls with the same. Quotes and config-style literals cannot form an
        // atom, so the exception cannot persist a credential value.
        return comparisonParts[0]
            .components(separatedBy: "??")
            .allSatisfy { candidate in
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                return atom.firstMatch(in: trimmed, range: range) != nil
            }
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: isCJK)
    }

    private static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func boundedFileData(root: URL, relativePath: String) throws -> Data {
        let rootDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard rootDescriptor >= 0 else {
            throw DevelopmentRepositoryIndexError.fileReadUnavailable
        }
        defer { Darwin.close(rootDescriptor) }
        let read = try boundedFileRead(rootDescriptor: rootDescriptor, relativePath: relativePath)
        guard !read.isOversized else {
            throw DevelopmentRepositoryIndexError.indexedContentTooLarge
        }
        return read.data
    }

    private static func boundedFileRead(rootDescriptor: Int32, relativePath: String) throws -> BoundedFileRead {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw DevelopmentRepositoryFileError.invalidRelativePath
        }
        var directoryDescriptor = Darwin.dup(rootDescriptor)
        guard directoryDescriptor >= 0 else {
            // The root descriptor is fixed before manifest generation; without a
            // duplicate we cannot guarantee every openat read stays in that inode.
            throw DevelopmentRepositoryIndexError.fileReadUnavailable
        }
        defer { Darwin.close(directoryDescriptor) }

        for component in components.dropLast() {
            let nextDescriptor = Darwin.openat(
                directoryDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard nextDescriptor >= 0 else {
                // A manifest cannot stably name a symlinked ancestor. Treat this
                // as a post-manifest race rather than an intentional file exclusion.
                throw DevelopmentRepositoryIndexError.fileReadUnavailable
            }
            Darwin.close(directoryDescriptor)
            directoryDescriptor = nextDescriptor
        }

        let descriptor = Darwin.openat(
            directoryDescriptor,
            components[components.count - 1],
            // A tracked pathname can be replaced with a FIFO after manifest
            // creation. Nonblocking open lets fstat reject it without a writer.
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw errno == ELOOP
                ? DevelopmentRepositoryFileError.symlinkNotAllowed
                : DevelopmentRepositoryIndexError.fileReadUnavailable
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var descriptorState = stat()
        guard Darwin.fstat(descriptor, &descriptorState) == 0 else {
            throw DevelopmentRepositoryIndexError.fileReadUnavailable
        }
        guard (descriptorState.st_mode & S_IFMT) == S_IFREG else {
            throw DevelopmentRepositoryIndexError.fileReadUnavailable
        }
        let data = try handle.read(upToCount: DevelopmentRepositoryFilePathPolicy.maximumContentBytes + 1) ?? Data()
        return BoundedFileRead(
            data: data,
            isOversized: data.count > DevelopmentRepositoryFilePathPolicy.maximumContentBytes
        )
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

private struct BoundedFileRead {
    let data: Data
    let isOversized: Bool
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
    static let defaultExecutableURL = URL(fileURLWithPath: "/usr/bin/git")
    private static let maximumGlobalExcludesOutputBytes = 4 * 1024
    private static let globalExcludesLookupTimeout: TimeInterval = 1

    struct Entry {
        let path: String
        let isUnavailable: Bool
    }

    struct RootIdentity {
        let device: dev_t
        let inode: ino_t
    }

    static func paths(
        at root: URL,
        timeout: TimeInterval = 15,
        executableURL: URL = defaultExecutableURL,
        expectedRootIdentity: RootIdentity? = nil
    ) throws -> [String] {
        try manifestEntries(
            at: root,
            timeout: timeout,
            executableURL: executableURL,
            expectedRootIdentity: expectedRootIdentity
        ).map(\.path)
    }

    static func entries(
        at root: URL,
        timeout: TimeInterval = 15,
        executableURL: URL = defaultExecutableURL,
        expectedRootIdentity: RootIdentity? = nil
    ) throws -> [Entry] {
        try manifestEntries(
            at: root,
            timeout: timeout,
            executableURL: executableURL,
            expectedRootIdentity: expectedRootIdentity
        )
    }

    private static func manifestEntries(
        at root: URL,
        timeout: TimeInterval = 15,
        executableURL: URL = defaultExecutableURL,
        expectedRootIdentity: RootIdentity? = nil
    ) throws -> [Entry] {
        let output = try manifestData(
            at: root,
            arguments: ["ls-files", "--cached", "--others", "--deleted", "--stage", "-v", "-z", "--exclude-standard"],
            timeout: timeout,
            executableURL: executableURL,
            expectedRootIdentity: expectedRootIdentity
        )
        var orderedPaths: [String] = []
        var unavailableByPath: [String: Bool] = [:]
        for record in nullTerminatedStrings(from: output) {
            guard let parsed = parseManifestRecord(record) else {
                throw DevelopmentRepositoryIndexError.gitManifestUnavailable
            }
            if let existing = unavailableByPath[parsed.path] {
                unavailableByPath[parsed.path] = existing || parsed.isUnavailable
            } else {
                orderedPaths.append(parsed.path)
                unavailableByPath[parsed.path] = parsed.isUnavailable
            }
        }
        guard orderedPaths.count <= DevelopmentRepositoryIndex.maximumFiles else {
            throw DevelopmentRepositoryIndexError.tooManyFiles
        }
        return orderedPaths.map { Entry(path: $0, isUnavailable: unavailableByPath[$0] == true) }
    }

    private static func parseManifestRecord(_ record: String) -> Entry? {
        if record.hasPrefix("? ") {
            return Entry(path: String(record.dropFirst(2)), isUnavailable: false)
        }
        guard let separator = record.firstIndex(of: "\t") else {
            return nil
        }
        let fields = record[..<separator].split(separator: " ")
        guard fields.count >= 2 else {
            return nil
        }
        let tag = fields[0].uppercased()
        let path = String(record[record.index(after: separator)...])
        return Entry(path: path, isUnavailable: tag == "R" || tag == "S" || fields[1] == "160000")
    }

    private static func nullTerminatedStrings(from output: ManifestData) -> [String] {
        output.data.split(separator: 0, omittingEmptySubsequences: true).compactMap { String(data: $0, encoding: .utf8) }
    }

    private static func manifestData(
        at root: URL,
        arguments: [String],
        timeout: TimeInterval = 15,
        executableURL: URL = defaultExecutableURL,
        expectedRootIdentity: RootIdentity? = nil
    ) throws -> ManifestData {
        #if os(iOS) || targetEnvironment(macCatalyst)
        // Repository manifests require a local git subprocess, which mobile
        // targets intentionally do not ship. Never fall back to a filesystem walk.
        throw DevelopmentRepositoryIndexError.gitManifestUnsupported
        #else
        let rootIdentity = try expectedRootIdentity ?? currentRootIdentity(at: root)
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // This read-only manifest must not inherit repository or user hooks.
        // In particular, core.fsmonitor can execute a repo-configured command.
        let options = [
            "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=/dev/null",
        ]
        var manifestArguments = arguments
        if let globalExcludesFile = try globalExcludesFile(executableURL: executableURL) {
            // `-c core.excludesFile` would replace the repository-local setting.
            // Add the global patterns as an ls-files input instead, retaining both
            // ignore sources while global hooks and commands remain isolated.
            manifestArguments.append("--exclude-from=\(globalExcludesFile)")
        }
        // Process holds `.` as its cwd across exec. Verify that inode inside the
        // child before invoking git so an ABA path replacement cannot redirect a
        // valid parent-side check to another workspace.
        process.arguments = [
            "-c",
            "actual=$(/usr/bin/stat -f '%d:%i' .) || exit 125\n[ \"$actual\" = \"$1\" ] || exit 125\nshift\nexec \"$@\"",
            "repository-manifest",
            "\(rootIdentity.device):\(rootIdentity.inode)",
            executableURL.path,
        ] + options + manifestArguments
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
        let result = try boundedGitOutput(
            process: process,
            standardOutput: standardOutput,
            timeout: timeout,
            limit: DevelopmentRepositoryIndex.maximumManifestBytes
        )
        guard !result.output.exceeded else {
            throw DevelopmentRepositoryIndexError.manifestTooLarge
        }
        guard result.terminationStatus == 0 else {
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        return result.output
        #endif
    }

    #if !(os(iOS) || targetEnvironment(macCatalyst))
    private static func currentRootIdentity(at root: URL) throws -> RootIdentity {
        var state = stat()
        guard Darwin.lstat(root.path, &state) == 0, (state.st_mode & S_IFMT) == S_IFDIR else {
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        return RootIdentity(device: state.st_dev, inode: state.st_ino)
    }
    #endif

    #if !(os(iOS) || targetEnvironment(macCatalyst))
    private static func globalExcludesFile(executableURL: URL) throws -> String? {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = executableURL
        process.arguments = ["config", "--global", "--path", "--get", "core.excludesFile"]
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        var environment = [
            "PATH": "/usr/bin:/bin",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
        ]
        let inherited = ProcessInfo.processInfo.environment
        for key in ["HOME", "XDG_CONFIG_HOME"] {
            if let value = inherited[key] {
                environment[key] = value
            }
        }
        process.environment = environment
        let result = try boundedGitOutput(
            process: process,
            standardOutput: standardOutput,
            timeout: globalExcludesLookupTimeout,
            limit: maximumGlobalExcludesOutputBytes
        )
        if result.terminationStatus == 1, result.output.data.isEmpty {
            return defaultGlobalExcludesFile(in: inherited)
        }
        guard result.terminationStatus == 0, !result.output.exceeded,
              var path = String(data: result.output.data, encoding: .utf8) else {
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        if path.last == "\n" {
            path.removeLast()
            if path.last == "\r" {
                path.removeLast()
            }
        }
        guard !path.isEmpty, !path.contains("\n"), !path.contains("\r") else {
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        return path
    }

    private static func defaultGlobalExcludesFile(in environment: [String: String]) -> String? {
        let path: String?
        if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
            path = URL(fileURLWithPath: xdgConfigHome, isDirectory: true)
                .appendingPathComponent("git/ignore").path
        } else if let home = environment["HOME"], !home.isEmpty {
            path = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".config/git/ignore").path
        } else {
            path = nil
        }
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    private static func boundedGitOutput(
        process: Process,
        standardOutput: Pipe,
        timeout: TimeInterval,
        limit: Int
    ) throws -> (output: ManifestData, terminationStatus: Int32) {
        let result = ProcessResult()
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            throw DevelopmentRepositoryIndexError.gitManifestUnavailable
        }
        // Drain concurrently because either git command can fill a pipe before exit.
        group.enter()
        DispatchQueue.global().async {
            result.output = boundedManifestData(from: standardOutput.fileHandleForReading, limit: limit)
            if result.output.exceeded {
                process.terminate()
            }
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
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
        return (result.output, process.terminationStatus)
    }
    #endif
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
