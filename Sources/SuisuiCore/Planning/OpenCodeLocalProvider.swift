import Darwin
import Foundation

public struct OpenCodeLocalConfiguration: Equatable, Sendable {
    public var executablePath: String?
    public var workspacePath: String?
    public var modelID: String
    public var isExecutionApproved: Bool
    public var timeoutInterval: TimeInterval

    public init(
        executablePath: String?,
        workspacePath: String?,
        modelID: String,
        isExecutionApproved: Bool,
        timeoutInterval: TimeInterval = 120
    ) {
        self.executablePath = executablePath
        self.workspacePath = workspacePath
        self.modelID = modelID
        self.isExecutionApproved = isExecutionApproved
        self.timeoutInterval = timeoutInterval
    }
}

public struct OpenCodeLocalInvocation: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectory: URL
    public var timeoutInterval: TimeInterval

    public init(
        executablePath: String,
        arguments: [String],
        workingDirectory: URL,
        timeoutInterval: TimeInterval
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.timeoutInterval = timeoutInterval
    }
}

public struct OpenCodeLocalCommandOutput: Equatable, Sendable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32
    public var timedOut: Bool

    public init(
        standardOutput: String,
        standardError: String,
        exitCode: Int32,
        timedOut: Bool
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}

public protocol OpenCodeLocalCommandRunner: Sendable {
    func run(_ invocation: OpenCodeLocalInvocation) async throws -> OpenCodeLocalCommandOutput
}

public struct OpenCodeLocalProvider: LLMProvider {
    public let providerID = "opencode.local"

    private let configuration: OpenCodeLocalConfiguration
    private let commandRunner: any OpenCodeLocalCommandRunner
    private let promptBuilder: PlanningPromptBuilder?
    private let responseParser: ActionPlanResponseParser
    private let redactor: DeveloperSecretRedactor

    public init(
        configuration: OpenCodeLocalConfiguration,
        commandRunner: any OpenCodeLocalCommandRunner = ProcessOpenCodeLocalCommandRunner(),
        promptBuilder: PlanningPromptBuilder? = nil,
        responseParser: ActionPlanResponseParser = ActionPlanResponseParser(),
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.configuration = configuration
        self.commandRunner = commandRunner
        self.promptBuilder = promptBuilder
        self.responseParser = responseParser
        self.redactor = redactor
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let validated = try validateConfiguration()
        let prompt = try (promptBuilder ?? PlanningPromptBuilder.loadDefault()).buildPrompt(for: request)
        let invocation = OpenCodeLocalInvocation(
            executablePath: validated.executablePath,
            arguments: makeArguments(
                modelID: validated.modelID,
                workspacePath: validated.workspaceURL.path,
                prompt: prompt
            ),
            workingDirectory: validated.workspaceURL,
            timeoutInterval: configuration.timeoutInterval
        )
        let output: OpenCodeLocalCommandOutput
        do {
            output = try await commandRunner.run(invocation)
        } catch let error as LLMProviderError {
            throw error
        } catch {
            throw LLMProviderError.network("OpenCode local execution failed to start. \(redactedError(error))")
        }

        if output.timedOut {
            throw LLMProviderError.network("OpenCode local execution timed out. \(redactedStderr(output.standardError))")
        }

        guard output.exitCode == 0 else {
            throw LLMProviderError.network(
                "OpenCode local execution failed with exit code \(output.exitCode). \(redactedStderr(output.standardError))"
            )
        }

        return responseParser.parse(rawContent: output.standardOutput, providerID: providerID)
    }

    private func makeArguments(modelID: String, workspacePath: String, prompt: PlanningPrompt) -> [String] {
        [
            "run",
            "--model",
            modelID,
            "--dir",
            workspacePath,
            """
            \(prompt.system)

            \(prompt.user)

            Return only Action Plan JSON. Do not include Markdown, prose, code fences, or commentary.
            """
        ]
    }

    private func validateConfiguration() throws -> ValidatedOpenCodeLocalConfiguration {
        guard configuration.isExecutionApproved else {
            throw LLMProviderError.executionNotApproved("OpenCode local execution requires explicit approval in Settings.")
        }

        let executablePath = try normalizedExecutablePath()
        let workspaceURL = try normalizedWorkspaceURL()
        let modelID = try normalizedModelID()

        return ValidatedOpenCodeLocalConfiguration(
            executablePath: executablePath,
            workspaceURL: workspaceURL,
            modelID: modelID
        )
    }

    private func normalizedExecutablePath() throws -> String {
        let path = configuration.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            throw LLMProviderError.invalidResponse("OpenCode executable path is required.")
        }
        guard !path.hasSuffix("/auth.json"), path != "auth.json" else {
            throw LLMProviderError.invalidResponse("OpenCode executable path must not point to auth.json.")
        }
        return path
    }

    private func normalizedWorkspaceURL() throws -> URL {
        let path = configuration.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            throw LLMProviderError.invalidResponse("OpenCode workspace path is required.")
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LLMProviderError.invalidResponse("OpenCode workspace directory is unavailable.")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func normalizedModelID() throws -> String {
        let modelID = configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            throw LLMProviderError.invalidResponse("OpenCode model id is required.")
        }
        guard modelID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw LLMProviderError.invalidResponse("OpenCode model id cannot contain whitespace.")
        }
        return modelID
    }

    private func redactedStderr(_ standardError: String) -> String {
        let redacted = redactor.redact(standardError).text.trimmingCharacters(in: .whitespacesAndNewlines)
        return redacted.isEmpty ? "" : "stderr: \(redacted)"
    }

    private func redactedError(_ error: Error) -> String {
        let redacted = redactor.redact(error.localizedDescription).text.trimmingCharacters(in: .whitespacesAndNewlines)
        return redacted.isEmpty ? "" : "error: \(redacted)"
    }
}

private struct ValidatedOpenCodeLocalConfiguration: Sendable {
    var executablePath: String
    var workspaceURL: URL
    var modelID: String
}

public struct ProcessOpenCodeLocalCommandRunner: OpenCodeLocalCommandRunner {
    private let redactor: DeveloperSecretRedactor

    public init(redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()) {
        self.redactor = redactor
    }

    public func run(_ invocation: OpenCodeLocalInvocation) async throws -> OpenCodeLocalCommandOutput {
        #if os(iOS) || targetEnvironment(macCatalyst)
        // OpenCode launches a local process, which is a macOS-only automation
        // boundary; mobile surfaces must use reviewable sync mutations instead.
        throw LLMProviderError.executionNotApproved("OpenCode local execution is available only on macOS.")
        #else
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        if invocation.executablePath.contains("/") {
            process.executableURL = URL(fileURLWithPath: invocation.executablePath)
            process.arguments = invocation.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [invocation.executablePath] + invocation.arguments
        }
        process.currentDirectoryURL = invocation.workingDirectory
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = ProcessInfo.processInfo.environment

        try process.run()

        let deadline = Date().addingTimeInterval(invocation.timeoutInterval)
        var didTimeOut = false
        while process.isRunning {
            if Date() >= deadline {
                didTimeOut = true
                process.terminate()
                try? await Task.sleep(nanoseconds: 150_000_000)
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        process.waitUntilExit()
        let stdoutData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let stderrData = standardError.fileHandleForReading.readDataToEndOfFile()

        return OpenCodeLocalCommandOutput(
            standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
            standardError: redactor.redact(String(data: stderrData, encoding: .utf8) ?? "").text,
            exitCode: process.terminationStatus,
            timedOut: didTimeOut
        )
        #endif
    }
}
