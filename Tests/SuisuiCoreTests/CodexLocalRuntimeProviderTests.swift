import Darwin
import Foundation
import XCTest
@testable import SuisuiCore

final class CodexLocalRuntimeProviderTests: XCTestCase {
    func testLiveAuthStoreAccessIsObservableUnderChildPIDWhenExplicitlyAudited() async throws {
        guard ProcessInfo.processInfo.environment["SUISUI_CODEX_AUTH_ACCESS_AUDIT"] == "1" else {
            throw XCTSkip("Run through check_codex_auth_access_evidence.sh with root filesystem tracing.")
        }
        let wrapperPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["SUISUI_CODEX_AUTH_ACCESS_AUDIT_WRAPPER"]
        )
        try "\(Darwin.getpid())\n".write(
            toFile: wrapperPath + ".parent-pid",
            atomically: true,
            encoding: .utf8
        )
        let transport = CodexAppServerStdioTransport(
            process: ProcessCodexAppServerProcess(
                configuration: CodexAppServerLaunchConfiguration(executablePath: wrapperPath)
            )
        )
        let account = CodexAppServerAccountClient(transport: transport)

        do {
            try await account.initialize(clientVersion: "auth-access-audit")
            let snapshot = try await account.readAccount(refresh: true)
            guard case .ready = snapshot.readiness else {
                XCTFail("Codex account is not ready: \(snapshot.readiness)")
                await transport.shutdown()
                return
            }
            let models = try await account.listModels()
            XCTAssertFalse(models.isEmpty)
            await transport.shutdown()
        } catch {
            await transport.shutdown()
            throw error
        }
    }

    func testLiveSubscriptionAccountModelAndCancelableLoginWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["SUISUI_CODEX_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set SUISUI_CODEX_LIVE_TEST=1 to probe the current Mac user's Codex account.")
        }
        let executablePath = try XCTUnwrap(ProcessInfo.processInfo.environment["SUISUI_CODEX_EXECUTABLE"])
        let approvedExecutable = try CodexAppServerRuntimeConfiguration.approve(executablePath: executablePath)
        _ = try CodexAppServerRuntimeConfiguration.validate(
            approvedExecutable: approvedExecutable,
            reportedVersion: try await ProcessCodexVersionReporter().versionOutput(executablePath: executablePath)
        )
        let transport = CodexAppServerStdioTransport(
            process: ProcessCodexAppServerProcess(
                configuration: CodexAppServerLaunchConfiguration(executablePath: executablePath)
            )
        )
        let account = CodexAppServerAccountClient(transport: transport)

        do {
            try await account.initialize(clientVersion: "live-smoke")
            let snapshot = try await account.readAccount(refresh: false)
            guard case .ready = snapshot.readiness else {
                XCTFail("Codex account is not ready: \(snapshot.readiness)")
                await transport.shutdown()
                return
            }
            let models = try await account.listModels()
            XCTAssertFalse(models.isEmpty)

            // Starting and immediately cancelling verifies the public login
            // contract without opening a browser or replacing the active login.
            let attempt = try await account.startLogin(.chatGPTBrowser)
            XCTAssertTrue(["chatgpt.com", "auth.openai.com"].contains(attempt.authorizationURL.host))
            try await account.cancelLogin(id: attempt.id)
            await transport.shutdown()
        } catch {
            await transport.shutdown()
            throw error
        }
    }

    func testLiveSubscriptionGeneratesToolFreeActionPlanWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["SUISUI_CODEX_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set SUISUI_CODEX_LIVE_TEST=1 to use the current Mac user's Codex allowance.")
        }
        let executablePath = try XCTUnwrap(ProcessInfo.processInfo.environment["SUISUI_CODEX_EXECUTABLE"])
        let approvedExecutable = try CodexAppServerRuntimeConfiguration.approve(executablePath: executablePath)
        let provider = CodexLocalRuntimeProvider(
            approvedExecutable: approvedExecutable,
            modelID: nil,
            clientVersion: "live-smoke"
        )

        let response = try await provider.generatePlan(for: PlanningRequest(
            userInput: "明日の午前10時に見積もりを確認するタスクを作成"
        ))

        XCTAssertNotNil(response.actionPlan)
        XCTAssertTrue(response.validationResult.isValid, "\(response.validationResult.issues)")
    }

    func testExplicitApprovalIsRequiredBeforeVersionProbeOrProcessLaunch() async {
        let reporter = RecordingVersionReporter()
        let provider = CodexLocalRuntimeProvider(
            approvedExecutable: nil,
            modelID: nil,
            clientVersion: "1.0",
            versionReporter: reporter
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "タスクを追加"))
            XCTFail("Expected approval error")
        } catch let error as LLMProviderError {
            guard case .executionNotApproved = error else {
                return XCTFail("Expected executionNotApproved, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callCount = await reporter.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testAccountEntryPointsCannotProbeVersionWithoutApprovedExecutable() async {
        for operation in ["check account", "sign in", "sign out"] {
            let reporter = RecordingVersionReporter()
            let resolver = CodexApprovedRuntimeResolver(versionReporter: reporter)

            do {
                _ = try await resolver.resolve(approvedExecutable: nil)
                XCTFail("Expected approval error for \(operation)")
            } catch let error as CodexAppServerRuntimeConfigurationError {
                XCTAssertEqual(error, .executionApprovalRequired, operation)
            } catch {
                XCTFail("Unexpected error for \(operation): \(error)")
            }
            let callCount = await reporter.callCount
            XCTAssertEqual(callCount, 0, operation)
        }
    }

    func testRequestRechecksCurrentApprovalInsteadOfUsingConstructionSnapshot() async throws {
        let reporter = RecordingVersionReporter()
        let approval = LockedCodexApproval(
            try CodexAppServerRuntimeConfiguration.approve(executablePath: "/usr/bin/true")
        )
        let provider = CodexLocalRuntimeProvider(
            approvedExecutableProvider: { approval.value },
            modelID: nil,
            clientVersion: "1.0",
            versionReporter: reporter
        )
        approval.value = nil

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "タスクを追加"))
            XCTFail("Expected approval error")
        } catch let error as LLMProviderError {
            guard case .executionNotApproved = error else {
                return XCTFail("Expected executionNotApproved, got \(error)")
            }
        }
        let callCount = await reporter.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testApprovalChangeStopsRunningPlanningTransport() async throws {
        let reporter = RecordingVersionReporter()
        let approved = try CodexAppServerRuntimeConfiguration.approve(executablePath: "/usr/bin/true")
        let changes = ControlledApprovalChanges()
        let transport = HangingPlanningCodexTransport()
        let provider = CodexLocalRuntimeProvider(
            approvedExecutableProvider: { approved },
            modelID: nil,
            clientVersion: "1.0",
            scratchRoot: FileManager.default.temporaryDirectory,
            versionReporter: reporter,
            approvalChangeStream: { changes.stream },
            transportFactory: { _ in transport }
        )
        let planning = Task {
            try await provider.generatePlan(for: PlanningRequest(userInput: "タスクを追加"))
        }
        await transport.waitUntilTurnStarted()

        changes.invalidate()

        do {
            _ = try await planning.value
            XCTFail("Expected approval invalidation")
        } catch let error as LLMProviderError {
            guard case .executionNotApproved = error else {
                return XCTFail("Expected executionNotApproved, got \(error)")
            }
        }
        let isShutdown = await transport.isShutdown
        XCTAssertTrue(isShutdown)
    }
}

