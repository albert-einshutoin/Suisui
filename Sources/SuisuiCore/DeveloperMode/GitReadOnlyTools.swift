import Foundation

public struct GitCommandInvocation: Equatable, Sendable {
    public var arguments: [String]
    public var workingDirectory: URL

    public init(arguments: [String], workingDirectory: URL) {
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct GitCommandOutput: Equatable, Sendable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

public protocol GitCommandRunner: Sendable {
    func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput
}

public struct ProcessGitCommandRunner: GitCommandRunner {
    private static let runtimeDevelopmentGitExecutableOverrideKey = "SUISUI_RUNTIME_DEVELOPMENT_PR_GIT_EXECUTABLE"
    private static let runtimeDevelopmentSmokeBookmarkFlagKey = "SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"
    private static let runtimeDevelopmentExpectedBranchKey = "SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_BRANCH"
    private static let runtimeDevelopmentExpectedHeadKey = "SUISUI_RUNTIME_DEVELOPMENT_PR_EXPECTED_HEAD"
    private static let runtimeDevelopmentPushLogKey = "SUISUI_RUNTIME_DEVELOPMENT_PR_PUSH_LOG"
    private static let runtimeDevelopmentBlockedExternalWriteLogKey = "SUISUI_RUNTIME_DEVELOPMENT_PR_BLOCKED_EXTERNAL_WRITE_LOG"

    public init() {}

    public func runGit(arguments: [String], workingDirectory: URL) throws -> GitCommandOutput {
        #if os(iOS) || targetEnvironment(macCatalyst)
        // Mobile builds expose synced task workflows, not local developer tooling;
        // keep git subprocess execution out of iOS/Catalyst binaries.
        throw GitReadOnlyError.workspaceUnavailable("Git command execution is available only on macOS.")
        #else
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        let environment = ProcessInfo.processInfo.environment
        if let smokeOutput = Self.runtimeDevelopmentSmokePushOutput(
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        ) {
            return smokeOutput
        }

        // Runtime publish smoke uses an explicit wrapper so tests can prove the
        // external push boundary without relying on PATH behavior in app launches.
        if environment[Self.runtimeDevelopmentSmokeBookmarkFlagKey] == "1",
            let override = environment[Self.runtimeDevelopmentGitExecutableOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty {
            process.executableURL = URL(fileURLWithPath: override)
            process.arguments = arguments
            // The runtime smoke wrapper validates expected branch/head metadata
            // from environment before any simulated push can run.
            process.environment = environment
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
        }
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return GitCommandOutput(
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
        #endif
    }

    private static func runtimeDevelopmentSmokePushOutput(
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]
    ) -> GitCommandOutput? {
        guard environment[Self.runtimeDevelopmentSmokeBookmarkFlagKey] == "1",
              arguments.first == "push" else {
            return nil
        }

        let expectedBranch = environment[Self.runtimeDevelopmentExpectedBranchKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expectedHead = environment[Self.runtimeDevelopmentExpectedHeadKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expectedRefSpec = "\(expectedHead):refs/heads/\(expectedBranch)"
        let commandPreview = arguments.joined(separator: " ")

        guard arguments == ["push", "-u", "origin", expectedRefSpec],
              !expectedBranch.isEmpty,
              !expectedHead.isEmpty else {
            let blockedPath = environment[Self.runtimeDevelopmentBlockedExternalWriteLogKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            appendRuntimeDevelopmentSmokeLog(
                "blocked publish command: \(commandPreview)\n",
                path: blockedPath
            )
            return GitCommandOutput(
                standardOutput: "",
                standardError: "blocked publish command: \(commandPreview)",
                exitCode: 42
            )
        }

        let pushLogPath = environment[Self.runtimeDevelopmentPushLogKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let log = """
        cwd=\(workingDirectory.path)
        args=\(commandPreview)
        branch=\(expectedBranch)
        head=\(expectedHead)
        """
        appendRuntimeDevelopmentSmokeLog(log + "\n", path: pushLogPath)
        return GitCommandOutput(
            standardOutput: "simulated branch push \(expectedRefSpec)\n",
            standardError: "",
            exitCode: 0
        )
    }

    private static func appendRuntimeDevelopmentSmokeLog(_ text: String, path: String?) {
        guard let path, !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        let data = Data(text.utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

public enum GitReadOnlyError: Error, Equatable, Sendable {
    case workspaceUnavailable(String)
    case commandNotAllowed([String])
    case commandFailed(arguments: [String], exitCode: Int32, standardError: String)
}

public enum GitReadOnlyCommandPolicy {
    public static func isAllowed(arguments: [String]) -> Bool {
        switch arguments {
        case ["status", "--short", "--branch"],
             ["branch", "--show-current"],
             ["diff", "--stat"]:
            return true
        default:
            guard arguments.count == 4,
                  arguments[0] == "log",
                  arguments[1] == "--oneline",
                  arguments[2] == "-n",
                  let limit = Int(arguments[3]) else {
                return false
            }
            return (1...50).contains(limit)
        }
    }
}

public struct GitStatusEntry: Equatable, Sendable {
    public var status: String
    public var path: String

    public init(status: String, path: String) {
        self.status = status
        self.path = path
    }
}

public struct GitStatusSummary: Equatable, Sendable {
    public var branch: String?
    public var entries: [GitStatusEntry]
    public var rawOutput: String

    public init(branch: String?, entries: [GitStatusEntry], rawOutput: String) {
        self.branch = branch
        self.entries = entries
        self.rawOutput = rawOutput
    }

    public var isClean: Bool {
        entries.isEmpty
    }

    public static func parse(_ standardOutput: String) -> GitStatusSummary {
        var branch: String?
        var entries: [GitStatusEntry] = []

        for rawLine in standardOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if line.hasPrefix("## ") {
                let branchLine = String(line.dropFirst(3))
                branch = branchLine.components(separatedBy: "...").first
                continue
            }

            let status = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let pathStart = line.index(line.startIndex, offsetBy: min(3, line.count))
            let path = String(line[pathStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(GitStatusEntry(status: status, path: path))
        }

        return GitStatusSummary(branch: branch, entries: entries, rawOutput: standardOutput)
    }
}

public enum GitReadOnlyCommand: Equatable, Sendable {
    case status
    case branch
    case logSummary(limit: Int)
    case diffSummary

    var arguments: [String] {
        switch self {
        case .status:
            return ["status", "--short", "--branch"]
        case .branch:
            return ["branch", "--show-current"]
        case .logSummary(let limit):
            return ["log", "--oneline", "-n", "\(limit)"]
        case .diffSummary:
            return ["diff", "--stat"]
        }
    }
}

public struct GitReadOnlyClient: Sendable {
    private let workspaceRoot: URL
    private let runner: any GitCommandRunner

    public init(workspaceRoot: URL, runner: any GitCommandRunner = ProcessGitCommandRunner()) {
        self.workspaceRoot = workspaceRoot
        self.runner = runner
    }

    public func status() throws -> GitStatusSummary {
        let output = try run(.status)
        return GitStatusSummary.parse(output.standardOutput)
    }

    public func branch() throws -> String {
        try run(.branch).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func logSummary(limit: Int = 10) throws -> [String] {
        let safeLimit = min(max(limit, 1), 50)
        let output = try run(.logSummary(limit: safeLimit))
        return output.standardOutput
            .split(separator: "\n")
            .map(String.init)
    }

    public func diffSummary() throws -> String {
        try run(.diffSummary).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ command: GitReadOnlyCommand) throws -> GitCommandOutput {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: workspaceRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitReadOnlyError.workspaceUnavailable(workspaceRoot.path)
        }

        let arguments = command.arguments
        guard GitReadOnlyCommandPolicy.isAllowed(arguments: arguments) else {
            throw GitReadOnlyError.commandNotAllowed(arguments)
        }

        let output = try runner.runGit(arguments: arguments, workingDirectory: workspaceRoot)
        guard output.exitCode == 0 else {
            throw GitReadOnlyError.commandFailed(
                arguments: arguments,
                exitCode: output.exitCode,
                standardError: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
    }
}

public struct GitReadOnlyTool: Tool {
    public var name: ActionTool
    public var description: String {
        switch name {
        case .gitStatus:
            return "Read the selected workspace git status."
        case .gitBranch:
            return "Read the selected workspace current git branch."
        case .gitLogSummary:
            return "Read a bounded oneline git log summary."
        case .gitDiffSummary:
            return "Read the selected workspace git diff stat."
        default:
            return "Unsupported git read-only tool."
        }
    }

    public var inputSchema: ToolInputSchema {
        switch name {
        case .gitLogSummary:
            return ToolInputSchema(properties: ["limit": "number"], additionalProperties: false)
        default:
            return ToolInputSchema(additionalProperties: false)
        }
    }

    public let permissionLevel: ToolPermissionLevel = .read

    private let client: GitReadOnlyClient

    public init(name: ActionTool, client: GitReadOnlyClient) {
        self.name = name
        self.client = client
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(arguments: arguments, context: context)
        try validateRequiredArguments(arguments)

        switch name {
        case .gitStatus:
            let status = try client.status()
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: status.isClean ? "Git workspace is clean." : "Git workspace has \(status.entries.count) changed path(s).",
                output: [
                    "branch": status.branch.map(JSONValue.string) ?? .null,
                    "isClean": .bool(status.isClean),
                    "entries": .array(status.entries.map { entry in
                        .object([
                            "status": .string(entry.status),
                            "path": .string(entry.path)
                        ])
                    }),
                    "raw": .string(status.rawOutput)
                ]
            )
        case .gitBranch:
            let branch = try client.branch()
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Current git branch is \(branch).",
                output: ["branch": .string(branch)]
            )
        case .gitLogSummary:
            let args = ToolArguments(arguments, tool: name)
            let limit = Int(try args.optionalInt64("limit") ?? 10)
            let entries = try client.logSummary(limit: limit)
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Read \(entries.count) git log entries.",
                output: ["entries": JSONValueFactory.strings(entries)]
            )
        case .gitDiffSummary:
            let summary = try client.diffSummary()
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: summary.isEmpty ? "No git diff stat output." : "Read git diff stat.",
                output: [
                    "summary": .string(summary),
                    "hasChanges": .bool(!summary.isEmpty)
                ]
            )
        default:
            throw ToolExecutionError.validationFailed(name, "Unsupported git read-only tool.")
        }
    }
}
