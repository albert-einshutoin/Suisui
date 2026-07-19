import Foundation

public struct DevelopmentCommandInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: URL

    public init(executable: String, arguments: [String], workingDirectory: URL) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    public var commandDisplay: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public struct DevelopmentCommandOutput: Equatable, Sendable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32
    public var timedOut: Bool
    public var durationMilliseconds: Int
    public var standardOutputTruncated: Bool
    public var standardErrorTruncated: Bool

    public init(
        standardOutput: String,
        standardError: String,
        exitCode: Int32,
        timedOut: Bool = false,
        durationMilliseconds: Int = 0,
        standardOutputTruncated: Bool = false,
        standardErrorTruncated: Bool = false
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.durationMilliseconds = durationMilliseconds
        self.standardOutputTruncated = standardOutputTruncated
        self.standardErrorTruncated = standardErrorTruncated
    }
}

public struct DevelopmentVerificationCommand: Equatable, Sendable {
    public var id: String
    public var executable: String
    public var arguments: [String]

    public init(id: String, executable: String, arguments: [String]) {
        self.id = id
        self.executable = executable
        self.arguments = arguments
    }

    public var commandDisplay: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public protocol DevelopmentCommandRunner: Sendable {
    func run(executable: String, arguments: [String], workingDirectory: URL) throws -> DevelopmentCommandOutput
}

public struct ProcessDevelopmentCommandRunner: DevelopmentCommandRunner {
    private let timeoutSeconds: TimeInterval
    private let outputCaptureLimitBytes: Int

    public init(timeoutSeconds: TimeInterval = 600, outputCaptureLimitBytes: Int = 128 * 1024) {
        self.timeoutSeconds = timeoutSeconds
        self.outputCaptureLimitBytes = outputCaptureLimitBytes
    }

    public func run(executable: String, arguments: [String], workingDirectory: URL) throws -> DevelopmentCommandOutput {
        #if os(iOS) || targetEnvironment(macCatalyst)
        throw DevelopmentVerificationCommandError.commandExecutionUnavailable("Local verification commands are available only on macOS.")
        #else
        let startedAt = Date()
        let process = Process()
        let standardOutput = DevelopmentCommandPipeCollector(maxBytes: outputCaptureLimitBytes)
        let standardError = DevelopmentCommandPipeCollector(maxBytes: outputCaptureLimitBytes)
        let tmpRoot = workingDirectory
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("suisui-verification", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeRoot = workingDirectory
            .appendingPathComponent(".tmp", isDirectory: true)
            .appendingPathComponent("suisui-home", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeRoot, withIntermediateDirectories: true)

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = workingDirectory
        // Verification commands execute repository code. Keep the child process
        // environment narrow so API/provider tokens from Suisui are not inherited.
        process.environment = [
            "HOME": homeRoot.path,
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": Self.commandSearchPath,
            "TMPDIR": tmpRoot.path
        ]
        process.standardOutput = standardOutput.pipe
        process.standardError = standardError.pipe

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        do {
            try process.run()
            standardOutput.closeWriting()
            standardError.closeWriting()
        } catch {
            standardOutput.close()
            standardError.close()
            throw error
        }

        let timeoutResult = terminationSemaphore.wait(timeout: .now() + timeoutSeconds)
        let timedOut = timeoutResult == .timedOut
        if timedOut {
            process.terminate()
            let terminateResult = terminationSemaphore.wait(timeout: .now() + 1)
            if terminateResult == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = terminationSemaphore.wait(timeout: .now() + 5)
            }
            standardOutput.closeReading()
            standardError.closeReading()
        }

        let stdout = standardOutput.finish()
        let stderr = standardError.finish()
        let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)

        return DevelopmentCommandOutput(
            standardOutput: stdout.text,
            standardError: stderr.text,
            exitCode: timedOut ? 124 : process.terminationStatus,
            timedOut: timedOut,
            durationMilliseconds: durationMilliseconds,
            standardOutputTruncated: stdout.truncated,
            standardErrorTruncated: stderr.truncated
        )
        #endif
    }