private actor RecordingVersionReporter: CodexVersionReporting {
    private(set) var callCount = 0
    func versionOutput(executablePath _: String) async throws -> String {
        callCount += 1
        return "codex-cli 0.144.1"
    }
}

private final class LockedCodexApproval: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: ApprovedCodexExecutable?

    init(_ value: ApprovedCodexExecutable?) {
        storedValue = value
    }

    var value: ApprovedCodexExecutable? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

private final class ControlledApprovalChanges: @unchecked Sendable {
    let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func invalidate() {
        continuation.yield(())
    }
}

private actor HangingPlanningCodexTransport: CodexAppServerTransport {
    private let notificationsStream: AsyncStream<CodexJSONRPCNotification>
    private let notificationsContinuation: AsyncStream<CodexJSONRPCNotification>.Continuation
    private var turnStartedContinuation: CheckedContinuation<Void, Never>?
    private var didStartTurn = false
    private(set) var isShutdown = false
    private var requestID: Int64 = 0

    init() {
        (notificationsStream, notificationsContinuation) = AsyncStream.makeStream(
            of: CodexJSONRPCNotification.self
        )
    }

    func start() async throws {}

    func request(
        method: String,
        params _: JSONValue?,
        timeout _: TimeInterval
    ) async throws -> CodexRawJSONRPCResponse {
        requestID += 1
        let result: JSONValue
        switch method {
        case CodexAppServerMethod.initialize:
            result = .object([:])
        case CodexAppServerMethod.accountRead:
            result = .object([
                "account": .object([
                    "type": .string("chatgpt"),
                    "planType": .string("plus")
                ]),
                "requiresOpenaiAuth": .bool(true)
            ])
        case CodexAppServerMethod.accountRateLimitsRead:
            result = .object([
                "rateLimits": .object([
                    "primary": .object(["usedPercent": .number(0)])
                ])
            ])
        case CodexAppServerMethod.modelList:
            result = .object([
                "data": .array([
                    .object([
                        "id": .string("gpt-5.4"),
                        "displayName": .string("GPT-5.4"),
                        "isDefault": .bool(true)
                    ])
                ])
            ])
        case CodexAppServerMethod.threadStart:
            result = .object(["thread": .object(["id": .string("thread-1")])])
        case CodexAppServerMethod.turnStart:
            didStartTurn = true
            turnStartedContinuation?.resume()
            turnStartedContinuation = nil
            result = .object(["turn": .object(["id": .string("turn-1")])])
        default:
            throw CodexAppServerTransportError.streamClosed
        }
        return CodexRawJSONRPCResponse(id: requestID, result: result)
    }

    func notify(method _: String, params _: JSONValue?) async throws {}
    func respond(id _: Int64, result _: JSONValue) async throws {}
    func notifications() async -> AsyncStream<CodexJSONRPCNotification> { notificationsStream }
    func shutdown() async {
        isShutdown = true
        notificationsContinuation.finish()
    }

    func waitUntilTurnStarted() async {
        if didStartTurn { return }
        await withCheckedContinuation { continuation in
            turnStartedContinuation = continuation
        }
    }
}
