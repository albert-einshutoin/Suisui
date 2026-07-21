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
        _ = try CodexAppServerRuntimeConfiguration.validate(
            executablePath: executablePath,
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
        let provider = CodexLocalRuntimeProvider(
            executablePath: executablePath,
            modelID: nil,
            isExecutionApproved: true,
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
            executablePath: "/usr/bin/true",
            modelID: nil,
            isExecutionApproved: false,
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
}

private actor RecordingVersionReporter: CodexVersionReporting {
    private(set) var callCount = 0
    func versionOutput(executablePath _: String) async throws -> String {
        callCount += 1
        return "codex-cli 0.144.1"
    }
}
