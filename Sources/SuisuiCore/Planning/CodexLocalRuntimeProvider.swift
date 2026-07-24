import Darwin
import Foundation

public protocol CodexVersionReporting: Sendable {
    func versionOutput(approvedExecutable: ApprovedCodexExecutable) async throws -> String
}

public struct ProcessCodexVersionReporter: CodexVersionReporting {
    public init() {}

    public func versionOutput(approvedExecutable: ApprovedCodexExecutable) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            #if os(iOS) || targetEnvironment(macCatalyst)
            throw CodexAppServerTransportError.localExecutionUnavailable
            #else
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            process.arguments = ["--version"]
            process.standardOutput = output
            process.standardError = errorOutput
            // Revalidate after Process setup so the integrity check stays next
            // to the first executable action (`--version`) as well.
            let executable = try CodexAppServerRuntimeConfiguration.preflight(
                approvedExecutable: approvedExecutable
            )
            process.executableURL = URL(fileURLWithPath: executable.resolvedPath)
            process.environment = CodexAppServerLaunchConfiguration(
                executablePath: executable.resolvedPath
            ).environment
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
        let versionOutput = try await versionReporter.versionOutput(approvedExecutable: executable)
        return try CodexAppServerRuntimeConfiguration.validate(
            approvedExecutable: approvedExecutable,
            reportedVersion: versionOutput
        )
    }
}

public final class CodexExecutionApprovalGeneration: @unchecked Sendable {
    public static let shared = CodexExecutionApprovalGeneration()

    private let lock = NSLock()
    private var generation: UInt64 = 0

    private init() {}

    public func current() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    @discardableResult
    public func advance() -> UInt64 {
        lock.lock()
        generation &+= 1
        let next = generation
        lock.unlock()
        return next
    }
}

private final class CodexApprovalNotificationObserver: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(center: NotificationCenter, continuation: AsyncStream<Void>.Continuation) {
        self.center = center
        token = center.addObserver(
            forName: .suisuiCodexExecutionApprovalDidChange,
            object: nil,
            queue: nil
        ) { _ in
            continuation.yield(())
        }
    }

    func cancel() {
        center.removeObserver(token)
    }
}

public enum CodexExecutionApprovalChanges {
    public static func invalidate(center: NotificationCenter = .default) {
        CodexExecutionApprovalGeneration.shared.advance()
        center.post(name: .suisuiCodexExecutionApprovalDidChange, object: nil)
    }

    public static func stream(
        center: NotificationCenter = .default
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = CodexApprovalNotificationObserver(
                center: center,
                continuation: continuation
            )
            continuation.onTermination = { _ in observer.cancel() }
        }
    }
}

/// Owns one short-lived App Server per planning request. This avoids sharing
/// authentication/process state across workspaces and guarantees cleanup even
/// when parsing or a provider policy check fails.
public struct CodexLocalRuntimeProvider: StreamingLLMProvider {
    public let providerID = "codex.local"

    private let approvedExecutableProvider: @Sendable () -> ApprovedCodexExecutable?
    private let modelID: String?
    private let clientVersion: String
    private let scratchRoot: URL
    private let runtimeResolver: CodexApprovedRuntimeResolver
    private let approvalChangeStream: @Sendable () -> AsyncStream<Void>
    private let approvalGenerationProvider: @Sendable () -> UInt64
    private let approvalInvalidator: @Sendable () -> Void
    private let transportFactory: @Sendable (ApprovedCodexExecutable) -> any CodexAppServerTransport

    public init(
        approvedExecutable: ApprovedCodexExecutable?,
        modelID: String?,
        clientVersion: String,
        scratchRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-planning", isDirectory: true),
        versionReporter: any CodexVersionReporting = ProcessCodexVersionReporter(),
        approvalInvalidator: @escaping @Sendable () -> Void = {
            CodexExecutionApprovalChanges.invalidate()
        }
    ) {
        self.approvedExecutableProvider = { approvedExecutable }
        self.modelID = modelID
        self.clientVersion = clientVersion
        self.scratchRoot = scratchRoot
        self.runtimeResolver = CodexApprovedRuntimeResolver(versionReporter: versionReporter)
        self.approvalChangeStream = { CodexExecutionApprovalChanges.stream() }
        self.approvalGenerationProvider = { CodexExecutionApprovalGeneration.shared.current() }
        self.approvalInvalidator = approvalInvalidator
        self.transportFactory = Self.makeProductionTransport
    }

    public init(
        approvedExecutableProvider: @escaping @Sendable () -> ApprovedCodexExecutable?,
        modelID: String?,
        clientVersion: String,
        scratchRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-planning", isDirectory: true),
        versionReporter: any CodexVersionReporting = ProcessCodexVersionReporter(),
        approvalInvalidator: @escaping @Sendable () -> Void = {
            CodexExecutionApprovalChanges.invalidate()
        }
    ) {
        self.approvedExecutableProvider = approvedExecutableProvider
        self.modelID = modelID
        self.clientVersion = clientVersion
        self.scratchRoot = scratchRoot
        self.runtimeResolver = CodexApprovedRuntimeResolver(versionReporter: versionReporter)
        self.approvalChangeStream = { CodexExecutionApprovalChanges.stream() }
        self.approvalGenerationProvider = { CodexExecutionApprovalGeneration.shared.current() }
        self.approvalInvalidator = approvalInvalidator
        self.transportFactory = Self.makeProductionTransport
    }

