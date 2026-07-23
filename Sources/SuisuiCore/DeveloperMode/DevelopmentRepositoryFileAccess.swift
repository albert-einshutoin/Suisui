import CryptoKit
import Foundation

public enum DevelopmentRepositoryFileError: Error, Equatable, Sendable {
    case unsupportedTool(ActionTool)
    case invalidRelativePath
    case gitMetadataPath
    case secretLikePath
    case unsupportedTextFile
    case pathEscapesWorkspace
    case fileNotFound
    case fileAlreadyExists
    case targetIsDirectory
    case symlinkNotAllowed
    case contentTooLarge(Int)
    case binaryOrNonUTF8Content
    case secretLikeContent([String])
    case staleDigest
    case invalidExpectedSHA256
    case currentBranchUnavailable
    case branchMismatch(expected: String, actual: String)

    public var userMessage: String {
        switch self {
        case .unsupportedTool:
            return "Unsupported repository file tool."
        case .invalidRelativePath:
            return "Repository file path must not contain traversal or empty components."
        case .gitMetadataPath:
            return "Repository file path must not target git metadata."
        case .secretLikePath:
            return "Repository file path looks like a credential or secret file."
        case .unsupportedTextFile:
            return "Repository file path must target a supported text file."
        case .pathEscapesWorkspace:
            return "Repository file path must not resolve outside the approved workspace."
        case .fileNotFound:
            return "Repository file was not found."
        case .fileAlreadyExists:
            return "Repository file already exists; use update instead."
        case .targetIsDirectory:
            return "Repository file path points to a directory."
        case .symlinkNotAllowed:
            return "Repository file path must not traverse or target a symlink."
        case .contentTooLarge(let maximumBytes):
            return "Repository file content exceeds the \(maximumBytes) byte limit."
        case .binaryOrNonUTF8Content:
            return "Repository file content must be UTF-8 text."
        case .secretLikeContent:
            return "Repository file content looks like it contains credentials or secrets."
        case .staleDigest:
            return "File changed since review; refresh the diff before updating."
        case .invalidExpectedSHA256:
            return "Expected SHA must be a 64 character hex digest."
        case .currentBranchUnavailable:
            return "Could not confirm the current repository branch before writing."
        case .branchMismatch(let expected, let actual):
            return "Repository branch mismatch: expected \(expected), found \(actual)."
        }
    }
}

public struct DevelopmentRepositoryFileRecord: Equatable, Sendable {
    public var relativePath: String
    public var contents: String
    public var byteCount: Int
    public var sha256: String
    public var workspacePath: String?
    public var absolutePath: String?

    public init(
        relativePath: String,
        contents: String,
        byteCount: Int,
        sha256: String,
        workspacePath: String? = nil,
        absolutePath: String? = nil
    ) {
        self.relativePath = relativePath
        self.contents = contents
        self.byteCount = byteCount
        self.sha256 = sha256
        self.workspacePath = workspacePath
        self.absolutePath = absolutePath
    }

    public var output: [String: JSONValue] {
        [
            "relativePath": .string(relativePath),
            "contents": .string(contents),
            "byteCount": .number(Double(byteCount)),
            "sha256": .string(sha256)
        ]
    }
}

public struct DevelopmentRepositoryFileListEntry: Equatable, Sendable {
    public var relativePath: String
    public var byteCount: Int

    public init(relativePath: String, byteCount: Int) {
        self.relativePath = relativePath
        self.byteCount = byteCount
    }

    public var output: JSONValue {
        .object([
            "relativePath": .string(relativePath),
            "byteCount": .number(Double(byteCount))
        ])
    }
}

public struct DevelopmentRepositoryFileList: Equatable, Sendable {
    public var entries: [DevelopmentRepositoryFileListEntry]
    public var truncated: Bool

    public init(entries: [DevelopmentRepositoryFileListEntry], truncated: Bool) {
        self.entries = entries
        self.truncated = truncated
    }
}

public enum DevelopmentRepositoryFilePathPolicy {
    public static let maximumContentBytes = 256 * 1024
    public static let maximumListedFileEntries = 500
    public static let maximumListedFileSystemNodes = 5_000

