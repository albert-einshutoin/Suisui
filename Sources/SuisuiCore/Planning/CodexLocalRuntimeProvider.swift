import Darwin
import Foundation

public protocol CodexVersionReporting: Sendable {
    func versionOutput(executablePath: String) async throws -> String
}

public struct ProcessCodexVersionReporter: CodexVersionReporting {
    public init() {}

    public func versionOutput(executablePath: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            #if os(iOS) || targetEnvironment(macCatalyst)
            throw CodexAppServerTransportError.localExecutionUnavailable
            #else
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["--version"]
            process.environment = CodexAppServerLaunchConfiguration(
                executablePath: executablePath
            ).environment
            process.standardOutput = output
            process.standardError = errorOutput
            do {
                try process.run()
            } catch {
                throw CodexAppServerTransportError.processLaunchFailed
            }
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline {
                Darwin.usleep(20_000)
            }
            if process.isRunning {
                process.terminate()
                Darwin.usleep(100_000)
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                throw CodexAppServerTransportError.timeout(method: "codex --version")
            }
            let standardOutput = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw CodexAppServerTransportError.processLaunchFailed
            }
            return standardOutput
            #endif
        }.value
    }
}

/// Owns one short-lived App Server per planning request. This avoids sharing
/// authentication/process state across workspaces and guarantees cleanup even
/// when parsing or a provider policy check fails.
public struct CodexLocalRuntimeProvider: StreamingLLMProvider {
    public let providerID = "codex.local"

    private let executablePath: String?
    private let modelID: String?
    private let isExecutionApproved: Bool
    private let clientVersion: String
    private let scratchRoot: URL
    private let versionReporter: any CodexVersionReporting

    public init(
        executablePath: String?,
        modelID: String?,
        isExecutionApproved: Bool,
        clientVersion: String,
        scratchRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-planning", isDirectory: true),
        versionReporter: any CodexVersionReporting = ProcessCodexVersionReporter()
    ) {
        self.executablePath = executablePath
        self.modelID = modelID
        self.isExecutionApproved = isExecutionApproved
        self.clientVersion = clientVersion
        self.scratchRoot = scratchRoot
        self.versionReporter = versionReporter
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        try await generatePlanStream(for: request, onTextDelta: { _ in })
    }

    public func generatePlanStream(
        for request: PlanningRequest,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws -> PlanningResponse {
        guard isExecutionApproved else {
            throw LLMProviderError.executionNotApproved("Review the Codex executable and approve local execution in Settings.")
        }
        guard let executablePath else {
            throw LLMProviderError.executionNotApproved("Select an absolute Codex executable path in Settings.")
        }

        let versionOutput = try await versionReporter.versionOutput(executablePath: executablePath)
        let runtime: CodexAppServerRuntimeConfiguration
        do {
            runtime = try CodexAppServerRuntimeConfiguration.validate(
                executablePath: executablePath,
                reportedVersion: versionOutput,
                fileManager: FileManager.default
            )
        } catch {
            throw LLMProviderError.executionNotApproved("The selected Codex executable is missing, unsafe, or unsupported.")
        }

        let scratchDirectory = scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        let process = ProcessCodexAppServerProcess(
            configuration: CodexAppServerLaunchConfiguration(executablePath: runtime.executablePath)
        )
        let transport = CodexAppServerStdioTransport(process: process)
        let account = CodexAppServerAccountClient(transport: transport)
        let provider = CodexAppServerProvider(
            transport: transport,
            prerequisites: account,
            configuration: CodexAppServerProviderConfiguration(
                modelID: modelID,
                scratchDirectory: scratchDirectory
            )
        )

        do {
            try await account.initialize(clientVersion: clientVersion)
            let response = try await provider.generatePlanStream(for: request, onTextDelta: onTextDelta)
            await transport.shutdown()
            try? FileManager.default.removeItem(at: scratchDirectory)
            return response
        } catch {
            await transport.shutdown()
            try? FileManager.default.removeItem(at: scratchDirectory)
            throw error
        }
    }
}
