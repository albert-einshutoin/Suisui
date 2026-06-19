import Foundation
import XCTest

final class MCPInspectorEvidenceTests: XCTestCase {
    func testInspectorVerificationScriptUsesOfficialCLIAndFixturePaths() throws {
        let script = try readPackageFile("script/verify_mcp_compliance.sh")

        XCTAssertTrue(script.contains("@modelcontextprotocol/inspector"))
        XCTAssertTrue(script.contains("--loglevel error"))
        XCTAssertTrue(script.contains("--cli"))
        XCTAssertTrue(script.contains("--method tools/list"))
        XCTAssertTrue(script.contains("--method tools/call"))
        XCTAssertTrue(script.contains("fixtures/mcp/stdio-fixture-server.mjs"))
        XCTAssertTrue(script.contains("docs/release/evidence/mcp-inspector.md"))
        XCTAssertFalse(script.contains("Sources/SoloPMCore/ExternalMCP/ExternalMCPTestKit"))
    }

    func testMCPFixtureServerCoversSuccessAndFailureModesOutsideRuntimeSources() throws {
        let fixture = try readPackageFile("fixtures/mcp/stdio-fixture-server.mjs")
        let smokeClient = try readPackageFile("fixtures/mcp/stdio-smoke-client.mjs")
        let runtimeSourceFiles = try allSwiftFiles(under: "Sources")

        XCTAssertTrue(fixture.contains("SOLOPM_MCP_FIXTURE_MODE"))
        XCTAssertTrue(fixture.contains("notifications/initialized"))
        XCTAssertTrue(fixture.contains("tools/list"))
        XCTAssertTrue(fixture.contains("tools/call"))
        for failureMode in ["malformed-json", "mismatched-id", "invalid-schema", "timeout"] {
            XCTAssertTrue(fixture.contains(failureMode), "fixture server is missing \(failureMode)")
            XCTAssertTrue(smokeClient.contains(failureMode), "smoke client is missing \(failureMode)")
        }

        for sourceFile in runtimeSourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            XCTAssertFalse(source.contains("stdio-fixture-server"), "\(sourceFile.path) references MCP fixture code.")
        }
    }

    func testInspectorEvidenceRecordsSuccessAndFailureTaxonomy() throws {
        let evidence = try readPackageFile("docs/release/evidence/mcp-inspector.md")

        XCTAssertTrue(evidence.contains("MCP Inspector CLI"))
        XCTAssertTrue(evidence.contains("initialize -> tools/list -> tools/call"))
        XCTAssertTrue(evidence.contains("tools/list"))
        XCTAssertTrue(evidence.contains("tools/call"))
        XCTAssertTrue(evidence.contains("malformed-json"))
        XCTAssertTrue(evidence.contains("mismatched-id"))
        XCTAssertTrue(evidence.contains("invalid-schema"))
        XCTAssertTrue(evidence.contains("timeout"))
        XCTAssertFalse(evidence.contains("TODO"))
        XCTAssertFalse(evidence.contains("TBD"))
    }

    func testComplianceReviewAndEvidenceRecordStableSpecAndDraftBoundary() throws {
        let complianceReview = try readPackageFile("docs/mcp-compliance.md")
        let evidence = try readPackageFile("docs/release/evidence/mcp-inspector.md")
        let script = try readPackageFile("script/verify_mcp_compliance.sh")

        for content in [complianceReview, evidence] {
            XCTAssertTrue(content.contains("Stable baseline: `2025-11-25`"))
            XCTAssertTrue(content.contains("Official stable latest: `2025-11-25`"))
            XCTAssertTrue(content.contains("Draft watchlist: `2026-07-28`"))
            XCTAssertTrue(content.contains("release-candidate"))
            XCTAssertTrue(content.contains("final specification is scheduled for 2026-07-28"))
            XCTAssertTrue(content.contains("not a full MCP host"))
        }
        XCTAssertTrue(script.contains("Stable baseline:"))
        XCTAssertTrue(script.contains("2025-11-25"))
        XCTAssertTrue(script.contains("Official stable latest:"))
        XCTAssertTrue(script.contains("Draft watchlist:"))
        XCTAssertTrue(script.contains("2026-07-28"))
        XCTAssertTrue(script.contains("final specification is scheduled for 2026-07-28"))
        XCTAssertTrue(script.contains("not a full MCP host"))
        XCTAssertTrue(complianceReview.contains("SoloPM does not send per-request protocol metadata"))
        XCTAssertTrue(complianceReview.contains("server/discover"))
        XCTAssertTrue(complianceReview.contains("will not claim draft or full-host compatibility"))
        XCTAssertTrue(complianceReview.contains("MCPInspectorEvidenceTests.testComplianceReviewAndEvidenceRecordStableSpecAndDraftBoundary"))
        XCTAssertTrue(complianceReview.contains("stdio command boundary"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testExternalMCPSettingsRejectsCompositeCommandBeforeSavingRegistration"))
        XCTAssertTrue(complianceReview.contains("Tool schema typing | Implemented for release subset"))
        XCTAssertTrue(complianceReview.contains("omitted `$schema` is treated as JSON Schema 2020-12"))
        XCTAssertTrue(complianceReview.contains("unsupported dialects are rejected with `invalid-schema`"))
        XCTAssertTrue(complianceReview.contains("Tools list pagination"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testClientFollowsToolsListPaginationCursor"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testClientRejectsMalformedToolsListPaginationCursor"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testClientRejectsRepeatedToolsListPaginationCursor"))
        XCTAssertTrue(complianceReview.contains("Tool name policy"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testToolsListRejectsInvalidToolNames"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testToolsListRejectsDuplicateToolNamesAcrossPages"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testToolsListRejectsUnsupportedInputSchemaDialect"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testToolsListRejectsNonObjectPropertySchemas"))
        XCTAssertTrue(complianceReview.contains("outputSchema"))
        XCTAssertTrue(complianceReview.contains("structuredContent"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testToolsListParsesStructuredOutputSchema"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testToolsListRejectsMalformedOutputSchema"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testExternalMCPExecutionRequiresStructuredContentWhenOutputSchemaProvided"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testExternalMCPExecutionRejectsStructuredContentViolatingOutputSchema"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testExternalMCPExecutionRejectsStructuredContentTypeMismatch"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testExternalMCPExecutionSkipsOutputSchemaValidationForToolErrors"))
        XCTAssertTrue(evidence.contains("Structured output and `outputSchema` release-subset validation"))
        XCTAssertTrue(evidence.contains("ExternalMCPTests.testToolsListParsesStructuredOutputSchema"))
    }

    func testInspectorVerificationScriptRunsWithFakeInspectorWithoutNetwork() throws {
        let temporaryDirectory = packageRoot()
            .appendingPathComponent(".build/test-mcp-inspector-\(UUID().uuidString)", isDirectory: true)
        let fakeInspector = temporaryDirectory.appendingPathComponent("fake-mcp-inspector.sh")
        let evidence = temporaryDirectory.appendingPathComponent("mcp-inspector.md")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '{"fakeInspector":true,"args":'
        printf '%s\\n' "$*" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip().split()))'
        printf '}\\n'
        """.write(to: fakeInspector, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeInspector.path)

        let result = try runScript(
            "script/verify_mcp_compliance.sh",
            environment: [
                "SOLOPM_MCP_INSPECTOR_BIN": fakeInspector.path,
                "SOLOPM_MCP_EVIDENCE_FILE": evidence.path
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let generatedEvidence = try String(contentsOf: evidence, encoding: .utf8)
        XCTAssertTrue(generatedEvidence.contains("fakeInspector"))
        XCTAssertTrue(generatedEvidence.contains("success"))
        XCTAssertTrue(generatedEvidence.contains("malformed-json"))
        XCTAssertTrue(generatedEvidence.contains("mismatched-id"))
        XCTAssertTrue(generatedEvidence.contains("invalid-schema"))
        XCTAssertTrue(generatedEvidence.contains("timeout"))
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func allSwiftFiles(under relativePath: String) throws -> [URL] {
        let root = packageRoot().appendingPathComponent(relativePath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }

    private func runScript(
        _ relativePath: String,
        environment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", packageRoot().appendingPathComponent(relativePath).path]
        process.currentDirectoryURL = packageRoot()
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
