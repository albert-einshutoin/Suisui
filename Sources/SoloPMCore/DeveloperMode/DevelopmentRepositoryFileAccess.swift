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
        }
    }
}

public struct DevelopmentRepositoryFileRecord: Equatable, Sendable {
    public var relativePath: String
    public var contents: String
    public var byteCount: Int
    public var sha256: String

    public init(relativePath: String, contents: String, byteCount: Int, sha256: String) {
        self.relativePath = relativePath
        self.contents = contents
        self.byteCount = byteCount
        self.sha256 = sha256
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

public enum DevelopmentRepositoryFilePathPolicy {
    public static let maximumContentBytes = 256 * 1024

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

        guard isSupportedTextPath(filename: components.last ?? "") else {
            throw DevelopmentRepositoryFileError.unsupportedTextFile
        }

        return components.joined(separator: "/")
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

    public init(project: ProjectRecord, redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) {
        self.project = project
        self.redactor = redactor
    }

    public func read(relativePath rawPath: String) throws -> DevelopmentRepositoryFileRecord {
        let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
        let scope = try ProjectWorkspaceScope(project: project)
        let fileURL = try resolveExistingFile(relativePath: relativePath, scope: scope)
        let data = try readData(at: fileURL)
        let contents = try decodeUTF8Text(data)
        // Path allowlists cannot distinguish source code about secrets from real
        // credentials, so reads fail closed if the file body matches token patterns.
        try failIfSecretLikeContent(contents)
        return record(relativePath: relativePath, contents: contents)
    }

    public func create(relativePath rawPath: String, contents: String) throws -> DevelopmentRepositoryFileRecord {
        let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
        try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
        // Avoid writing credential-looking material into a repo file through the
        // assistant queue; users can still edit such files manually outside SoloPM.
        try failIfSecretLikeContent(contents)
        let scope = try ProjectWorkspaceScope(project: project)
        let fileURL = try resolveNewFile(relativePath: relativePath, scope: scope)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL, options: [.atomic])

        return record(relativePath: relativePath, contents: contents)
    }

    public func update(
        relativePath rawPath: String,
        contents: String,
        expectedSHA256: String?
    ) throws -> DevelopmentRepositoryFileRecord {
        let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
        try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
        try failIfSecretLikeContent(contents)
        let scope = try ProjectWorkspaceScope(project: project)
        let fileURL = try resolveExistingFile(relativePath: relativePath, scope: scope)

        if let expectedSHA256 {
            // The digest is a cheap compare-and-swap guard: the user reviews one
            // file version, and SoloPM refuses to overwrite a later edit.
            let currentDigest = sha256(try readData(at: fileURL))
            guard currentDigest == expectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                throw DevelopmentRepositoryFileError.staleDigest
            }
        }

        try Data(contents.utf8).write(to: fileURL, options: [.atomic])
        return record(relativePath: relativePath, contents: contents)
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

    private func failIfSecretLikeContent(_ contents: String) throws {
        let report = redactor.redact(contents).report
        guard report.replacementCount == 0 else {
            throw DevelopmentRepositoryFileError.secretLikeContent(report.matchedPatternNames)
        }
    }

    private func record(relativePath: String, contents: String) -> DevelopmentRepositoryFileRecord {
        DevelopmentRepositoryFileRecord(
            relativePath: relativePath,
            contents: contents,
            byteCount: Data(contents.utf8).count,
            sha256: sha256(Data(contents.utf8))
        )
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isInsideWorkspace(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

public struct DevelopmentRepositoryFileTool: Tool {
    public var name: ActionTool
    public var description: String {
        switch name {
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
        case .developmentRepositoryReadFile:
            return ToolInputSchema(
                required: ["projectId", "relativePath"],
                properties: ["projectId": "integer", "relativePath": "string"],
                nonBlank: ["relativePath"]
            )
        case .developmentRepositoryCreateFile:
            return ToolInputSchema(
                required: ["projectId", "relativePath", "contents"],
                properties: ["projectId": "integer", "relativePath": "string", "contents": "string"],
                nonBlank: ["relativePath"]
            )
        case .developmentRepositoryUpdateFile:
            return ToolInputSchema(
                required: ["projectId", "relativePath", "contents"],
                properties: [
                    "projectId": "integer",
                    "relativePath": "string",
                    "contents": "string",
                    "expectedSHA256": "string"
                ],
                nonBlank: ["relativePath", "expectedSHA256"]
            )
        default:
            return ToolInputSchema()
        }
    }

    public var permissionLevel: ToolPermissionLevel {
        name.defaultRiskLevel >= .write ? .writeWithApproval : .read
    }

    private let projectStore: SQLiteProjectStore
    private let redactor: DeveloperSecretRedactor

    public init(name: ActionTool, projectStore: SQLiteProjectStore, redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) {
        self.name = name
        self.projectStore = projectStore
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")

        do {
            let project = try projectStore.get(id: projectID)
            let client = DevelopmentRepositoryFileClient(project: project, redactor: redactor)
            let relativePath = try args.requiredTrimmedString("relativePath")
            let record: DevelopmentRepositoryFileRecord

            switch name {
            case .developmentRepositoryReadFile:
                record = try client.read(relativePath: relativePath)
            case .developmentRepositoryCreateFile:
                record = try client.create(
                    relativePath: relativePath,
                    contents: try args.requiredString("contents")
                )
            case .developmentRepositoryUpdateFile:
                record = try client.update(
                    relativePath: relativePath,
                    contents: try args.requiredString("contents"),
                    expectedSHA256: try args.optionalTrimmedString("expectedSHA256")
                )
            default:
                throw DevelopmentRepositoryFileError.unsupportedTool(name)
            }

            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "\(summaryVerb) \(record.relativePath).",
                output: record.output,
                rollbackMetadata: [
                    "projectId": .number(Double(project.id)),
                    "relativePath": .string(record.relativePath),
                    "sha256": .string(record.sha256)
                ]
            )
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
}