    private static let allowedTextExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "csv", "go", "h", "hpp", "html", "ini", "java",
        "js", "json", "jsx", "kt", "m", "markdown", "md", "mm", "py", "rb", "rs",
        "scss", "sh", "sql", "swift", "toml", "ts", "tsx", "txt", "xml", "yaml", "yml"
    ]

    private static let allowedExtensionlessFilenames: Set<String> = [
        "dockerfile", "gemfile", "license", "makefile", "readme"
    ]

    private static let secretBasenames: Set<String> = [
        ".env", ".netrc", ".npmrc", ".pypirc", ".yarnrc", "credentials", "credentials.json",
        "id_rsa", "id_dsa", "password.json", "secret.json", "secrets.json", "token.json"
    ]

    private static let secretDirectories: Set<String> = [
        ".aws", ".config/gh", ".gnupg", ".ssh"
    ]

    public static func validatedRelativePath(_ rawPath: String) throws -> String {
        let components = try validatedPathComponents(rawPath)

        guard isSupportedTextPath(filename: components.last ?? "") else {
            throw DevelopmentRepositoryFileError.unsupportedTextFile
        }

        return components.joined(separator: "/")
    }

    public static func validatedRelativeDirectoryPath(_ rawPath: String?) throws -> String? {
        guard let rawPath else {
            return nil
        }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return try validatedPathComponents(trimmed).joined(separator: "/")
    }

    public static func isSupportedListedFile(relativePath rawPath: String) -> Bool {
        do {
            _ = try validatedRelativePath(rawPath)
            return true
        } catch DevelopmentRepositoryFileError.gitMetadataPath,
                DevelopmentRepositoryFileError.secretLikePath,
                DevelopmentRepositoryFileError.unsupportedTextFile {
            return false
        } catch {
            return false
        }
    }

    public static func shouldSkipListedDirectory(relativePath rawPath: String) -> Bool {
        do {
            _ = try validatedRelativeDirectoryPath(rawPath)
            return false
        } catch DevelopmentRepositoryFileError.gitMetadataPath,
                DevelopmentRepositoryFileError.secretLikePath {
            return true
        } catch {
            return true
        }
    }

    private static func validatedPathComponents(_ rawPath: String) throws -> [String] {
        guard !rawPath.contains("\u{0}") else {
            throw DevelopmentRepositoryFileError.invalidRelativePath
        }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("//") else {
            throw DevelopmentRepositoryFileError.invalidRelativePath
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw DevelopmentRepositoryFileError.invalidRelativePath
        }

        if components.contains(".git") {
            throw DevelopmentRepositoryFileError.gitMetadataPath
        }

        if isSecretLike(components: components) {
            throw DevelopmentRepositoryFileError.secretLikePath
        }

        return components
    }

    public static func validateTextContent(_ contents: String) throws {
        let byteCount = Data(contents.utf8).count
        guard byteCount <= maximumContentBytes else {
            throw DevelopmentRepositoryFileError.contentTooLarge(maximumContentBytes)
        }

        guard !contents.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw DevelopmentRepositoryFileError.binaryOrNonUTF8Content
        }
    }

    public static func validatedExpectedSHA256(_ rawDigest: String) throws -> String {
        let digest = rawDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard digest.count == 64,
              digest.unicodeScalars.allSatisfy({ hexCharacters.contains($0) }) else {
            throw DevelopmentRepositoryFileError.invalidExpectedSHA256
        }
        return digest.lowercased()
    }

    private static func isSupportedTextPath(filename: String) -> Bool {
        let lowercased = filename.lowercased()
        if allowedExtensionlessFilenames.contains(lowercased) {
            return true
        }

        let pathExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return !pathExtension.isEmpty && allowedTextExtensions.contains(pathExtension)
    }

    private static func isSecretLike(components: [String]) -> Bool {
        for (index, component) in components.enumerated() {
            let lowercased = component.lowercased()
            if secretDirectories.contains(lowercased) {
                return true
            }
            if index > 0 {
                let parentPair = "\(components[index - 1].lowercased())/\(lowercased)"
                if secretDirectories.contains(parentPair) {
                    return true
                }
            }
            if secretBasenames.contains(lowercased) || lowercased.hasPrefix(".env.") {
                return true
            }
            if lowercased.hasSuffix(".pem") || lowercased.hasSuffix(".key") {
                return true
            }
            if lowercased.hasSuffix("-credentials.json") || lowercased.hasSuffix("_credentials.json") {
                return true
            }
        }
        return false
    }
}

