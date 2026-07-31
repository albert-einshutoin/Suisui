import Foundation
import XCTest

final class MCPInspectorEvidenceTests: XCTestCase {
    func testCodexLocalEnterpriseKnownClientBoundaryIsDocumentedAndTracked() throws {
        let complianceReview = try readPackageFile("docs/mcp-compliance.md")
        let phaseChecklist = try readPackageFile("tasks/Phase11-ProviderSyncUXProductization.md")

        XCTAssertTrue(complianceReview.contains("`clientInfo.name = \"suisui\"` is not registered as an OpenAI known client"))
        XCTAssertTrue(complianceReview.contains("Suisui-specific identification in Compliance Logs is not supported"))
        XCTAssertTrue(complianceReview.contains("Personal Preview only"))
        XCTAssertTrue(complianceReview.contains("Enterprise support remains a separate release gate"))
        XCTAssertTrue(
            phaseChecklist.contains(
                "- [x] Enterprise対応を表明する前に`clientInfo.name = \"suisui\"`のknown-client登録"
            )
        )
    }

    func testInspectorVerificationScriptUsesOfficialCLIAndFixturePaths() throws {
        let script = try readPackageFile("script/verify_mcp_compliance.sh")
        let provenance = try readPackageFile("script/mcp_source_provenance.sh")

        XCTAssertTrue(script.contains("@modelcontextprotocol/inspector"))
        XCTAssertTrue(script.contains("--loglevel error"))
        XCTAssertTrue(script.contains("--cli"))
        XCTAssertTrue(script.contains("--method tools/list"))
        XCTAssertTrue(script.contains("--method tools/call"))
        XCTAssertTrue(script.contains("fixtures/mcp/stdio-fixture-server.mjs"))
        XCTAssertTrue(script.contains("docs/release/evidence/mcp-inspector.md"))
        XCTAssertTrue(script.contains("mcp_evidence_source_commit()"))
        XCTAssertTrue(provenance.contains("Sources/SuisuiApp/Composition"))
        XCTAssertFalse(provenance.contains("Sources/SuisuiCore/ExternalMCP/ExternalMCPTestKit"))
    }

