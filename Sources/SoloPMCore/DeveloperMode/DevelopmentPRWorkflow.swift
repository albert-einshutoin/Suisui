import Foundation

public enum DevelopmentPRWorkflowError: Error, Equatable, Sendable {
    case projectWorkspaceRequired(Int64)
    case projectWorkspaceMustBeAbsolute
    case projectWorkspaceUnavailable(String)
    case projectWorkspaceIsSymlink
    case projectWorkspaceBookmarkUnavailable
    case projectWorkspaceBookmarkStale
    case projectWorkspaceBookmarkPathMismatch
    case invalidBranchName(String)
    case commandNotAllowed([String])
    case commandFailed(arguments: [String], exitCode: Int32, standardError: String)

    var userMessage: String {
        switch self {
        case .projectWorkspaceRequired(let projectID):
            return "Project \(projectID) must have an approved workspace directory before preparing a PR workflow."
        case .projectWorkspaceMustBeAbsolute:
            return "Project workspace must be an absolute directory."
        case .projectWorkspaceUnavailable:
            return "Project workspace directory is unavailable."
        case .projectWorkspaceIsSymlink:
            return "Project workspace must not be a symlink."
        case .projectWorkspaceBookmarkUnavailable:
            return "Project workspace access bookmark could not be resolved and must be renewed."
        case .projectWorkspaceBookmarkStale:
            return "Project workspace access bookmark is stale and must be renewed."
        case .projectWorkspaceBookmarkPathMismatch:
            return "Project workspace access bookmark does not match the approved workspace directory."
        case .invalidBranchName:
            return "Branch name contains characters outside the safe GitHub Flow subset."
        case .commandNotAllowed:
            return "Git command is not allowed for development PR workflow preparation."
        case .commandFailed(let arguments, let exitCode, let standardError):
            let command = (["git"] + arguments).joined(separator: " ")
            let suffix = standardError.isEmpty ? "" : " stderr: \(standardError)"
            return "\(command) failed with exit code \(exitCode).\(suffix)"
        }
    }
}

public struct ProjectWorkspaceBookmarkResolution: Sendable {
    public var url: URL
    public var isStale: Bool
    public var didStartAccessing: Bool

    private let stopAccessing: (@Sendable () -> Void)?

    public init(
        url: URL,
        isStale: Bool,
        didStartAccessing: Bool,
        stopAccessing: (@Sendable () -> Void)? = nil
    ) {
        self.url = url
        self.isStale = isStale
        self.didStartAccessing = didStartAccessing
        self.stopAccessing = stopAccessing
    }

    fileprivate func makeLease() -> ProjectWorkspaceBookmarkAccessLease? {
        guard didStartAccessing, let stopAccessing else {
            return nil
        }
        return ProjectWorkspaceBookmarkAccessLease(stopAccessing: stopAccessing)
    }
}

public protocol ProjectWorkspaceBookmarkResolving: Sendable {
    func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution
}

public struct SecurityScopedProjectWorkspaceBookmarkResolver: ProjectWorkspaceBookmarkResolving {
    public init() {}

    public func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution {
        var isStale = false
        let workspaceURL: URL
        do {
            workspaceURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkUnavailable
        }

        guard !isStale else {
            throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkStale
        }

        let didStartAccessing = workspaceURL.startAccessingSecurityScopedResource()
        guard didStartAccessing else {
            throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkUnavailable
        }
        return ProjectWorkspaceBookmarkResolution(
            url: workspaceURL,
            isStale: isStale,
            didStartAccessing: didStartAccessing,
            stopAccessing: { workspaceURL.stopAccessingSecurityScopedResource() }
        )
    }
}

private final class ProjectWorkspaceBookmarkAccessLease: @unchecked Sendable {
    private let lock = NSLock()
    private let stopAccessing: @Sendable () -> Void
    private var didStop = false

    init(stopAccessing: @escaping @Sendable () -> Void) {
        self.stopAccessing = stopAccessing
    }

    deinit {
        stop()
    }

    func stop() {
        lock.lock()
        let shouldStop = !didStop
        didStop = true
        lock.unlock()

        if shouldStop {
            stopAccessing()
        }
    }
}

public struct ProjectWorkspaceScope: Equatable, Sendable {
    public let rootURL: URL
    private let bookmarkAccessLease: ProjectWorkspaceBookmarkAccessLease?

