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

public struct CodexApprovedRuntimeResolver: Sendable {
    private let versionReporter: any CodexVersionReporting

    public init(versionReporter: any CodexVersionReporting = ProcessCodexVersionReporter()) {
        self.versionReporter = versionReporter
    }

    public func resolve(
        approvedExecutable: ApprovedCodexExecutable?
    ) async throws -> CodexAppServerRuntimeConfiguration {
        // This sequencing is shared by Planning and every account operation so
        // a UI route cannot accidentally turn `--version` into an approval bypass.
        let executable = try CodexAppServerRuntimeConfiguration.preflight(
            approvedExecutable: approvedExecutable
        )
        let versionOutput = try await versionReporter.versionOutput(
            executablePath: executable.resolvedPath
        )
        return try CodexAppServerRuntimeConfiguration.validate(
            approvedExecutable: approvedExecutable,
            reportedVersion: versionOutput
        )
    }
}

/// Owns one short-lived App Server per planning request. This avoids sharing
/// authentication/process state across workspaces and guarantees cleanup even
/// when parsing or a provider policy check fails.
public struct CodexLocalRuntimeProvider: StreamingLLMProvider {
    public let providerID = "codex.local"

    private let approvedExecutable: ApprovedCodexExecutable?
    private let modelID: String?
    private let clientVersion: String
    private let scratchRoot: URL
    private let runtimeResolver: CodexApprovedRuntimeResolver

    public init(
        approvedExecutable: ApprovedCodexExecutable?,
        modelID: String?,
        clientVersion: String,
        scratchRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-planning", isDirectory: true),
        versionReporter: any CodexVersionReporting = ProcessCodexVersionReporter()
    ) {
        self.approvedExecutable = approvedExecutable
        self.modelID = modelID
        self.clientVersion = clientVersion
        self.scratchRoot = scratchRoot
        self.runtimeResolver = CodexApprovedRuntimeResolver(versionReporter: versionReporter)
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        try await generatePlanStream(for: request, onTextDelta: { _ in })
    }

    public func generatePlanStream(
        for request: PlanningRequest,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws -> PlanningResponse {
        // Preflight and approval identity matching must happen before even the
        // version probe because `--version` is already arbitrary local execution.
        let runtime: CodexAppServerRuntimeConfiguration
        do {
            runtime = try await runtimeResolver.resolve(approvedExecutable: approvedExecutable)
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