    private static let commandSearchPath = [
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin"
    ].joined(separator: ":")
}

private final class DevelopmentCommandPipeCollector: @unchecked Sendable {
    let pipe = Pipe()
    private let maxBytes: Int
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()
    private var isTruncated = false

    init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
        DispatchQueue.global(qos: .utility).async {
            self.readUntilEOF()
        }
    }

    func closeWriting() {
        try? pipe.fileHandleForWriting.close()
    }

    func closeReading() {
        try? pipe.fileHandleForReading.close()
    }

    func close() {
        closeWriting()
        closeReading()
    }

    func finish() -> (text: String, truncated: Bool) {
        _ = done.wait(timeout: .now() + 5)
        close()
        lock.lock()
        defer { lock.unlock() }
        return (
            String(data: data, encoding: .utf8) ?? "",
            isTruncated
        )
    }

    private func readUntilEOF() {
        defer {
            done.signal()
        }

        while true {
            do {
                guard let chunk = try pipe.fileHandleForReading.read(upToCount: 8 * 1024), !chunk.isEmpty else {
                    return
                }
                append(chunk)
            } catch {
                return
            }
        }
    }

    private func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }

        let remainingBytes = maxBytes - data.count
        guard remainingBytes > 0 else {
            isTruncated = true
            return
        }

        if chunk.count > remainingBytes {
            data.append(chunk.prefix(remainingBytes))
            isTruncated = true
        } else {
            data.append(chunk)
        }
    }
}

public enum DevelopmentVerificationCommandError: Error, Equatable, Sendable {
    case commandNotAllowed
    case commandExecutionUnavailable(String)
    case commandScriptUnavailable
    case commandScriptEscapesWorkspace
    case commandScriptSymlinkNotAllowed
    case commandScriptNotExecutable
    case currentBranchUnavailable
    case branchMismatch(expected: String, actual: String)

    public var userMessage: String {
        switch self {
        case .commandNotAllowed:
            return "Verification command is not in the approved local command allowlist."
        case .commandExecutionUnavailable(let reason):
            return reason
        case .commandScriptUnavailable:
            return "Verification command script is unavailable."
        case .commandScriptEscapesWorkspace:
            return "Verification command script must stay inside the approved project directory."
        case .commandScriptSymlinkNotAllowed:
            return "Verification command script must not contain symlink components."
        case .commandScriptNotExecutable:
            return "Verification command script is not executable."
        case .currentBranchUnavailable:
            return "Could not confirm the current repository branch before verification."
        case .branchMismatch(let expected, let actual):
            return "Repository branch mismatch before verification: expected \(expected), found \(actual)."
        }
    }
}

public enum DevelopmentVerificationCommandPolicy {
    public static func validated(commandID rawCommandID: String) throws -> DevelopmentVerificationCommand {
        let commandID = rawCommandID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandID.isEmpty,
              !commandID.contains("\u{0}"),
              let command = commands[commandID] else {
            throw DevelopmentVerificationCommandError.commandNotAllowed
        }
        return command
    }

    public static func resolvedExecutable(for command: DevelopmentVerificationCommand, scope: ProjectWorkspaceScope) throws -> String {
        guard command.executable.hasPrefix("./") else {
            return command.executable
        }

        let relativePath = String(command.executable.dropFirst(2))
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw DevelopmentVerificationCommandError.commandScriptEscapesWorkspace
        }

