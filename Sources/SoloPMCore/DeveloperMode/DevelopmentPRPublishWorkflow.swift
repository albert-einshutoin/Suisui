import Foundation

public struct GitHubCLICommandInvocation: Equatable, Sendable {
    public var arguments: [String]
    public var workingDirectory: URL

    public init(arguments: [String], workingDirectory: URL) {
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct GitHubCLICommandOutput: Equatable, Sendable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

public protocol GitHubCLICommandRunner: Sendable {
    func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput
}

public struct ProcessGitHubCLICommandRunner: GitHubCLICommandRunner {
    public init() {}

    public func runGitHub(arguments: [String], workingDirectory: URL) throws -> GitHubCLICommandOutput {
        #if os(iOS) || targetEnvironment(macCatalyst)
        throw DevelopmentPRPublishWorkflowError.commandFailed(
            tool: .developmentCreatePullRequest,
            command: ["gh"] + arguments,
            exitCode: 127,
            standardError: "GitHub CLI execution is available only on macOS."
        )
        #else
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        ]

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return GitHubCLICommandOutput(
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
        #endif
    }
}

public enum DevelopmentPRPublishWorkflowError: Error, Equatable, Sendable {
    case unexpectedBranch(expected: String, actual: String?)
    case dirtyWorkspace(changedPathCount: Int)
    case invalidPullRequestTitle
    case invalidPullRequestBody
    case secretLikePullRequestContent
    case missingPullRequestURL
    case commandNotAllowed(tool: ActionTool, command: [String])
    case commandFailed(tool: ActionTool, command: [String], exitCode: Int32, standardError: String)

    var userMessage: String {
        switch self {
        case .unexpectedBranch(let expected, let actual):
            return "Expected current branch \(expected), but found \(actual ?? "(unknown)")."
        case .dirtyWorkspace(let changedPathCount):
            return "Workspace has \(changedPathCount) changed path(s); push and PR creation require a clean reviewed commit."
        case .invalidPullRequestTitle:
            return "Pull request title must be non-blank, single-line text under 200 characters."
        case .invalidPullRequestBody:
            return "Pull request body must be non-blank UTF-8 text under 20000 bytes."
        case .secretLikePullRequestContent:
            return "Pull request title or body looks like it contains credentials or secrets."
        case .missingPullRequestURL:
            return "GitHub CLI did not return a pull request URL."
        case .commandNotAllowed:
            return "Command is not allowed for development publish workflow."
        case .commandFailed(let tool, let command, let exitCode, let standardError):
            let suffix = standardError.isEmpty ? "" : " stderr: \(standardError)"
            if tool == .developmentCreatePullRequest {
                return "GitHub CLI pull request creation failed with exit code \(exitCode).\(suffix)"
            }
            return "\((["git"] + command).joined(separator: " ")) failed with exit code \(exitCode).\(suffix)"
        }
    }
}

public enum DevelopmentPublishGitCommandPolicy {
    public static func isAllowed(arguments: [String]) -> Bool {
        if arguments == ["status", "--short", "--branch"] {
            return true
        }

        guard arguments.count == 4,
              arguments[0] == "push",
              arguments[1] == "-u",
              arguments[2] == "origin" else {
            return false
        }
        return (try? DevelopmentBranchNamePolicy.validated(arguments[3])) != nil
    }
}

public enum DevelopmentGitHubPRCommandPolicy {
    public static func isAllowed(arguments: [String]) -> Bool {
        guard arguments.count == 10,
              arguments[0] == "pr",
              arguments[1] == "create",
              arguments[2] == "--base",
              arguments[4] == "--head",
              arguments[6] == "--title",
              arguments[8] == "--body-file" else {
            return false
        }

        guard (try? DevelopmentBranchNamePolicy.validated(arguments[3])) != nil,
              (try? DevelopmentBranchNamePolicy.validated(arguments[5])) != nil,
              isValidPullRequestTitle(arguments[7]) else {
            return false
        }

        let bodyFilePath = arguments[9]
        return bodyFilePath.hasPrefix("/")
            && !bodyFilePath.contains("\u{0}")
            && !URL(fileURLWithPath: bodyFilePath).lastPathComponent.hasPrefix("-")
    }

    public static func validatedPullRequestTitle(
        _ rawTitle: String,
        redactor: DeveloperSecretRedactor
    ) throws -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPullRequestTitle(title) else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestTitle
        }
        guard redactor.redact(title).report.replacementCount == 0 else {
            throw DevelopmentPRPublishWorkflowError.secretLikePullRequestContent
        }
        return title
    }