public struct DevelopmentRepositoryFileClient: Sendable {
    private let project: ProjectRecord
    private let redactor: DeveloperSecretRedactor
    private let bookmarkResolver: any ProjectWorkspaceBookmarkResolving
    private let requireBookmark: Bool
    private let gitRunner: any GitCommandRunner

    public init(
        project: ProjectRecord,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver(),
        requireBookmark: Bool = false,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner()
    ) {
        self.project = project
        self.redactor = redactor
        self.bookmarkResolver = bookmarkResolver
        self.requireBookmark = requireBookmark
        self.gitRunner = gitRunner
    }

    public func list(relativePath rawPath: String? = nil) throws -> DevelopmentRepositoryFileList {
        let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativeDirectoryPath(rawPath)
        let scope = try ProjectWorkspaceScope(
            project: project,
            bookmarkResolver: bookmarkResolver,
            requireBookmark: requireBookmark
        )
        return try withExtendedLifetime(scope) {
            let directoryURL = try resolveExistingDirectory(relativePath: relativePath, scope: scope)
            let list = try listedEntries(directoryURL: directoryURL, scope: scope)
            return DevelopmentRepositoryFileList(
                entries: list.entries.sorted { $0.relativePath < $1.relativePath },
                truncated: list.truncated
            )
        }
    }

    public func read(relativePath rawPath: String) throws -> DevelopmentRepositoryFileRecord {
        let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
        let scope = try ProjectWorkspaceScope(
            project: project,
            bookmarkResolver: bookmarkResolver,
            requireBookmark: requireBookmark
        )
        return try withExtendedLifetime(scope) {
            let fileURL = try resolveExistingFile(relativePath: relativePath, scope: scope)
            let data = try readData(at: fileURL)
            let contents = try decodeUTF8Text(data)
            // Path allowlists cannot distinguish source code about secrets from real
            // credentials, so reads fail closed if the file body matches token patterns.
            try failIfSecretLikeContent(contents)
            return record(relativePath: relativePath, contents: contents, scope: scope)
        }
    }