    public init(
        project: ProjectRecord,
        fileManager: FileManager = .default,
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver(),
        requireBookmark: Bool = false
    ) throws {
        guard let workspacePath = project.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workspacePath.isEmpty else {
            throw DevelopmentPRWorkflowError.projectWorkspaceRequired(project.id)
        }
        guard workspacePath.hasPrefix("/") else {
            throw DevelopmentPRWorkflowError.projectWorkspaceMustBeAbsolute
        }

        let selectedURL = URL(fileURLWithPath: workspacePath, isDirectory: true).standardizedFileURL

        if let bookmarkData = project.workspaceBookmarkData {
            guard !bookmarkData.isEmpty else {
                throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkUnavailable
            }
            let resolution = try bookmarkResolver.resolve(bookmarkData: bookmarkData)
            let lease = resolution.makeLease()
            // A stored bookmark is the user's durable approval for this
            // workspace. Once it exists, falling back to the raw path would let
            // background developer automation outlive revoked or stale access.
            do {
                guard !resolution.isStale else {
                    throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkStale
                }
                guard let activeLease = lease else {
                    throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkUnavailable
                }

                let selectedRootURL = try Self.validatedExistingRoot(
                    selectedURL: selectedURL,
                    workspacePath: workspacePath,
                    fileManager: fileManager
                )
                let resolvedBookmarkURL = resolution.url.resolvingSymlinksInPath().standardizedFileURL
                guard resolvedBookmarkURL.path == selectedRootURL.path else {
                    throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkPathMismatch
                }

                rootURL = resolvedBookmarkURL
                bookmarkAccessLease = activeLease
            } catch {
                lease?.stop()
                throw error
            }
        } else {
            guard !requireBookmark else {
                // External PR automation must prove the user approved the project
                // directory; a stored path alone is not enough authority to read,
                // publish, review, or merge repository state.
                throw DevelopmentPRWorkflowError.projectWorkspaceBookmarkUnavailable
            }
            rootURL = try Self.validatedExistingRoot(
                selectedURL: selectedURL,
                workspacePath: workspacePath,
                fileManager: fileManager
            )
            bookmarkAccessLease = nil
        }
    }

    public static func == (lhs: ProjectWorkspaceScope, rhs: ProjectWorkspaceScope) -> Bool {
        lhs.rootURL == rhs.rootURL
    }

    private static func validatedExistingRoot(
        selectedURL: URL,
        workspacePath: String,
        fileManager: FileManager
    ) throws -> URL {
        let resourceValues = try? selectedURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard resourceValues?.isSymbolicLink != true else {
            throw DevelopmentPRWorkflowError.projectWorkspaceIsSymlink
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DevelopmentPRWorkflowError.projectWorkspaceUnavailable(workspacePath)
        }

        return selectedURL.resolvingSymlinksInPath().standardizedFileURL
    }
}

public enum DevelopmentBranchNamePolicy {
    public static func deterministicBranchName(project: ProjectRecord, task: TaskRecord?) -> String {
        let title = task?.title ?? project.title
        let slug = asciiSlug(title)
        if let task {
            return "feature/solopm-\(project.id)-\(task.id)-\(slug)"
        }
        return "feature/solopm-\(project.id)-\(slug)"
    }

    public static func validated(_ value: String) throws -> String {
        let branch = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty,
              branch.count <= 120,
              branch.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]*[A-Za-z0-9]$"#, options: .regularExpression) != nil,
              !branch.contains(".."),
              !branch.contains("//"),
              !branch.contains("@{"),
              !branch.hasSuffix(".lock"),
              !branch.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw DevelopmentPRWorkflowError.invalidBranchName(value)
        }
        return branch
    }

    private static func asciiSlug(_ value: String) -> String {
        let lowercased = value.lowercased()
        var characters: [Character] = []
        var previousWasDash = false

        for scalar in lowercased.unicodeScalars {
            let isLetter = ("a"..."z").contains(Character(scalar))
            let isDigit = ("0"..."9").contains(Character(scalar))
            if isLetter || isDigit {
                characters.append(Character(scalar))
                previousWasDash = false
            } else if !previousWasDash {
                characters.append("-")
                previousWasDash = true
            }
        }

        let slug = String(characters).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "task" : String(slug.prefix(48))
    }
}

