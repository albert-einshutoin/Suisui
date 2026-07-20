import XCTest
@testable import SuisuiCore

final class CodebaseMemoryIntegrationTests: XCTestCase {
    func testDisabledConnectorDoesNotFailPlanningOrCallConnector() async throws {
        let connector = RecordingCodebaseMemoryConnector()
        let request = PlanningRequest(userInput: "Summarize Phase6 developer mode")
        let integration = CodebaseMemoryPlanningIntegration(
            policy: .disabled,
            connector: connector
        )

        let enriched = try await integration.enrichPlanningRequest(
            request,
            workspace: CodebaseMemoryWorkspace(rootPath: "/repo", selectedRelativePaths: ["tasks/Phase6-DeveloperMode.md"]),
            approval: .notApproved
        )

        XCTAssertEqual(enriched, request)
        XCTAssertEqual(connector.searchRequests.count, 0)
    }

    func testPreviewShowsSendContextAndRedactsSecrets() {
        let apiKey = "sk" + "-proj-" + "SECRETSECRETSECRETSECRET"
        let request = PlanningRequest(userInput: "Review token \(apiKey)")
        let preview = CodebaseMemoryPlanningIntegration(policy: .previewOnly).preview(
            request: request,
            workspace: CodebaseMemoryWorkspace(rootPath: "/repo", selectedRelativePaths: ["Sources/SuisuiCore"])
        )

        XCTAssertTrue(preview.body.contains("Workspace: /repo"))
        XCTAssertTrue(preview.body.contains("Sources/SuisuiCore"))
        XCTAssertFalse(preview.body.contains(apiKey))
        XCTAssertTrue(preview.body.contains("[REDACTED_SECRET]"))
        XCTAssertEqual(preview.redactionReport.replacementCount, 1)
    }
}

private final class RecordingCodebaseMemoryConnector: CodebaseMemoryConnector, @unchecked Sendable {
    private(set) var searchRequests: [CodebaseMemorySearchRequest] = []

    func search(_ request: CodebaseMemorySearchRequest) async throws -> [CodebaseMemorySnippet] {
        searchRequests.append(request)
        return []
    }
}
