import Darwin
import Foundation
import XCTest
@testable import SuisuiCore

final class CodexLocalRuntimeProviderTests: XCTestCase {
    func testExecutableSwapAfterApprovalFailsBeforeVersionProbeLaunch() async throws {
        #if os(macOS)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-version-integrity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        let marker = directory.appendingPathComponent("version-probe-launched")
        try Data("#!/bin/sh\necho 'codex-cli 0.144.1'\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path,
            trustPolicy: .developerUnsignedAllowed
        )

        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        do {
            _ = try await ProcessCodexVersionReporter().versionOutput(
                approvedExecutable: approved
            )
            XCTFail("Expected the changed executable to be rejected")
        } catch {
            XCTAssertEqual(
                error as? CodexAppServerRuntimeConfigurationError,
                .approvedExecutableChanged
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        #endif
    }

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
        let parentRouteReadyPath = wrapperPath + ".parent-route-ready"
        let parentRouteDeadline = Date().addingTimeInterval(180)
        // The runtime evidence must cover every Codex-specific production
        // object, not only the child after Process.start(). The root tracer
        // releases this gate only after ktrace reports that capture started.
        while Darwin.access(parentRouteReadyPath, F_OK) != 0 {
            guard errno == ENOENT else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            guard Date() < parentRouteDeadline else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let approvedWrapper = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: wrapperPath,
            trustPolicy: .developerUnsignedAllowed
        )
        let transport = CodexAppServerStdioTransport(
            process: ProcessCodexAppServerProcess(
                configuration: CodexAppServerLaunchConfiguration(executablePath: wrapperPath),
                approvedExecutable: approvedWrapper
            )
        )
        // fs_usage can materially delay the first App Server response. This
        // audit-only budget does not weaken the product runtime's 10-second default.
        let account = CodexAppServerAccountClient(
            transport: transport,
            initializationTimeout: 60
        )

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
        let approvedExecutable = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executablePath,
            trustPolicy: .developerUnsignedAllowed
        )
        _ = try CodexAppServerRuntimeConfiguration.validate(
            approvedExecutable: approvedExecutable,
            reportedVersion: try await ProcessCodexVersionReporter().versionOutput(
                approvedExecutable: approvedExecutable
            )
        )
        let transport = CodexAppServerStdioTransport(
            process: ProcessCodexAppServerProcess(
                configuration: CodexAppServerLaunchConfiguration(executablePath: executablePath),
                approvedExecutable: approvedExecutable
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
        let approvedExecutable = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executablePath,
            trustPolicy: .developerUnsignedAllowed
        )
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

    func testIntegrityMismatchRequestsPersistedApprovalInvalidationBeforeVersionProbe() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-invalidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\necho first\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path,
            trustPolicy: .developerUnsignedAllowed
        )
        try Data("#!/bin/sh\necho other\n".utf8).write(to: executable)
        let invalidations = LockedCounter()
        let reporter = RecordingVersionReporter()
        let provider = CodexLocalRuntimeProvider(
            approvedExecutableProvider: { approved },
            modelID: nil,
            clientVersion: "1.0",
            scratchRoot: FileManager.default.temporaryDirectory,
            versionReporter: reporter,
            approvalChangeStream: { AsyncStream { _ in } },
            approvalInvalidator: { invalidations.increment() },
            transportFactory: { _ in HangingPlanningCodexTransport() }
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "タスクを追加"))
            XCTFail("Expected integrity mismatch")
        } catch let error as LLMProviderError {
            guard case .executionNotApproved = error else {
                return XCTFail("Expected executionNotApproved, got \(error)")
            }
        }
        XCTAssertEqual(invalidations.value, 1)
        let versionProbeCount = await reporter.callCount
        XCTAssertEqual(versionProbeCount, 0)
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
        let invalidations = LockedCounter()
        let approval = LockedCodexApproval(
            try CodexAppServerRuntimeConfiguration.approve(
                executablePath: "/usr/bin/true",
                trustPolicy: .developerUnsignedAllowed
            )
        )
        let provider = CodexLocalRuntimeProvider(
            approvedExecutableProvider: { approval.value },
            modelID: nil,
            clientVersion: "1.0",
            versionReporter: reporter,
            approvalInvalidator: { invalidations.increment() }
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
        XCTAssertEqual(invalidations.value, 0)
    }

    func testApprovalChangeStopsRunningPlanningTransport() async throws {
        let reporter = RecordingVersionReporter()
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/usr/bin/true",
            trustPolicy: .developerUnsignedAllowed
        )
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

    func testApprovalChangeDuringObserverRegistrationPreventsTransportCreation() async throws {
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/usr/bin/true",
            trustPolicy: .developerUnsignedAllowed
        )
        let generation = LockedApprovalGeneration()
        let transportCreations = LockedCounter()
        let provider = CodexLocalRuntimeProvider(
            approvedExecutableProvider: { approved },
            modelID: nil,
            clientVersion: "1.0",
            scratchRoot: FileManager.default.temporaryDirectory,
            versionReporter: RecordingVersionReporter(),
            approvalChangeStream: {
                generation.advance()
                return AsyncStream { _ in }
            },
            approvalGenerationProvider: { generation.current },
            transportFactory: { _ in
                transportCreations.increment()
                return HangingPlanningCodexTransport()
            }
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "タスクを追加"))
            XCTFail("Expected approval invalidation")
        } catch let error as LLMProviderError {
            guard case .executionNotApproved = error else {
                return XCTFail("Expected executionNotApproved, got \(error)")
            }
        }
        XCTAssertEqual(transportCreations.value, 0)
    }

    func testApprovalChangeBeforeResultAcceptanceRejectsCompletedResponse() async throws {
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: "/usr/bin/true",
            trustPolicy: .developerUnsignedAllowed
        )
        let generations = SequencedApprovalGenerations([0, 0, 0, 1])
        let transport = HangingPlanningCodexTransport(completesPlan: true)
        let provider = CodexLocalRuntimeProvider(
            approvedExecutableProvider: { approved },
            modelID: nil,
            clientVersion: "1.0",
            scratchRoot: FileManager.default.temporaryDirectory,
            versionReporter: RecordingVersionReporter(),
            approvalChangeStream: { AsyncStream { _ in } },
            approvalGenerationProvider: { generations.next() },
            transportFactory: { _ in transport }
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "タスクを追加"))
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
    func versionOutput(approvedExecutable _: ApprovedCodexExecutable) async throws -> String {
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

private final class LockedApprovalGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: UInt64 = 0

    var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func advance() {
        lock.lock()
        storedValue &+= 1
        lock.unlock()
    }
}