public enum DevelopmentGitCommandPolicy {
    public static func isAllowed(arguments: [String]) -> Bool {
        guard !arguments.isEmpty else {
            return false
        }

        if arguments == ["status", "--short", "--branch"] || arguments == ["diff", "--stat"] {
            return true
        }

        guard arguments.count == 3, arguments[0] == "switch", arguments[1] == "-c" else {
            return false
        }
        return (try? DevelopmentBranchNamePolicy.validated(arguments[2])) != nil
    }
}

public struct DevelopmentPRWorkflowTool: Tool {
    public let name: ActionTool = .developmentPreparePullRequestWorkflow
    public let description: String = "Prepare an approval-gated local branch for a development pull request workflow."
    public let inputSchema = ToolInputSchema(
        required: ["projectId"],
        properties: [
            "projectId": "integer",
            "taskId": "integer",
            "branchName": "string"
        ],
        nonBlank: ["branchName"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore?
    private let gitRunner: any GitCommandRunner
    private let bookmarkResolver: any ProjectWorkspaceBookmarkResolving
    private let requireBookmark: Bool
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore? = nil,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver(),
        requireBookmark: Bool = false,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.gitRunner = gitRunner
        self.bookmarkResolver = bookmarkResolver
        self.requireBookmark = requireBookmark
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")
        let taskID = try args.optionalInt64("taskId")

        do {
            let project = try projectStore.get(id: projectID)
            let task = try taskID.map { id -> TaskRecord in
                guard let taskStore else {
                    throw ToolExecutionError.executionFailed(name, "Task store is required when taskId is provided.")
                }
                return try taskStore.get(id: id)
            }
            let scope = try ProjectWorkspaceScope(
                project: project,
                bookmarkResolver: bookmarkResolver,
                requireBookmark: requireBookmark
            )
            let branchName = try DevelopmentBranchNamePolicy.validated(
                try args.optionalTrimmedString("branchName")
                    ?? DevelopmentBranchNamePolicy.deterministicBranchName(project: project, task: task)
            )

            return try withExtendedLifetime(scope) {
                // Push and PR creation intentionally stay preview-only here. They are
                // external writes and must get a separate review gate after the user
                // sees the local branch, status, and diff preview in the receipt.
                let externalWritePreview = "git push -u origin \(branchName) && gh pr create --fill"
                var output: [String: JSONValue] = [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName),
                    "workspacePath": .string(scope.rootURL.path),
                    "requiresPushApproval": .bool(true),
                    "requiresPullRequestApproval": .bool(true),
                    "externalWritePreview": .string(externalWritePreview)
                ]
                if let task {
                    output["taskId"] = .number(Double(task.id))
                }

                _ = try runGit(arguments: ["switch", "-c", branchName], workingDirectory: scope.rootURL)
                do {
                    let status = try runGit(arguments: ["status", "--short", "--branch"], workingDirectory: scope.rootURL)
                    output["status"] = .string(redacted(status.standardOutput))
                    let diff = try runGit(arguments: ["diff", "--stat"], workingDirectory: scope.rootURL)
                    output["diffStat"] = .string(redacted(diff.standardOutput))
                } catch {
                    output["gitEvidenceError"] = .string(redacted(developmentPRWorkflowErrorMessage(for: error)))
                    return ToolResult(
                        tool: name,
                        status: .failed,
                        summary: "Prepared local development branch \(branchName), but could not capture git evidence. Push and PR creation require a separate approval gate.",
                        output: output,
                        rollbackMetadata: ["branchName": .string(branchName)],
                        compensationHint: "Review the local branch manually before any push or PR creation."
                    )
                }

                return ToolResult(
                    tool: name,
                    status: .succeeded,
                    summary: "Prepared local development branch \(branchName). Push and PR creation require a separate approval gate.",
                    output: output,
                    rollbackMetadata: ["branchName": .string(branchName)]
                )
            }
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        guard DevelopmentGitCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRWorkflowError.commandNotAllowed(arguments)
        }
        let output = try gitRunner.runGit(arguments: arguments, workingDirectory: workingDirectory)
        guard output.exitCode == 0 else {
            throw DevelopmentPRWorkflowError.commandFailed(
                arguments: arguments,
                exitCode: output.exitCode,
                standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }
        return output
    }

    private func redacted(_ value: String) -> String {
        redactor.redact(value).text
    }

    private func developmentPRWorkflowErrorMessage(for error: Error) -> String {
        if let error = error as? DevelopmentPRWorkflowError {
            return error.userMessage
        }
        if let error = error as? GitReadOnlyError {
            return String(describing: error)
        }
        return String(describing: error)
    }
}