    func testMCPSourceProvenanceUsesExplicitPullRequestHeadWhenAvailable() throws {
        let script = try readPackageFile("script/verify_mcp_compliance.sh")
        let provenance = try readPackageFile("script/mcp_source_provenance.sh")
        let workflow = try readPackageFile(".github/workflows/ci.yml")

        XCTAssertTrue(script.contains(#"MCP_SOURCE_REF="${SUISUI_MCP_SOURCE_REF:-HEAD}""#))
        XCTAssertTrue(provenance.contains(#""${source_ref}^{commit}""#))
        XCTAssertTrue(provenance.contains(#""$content_source_ref" --"#))
        XCTAssertTrue(
            workflow.contains(
                "SUISUI_MCP_SOURCE_REF: ${{ github.event.pull_request.head.sha || github.sha }}"
            )
        )
    }

    func testMCPSourceProvenanceFollowsAContentPreservingMergeParent() throws {
        let script = try readPackageFile("script/mcp_source_provenance.sh")

        XCTAssertTrue(script.contains("mcp_content_source_ref()"))
        XCTAssertTrue(script.contains("while true; do"))
        XCTAssertTrue(script.contains(#"for parent_suffix in ^2 ^1"#))
        XCTAssertTrue(
            script.contains(
                #"git -C "$root_dir" diff --quiet "$candidate_parent" "$content_source_ref" --"#
            )
        )
    }

    func testMCPSourceProvenanceIsSharedWithReleaseReadiness() throws {
        let provenance = try readPackageFile("script/mcp_source_provenance.sh")
        let verifier = try readPackageFile("script/verify_mcp_compliance.sh")
        let releaseReadiness = try readPackageFile("script/release_readiness_report.sh")

        XCTAssertTrue(provenance.contains("mcp_content_source_ref()"))
        XCTAssertTrue(provenance.contains("mcp_evidence_source_commit_for_ref()"))
        XCTAssertTrue(provenance.contains("Sources/SuisuiApp/Views/SettingsView.swift"))
        for consumer in [verifier, releaseReadiness] {
            XCTAssertTrue(
                consumer.contains(#"source "$ROOT_DIR/script/mcp_source_provenance.sh""#)
            )
            XCTAssertTrue(consumer.contains("mcp_evidence_source_commit_for_ref"))
        }
    }

    func testMCPSourceProvenanceRejectsAnUnknownExplicitRef() throws {
        let temporaryDirectory = packageRoot()
            .appendingPathComponent(".build/test-mcp-provenance-\(UUID().uuidString)", isDirectory: true)
        let evidence = temporaryDirectory.appendingPathComponent("mcp-inspector.md")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let result = try runScript(
            "script/verify_mcp_compliance.sh",
            environment: [
                "SUISUI_MCP_INSPECTOR_BIN": "/usr/bin/true",
                "SUISUI_MCP_EVIDENCE_FILE": evidence.path,
                "SUISUI_MCP_SOURCE_REF": "refs/heads/suisui-missing-mcp-source-ref"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Invalid SUISUI_MCP_SOURCE_REF"), result.output)
    }

    func testMCPFixtureServerCoversSuccessAndFailureModesOutsideRuntimeSources() throws {
        let fixture = try readPackageFile("fixtures/mcp/stdio-fixture-server.mjs")
        let smokeClient = try readPackageFile("fixtures/mcp/stdio-smoke-client.mjs")
        let runtimeSourceFiles = try allSwiftFiles(under: "Sources")

        XCTAssertTrue(fixture.contains("SUISUI_MCP_FIXTURE_MODE"))
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
        XCTAssertTrue(evidence.contains("- Source commit: `"))
        XCTAssertTrue(evidence.contains("malformed-json"))
        XCTAssertTrue(evidence.contains("mismatched-id"))
        XCTAssertTrue(evidence.contains("invalid-schema"))
        XCTAssertTrue(evidence.contains("timeout"))
        XCTAssertFalse(evidence.contains("TODO"))
        XCTAssertFalse(evidence.contains("TBD"))
    }

    func testTrackedInspectorEvidenceSourceCommitMatchesCurrentMCPSourceCommit() throws {
        let trackedEvidence = try readPackageFile("docs/release/evidence/mcp-inspector.md")
        let temporaryDirectory = packageRoot()
            .appendingPathComponent(".build/test-mcp-tracked-evidence-\(UUID().uuidString)", isDirectory: true)
        let generatedEvidenceURL = temporaryDirectory.appendingPathComponent("mcp-inspector.md")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let result = try runScript(
            "script/verify_mcp_compliance.sh",
            environment: [
                "SUISUI_MCP_INSPECTOR_BIN": "/usr/bin/true",
                "SUISUI_MCP_EVIDENCE_FILE": generatedEvidenceURL.path
            ]
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let generatedEvidence = try String(contentsOf: generatedEvidenceURL, encoding: .utf8)
        let generatedSourceLine = generatedEvidence.split(separator: "\n")
            .first { $0.hasPrefix("- Source commit: `") }
            .map(String.init)
        let sourceLine = try XCTUnwrap(generatedSourceLine)
        XCTAssertTrue(
            trackedEvidence.contains(sourceLine),
            "Run ./script/verify_mcp_compliance.sh after MCP runtime, settings, fixture, or package changes."
        )
    }

    func testReleaseReadinessAgreesWithGeneratedInspectorEvidenceSourceCommit() throws {
        let result = try runScript(
            "script/release_readiness_report.sh",
            environment: ["SUISUI_MCP_INSPECTOR_BIN": "/usr/bin/true"]
        )

        XCTAssertFalse(
            result.output.contains(
                "MCP compliance verifier output source commit does not match current MCP source commit"
            ),
            result.output
        )
        XCTAssertFalse(
            result.output.contains(
                "MCP Inspector evidence source commit does not match current MCP source commit"
            ),
            result.output
        )
    }

    func testComplianceReviewAndEvidenceRecordLegacyBaselineAndCurrentStableBoundary() throws {
        let complianceReview = try readPackageFile("docs/mcp-compliance.md")
        let evidence = try readPackageFile("docs/release/evidence/mcp-inspector.md")
        let script = try readPackageFile("script/verify_mcp_compliance.sh")

        for content in [complianceReview, evidence] {
            XCTAssertTrue(content.contains("Implemented legacy baseline: `2025-11-25`"))
            XCTAssertTrue(content.contains("Official stable latest: `2026-07-28`"))
            XCTAssertTrue(content.contains("Official latest source: https://modelcontextprotocol.io/specification"))
            XCTAssertTrue(content.contains("Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases"))
            XCTAssertTrue(content.contains("Official GitHub release assertion: GitHub marks 2026-07-28 as Latest stable release and 2026-07-28 RC as Pre-release."))
            XCTAssertTrue(content.contains("Official versioning source: https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning"))
            XCTAssertTrue(content.contains("Official versioning assertion: current stable protocol version is `2026-07-28`; `2025-11-25` is a legacy protocol revision."))
            XCTAssertTrue(content.contains("Official latest checked: 2026-07-31"))
            XCTAssertTrue(content.contains("Implemented legacy source: https://modelcontextprotocol.io/specification/2025-11-25"))
            XCTAssertTrue(content.contains("Current stable source: https://modelcontextprotocol.io/specification/2026-07-28"))
            XCTAssertTrue(content.contains("Historical RC source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/"))
            XCTAssertTrue(content.contains("Historical RC assertion: GitHub marks 2026-07-28 RC as Pre-release; it is superseded by stable 2026-07-28."))
            XCTAssertTrue(content.contains("Current stable changelog source: https://modelcontextprotocol.io/specification/2026-07-28/changelog"))
            XCTAssertTrue(content.contains("Current stable changelog assertion: changes are listed since legacy `2025-11-25`; `2026-07-28` is the current stable release."))
            XCTAssertTrue(content.contains("Current stable support status: MCP 2026-07-28 is not implemented in Suisui public alpha."))
            XCTAssertTrue(content.contains("Current stable 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions"))
            XCTAssertTrue(content.contains("per-request `_meta` protocolVersion/clientInfo/clientCapabilities"))
            XCTAssertTrue(content.contains("Current stable `server/discover` is required"))
            XCTAssertTrue(content.contains("Current stable tools/list cache hints `ttlMs` / `cacheScope` are not implemented"))
            XCTAssertTrue(content.contains("not a full MCP host"))
        }
        XCTAssertTrue(script.contains("Implemented legacy baseline:"))
        XCTAssertTrue(script.contains("2025-11-25"))
        XCTAssertTrue(script.contains("Official stable latest:"))
        XCTAssertTrue(script.contains("Official latest source: https://modelcontextprotocol.io/specification"))
        XCTAssertTrue(script.contains("Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases"))
        XCTAssertTrue(script.contains("Official GitHub release assertion: GitHub marks 2026-07-28 as Latest stable release and 2026-07-28 RC as Pre-release."))
        XCTAssertTrue(script.contains("Official versioning source: https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning"))
        XCTAssertTrue(script.contains("Official versioning assertion: current stable protocol version is \\`2026-07-28\\`; \\`2025-11-25\\` is a legacy protocol revision."))
        XCTAssertTrue(script.contains("Official latest checked: 2026-07-31"))
        XCTAssertTrue(script.contains("Implemented legacy source: https://modelcontextprotocol.io/specification/2025-11-25"))
        XCTAssertTrue(script.contains("Current stable source: https://modelcontextprotocol.io/specification/2026-07-28"))
        XCTAssertTrue(script.contains("Historical RC source: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/"))
        XCTAssertTrue(script.contains("Historical RC assertion: GitHub marks 2026-07-28 RC as Pre-release; it is superseded by stable 2026-07-28."))
        XCTAssertTrue(script.contains("Current stable changelog source: https://modelcontextprotocol.io/specification/2026-07-28/changelog"))
        XCTAssertTrue(script.contains("Current stable changelog assertion: changes are listed since legacy \\`2025-11-25\\`; \\`2026-07-28\\` is the current stable release."))
        XCTAssertTrue(script.contains("Current stable support status: MCP 2026-07-28 is not implemented in Suisui public alpha."))
        XCTAssertTrue(script.contains("Current stable 2026-07-28 removes initialize/notifications/initialized and protocol-level sessions"))
        XCTAssertTrue(script.contains(#"per-request \`_meta\` protocolVersion/clientInfo/clientCapabilities"#))
        XCTAssertTrue(script.contains(#"Current stable \`server/discover\` is required"#))
        XCTAssertTrue(script.contains(#"Current stable tools/list cache hints \`ttlMs\` / \`cacheScope\` are not implemented"#))
        XCTAssertTrue(script.contains("not a full MCP host"))
        XCTAssertTrue(complianceReview.contains("Suisui does not send per-request protocol metadata"))
        XCTAssertTrue(complianceReview.contains("server/discover"))
        XCTAssertTrue(complianceReview.contains("will not claim current-stable or full-host compatibility"))
        XCTAssertTrue(complianceReview.contains("Servers that return current stable `2026-07-28` or an `Unsupported protocol version` initialize error are rejected with legacy-baseline guidance"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testClientRejectsCurrentStable20260728WithLegacyBaselineGuidance"))
        XCTAssertTrue(complianceReview.contains("`Unsupported protocol version` initialize error"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testClientRejectsModernProtocolOnlyInitializeErrorWithLegacyBaselineGuidance"))
        XCTAssertTrue(complianceReview.contains("ExternalMCPTests.testExternalMCPSettingsViewModelShowsLegacyGuidanceForModernProtocolOnlyServer"))
        XCTAssertTrue(complianceReview.contains("MCPInspectorEvidenceTests.testComplianceReviewAndEvidenceRecordLegacyBaselineAndCurrentStableBoundary"))
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
        XCTAssertTrue(complianceReview.contains("every enabled external MCP `tools/call` requires an explicit approval token"))
        XCTAssertTrue(complianceReview.contains("`dangerous` tools are blocked even after paid entitlement approval"))
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

    func testComplianceReviewDateMatchesOfficialLatestCheckDate() throws {
        let complianceReview = try readPackageFile("docs/mcp-compliance.md")
        let releaseReport = try readPackageFile("script/release_readiness_report.sh")

        XCTAssertTrue(complianceReview.contains("Last reviewed: 2026-07-31"))
        XCTAssertTrue(complianceReview.contains("Official latest checked: 2026-07-31"))
        XCTAssertTrue(releaseReport.contains("Last reviewed: 2026-07-31"))
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
                "SUISUI_MCP_INSPECTOR_BIN": fakeInspector.path,
                "SUISUI_MCP_EVIDENCE_FILE": evidence.path
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let generatedEvidence = try String(contentsOf: evidence, encoding: .utf8)
        XCTAssertTrue(generatedEvidence.contains("fakeInspector"))
        XCTAssertTrue(generatedEvidence.contains("- Source commit: `"))
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
