import Foundation
import XCTest
@testable import SuisuiCore

final class CodexLocalRuntimeProviderTests: XCTestCase {
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
