import Foundation

public enum DevelopmentPRWorkflowError: Error, Equatable, Sendable {
    case projectWorkspaceRequired(Int64)
    case projectWorkspaceMustBeAbsolute
    case projectWorkspaceUnavailable(String)
    case projectWorkspaceIsSymlink
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

public struct ProjectWorkspaceScope: Equatable, Sendable {
    public var rootURL: URL

    public init(project: ProjectRecord, fileManager: FileManager = .default) throws {
        guard let workspacePath = project.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workspacePath.isEmpty else {
            throw DevelopmentPRWorkflowError.projectWorkspaceRequired(project.id)
        }
        guard workspacePath.hasPrefix("/") else {
            throw DevelopmentPRWorkflowError.projectWorkspaceMustBeAbsolute
        }

        let selectedURL = URL(fileURLWithPath: workspacePath, isDirectory: true).standardizedFileURL
        let resourceValues = try? selectedURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard resourceValues?.isSymbolicLink != true else {
            throw DevelopmentPRWorkflowError.projectWorkspaceIsSymlink
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DevelopmentPRWorkflowError.projectWorkspaceUnavailable(workspacePath)
        }

        rootURL = selectedURL.resolvingSymlinksInPath()
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
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore? = nil,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.gitRunner = gitRunner
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
            let scope = try ProjectWorkspaceScope(project: project)
            let branchName = try DevelopmentBranchNamePolicy.validated(
                try args.optionalTrimmedString("branchName")
                    ?? DevelopmentBranchNamePolicy.deterministicBranchName(project: project, task: task)
            )

            _ = try runGit(arguments: ["switch", "-c", branchName], workingDirectory: scope.rootURL)
            let status = try runGit(arguments: ["status", "--short", "--branch"], workingDirectory: scope.rootURL)
            let diff = try runGit(arguments: ["diff", "--stat"], workingDirectory: scope.rootURL)

            // Push and PR creation intentionally stay preview-only here. They are
            // external writes and must get a separate review gate after the user
            // sees the local branch, status, and diff preview in the receipt.
            let externalWritePreview = "git push -u origin \(branchName) && gh pr create --fill"

            var output: [String: JSONValue] = [
                "projectId": .number(Double(project.id)),
                "branchName": .string(branchName),
                "workspacePath": .string(scope.rootURL.path),
                "status": .string(redacted(status.standardOutput)),
                "diffStat": .string(redacted(diff.standardOutput)),
                "requiresPushApproval": .bool(true),
                "requiresPullRequestApproval": .bool(true),
                "externalWritePreview": .string(externalWritePreview)
            ]
            if let task {
                output["taskId"] = .number(Double(task.id))
            }

            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Prepared local development branch \(branchName). Push and PR creation require a separate approval gate.",
                output: output,
                rollbackMetadata: ["branchName": .string(branchName)]
            )
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
}
