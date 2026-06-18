import Foundation
import XCTest
@testable import SoloPMCore

final class OpenCodeLocalProviderTests: XCTestCase {
    func testProviderBuildsRunInvocationFromUserSelectedExecutableWorkspaceAndModel() async throws {
        let workspace = try makeTemporaryDirectory()
        let runner = RecordingOpenCodeLocalCommandRunner(
            output: .init(
                standardOutput: validActionPlanJSON,
                standardError: "",
                exitCode: 0,
                timedOut: false
            )
        )
        let provider = OpenCodeLocalProvider(
            configuration: OpenCodeLocalConfiguration(
                executablePath: "/usr/local/bin/opencode",
                workspacePath: workspace.path,
                modelID: "opencode-go/kimi-k2.7-code",
                isExecutionApproved: true,
                timeoutInterval: 12
            ),
            commandRunner: runner
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        let recordedInvocation = await runner.firstInvocation()
        let invocation = try XCTUnwrap(recordedInvocation)
        XCTAssertEqual(invocation.executablePath, "/usr/local/bin/opencode")
        XCTAssertEqual(invocation.workingDirectory.path, workspace.path)
        XCTAssertEqual(invocation.timeoutInterval, 12)
        XCTAssertEqual(Array(invocation.arguments.prefix(5)), ["run", "--model", "opencode-go/kimi-k2.7-code", "--dir", workspace.path])
        XCTAssertFalse(invocation.arguments.joined(separator: " ").contains("auth.json"))
        XCTAssertFalse(invocation.arguments.contains("--dangerously-skip-permissions"))
        XCTAssertEqual(response.providerID, "opencode.local")
        XCTAssertEqual(response.actionPlan?.id, "plan-1")
        XCTAssertTrue(response.validationResult.isValid)
    }

    func testProviderRejectsUnapprovedExecutionBeforeSubprocess() async throws {
        let workspace = try makeTemporaryDirectory()
        let runner = RecordingOpenCodeLocalCommandRunner()
        let provider = OpenCodeLocalProvider(
            configuration: OpenCodeLocalConfiguration(
                executablePath: "/usr/local/bin/opencode",
                workspacePath: workspace.path,
                modelID: "opencode-go/kimi-k2.7-code",
                isExecutionApproved: false
            ),
            commandRunner: runner
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected unapproved OpenCode execution to fail.")
        } catch {
            XCTAssertEqual(
                error as? LLMProviderError,
                .executionNotApproved("OpenCode local execution requires explicit approval in Settings.")
            )
            let invocations = await runner.recordedInvocations()
            XCTAssertTrue(invocations.isEmpty)
        }
    }

    func testProviderRejectsMissingWorkspaceBeforeSubprocess() async throws {
        let runner = RecordingOpenCodeLocalCommandRunner()
        let provider = OpenCodeLocalProvider(
            configuration: OpenCodeLocalConfiguration(
                executablePath: "/usr/local/bin/opencode",
                workspacePath: "/tmp/solopm-missing-\(UUID().uuidString)",
                modelID: "opencode-go/kimi-k2.7-code",
                isExecutionApproved: true
            ),
            commandRunner: runner
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected missing workspace to fail.")
        } catch {
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("OpenCode workspace directory is unavailable.")
            )
            let invocations = await runner.recordedInvocations()
            XCTAssertTrue(invocations.isEmpty)
        }
    }