    public func create(
        relativePath rawPath: String,
        contents: String,
        branchName: String? = nil
    ) throws -> DevelopmentRepositoryFileRecord {
        let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
        try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
        // Avoid writing credential-looking material into a repo file through the
        // assistant queue; users can still edit such files manually outside Suisui.
        try failIfSecretLikeContent(contents)
        let scope = try ProjectWorkspaceScope(
            project: project,
            bookmarkResolver: bookmarkResolver,
            requireBookmark: requireBookmark
        )
        return try withExtendedLifetime(scope) {
            try ensureCurrentBranch(matches: branchName, scope: scope)
            let fileURL = try resolveNewFile(relativePath: relativePath, scope: scope)

            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: fileURL, options: [.atomic])

            return record(relativePath: relativePath, contents: contents, scope: scope)
        }
    }

    public func update(
        relativePath rawPath: String,
        contents: String,
        expectedSHA256: String,
        branchName: String? = nil
    ) throws -> DevelopmentRepositoryFileRecord {
        let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
        let expectedDigest = try DevelopmentRepositoryFilePathPolicy.validatedExpectedSHA256(expectedSHA256)
        try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
        try failIfSecretLikeContent(contents)
        let scope = try ProjectWorkspaceScope(
            project: project,
            bookmarkResolver: bookmarkResolver,
            requireBookmark: requireBookmark
        )
        return try withExtendedLifetime(scope) {
            try ensureCurrentBranch(matches: branchName, scope: scope)
            let fileURL = try resolveExistingFile(relativePath: relativePath, scope: scope)

            // The digest is a cheap compare-and-swap guard: the user reviews one
            // file version, and Suisui refuses to overwrite a later edit.
            let currentDigest = sha256(try readData(at: fileURL))
            guard currentDigest == expectedDigest else {
                throw DevelopmentRepositoryFileError.staleDigest
            }

            try Data(contents.utf8).write(to: fileURL, options: [.atomic])
            return record(relativePath: relativePath, contents: contents, scope: scope)
        }
    }

    private func resolveExistingDirectory(relativePath: String?, scope: ProjectWorkspaceScope) throws -> URL {
        let directoryURL: URL
        if let relativePath {
            directoryURL = try resolvedURL(relativePath: relativePath, scope: scope)
            try rejectSymlinkComponents(relativePath: relativePath, rootURL: scope.rootURL, requireTargetExists: true)
        } else {
            directoryURL = scope.rootURL
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            throw DevelopmentRepositoryFileError.fileNotFound
        }
        guard isDirectory.boolValue else {
            throw DevelopmentRepositoryFileError.targetIsDirectory
        }

        let resolvedDirectoryURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        guard isInsideWorkspace(resolvedDirectoryURL, rootURL: scope.rootURL) else {
            throw DevelopmentRepositoryFileError.pathEscapesWorkspace
        }
        return resolvedDirectoryURL
    }

    private func listedEntries(
        directoryURL: URL,
        scope: ProjectWorkspaceScope
    ) throws -> DevelopmentRepositoryFileList {
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            throw DevelopmentRepositoryFileError.fileNotFound
        }

        var entries: [DevelopmentRepositoryFileListEntry] = []
        var visitedNodeCount = 0
        for case let fileURL as URL in enumerator {
            visitedNodeCount += 1
            // Accepted-entry caps protect the LLM context; a separate node budget
            // keeps generated or vendor-heavy trees from tying up the review UI.
            guard visitedNodeCount <= DevelopmentRepositoryFilePathPolicy.maximumListedFileSystemNodes else {
                return DevelopmentRepositoryFileList(entries: entries, truncated: true)
            }

            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            guard values.isSymbolicLink != true else {
                throw DevelopmentRepositoryFileError.symlinkNotAllowed
            }
            guard let relativePath = relativePath(for: fileURL, rootURL: scope.rootURL) else {
                throw DevelopmentRepositoryFileError.pathEscapesWorkspace
            }

            if values.isDirectory == true {
                if DevelopmentRepositoryFilePathPolicy.shouldSkipListedDirectory(relativePath: relativePath) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true,
                  DevelopmentRepositoryFilePathPolicy.isSupportedListedFile(relativePath: relativePath) else {
                continue
            }

            let byteCount = values.fileSize ?? 0
            guard byteCount <= DevelopmentRepositoryFilePathPolicy.maximumContentBytes else {
                continue
            }
            guard try isUTF8TextFile(fileURL) else {
                continue
            }

            entries.append(DevelopmentRepositoryFileListEntry(relativePath: relativePath, byteCount: byteCount))
            // Repository scans are context-feed material, so cap the result before a
            // generated tree can flood the review UI or planner prompt. The truncated
            // subset is a bounded preview, not a complete lexicographic inventory.
            if entries.count >= DevelopmentRepositoryFilePathPolicy.maximumListedFileEntries {
                return DevelopmentRepositoryFileList(entries: entries, truncated: true)
            }
        }
        return DevelopmentRepositoryFileList(entries: entries, truncated: false)
    }

    private func resolveExistingFile(relativePath: String, scope: ProjectWorkspaceScope) throws -> URL {
        let fileURL = try resolvedURL(relativePath: relativePath, scope: scope)
        try rejectSymlinkComponents(relativePath: relativePath, rootURL: scope.rootURL, requireTargetExists: true)

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            throw DevelopmentRepositoryFileError.fileNotFound
        }
        guard !isDirectory.boolValue else {
            throw DevelopmentRepositoryFileError.targetIsDirectory
        }

        let resolvedFileURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        guard isInsideWorkspace(resolvedFileURL, rootURL: scope.rootURL) else {
            throw DevelopmentRepositoryFileError.pathEscapesWorkspace
        }

        return resolvedFileURL
    }

    private func resolveNewFile(relativePath: String, scope: ProjectWorkspaceScope) throws -> URL {
        let fileURL = try resolvedURL(relativePath: relativePath, scope: scope)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DevelopmentRepositoryFileError.fileAlreadyExists
        }

        // Missing child directories are okay, but existing ancestors must be real
        // directories under the approved root rather than symlink escape hatches.
        try rejectSymlinkComponents(relativePath: relativePath, rootURL: scope.rootURL, requireTargetExists: false)
        return fileURL
    }

    private func resolvedURL(relativePath: String, scope: ProjectWorkspaceScope) throws -> URL {
        let fileURL = scope.rootURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        guard isInsideWorkspace(fileURL, rootURL: scope.rootURL) else {
            throw DevelopmentRepositoryFileError.pathEscapesWorkspace
        }
        return fileURL
    }

    private func rejectSymlinkComponents(
        relativePath: String,
        rootURL: URL,
        requireTargetExists: Bool
    ) throws {
        var current = rootURL
        let components = relativePath.split(separator: "/").map(String.init)
        for (index, component) in components.enumerated() {
            current = current.appendingPathComponent(component, isDirectory: false)
            let exists = FileManager.default.fileExists(atPath: current.path)
            guard exists else {
                if requireTargetExists {
                    throw DevelopmentRepositoryFileError.fileNotFound
                }
                break
            }

            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                if index == components.count - 1 {
                    let resolved = current.resolvingSymlinksInPath().standardizedFileURL
                    guard isInsideWorkspace(resolved, rootURL: rootURL) else {
                        throw DevelopmentRepositoryFileError.pathEscapesWorkspace
                    }
                }
                throw DevelopmentRepositoryFileError.symlinkNotAllowed
            }
        }
    }

    private func readData(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw DevelopmentRepositoryFileError.targetIsDirectory
        }

        let fileSize = values.fileSize ?? 0
        guard fileSize <= DevelopmentRepositoryFilePathPolicy.maximumContentBytes else {
            throw DevelopmentRepositoryFileError.contentTooLarge(DevelopmentRepositoryFilePathPolicy.maximumContentBytes)
        }

        return try Data(contentsOf: url)
    }

    private func decodeUTF8Text(_ data: Data) throws -> String {
        guard !data.contains(0), let contents = String(data: data, encoding: .utf8) else {
            throw DevelopmentRepositoryFileError.binaryOrNonUTF8Content
        }
        try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
        return contents
    }

    private func isUTF8TextFile(_ url: URL) throws -> Bool {
        let data = try Data(contentsOf: url)
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil else {
            return false
        }
        return true
    }

    private func failIfSecretLikeContent(_ contents: String) throws {
        let report = redactor.redact(contents).report
        guard report.replacementCount == 0 else {
            throw DevelopmentRepositoryFileError.secretLikeContent(report.matchedPatternNames)
        }
    }

    private func record(
        relativePath: String,
        contents: String,
        scope: ProjectWorkspaceScope
    ) -> DevelopmentRepositoryFileRecord {
        DevelopmentRepositoryFileRecord(
            relativePath: relativePath,
            contents: contents,
            byteCount: Data(contents.utf8).count,
            sha256: sha256(Data(contents.utf8)),
            workspacePath: scope.rootURL.path,
            absolutePath: scope.rootURL.appendingPathComponent(relativePath).standardizedFileURL.path
        )
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func relativePath(for url: URL, rootURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return nil
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func isInsideWorkspace(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func ensureCurrentBranch(matches rawBranchName: String?, scope: ProjectWorkspaceScope) throws {
        guard let rawBranchName else {
            return
        }

        let expectedBranch = try DevelopmentBranchNamePolicy.validated(rawBranchName)
        do {
            let output = try gitRunner.runGit(arguments: ["branch", "--show-current"], workingDirectory: scope.rootURL)
            guard output.exitCode == 0 else {
                throw DevelopmentRepositoryFileError.currentBranchUnavailable
            }

            let currentBranch = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentBranch.isEmpty else {
                throw DevelopmentRepositoryFileError.currentBranchUnavailable
            }
            guard currentBranch == expectedBranch else {
                throw DevelopmentRepositoryFileError.branchMismatch(expected: expectedBranch, actual: currentBranch)
            }
        } catch let error as DevelopmentRepositoryFileError {
            throw error
        } catch {
            throw DevelopmentRepositoryFileError.currentBranchUnavailable
        }
    }
}

public struct DevelopmentRepositoryFileTool: Tool {
    public var name: ActionTool
    public var description: String {
        switch name {
        case .developmentRepositoryListFiles:
            return "List supported text files inside an approved project workspace."
        case .developmentRepositoryReadFile:
            return "Read a supported text file inside an approved project workspace."
        case .developmentRepositoryCreateFile:
            return "Create a supported text file inside an approved project workspace."
        case .developmentRepositoryUpdateFile:
            return "Update a supported text file inside an approved project workspace."
        default:
            return "Unsupported repository file tool."
        }
    }

    public var inputSchema: ToolInputSchema {
        switch name {
        case .developmentRepositoryListFiles:
            return ToolInputSchema(
                required: ["projectId"],
                properties: ["projectId": "integer", "relativePath": "string"],
                nonBlank: ["relativePath"]
            )
        case .developmentRepositoryReadFile:
            return ToolInputSchema(
                required: ["projectId", "relativePath"],
                properties: ["projectId": "integer", "relativePath": "string"],
                nonBlank: ["relativePath"]
            )
        case .developmentRepositoryCreateFile:
            return ToolInputSchema(
                required: ["projectId", "relativePath", "contents"],
                properties: [
                    "projectId": "integer",
                    "taskId": "integer",
                    "branchName": "string",
                    "relativePath": "string",
                    "contents": "string"
                ],
                nonBlank: ["branchName", "relativePath"]
            )
        case .developmentRepositoryUpdateFile:
            return ToolInputSchema(
                required: ["projectId", "relativePath", "contents", "expectedSHA256"],
                properties: [
                    "projectId": "integer",
                    "taskId": "integer",
                    "branchName": "string",
                    "relativePath": "string",
                    "contents": "string",
                    "expectedSHA256": "string"
                ],
                nonBlank: ["branchName", "relativePath", "expectedSHA256"]
            )
        default:
            return ToolInputSchema()
        }
    }

    public var permissionLevel: ToolPermissionLevel {
        name.defaultRiskLevel >= .write ? .writeWithApproval : .read
    }

    private let projectStore: SQLiteProjectStore
    private let artifactStore: SQLiteArtifactStore?
    private let redactor: DeveloperSecretRedactor
    private let bookmarkResolver: any ProjectWorkspaceBookmarkResolving
    private let requireBookmark: Bool
    private let gitRunner: any GitCommandRunner

    public init(
        name: ActionTool,
        projectStore: SQLiteProjectStore,
        artifactStore: SQLiteArtifactStore? = nil,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver(),
        requireBookmark: Bool = false,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner()
    ) {
        self.name = name
        self.projectStore = projectStore
        self.artifactStore = artifactStore
        self.redactor = redactor
        self.bookmarkResolver = bookmarkResolver
        self.requireBookmark = requireBookmark
        self.gitRunner = gitRunner
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(arguments: arguments, context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")

        do {
            let project = try projectStore.get(id: projectID)
            let client = DevelopmentRepositoryFileClient(
                project: project,
                redactor: redactor,
                bookmarkResolver: bookmarkResolver,
                requireBookmark: requireBookmark,
                gitRunner: gitRunner
            )
            let taskID = try args.optionalInt64("taskId")
            let branchName = try args.optionalTrimmedString("branchName")

            switch name {
            case .developmentRepositoryListFiles:
                let list = try client.list(relativePath: try args.optionalTrimmedString("relativePath"))
                return ToolResult(
                    tool: name,
                    status: .succeeded,
                    summary: "Listed \(list.entries.count) repository files.",
                    output: [
                        "entryCount": .number(Double(list.entries.count)),
                        "entries": .array(list.entries.map(\.output)),
                        "truncated": .bool(list.truncated)
                    ],
                    rollbackMetadata: [
                        "projectId": .number(Double(project.id))
                    ]
                )
            case .developmentRepositoryReadFile:
                let relativePath = try args.requiredTrimmedString("relativePath")
                let record = try client.read(relativePath: relativePath)
                return try result(record: record, project: project)
            case .developmentRepositoryCreateFile:
                let relativePath = try args.requiredTrimmedString("relativePath")
                let record = try client.create(
                    relativePath: relativePath,
                    contents: try args.requiredString("contents"),
                    branchName: branchName
                )
                return try result(record: record, project: project, taskID: taskID, branchName: branchName, linkArtifact: true)
            case .developmentRepositoryUpdateFile:
                let relativePath = try args.requiredTrimmedString("relativePath")
                let record = try client.update(
                    relativePath: relativePath,
                    contents: try args.requiredString("contents"),
                    expectedSHA256: try args.requiredTrimmedString("expectedSHA256"),
                    branchName: branchName
                )
                return try result(record: record, project: project, taskID: taskID, branchName: branchName, linkArtifact: true)
            default:
                throw DevelopmentRepositoryFileError.unsupportedTool(name)
            }
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentRepositoryFileError {
            throw ToolExecutionError.executionFailed(name, redactor.redact(error.userMessage).text)
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redactor.redact(error.userMessage).text)
        } catch {
            throw ToolExecutionError.executionFailed(name, redactor.redact(String(describing: error)).text)
        }
    }

    private var summaryVerb: String {
        switch name {
        case .developmentRepositoryListFiles:
            return "Listed"
        case .developmentRepositoryReadFile:
            return "Read"
        case .developmentRepositoryCreateFile:
            return "Created"
        case .developmentRepositoryUpdateFile:
            return "Updated"
        default:
            return "Processed"
        }
    }

    private func result(
        record: DevelopmentRepositoryFileRecord,
        project: ProjectRecord,
        taskID: Int64? = nil,
        branchName: String? = nil,
        linkArtifact: Bool = false
    ) throws -> ToolResult {
        let artifact = try linkArtifact ? persistedArtifactLink(for: record, project: project) : nil
        var output = record.output
        output["projectId"] = .number(Double(project.id))
        var rollbackMetadata: [String: JSONValue] = [
            "projectId": .number(Double(project.id)),
            "relativePath": .string(record.relativePath),
            "sha256": .string(record.sha256)
        ]
        if let taskID {
            output["taskId"] = .number(Double(taskID))
        }
        if let branchName {
            output["branchName"] = .string(branchName)
            rollbackMetadata["branchName"] = .string(branchName)
        }
        if let artifact {
            output["artifactId"] = .number(Double(artifact.id))
            rollbackMetadata["artifactId"] = .number(Double(artifact.id))
        }

        return ToolResult(
            tool: name,
            status: .succeeded,
            summary: "\(summaryVerb) \(record.relativePath).",
            output: output,
            rollbackMetadata: rollbackMetadata
        )
    }

    private func persistedArtifactLink(
        for record: DevelopmentRepositoryFileRecord,
        project: ProjectRecord
    ) throws -> ArtifactRecord? {
        guard let artifactStore else {
            return nil
        }
        guard let workspacePath = record.workspacePath, let absolutePath = record.absolutePath else {
            throw ToolExecutionError.executionFailed(name, "Repository file client did not report an absolute artifact path.")
        }

        let updated = try artifactStore.updateProjectArtifactFromFileEvent(
            projectID: project.id,
            workspacePath: workspacePath,
            path: absolutePath,
            modifiedAt: Date()
        )
        if let artifact = updated.first {
            return artifact
        }

        // Repository create/update results are project deliverables, not just
        // transient file edits, so link them into the Project overview once the
        // approved write succeeds.
        return try artifactStore.create(
            projectID: project.id,
            workspacePath: workspacePath,
            expectedPath: absolutePath,
            createdState: .created
        )
    }
}
