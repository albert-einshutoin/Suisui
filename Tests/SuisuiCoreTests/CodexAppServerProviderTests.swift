import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerProviderTests: XCTestCase {
    func testGeneratePlanUsesStableEphemeralReadOnlyThread() async throws {
        let transport = PlanningCodexTransport(mode: .success)
        let provider = CodexAppServerProvider(
            transport: transport,
            prerequisites: ReadyCodexPrerequisites(),
            configuration: CodexAppServerProviderConfiguration(
                modelID: nil,
                scratchDirectory: URL(fileURLWithPath: "/tmp/suisui-codex-tests", isDirectory: true),
                turnTimeout: 1
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "明日見積もりを確認"))

        XCTAssertNotNil(response.actionPlan)
        XCTAssertEqual(response.providerID, "codex.local")
        let requests = await transport.requests
        let start = try XCTUnwrap(requests.first { $0.method == CodexAppServerMethod.threadStart })
        XCTAssertEqual(start.params?["ephemeral"], .bool(true))
        XCTAssertEqual(start.params?["sandbox"], .string("read-only"))
        XCTAssertEqual(start.params?["approvalPolicy"], .string("never"))
        XCTAssertEqual(start.params?["cwd"], .string("/tmp/suisui-codex-tests"))
        XCTAssertNil(start.params?["dynamicTools"])
        XCTAssertNil(start.params?["environments"])
        XCTAssertNil(start.params?["selectedCapabilityRoots"])
    }

    func testCommandApprovalIsCancelledInterruptedAndNeverAcceptedAsPlan() async throws {
        let transport = PlanningCodexTransport(mode: .commandApproval)
        let provider = CodexAppServerProvider(
            transport: transport,
            prerequisites: ReadyCodexPrerequisites(),
            configuration: CodexAppServerProviderConfiguration(
                modelID: "gpt-5.4",
                scratchDirectory: URL(fileURLWithPath: "/tmp/suisui-codex-tests", isDirectory: true),
                turnTimeout: 1
            )
        )

        await XCTAssertThrowsProviderError(
            try await provider.generatePlan(for: PlanningRequest(userInput: "shellでpwdして"))
        ) { error in
            guard case .executionNotApproved = error else {
                return XCTFail("Expected executionNotApproved, got \(error)")
            }
        }

        let responses = await transport.responses
        let notifications = await transport.notifications
        XCTAssertEqual(responses, [
            .init(id: 91, result: .object(["decision": .string("cancel")]))
        ])
        XCTAssertTrue(notifications.contains { $0.method == CodexAppServerMethod.turnInterrupt })
    }

    func testSignedOutAccountDoesNotStartThreadOrFallback() async throws {
        let transport = PlanningCodexTransport(mode: .success)
        let provider = CodexAppServerProvider(
            transport: transport,
            prerequisites: SignedOutCodexPrerequisites(),
            configuration: CodexAppServerProviderConfiguration(
                modelID: nil,
                scratchDirectory: URL(fileURLWithPath: "/tmp/suisui-codex-tests", isDirectory: true),
                turnTimeout: 1
            )
        )

        await XCTAssertThrowsProviderError(
            try await provider.generatePlan(for: PlanningRequest(userInput: "タスクを追加"))
        ) { error in
            XCTAssertEqual(error, .authenticationFailed)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testStartedWebSearchLifecycleInterruptsTurnEvenWithoutApprovalRequest() async throws {
        let transport = PlanningCodexTransport(mode: .webSearch)
        let provider = CodexAppServerProvider(
            transport: transport,
            prerequisites: ReadyCodexPrerequisites(),
            configuration: CodexAppServerProviderConfiguration(
                modelID: nil,
                scratchDirectory: URL(fileURLWithPath: "/tmp/suisui-codex-tests", isDirectory: true),
                turnTimeout: 1
            )
        )

        await XCTAssertThrowsProviderError(
            try await provider.generatePlan(for: PlanningRequest(userInput: "Web検索して"))
        ) { error in
            guard case .executionNotApproved = error else {
                return XCTFail("Expected executionNotApproved, got \(error)")
            }
        }
        let notifications = await transport.notifications
        XCTAssertTrue(notifications.contains { $0.method == CodexAppServerMethod.turnInterrupt })
    }
}

private struct ReadyCodexPrerequisites: CodexPlanningPrerequisiteProviding {
    func readAccount(refresh _: Bool) async throws -> CodexAccountSnapshot {
        CodexAccountSnapshot(account: .chatGPT(email: nil, plan: .plus), readiness: .ready(plan: .plus))
    }

    func listModels() async throws -> [CodexModel] {
        [CodexModel(id: "gpt-5.4", displayName: "GPT-5.4", isDefault: true)]
    }
}

private struct SignedOutCodexPrerequisites: CodexPlanningPrerequisiteProviding {
    func readAccount(refresh _: Bool) async throws -> CodexAccountSnapshot {
        CodexAccountSnapshot(account: nil, readiness: .signedOut)
    }

    func listModels() async throws -> [CodexModel] { [] }
}

private actor PlanningCodexTransport: CodexAppServerTransport {
    enum Mode: Sendable { case success, commandApproval, webSearch }
    struct Request: Sendable { let method: String; let params: JSONValue? }
    struct Notification: Sendable { let method: String; let params: JSONValue? }
    struct Response: Equatable, Sendable { let id: Int64; let result: JSONValue }

    private let mode: Mode
    private let stream: AsyncStream<CodexJSONRPCNotification>
    private let continuation: AsyncStream<CodexJSONRPCNotification>.Continuation
    private(set) var requests: [Request] = []
    private(set) var notifications: [Notification] = []
    private(set) var responses: [Response] = []

    init(mode: Mode) {
        self.mode = mode
        (stream, continuation) = AsyncStream.makeStream(of: CodexJSONRPCNotification.self)
    }

    func start() async throws {}

    func request(method: String, params: JSONValue?, timeout _: TimeInterval) async throws -> CodexRawJSONRPCResponse {
        requests.append(Request(method: method, params: params))
        switch method {
        case CodexAppServerMethod.threadStart:
            return CodexRawJSONRPCResponse(
                id: Int64(requests.count),
                result: .object(["thread": .object(["id": .string("thread-1")])])
            )
        case CodexAppServerMethod.turnStart:
            let mode = mode
            let continuation = continuation
            Task {
                await Task.yield()
                switch mode {
                case .success:
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
                        params: .object(["turn": .object(["id": .string("turn-1"), "status": .string("completed")])])
                    ))
                case .commandApproval:
                    continuation.yield(CodexJSONRPCNotification(
                        id: 91,
                        method: CodexAppServerMethod.commandExecutionRequestApproval,
                        params: .object(["turnId": .string("turn-1")])
                    ))
                case .webSearch:
                    continuation.yield(CodexJSONRPCNotification(
                        id: nil,
                        method: "item/started",
                        params: .object([
                            "threadId": .string("thread-1"),
                            "turnId": .string("turn-1"),
                            "item": .object(["type": .string("webSearch")])
                        ])
                    ))
                }
            }
            return CodexRawJSONRPCResponse(id: Int64(requests.count), result: .object(["turn": .object(["id": .string("turn-1")])]))
        default:
            throw CodexAppServerTransportError.streamClosed
        }
    }

    func notify(method: String, params: JSONValue?) async throws {
        notifications.append(Notification(method: method, params: params))
    }

    func respond(id: Int64, result: JSONValue) async throws {
        responses.append(Response(id: id, result: result))
    }

    func notifications() async -> AsyncStream<CodexJSONRPCNotification> { stream }
    func shutdown() async { continuation.finish() }

    private static let validActionPlan = #"{"id":"plan-codex","userInput":"明日見積もりを確認","summary":"見積もり確認タスクを作成","riskLevel":"write","requiresApproval":true,"actions":[{"id":"action-1","tool":"task.create","riskLevel":"write","requiresUserConfirmation":false,"arguments":{"title":"見積もりを確認"}}]}"#
}

private extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case let .object(values) = self else { return nil }
        return values[key]
    }
}

private func XCTAssertThrowsProviderError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (LLMProviderError) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch let error as LLMProviderError {
        errorHandler(error)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
