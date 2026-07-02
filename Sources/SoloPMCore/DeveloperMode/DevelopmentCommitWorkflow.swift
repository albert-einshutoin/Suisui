import Foundation

public enum DevelopmentCommitWorkflowError: Error, Equatable, Sendable {
    case noRelativePaths
    case invalidCommitMessage
    case secretLikeCommitMessage
    case preexistingStagedChanges
    case stagedChangesMismatch
    case commandNotAllowed([String])
    case commandFailed(arguments: [String], exitCode: Int32, standardError: String)

    var userMessage: String {
        switch self {
        case .noRelativePaths:
            return "Commit workflow requires at least one approved repository file path."
        case .invalidCommitMessage:
            return "Commit message must be non-blank, single-line text under 200 characters."
        case .secretLikeCommitMessage:
            return "Commit message looks like it contains credentials or secrets."
        case .preexistingStagedChanges:
            return "Git index already contains staged changes outside the approved file list."
        case .stagedChangesMismatch:
            return "Git staged changes did not match the approved file list."
        case .commandNotAllowed:
            return "Git command is not allowed for development commit workflow."
        case .commandFailed(let arguments, let exitCode, let standardError):
            let command = (["git"] + arguments).joined(separator: " ")
            let suffix = standardError.isEmpty ? "" : " stderr: \(standardError)"
            return "\(command) failed with exit code \(exitCode).\(suffix)"
        }
    }
}

public enum DevelopmentCommitGitCommandPolicy {
    public static func isAllowed(arguments: [String]) -> Bool {
        guard !arguments.isEmpty else {
            return false
        }

        if arguments == ["status", "--short", "--branch"] {
            return true
        }

        if arguments == ["diff", "--cached", "--name-only", "-z"] {
            return true
        }

        if arguments.count >= 3, arguments[0] == "add", arguments[1] == "--" {
            return arguments.dropFirst(2).allSatisfy { path in
                (try? DevelopmentRepositoryFilePathPolicy.validatedRelativePath(path)) != nil
            }
        }

        guard arguments.count == 5,
              arguments[0] == "-c",
              arguments[1] == "core.hooksPath=/dev/null",
              arguments[2] == "commit",
              arguments[3] == "-m" else {
            return false
        }
        return isValidCommitMessage(arguments[4])
    }

    static func validatedCommitMessage(_ rawMessage: String, redactor: DeveloperSecretRedactor) throws -> String {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidCommitMessage(message) else {
            throw DevelopmentCommitWorkflowError.invalidCommitMessage
        }
        guard redactor.redact(message).report.replacementCount == 0 else {
            throw DevelopmentCommitWorkflowError.secretLikeCommitMessage
        }
        return message
    }

    private static func isValidCommitMessage(_ message: String) -> Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && message.count <= 200
            && !message.contains("\u{0}")
            && !message.contains("\n")
            && !message.contains("\r")
    }
}