private final class SequencedApprovalGenerations: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [UInt64]
    private var index = 0

    init(_ values: [UInt64]) {
        self.values = values
    }

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

private actor HangingPlanningCodexTransport: CodexAppServerTransport {
    private let accountNotificationsStream: AsyncStream<CodexJSONRPCNotification>
    private let accountNotificationsContinuation: AsyncStream<CodexJSONRPCNotification>.Continuation
    private let planningNotificationsStream: AsyncStream<CodexJSONRPCNotification>
    private let planningNotificationsContinuation: AsyncStream<CodexJSONRPCNotification>.Continuation
    private var notificationSubscriberCount = 0
    private var turnStartedContinuation: CheckedContinuation<Void, Never>?
    private var didStartTurn = false
    private(set) var isShutdown = false
    private var requestID: Int64 = 0
    private let completesPlan: Bool

    init(completesPlan: Bool = false) {
        self.completesPlan = completesPlan
        (accountNotificationsStream, accountNotificationsContinuation) = AsyncStream.makeStream(
            of: CodexJSONRPCNotification.self
        )
        (planningNotificationsStream, planningNotificationsContinuation) = AsyncStream.makeStream(
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
            if completesPlan {
                let continuation = planningNotificationsContinuation
                Task {
                    await Task.yield()
                    continuation.yield(CodexJSONRPCNotification(
                        id: nil,
                        method: "item/completed",
                        params: .object(["item": .object([
                            "type": .string("agentMessage"),
                            "text": .string(Self.validActionPlan)
                        ])])
                    ))
                    continuation.yield(CodexJSONRPCNotification(
                        id: nil,
                        method: "turn/completed",
                        params: .object(["turn": .object([
                            "id": .string("turn-1"),
                            "status": .string("completed")
                        ])])
                    ))
                }
            }
            result = .object(["turn": .object(["id": .string("turn-1")])])
        default:
            throw CodexAppServerTransportError.streamClosed
        }
        return CodexRawJSONRPCResponse(id: requestID, result: result)
    }

    func notify(method _: String, params _: JSONValue?) async throws {}
    func respond(id _: Int64, result _: JSONValue) async throws {}
    func notifications() async -> AsyncStream<CodexJSONRPCNotification> {
        notificationSubscriberCount += 1
        return notificationSubscriberCount == 1
            ? accountNotificationsStream
            : planningNotificationsStream
    }
    func shutdown() async {
        isShutdown = true
        accountNotificationsContinuation.finish()
        planningNotificationsContinuation.finish()
    }

    func waitUntilTurnStarted() async {
        if didStartTurn { return }
        await withCheckedContinuation { continuation in
            turnStartedContinuation = continuation
        }
    }

    private static let validActionPlan = #"{"id":"plan-codex-race","userInput":"タスクを追加","summary":"タスクを追加","riskLevel":"write","requiresApproval":true,"actions":[{"id":"action-1","tool":"task.create","riskLevel":"write","requiresUserConfirmation":false,"arguments":{"title":"タスクを追加"}}]}"#
}