        let scriptURL = scope.rootURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        guard isInsideWorkspace(scriptURL, rootURL: scope.rootURL) else {
            throw DevelopmentVerificationCommandError.commandScriptEscapesWorkspace
        }
        try rejectSymlinkComponents(relativePath: relativePath, rootURL: scope.rootURL)

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw DevelopmentVerificationCommandError.commandScriptUnavailable
        }
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            throw DevelopmentVerificationCommandError.commandScriptNotExecutable
        }

        let resolvedScriptURL = scriptURL.resolvingSymlinksInPath().standardizedFileURL
        guard isInsideWorkspace(resolvedScriptURL, rootURL: scope.rootURL) else {
            throw DevelopmentVerificationCommandError.commandScriptEscapesWorkspace
        }
        return resolvedScriptURL.path
    }

    private static let commands: [String: DevelopmentVerificationCommand] = [
        "swift.test": DevelopmentVerificationCommand(
            id: "swift.test",
            executable: "swift",
            arguments: ["test", "--quiet"]
        ),
        "swift.test.app_experience_sources": DevelopmentVerificationCommand(
            id: "swift.test.app_experience_sources",
            executable: "swift",
            arguments: ["test", "--filter", "AppExperienceSourceTests", "--quiet"]
        ),
        "swift.test.quality_source_contract": DevelopmentVerificationCommand(
            id: "swift.test.quality_source_contract",
            executable: "swift",
            arguments: ["test", "--filter", "QualitySourceContractTests", "--quiet"]
        ),
        "swift.test.project_board_store": DevelopmentVerificationCommand(
            id: "swift.test.project_board_store",
            executable: "swift",
            arguments: ["test", "--filter", "ProjectBoardStoreTests", "--quiet"]
        ),
        "swift.build": DevelopmentVerificationCommand(
            id: "swift.build",
            executable: "swift",
            arguments: ["build"]
        ),
        "swift.build.suisui_cli": DevelopmentVerificationCommand(
            id: "swift.build.suisui_cli",
            executable: "swift",
            arguments: ["build", "--product", "suisui-cli"]
        ),
        "git.diff_check": DevelopmentVerificationCommand(
            id: "git.diff_check",
            executable: "git",
            arguments: ["diff", "--check"]
        ),
        "security.regression_scan": DevelopmentVerificationCommand(
            id: "security.regression_scan",
            executable: "./script/check_security_regressions.sh",
            arguments: []
        )
    ]

    private static func rejectSymlinkComponents(relativePath: String, rootURL: URL) throws {
        var current = rootURL
        for component in relativePath.split(separator: "/").map(String.init) {
            current = current.appendingPathComponent(component, isDirectory: false)
            guard FileManager.default.fileExists(atPath: current.path) else {
                throw DevelopmentVerificationCommandError.commandScriptUnavailable
            }
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw DevelopmentVerificationCommandError.commandScriptSymlinkNotAllowed
            }
        }
    }

    private static func isInsideWorkspace(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}

public enum DevelopmentVerificationOutputPolicy {
    public static let maximumOutputCharacters = 12_000

    public static func sanitize(_ value: String, redactor: DeveloperSecretRedactor) -> (text: String, truncated: Bool) {
        let redacted = redactor.redact(value).text
        guard redacted.count > maximumOutputCharacters else {
            return (redacted, false)
        }

        return (String(redacted.prefix(maximumOutputCharacters)) + "\n[truncated]", true)
    }
}

public struct DevelopmentVerificationCommandTool: Tool {
    public let name: ActionTool = .developmentRunVerification
    public let description: String = "Run an approved local verification command inside an approved project workspace."
    public let inputSchema = ToolInputSchema(
        required: ["projectId", "commandId"],
        properties: [
            "projectId": "integer",
            "taskId": "integer",
            // branchName is reviewed context for receipts and handoff recovery;
            // command execution remains scoped to the approved project directory.
            "branchName": "string",
            "commandId": "string"
        ],
        nonBlank: ["branchName", "commandId"]
    )
    public let permissionLevel: ToolPermissionLevel = .writeWithApproval

    private let projectStore: SQLiteProjectStore
    private let commandRunner: any DevelopmentCommandRunner
    private let gitRunner: any GitCommandRunner
    private let redactor: DeveloperSecretRedactor
    private let bookmarkResolver: any ProjectWorkspaceBookmarkResolving
    private let requireBookmark: Bool

