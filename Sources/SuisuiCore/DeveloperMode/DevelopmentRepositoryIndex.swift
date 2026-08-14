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
    case fileReadUnavailable
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
    // For indexing, reject every such assignment unless it matches one of the
    // narrow Swift grammars below; unknown syntax stays fail-closed.
    private static let credentialKeyAssignments = try? NSRegularExpression(
        pattern: #"\b(?i:(?:[A-Za-z_][A-Za-z0-9_]*)?(?:api[_-]?key|access[_-]?key|private[_-]?key|token|password|secret))\s*\"?\s*[:=]"#
    )
    private static let safeSwiftAssignment = try? NSRegularExpression(
        pattern: #"^\s*(?:(?:let|var)\s+)?(?:self\.)?[A-Za-z_][A-Za-z0-9_]*\s+=\s*(.+?)\s*$"#
    )
    private static let safeSwiftCallLabel = try? NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*\s*:\s*(.+?)\s*,?\s*\)*\s*$"#
    )
    private static let safeSwiftExpressionAtom = try? NSRegularExpression(
        pattern: #"^(?:try\s+)?(?:nil|true|false|[A-Za-z_][A-Za-z0-9_]*(?:(?:\?\.|\.)[A-Za-z_][A-Za-z0-9_]*)*(?:\(\s*(?:(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?\.?[A-Za-z_][A-Za-z0-9_]*(?:(?:\?\.|\.)[A-Za-z_][A-Za-z0-9_]*)*(?:\s*,\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?\.?[A-Za-z_][A-Za-z0-9_]*(?:(?:\?\.|\.)[A-Za-z_][A-Za-z0-9_]*)*)*)?\s*\))?)$"#
    )
    private static let safeSourceTypedDeclaration = try? NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*\s*:\s*[A-Z][A-Za-z0-9_.<>?]*\s*$"#
    )
    private static let safeSourceTypedFunctionParameter = try? NSRegularExpression(
        pattern: #"^[A-Za-z_][A-Za-z0-9_]*\s*:\s*[A-Z][A-Za-z0-9_.<>?]*(?=\s*(?:,|\)))"#
    )
    private static let safeSwiftNominalTypeDeclaration = try? NSRegularExpression(
        pattern: #"^\s*(?:(?:private|public|internal|fileprivate|final)\s+)*(?:struct|class|enum|protocol|actor)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*[A-Z][A-Za-z0-9_.<>?]*(?:\s*,\s*[A-Z][A-Za-z0-9_.<>?]*)*\s*(?:[{][}]?)?\s*$"#
    )
    private static let serializedCredential = try? NSRegularExpression(
        pattern: #"(?im)^\s*client[-_]key[-_]data\s*:\s*\S+|^\s*-----BEGIN (?:[A-Z0-9 ]*PRIVATE KEY)-----"#
    )
    private static let swiftTypedDeclarationPrefix = try? NSRegularExpression(
        pattern: #"^\s*(?:(?:private|public|internal|fileprivate|static|final|lazy)\s+)*(?:let|var)\s+$"#
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
        let entries = try GitManifestReader.entries(at: root)
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
            guard let relativePath = try? DevelopmentRepositoryFilePathPolicy.validatedRelativePath(path),
                  // The policy trims user-facing paths, but git names are byte-level
                  // identities.  Never let a trimmed manifest name reopen another file.
                  relativePath == path else {
                continue
            }
            // The manifest name is untrusted filesystem input.  Descending from
            // the approved root with openat/O_NOFOLLOW rejects both an ancestor
            // swap and a final-component symlink before any bytes are indexed.
            let data: Data
            do {
                data = try boundedFileData(root: root, relativePath: relativePath)
            } catch DevelopmentRepositoryFileError.symlinkNotAllowed,
                    DevelopmentRepositoryIndexError.indexedContentTooLarge {
                continue
            } catch {
                // A partial snapshot is worse than a failed refresh: preserve the
                // prior generation until all manifest files can be read again.
                throw DevelopmentRepositoryIndexError.fileReadUnavailable
            }
            guard let contents = String(data: data, encoding: .utf8),
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
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        guard let serializedCredential else {
            return true
        }
        if serializedCredential.firstMatch(in: contents, range: range) != nil {
            return true
        }
        let report = redactor.redact(contents).report
        // Shared redaction intentionally treats every token assignment as risky for
        // user-visible output. Source indexing keeps that policy for specific
        // patterns, while allowing typed Swift names such as `token: Type`.
        if report.matchedPatternNames.contains(where: { $0 != "assignment" }) {
            return true
        }
        guard let assignments = credentialKeyAssignments,
              let safeAssignment = safeSwiftAssignment,
              let safeCallLabel = safeSwiftCallLabel,
              let safeExpressionAtom = safeSwiftExpressionAtom,
              let safeTypedDeclaration = safeSourceTypedDeclaration,
              let safeTypedFunctionParameter = safeSourceTypedFunctionParameter,
              let safeNominalTypeDeclaration = safeSwiftNominalTypeDeclaration,
              let typedDeclarationPrefix = swiftTypedDeclarationPrefix,
              let functionParameterPrefix = swiftFunctionParameterPrefix,
              let callOpener = swiftCallOpener else {
            return true
        }
        let matches = assignments.matches(in: contents, range: range)
        guard !matches.isEmpty else {
            return report.matchedPatternNames.contains("assignment")
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
            let isTypedDeclaration = (hasSafeTypedDeclaration || isTypedFunctionParameter) &&
                !line.contains("=") && !line.contains("\"") && !line.contains("'")
            let fullLineRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let isNominalType = safeNominalTypeDeclaration.firstMatch(in: line, range: fullLineRange) != nil
            let isSafeAssignment = containsSafeSwiftExpression(in: line, grammar: safeAssignment, atom: safeExpressionAtom)
            // These forms contain only source identifiers/member references, never
            // a literal credential. The surrounding argument list prevents config
            // syntax from becoming an indexing exception.
            let hasCurrentLineCommentOrQuote = assignmentPrefix.contains("//") ||
                assignmentPrefix.contains("/*") ||
                assignmentPrefix.contains("\"") ||
                assignmentPrefix.contains("'")
            let isCallLabel = !hasCurrentLineCommentOrQuote &&
                hasOpenSwiftArgumentList(in: contents, openParenthesis: lexicalPosition.openParenthesis, callOpener: callOpener) &&
                containsSafeSwiftExpression(in: assignmentSuffix, grammar: safeCallLabel, atom: safeExpressionAtom)
            return !(isTypedDeclaration || isNominalType || isSafeAssignment || isCallLabel)
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
                lineComment = character != "\n"
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
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF, 0xFF66...0xFF9F:
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
            // The root was trusted before manifest generation. A failure here means
            // it may have been replaced, so publishing a partial empty generation
            // would be less safe than retaining the previous snapshot.
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
    struct Entry {
        let path: String
        let isUnavailable: Bool
    }

    static func paths(
        at root: URL,
        timeout: TimeInterval = 15,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) throws -> [String] {
        let output = try manifestData(
            at: root,
            arguments: ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            timeout: timeout,
            executableURL: executableURL
        )
        let paths = nullTerminatedStrings(from: output)
        guard paths.count <= DevelopmentRepositoryIndex.maximumFiles else {
            throw DevelopmentRepositoryIndexError.tooManyFiles
        }
        return paths
    }

    static func entries(at root: URL) throws -> [Entry] {
        // Capture Git's intentional-unavailability metadata before listing the
        // names. A later filesystem change then remains a read failure instead
        // of being mistaken for an intentional manifest exclusion.
        let stages = try stagedModes(at: root)
        let deleted = try deletedPaths(at: root)
        let skipWorktree = try skipWorktreePaths(at: root)
        let paths = try paths(at: root)
        return paths.map { path in
            Entry(
                path: path,
                isUnavailable: stages[path] == "160000" || deleted.contains(path) || skipWorktree.contains(path)
            )
        }
    }

    private static func stagedModes(at root: URL) throws -> [String: String] {
        let output = try manifestData(at: root, arguments: ["ls-files", "--cached", "--stage", "-z"])
        return nullTerminatedStrings(from: output).reduce(into: [:]) { modes, entry in
            guard let separator = entry.firstIndex(of: "\t") else {
                return
            }
            let fields = entry[..<separator].split(separator: " ", maxSplits: 1)
            guard let mode = fields.first else {
                return
            }
            modes[String(entry[entry.index(after: separator)...])] = String(mode)
        }
    }

    private static func deletedPaths(at root: URL) throws -> Set<String> {
        Set(nullTerminatedStrings(from: try manifestData(at: root, arguments: ["ls-files", "--deleted", "-z"])))
    }

    private static func skipWorktreePaths(at root: URL) throws -> Set<String> {
        Set(nullTerminatedStrings(from: try manifestData(at: root, arguments: ["ls-files", "--cached", "-v", "-z"])).compactMap { entry in
            guard entry.hasPrefix("S ") else {
                return nil
            }
            return String(entry.dropFirst(2))
        })
    }

    private static func nullTerminatedStrings(from output: ManifestData) -> [String] {
        output.data.split(separator: 0, omittingEmptySubsequences: true).compactMap { String(data: $0, encoding: .utf8) }
    }

    private static func manifestData(
        at root: URL,
        arguments: [String],
        timeout: TimeInterval = 15,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) throws -> ManifestData {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = executableURL
        // This read-only manifest must not inherit repository or user hooks.
        // In particular, core.fsmonitor can execute a repo-configured command.
        process.arguments = [
            "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=/dev/null",
        ] + arguments
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
        return result.output
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