    init(
        approvedExecutableProvider: @escaping @Sendable () -> ApprovedCodexExecutable?,
        modelID: String?,
        clientVersion: String,
        scratchRoot: URL,
        versionReporter: any CodexVersionReporting,
        approvalChangeStream: @escaping @Sendable () -> AsyncStream<Void>,
        approvalGenerationProvider: @escaping @Sendable () -> UInt64 = {
            CodexExecutionApprovalGeneration.shared.current()
        },
        approvalInvalidator: @escaping @Sendable () -> Void = {
            CodexExecutionApprovalChanges.invalidate()
        },
        transportFactory: @escaping @Sendable (ApprovedCodexExecutable) -> any CodexAppServerTransport
    ) {
        self.approvedExecutableProvider = approvedExecutableProvider
        self.modelID = modelID
        self.clientVersion = clientVersion
        self.scratchRoot = scratchRoot
        self.runtimeResolver = CodexApprovedRuntimeResolver(versionReporter: versionReporter)
        self.approvalChangeStream = approvalChangeStream
        self.approvalGenerationProvider = approvalGenerationProvider
        self.approvalInvalidator = approvalInvalidator
        self.transportFactory = transportFactory
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
        let approvedExecutable = approvedExecutableProvider()
        let approvalGeneration = approvalGenerationProvider()
        let runtime: CodexAppServerRuntimeConfiguration
        do {
            runtime = try await runtimeResolver.resolve(approvedExecutable: approvedExecutable)
        } catch {
            if Self.isExecutableIntegrityMismatch(error) {
                approvalInvalidator()
            }
            throw LLMProviderError.executionNotApproved("The selected Codex executable is missing, unsafe, or unsupported.")
        }
        // Register before creating scratch state or a transport. The generation
        // check immediately below closes changes that happened just before the
        // observer became active, while the stream covers everything after it.
        let changes = approvalChangeStream()
        guard approvedExecutableProvider() == approvedExecutable,
              approvalGenerationProvider() == approvalGeneration else {
            throw LLMProviderError.executionNotApproved("Codex approval changed before the local process could start.")
        }

        let scratchDirectory = scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        let transport = transportFactory(runtime.approvedExecutable)
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
            let response = try await withThrowingTaskGroup(of: PlanningResponse.self) { group in
                group.addTask {
                    try await account.initialize(clientVersion: clientVersion)
                    guard approvedExecutableProvider() == approvedExecutable,
                          approvalGenerationProvider() == approvalGeneration else {
                        throw LLMProviderError.executionNotApproved(
                            "Codex approval changed before the planning turn could start."
                        )
                    }
                    return try await provider.generatePlanStream(for: request, onTextDelta: onTextDelta)
                }
                group.addTask {
                    for await _ in changes {
                        // Close stdio before surfacing revocation so a provider
                        // blocked on an App Server event cannot keep the old
                        // process alive while the task group is unwinding.
                        await transport.shutdown()
                        throw LLMProviderError.executionNotApproved(
                            "Codex approval changed while the planning request was running."
                        )
                    }
                    try await Task.sleep(nanoseconds: .max)
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw CancellationError()
                }
                return first
            }
            guard approvedExecutableProvider() == approvedExecutable,
                  approvalGenerationProvider() == approvalGeneration else {
                throw LLMProviderError.executionNotApproved(
                    "Codex approval changed before the planning result was accepted."
                )
            }
            await transport.shutdown()
            try? FileManager.default.removeItem(at: scratchDirectory)
            return response
        } catch {
            await transport.shutdown()
            try? FileManager.default.removeItem(at: scratchDirectory)
            if Self.isExecutableIntegrityMismatch(error) {
                approvalInvalidator()
            }
            throw error
        }
    }

    private static func isExecutableIntegrityMismatch(_ error: any Error) -> Bool {
        guard let runtimeError = error as? CodexAppServerRuntimeConfigurationError else {
            return false
        }
        // A missing approval can also mean the user switched away from Codex.
        // Only evidence that the approved file changed revokes persisted state.
        return runtimeError == .approvedExecutableChanged
    }

    private static func makeProductionTransport(
        approvedExecutable: ApprovedCodexExecutable
    ) -> any CodexAppServerTransport {
        CodexAppServerStdioTransport(
            process: ProcessCodexAppServerProcess(
                configuration: CodexAppServerLaunchConfiguration(
                    executablePath: approvedExecutable.resolvedPath
                ),
                approvedExecutable: approvedExecutable
            )
        )
    }
}