    public static func validatedPullRequestBody(
        _ rawBody: String,
        redactor: DeveloperSecretRedactor
    ) throws -> String {
        guard !rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Data(rawBody.utf8).count <= 20_000,
              !rawBody.contains("\u{0}") else {
            throw DevelopmentPRPublishWorkflowError.invalidPullRequestBody
        }
        guard redactor.redact(rawBody).report.replacementCount == 0 else {
            throw DevelopmentPRPublishWorkflowError.secretLikePullRequestContent
        }
        return rawBody
    }

    private static func isValidPullRequestTitle(_ title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 200
            && !title.contains("\u{0}")
            && !title.contains("\n")
            && !title.contains("\r")
    }
}

public struct DevelopmentPushWorkflowTool: Tool {
    public let name: ActionTool = .developmentPushBranch
    public let description: String = "Push a reviewed development branch to origin after explicit approval."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "branchName"],
        properties: [
            "projectId": "integer",
            "branchName": "string"
        ],
        nonBlank: ["branchName"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let projectStore: SQLiteProjectStore
    private let gitRunner: any GitCommandRunner
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.projectStore = projectStore
        self.gitRunner = gitRunner
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")

        do {
            let project = try projectStore.get(id: projectID)
            let scope = try ProjectWorkspaceScope(project: project)
            let branchName = try DevelopmentBranchNamePolicy.validated(args.requiredTrimmedString("branchName"))

            let readiness = try workspacePublishReadiness(branchName: branchName, scope: scope)
            guard readiness.isReady else {
                return failedReadinessResult(projectID: project.id, branchName: branchName, readiness: readiness)
            }

            let push = try runGit(arguments: ["push", "-u", "origin", branchName], workingDirectory: scope.rootURL)
            guard push.exitCode == 0 else {
                return failedCommandResult(
                    projectID: project.id,
                    branchName: branchName,
                    error: .commandFailed(
                        tool: name,
                        command: ["push", "-u", "origin", branchName],
                        exitCode: push.exitCode,
                        standardError: redacted(push.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                    )
                )
            }

            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Pushed development branch \(branchName). Pull request creation requires a separate approval gate.",
                output: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName),
                    "remoteName": .string("origin"),
                    "workspaceClean": .bool(true),
                    "pushSummary": .string(redacted(push.standardOutput)),
                    "requiresPullRequestApproval": .bool(true)
                ],
                rollbackMetadata: ["branchName": .string(branchName)],
                compensationHint: "Review the pushed branch before creating a pull request."
            )
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRPublishWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func failedReadinessResult(
        projectID: Int64,
        branchName: String,
        readiness: DevelopmentPublishReadiness
    ) -> ToolResult {
        ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(readiness.failureMessage ?? "Workspace is not ready for push."),
            output: readiness.output(projectID: projectID, branchName: branchName),
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Commit or resolve local changes, then request push approval again."
        )
    }

    private func failedCommandResult(
        projectID: Int64,
        branchName: String,
        error: DevelopmentPRPublishWorkflowError
    ) -> ToolResult {
        ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(error.userMessage),
            output: [
                "projectId": .number(Double(projectID)),
                "branchName": .string(branchName),
                "remoteName": .string("origin"),
                "workspaceClean": .bool(true),
                "publishError": .string(redacted(error.userMessage))
            ],
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Inspect the branch and retry push after fixing the Git error."
        )
    }

    private func workspacePublishReadiness(branchName: String, scope: ProjectWorkspaceScope) throws -> DevelopmentPublishReadiness {
        let output = try runGit(arguments: ["status", "--short", "--branch"], workingDirectory: scope.rootURL)
        guard output.exitCode == 0 else {
            return DevelopmentPublishReadiness(
                currentBranch: nil,
                isClean: false,
                changedPathCount: nil,
                failureMessage: redacted(DevelopmentPRPublishWorkflowError.commandFailed(
                    tool: name,
                    command: ["status", "--short", "--branch"],
                    exitCode: output.exitCode,
                    standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                ).userMessage)
            )
        }

        let status = GitStatusSummary.parse(output.standardOutput)
        if status.branch != branchName {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: status.isClean,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.unexpectedBranch(
                    expected: branchName,
                    actual: status.branch
                ).userMessage
            )
        }
        guard status.isClean else {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: false,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.dirtyWorkspace(
                    changedPathCount: status.entries.count
                ).userMessage
            )
        }
        return DevelopmentPublishReadiness(
            currentBranch: status.branch,
            isClean: true,
            changedPathCount: 0,
            failureMessage: nil
        )
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        guard DevelopmentPublishGitCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: name, command: arguments)
        }
        return try gitRunner.runGit(arguments: arguments, workingDirectory: workingDirectory)
    }

    private func redacted(_ value: String) -> String {
        LocalPathRedactor.redact(redactor.redact(value).text)
    }
}