    public init(
        projectStore: SQLiteProjectStore,
        commandRunner: any DevelopmentCommandRunner = ProcessDevelopmentCommandRunner(),
        gitRunner: any GitCommandRunner = ProcessGitCommandRunner(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        bookmarkResolver: any ProjectWorkspaceBookmarkResolving = SecurityScopedProjectWorkspaceBookmarkResolver(),
        requireBookmark: Bool = false
    ) {
        self.projectStore = projectStore
        self.commandRunner = commandRunner
        self.gitRunner = gitRunner
        self.redactor = redactor
        self.bookmarkResolver = bookmarkResolver
        self.requireBookmark = requireBookmark
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let projectID = try args.requiredInt64("projectId")
        let commandID = try args.requiredTrimmedString("commandId")
        let branchName = try args.optionalTrimmedString("branchName").map {
            try DevelopmentBranchNamePolicy.validated($0)
        }

        do {
            let command = try DevelopmentVerificationCommandPolicy.validated(commandID: commandID)
            let project = try projectStore.get(id: projectID)
            let scope = try ProjectWorkspaceScope(
                project: project,
                bookmarkResolver: bookmarkResolver,
                requireBookmark: requireBookmark
            )
            return try withExtendedLifetime(scope) {
                try ensureCurrentBranch(matches: branchName, scope: scope)
                let executable = try DevelopmentVerificationCommandPolicy.resolvedExecutable(for: command, scope: scope)
                let output = try commandRunner.run(
                    executable: executable,
                    arguments: command.arguments,
                    workingDirectory: scope.rootURL
                )

                let stdout = DevelopmentVerificationOutputPolicy.sanitize(output.standardOutput, redactor: redactor)
                let stderr = DevelopmentVerificationOutputPolicy.sanitize(output.standardError, redactor: redactor)
                let passed = output.exitCode == 0 && !output.timedOut
                let summary = if passed {
                    "Ran \(command.commandDisplay) successfully."
                } else if output.timedOut {
                    "Verification command \(command.commandDisplay) timed out."
                } else {
                    "Verification command \(command.commandDisplay) failed with exit code \(output.exitCode)."
                }

                return ToolResult(
                    tool: name,
                    status: passed ? .succeeded : .failed,
                    summary: summary,
                    output: [
                        "projectId": .number(Double(project.id)),
                        "commandId": .string(command.id),
                        "command": .string(command.commandDisplay),
                        "executable": .string(executable),
                        "arguments": JSONValueFactory.strings(command.arguments),
                        "exitCode": .number(Double(output.exitCode)),
                        "passed": .bool(passed),
                        "timedOut": .bool(output.timedOut),
                        "durationMs": .number(Double(output.durationMilliseconds)),
                        "stdout": .string(stdout.text),
                        "stderr": .string(stderr.text),
                        "stdoutTruncated": .bool(output.standardOutputTruncated || stdout.truncated),
                        "stderrTruncated": .bool(output.standardErrorTruncated || stderr.truncated)
                    ]
                )
            }
        } catch let error as ToolExecutionError {
            throw error
        } catch let error as DevelopmentVerificationCommandError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch let error as DevelopmentPRWorkflowError {
            throw ToolExecutionError.executionFailed(name, redacted(error.userMessage))
        } catch {
            throw ToolExecutionError.executionFailed(name, redacted(String(describing: error)))
        }
    }

    private func redacted(_ value: String) -> String {
        redactor.redact(value).text
    }

    private func ensureCurrentBranch(matches expectedBranch: String?, scope: ProjectWorkspaceScope) throws {
        guard let expectedBranch else {
            return
        }

        do {
            let output = try gitRunner.runGit(arguments: ["branch", "--show-current"], workingDirectory: scope.rootURL)
            guard output.exitCode == 0 else {
                throw DevelopmentVerificationCommandError.currentBranchUnavailable
            }
            let currentBranch = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentBranch.isEmpty else {
                throw DevelopmentVerificationCommandError.currentBranchUnavailable
            }
            guard currentBranch == expectedBranch else {
                throw DevelopmentVerificationCommandError.branchMismatch(expected: expectedBranch, actual: currentBranch)
            }
        } catch let error as DevelopmentVerificationCommandError {
            throw error
        } catch {
            throw DevelopmentVerificationCommandError.currentBranchUnavailable
        }
    }
}