    func testProviderRejectsAuthJSONExecutablePathBeforeSubprocess() async throws {
        let workspace = try makeTemporaryDirectory()
        let runner = RecordingOpenCodeLocalCommandRunner()
        let provider = OpenCodeLocalProvider(
            configuration: OpenCodeLocalConfiguration(
                executablePath: "~/.local/share/opencode/auth.json",
                workspacePath: workspace.path,
                modelID: "opencode-go/kimi-k2.7-code",
                isExecutionApproved: true
            ),
            commandRunner: runner
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected auth.json executable path to fail.")
        } catch {
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("OpenCode executable path must not point to auth.json.")
            )
            let invocations = await runner.recordedInvocations()
            XCTAssertTrue(invocations.isEmpty)
        }
    }

    func testProviderMapsTimeoutAndRedactsStderr() async throws {
        let workspace = try makeTemporaryDirectory()
        let provider = OpenCodeLocalProvider(
            configuration: OpenCodeLocalConfiguration(
                executablePath: "/usr/local/bin/opencode",
                workspacePath: workspace.path,
                modelID: "opencode-go/kimi-k2.7-code",
                isExecutionApproved: true
            ),
            commandRunner: RecordingOpenCodeLocalCommandRunner(
                output: .init(
                    standardOutput: "",
                    standardError: "token=sk-secret request hung",
                    exitCode: -9,
                    timedOut: true
                )
            )
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected timeout to fail.")
        } catch {
            guard case .network(let message) = error as? LLMProviderError else {
                return XCTFail("Expected network timeout, got \(error).")
            }
            XCTAssertTrue(message.contains("OpenCode local execution timed out."))
            XCTAssertFalse(message.contains("sk-secret"))
            XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        }
    }

    func testProviderMapsProcessStartFailureAndRedactsErrorDescription() async throws {
        let workspace = try makeTemporaryDirectory()
        let provider = OpenCodeLocalProvider(
            configuration: OpenCodeLocalConfiguration(
                executablePath: "/usr/local/bin/opencode",
                workspacePath: workspace.path,
                modelID: "opencode-go/kimi-k2.7-code",
                isExecutionApproved: true
            ),
            commandRunner: FailingOpenCodeLocalCommandRunner(
                error: OpenCodeLocalRunnerFailure(
                    message: "launch failed token=sk-secret"
                )
            )
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected process start failure to fail.")
        } catch {
            guard case .network(let message) = error as? LLMProviderError else {
                return XCTFail("Expected network start failure, got \(error).")
            }
            XCTAssertTrue(message.contains("OpenCode local execution failed to start."))
            XCTAssertFalse(message.contains("sk-secret"))
            XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        }
    }

    func testProviderRejectsNonJSONNaturalLanguageOutput() async throws {
        let workspace = try makeTemporaryDirectory()
        let provider = OpenCodeLocalProvider(
            configuration: OpenCodeLocalConfiguration(
                executablePath: "/usr/local/bin/opencode",
                workspacePath: workspace.path,
                modelID: "opencode-go/kimi-k2.7-code",
                isExecutionApproved: true
            ),
            commandRunner: RecordingOpenCodeLocalCommandRunner(
                output: .init(
                    standardOutput: "Sure, I can create that task.",
                    standardError: "",
                    exitCode: 0,
                    timedOut: false
                )
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertNil(response.actionPlan)
        XCTAssertFalse(response.validationResult.isValid)
        XCTAssertFalse(response.validationResult.issues.isEmpty)
    }

    private var validActionPlanJSON: String {
        """
        {"id":"plan-1","userInput":"Create a task","summary":"Create task","riskLevel":"write","requiresApproval":true,"actions":[{"id":"action-1","tool":"task.create"}]}
        """
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloPMOpenCodeLocalProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private struct FailingOpenCodeLocalCommandRunner: OpenCodeLocalCommandRunner {
    var error: Error

    func run(_ invocation: OpenCodeLocalInvocation) async throws -> OpenCodeLocalCommandOutput {
        throw error
    }
}

private struct OpenCodeLocalRunnerFailure: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private actor RecordingOpenCodeLocalCommandRunner: OpenCodeLocalCommandRunner {
    private(set) var invocations: [OpenCodeLocalInvocation] = []
    var output: OpenCodeLocalCommandOutput

    init(
        output: OpenCodeLocalCommandOutput = .init(
            standardOutput: "",
            standardError: "",
            exitCode: 0,
            timedOut: false
        )
    ) {
        self.output = output
    }

    func run(_ invocation: OpenCodeLocalInvocation) async throws -> OpenCodeLocalCommandOutput {
        invocations.append(invocation)
        return output
    }

    func recordedInvocations() -> [OpenCodeLocalInvocation] {
        invocations
    }

    func firstInvocation() -> OpenCodeLocalInvocation? {
        invocations.first
    }
}