public struct DevelopmentPullRequestCreationTool: Tool {
    public let name: ActionTool = .developmentCreatePullRequest
    public let description: String = "Create a GitHub pull request for a reviewed pushed branch after explicit approval."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "branchName", "baseBranch", "title", "body"],
        properties: [
            "projectId": "integer",
            "branchName": "string",
            "baseBranch": "string",
            "title": "string",
            "body": "string"
        ],
        nonBlank: ["branchName", "baseBranch", "title", "body"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let projectStore: SQLiteProjectStore
    private let gitRunner: any GitCommandRunner
    private let githubRunner: any GitHubCLICommandRunner
    private let redactor: DeveloperSecretRedactor

    public init(
        projectStore: SQLiteProjectStore,
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        githubRunner: any GitHubCLICommandRunner = ProcessGitHubCLICommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.projectStore = projectStore
        self.gitRunner = gitRunner
        self.githubRunner = githubRunner
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")

        do {
            let branchName = try DevelopmentBranchNamePolicy.validated(args.requiredTrimmedString("branchName"))
            let baseBranch = try DevelopmentBranchNamePolicy.validated(args.requiredTrimmedString("baseBranch"))
            let title = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestTitle(
                args.requiredString("title"),
                redactor: redactor
            )
            let body = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestBody(
                args.requiredString("body"),
                redactor: redactor
            )
            let project = try projectStore.get(id: projectID)
            let scope = try ProjectWorkspaceScope(project: project)

            let readiness = try workspacePublishReadiness(branchName: branchName, scope: scope)
            guard readiness.isReady else {
                return failedReadinessResult(
                    projectID: project.id,
                    branchName: branchName,
                    baseBranch: baseBranch,
                    readiness: readiness
                )
            }

            let fileManager = FileManager.default
            let bodyFileURL = fileManager.temporaryDirectory
                .appendingPathComponent("solopm-pr-body-\(UUID().uuidString).md")
            try body.write(to: bodyFileURL, atomically: true, encoding: .utf8)
            defer { try? fileManager.removeItem(at: bodyFileURL) }

            // Use --body-file so reviewed PR text never becomes shell-interpreted
            // or logged as an inline command argument by process tooling.
            let githubArguments = [
                "pr", "create",
                "--base", baseBranch,
                "--head", branchName,
                "--title", title,
                "--body-file", bodyFileURL.path
            ]
            guard DevelopmentGitHubPRCommandPolicy.isAllowed(arguments: githubArguments) else {
                throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: name, command: githubArguments)
            }

            let output = try githubRunner.runGitHub(arguments: githubArguments, workingDirectory: scope.rootURL)
            guard output.exitCode == 0 else {
                return failedCommandResult(
                    projectID: project.id,
                    branchName: branchName,
                    baseBranch: baseBranch,
                    error: .commandFailed(
                        tool: name,
                        command: githubArguments,
                        exitCode: output.exitCode,
                        standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                    )
                )
            }

            guard let pullRequestURL = pullRequestURL(from: output.standardOutput) else {
                return failedCommandResult(
                    projectID: project.id,
                    branchName: branchName,
                    baseBranch: baseBranch,
                    error: .missingPullRequestURL
                )
            }

            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Created pull request \(pullRequestURL) from \(branchName) into \(baseBranch).",
                output: [
                    "projectId": .number(Double(project.id)),
                    "branchName": .string(branchName),
                    "baseBranch": .string(baseBranch),
                    "title": .string(title),
                    "pullRequestURL": .string(pullRequestURL),
                    "workspaceClean": .bool(true)
                ],
                rollbackMetadata: [
                    "branchName": .string(branchName),
                    "pullRequestURL": .string(pullRequestURL)
                ],
                compensationHint: "Review CI and code review status before merging the pull request."
            )
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRPublishWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as GitReadOnlyError {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func failedReadinessResult(
        projectID: Int64,
        branchName: String,
        baseBranch: String,
        readiness: DevelopmentPublishReadiness
    ) -> ToolResult {
        var output = readiness.output(projectID: projectID, branchName: branchName)
        output["baseBranch"] = .string(baseBranch)
        return ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(readiness.failureMessage ?? "Workspace is not ready for pull request creation."),
            output: output,
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Confirm the pushed branch and clean workspace, then request PR creation approval again."
        )
    }

    private func failedCommandResult(
        projectID: Int64,
        branchName: String,
        baseBranch: String,
        error: DevelopmentPRPublishWorkflowError
    ) -> ToolResult {
        ToolResult(
            tool: name,
            status: .failed,
            summary: redacted(error.userMessage),
            output: [
                "projectId": .number(Double(projectID)),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch),
                "workspaceClean": .bool(true),
                "publishError": .string(redacted(error.userMessage))
            ],
            rollbackMetadata: ["branchName": .string(branchName)],
            compensationHint: "Inspect the GitHub CLI result and retry PR creation after fixing the error."
        )
    }

    private func workspacePublishReadiness(branchName: String, scope: ProjectWorkspaceScope) throws -> DevelopmentPublishReadiness {
        let output = try runGit(arguments: ["status", "--short", "--branch"], workingDirectory: scope.rootURL)
        guard output.exitCode == 0 else {
            return DevelopmentPublishReadiness(
                currentBranch: nil,
                isClean: false,
                changedPathCount: nil,
                failureMessage: redacted(DevelopmentPRPublishWorkflowError.commandFailed(
                    tool: name,
                    command: ["status", "--short", "--branch"],
                    exitCode: output.exitCode,
                    standardError: redacted(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                ).userMessage)
            )
        }

        let status = GitStatusSummary.parse(output.standardOutput)
        if status.branch != branchName {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: status.isClean,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.unexpectedBranch(
                    expected: branchName,
                    actual: status.branch
                ).userMessage
            )
        }
        guard status.isClean else {
            return DevelopmentPublishReadiness(
                currentBranch: status.branch,
                isClean: false,
                changedPathCount: status.entries.count,
                failureMessage: DevelopmentPRPublishWorkflowError.dirtyWorkspace(
                    changedPathCount: status.entries.count
                ).userMessage
            )
        }
        return DevelopmentPublishReadiness(
            currentBranch: status.branch,
            isClean: true,
            changedPathCount: 0,
            failureMessage: nil
        )
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        guard DevelopmentPublishGitCommandPolicy.isAllowed(arguments: arguments) else {
            throw DevelopmentPRPublishWorkflowError.commandNotAllowed(tool: name, command: arguments)
        }
        return try gitRunner.runGit(arguments: arguments, workingDirectory: workingDirectory)
    }

    private func pullRequestURL(from standardOutput: String) -> String? {
        standardOutput
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .first { token in
                token.hasPrefix("https://") && token.contains("/pull/")
            }
    }

    private func redacted(_ value: String) -> String {
        LocalPathRedactor.redact(redactor.redact(value).text)
    }
}

private struct DevelopmentPublishReadiness: Equatable, Sendable {
    var currentBranch: String?
    var isClean: Bool
    var changedPathCount: Int?
    var failureMessage: String?

    var isReady: Bool {
        failureMessage == nil && isClean
    }

    func output(projectID: Int64, branchName: String) -> [String: JSONValue] {
        var output: [String: JSONValue] = [
            "projectId": .number(Double(projectID)),
            "branchName": .string(branchName),
            "workspaceClean": .bool(isClean)
        ]
        if let currentBranch {
            output["currentBranch"] = .string(currentBranch)
        }
        if let changedPathCount {
            output["changedPathCount"] = .number(Double(changedPathCount))
        }
        if let failureMessage {
            output["publishError"] = .string(failureMessage)
        }
        return output
    }
}