public struct DevelopmentCommitWorkflowTool: Tool {
    public let name: ActionTool = .developmentCommitChanges
    public let description: String = "Create a local commit from approved text-file changes inside an approved project workspace."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "relativePaths", "commitMessage"],
        properties: [
            "projectId": "integer",
            "taskId": "integer",
            "relativePaths": "array",
            "commitMessage": "string"
        ],
        nonBlank: ["commitMessage"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let projectStore: SQLiteProjectStore
    private let gitRunner: any GitCommandRunner
    private let bookmarkResolver: any ProjectWorkspaceBookmarkResolving
    private let requireBookmark: Bool
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver(),
        requireBookmark: Bool = false,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.projectStore = projectStore
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

        do {
            let project = try projectStore.get(id: projectID)
            let scope = try ProjectWorkspaceScope(
                project: project,
                bookmarkResolver: bookmarkResolver,
                requireBookmark: requireBookmark
            )
            let relativePaths = try validatedRelativePaths(args.trimmedStringArray("relativePaths"), project: project)
            let commitMessage = try DevelopmentCommitGitCommandPolicy.validatedCommitMessage(
                args.requiredString("commitMessage"),
                redactor: redactor
            )

            return try withExtendedLifetime(scope) {
                let preexistingStagedPaths = try stagedRelativePaths(workingDirectory: scope.rootURL)
                guard preexistingStagedPaths.isEmpty else {
                    throw DevelopmentCommitWorkflowError.preexistingStagedChanges
                }

                // The commit gate stages only the reviewed file list. This keeps the
                // assistant from sweeping unrelated user edits into a local commit.
                _ = try runGit(arguments: ["add", "--"] + relativePaths, workingDirectory: scope.rootURL)

                let stagedPaths = try stagedRelativePaths(workingDirectory: scope.rootURL)
                guard Set(stagedPaths) == Set(relativePaths) else {
                    throw DevelopmentCommitWorkflowError.stagedChangesMismatch
                }

                // Repository hooks are arbitrary local code. Verification has its own
                // approved command gate, so this commit step records the reviewed diff
                // without silently running hook scripts.
                let commit = try runGit(
                    arguments: ["-c", "core.hooksPath=/dev/null", "commit", "-m", commitMessage],
                    workingDirectory: scope.rootURL
                )
                let status = try runGit(arguments: ["status", "--short", "--branch"], workingDirectory: scope.rootURL)

                let externalWritePreview = "git push -u origin HEAD && gh pr create --fill"
                return ToolResult(
                    tool: name,
                    status: .succeeded,
                    summary: "Created a local development commit. Push and PR creation require a separate approval gate.",
                    output: [
                        "projectId": .number(Double(project.id)),
                        "workspacePath": .string(scope.rootURL.path),
                        "relativePaths": JSONValueFactory.strings(relativePaths),
                        "commitMessage": .string(commitMessage),
                        "commitSummary": .string(redacted(commit.standardOutput)),
                        "status": .string(redacted(status.standardOutput)),
                        "requiresPushApproval": .bool(true),
                        "requiresPullRequestApproval": .bool(true),
                        "externalWritePreview": .string(externalWritePreview)
                    ],
                    rollbackMetadata: [
                        "relativePaths": JSONValueFactory.strings(relativePaths),
                        "commitMessage": .string(commitMessage)
                    ],
                    compensationHint: "Review the local commit manually before any push or PR creation."
                )
            }
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentRepositoryFileError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentCommitWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func validatedRelativePaths(_ rawPaths: [String], project: ProjectRecord) throws -> [String] {
        guard !rawPaths.isEmpty else {
            throw DevelopmentCommitWorkflowError.noRelativePaths
        }

        let fileClient = DevelopmentRepositoryFileClient(
            project: project,
            redactor: redactor,
            bookmarkResolver: bookmarkResolver,
            requireBookmark: requireBookmark
        )
        var seen: Set<String> = []
        var relativePaths: [String] = []
        for rawPath in rawPaths {
            let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
            guard seen.insert(relativePath).inserted else {
                continue
            }
            _ = try fileClient.read(relativePath: relativePath)
            relativePaths.append(relativePath)
        }

        guard !relativePaths.isEmpty else {
            throw DevelopmentCommitWorkflowError.noRelativePaths
        }
        return relativePaths
    }

    private func stagedRelativePaths(workingDirectory: URL) throws -> [String] {
        let output = try runGit(
            arguments: ["diff", "--cached", "--name-only", "-z"],
            workingDirectory: workingDirectory
        )
        return output.standardOutput
            .split(separator: "\u{0}", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        guard DevelopmentCommitGitCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentCommitWorkflowError.commandNotAllowed(arguments)
        }
        let output = try gitRunner.runGit(arguments: arguments, workingDirectory: workingDirectory)
        guard output.exitCode == 0 else {
            throw DevelopmentCommitWorkflowError.commandFailed(
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
